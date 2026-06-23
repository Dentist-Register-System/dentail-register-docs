# SP5.1 — Hook/Job Execution Substrate (Backend) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a DB-backed transactional outbox (`hook_beta`) + a dual-trigger polling worker that executes hooks idempotently with retry, wire it into the appointment transitions that exist today, and expose a clinic-scoped recovery API — all with mock/log provider handlers.

**Architecture:** A new `app/modules/hooks` module. `enqueue_hook()` inserts a `scheduled` hook **inside the caller's transaction** (flush-only, like `record_audit`) — giving "after commit" + atomicity for free. `run_due_hooks()` claims due hooks via `SELECT … FOR UPDATE SKIP LOCKED`, re-validates the related entity, dispatches to a handler registry (mock handlers this slice), then marks `succeeded` / reschedules with exponential backoff / terminal `failed`. Triggered by both an in-process lifespan loop and a secret-protected `POST /internal/hooks/tick` (pinged by cron-job.org in deploy). A recovery API lists/retries/cancels hooks.

**Tech Stack:** FastAPI, SQLAlchemy 2.x (sync), Pydantic v2, Alembic, pytest (local Postgres :5433). Backend repo: `dentist-registry-backend`.

**Spec:** `docs/specs/2026-06-23-sp5-1-hook-substrate-design.md` (issue #116, slice of epic #11).

## Global Constraints

- **Migration → Supabase is controller-only.** Implementers validate via `make test` (local Postgres :5433) ONLY; NEVER run `make migrate` / `alembic upgrade` against `.env` (it points at Supabase). Tests build the schema via `alembic upgrade head`. **Verify the latest revision before authoring** (`ls alembic/versions/` — design-time latest is `0017`; this plan assumes the new migration is **`0018`** — renumber if a higher revision merged first, and set `down_revision` to the true head).
- **Status/type columns are `String` + CHECK** (the scheduling-module convention, NOT native PG enums). Python `str`-`Enum` classes give code-level safety; the DB column is `String(N)` with a CHECK listing allowed values.
- **`_beta` table suffix; UUID PKs (`default=uuid.uuid4`); tz-aware timestamps** via `DateTime(timezone=True), server_default=func.clock_timestamp()` (+ `onupdate` for `updated_at`). Follow the naming convention in `app/core/base.py`.
- **Transactional outbox:** `enqueue_hook` only `db.flush()`es — the **caller owns `db.commit()`**. A rolled-back business transaction discards its hooks.
- **Idempotency is mandatory (§6.4):** unique `idempotency_key`; enqueue is `INSERT … ON CONFLICT (idempotency_key) DO NOTHING` then re-select. Handlers are idempotent.
- **A side-effect failure NEVER touches appointment/request state (§8.2)** — only the hook row changes.
- **Re-validate before execute (§8.3):** dispatch only if the related entity is still in a state where the side effect makes sense; else `cancelled` with a reason.
- **Audit every transition (§7):** `record_audit` (in the worker's per-hook transaction) for `hook.enqueued`, `hook.succeeded`, `hook.failed`, `hook.retried`, `hook.manual_retried`, `hook.cancelled`.
- **No PHI in `last_error` / logs (§11.1):** codes + structured metadata + IDs only.
- **No new dependencies** beyond what's installed (FastAPI/SQLAlchemy/Pydantic/Alembic/pytest). Permissive-OSS only.
- **All handlers are mock/log this slice.** Real WhatsApp/GCal are SP5.2 (#117) / SP5.3 (#118).
- Commit trailer: `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`. Feature branch → PR (never push `main`). Suggested branch: `feat/sp5-1-hook-substrate-backend`.

---

## File Structure

**Backend (`dentist-registry-backend`)**
- `alembic/versions/0018_hook_outbox.py` — create `hook_beta` (+ indexes, CHECKs).
- `app/modules/hooks/__init__.py` — new module.
- `app/modules/hooks/models.py` — `Hook` model + `HookStatus`, `HookType` str-enums + allowed-value tuples.
- `app/modules/hooks/service.py` — `enqueue_hook()` (transactional, idempotent) + audit.
- `app/modules/hooks/backoff.py` — pure `backoff_seconds(attempt, jitter=True)`.
- `app/modules/hooks/handlers.py` — handler registry, mock/log handlers, validator registry, `FAILING_TEST_HOOK_TYPE`.
- `app/modules/hooks/worker.py` — `run_due_hooks(db, batch_size)` (claim → validate → dispatch → settle), `reclaim_stale_running()`, `run_worker_loop()`.
- `app/modules/hooks/schemas.py` — `HookRead`, `HookListPage`.
- `app/modules/hooks/router.py` — clinic-scoped recovery API + internal tick router.
- `app/modules/hooks/deps.py` — `require_internal_tick` (secret guard).
- `app/core/config.py` — add hook config fields.
- `app/core/errors.py` — add `HookNotRetryableError`.
- `app/db/base.py` — register `Hook`.
- `app/main.py` — mount routers + lifespan loop.
- `app/modules/scheduling/booking.py` — enqueue confirmation/cancellation hooks.
- Tests: `tests/hooks/test_enqueue.py`, `test_backoff.py`, `test_worker.py`, `test_worker_concurrency.py`, `test_tick.py`, `test_recovery_api.py`, `tests/scheduling/test_hook_wiring.py`.

---

## Task 1: migration 0018 + Hook model + config + registration

**Files:**
- Create: `alembic/versions/0018_hook_outbox.py`, `app/modules/hooks/__init__.py`, `app/modules/hooks/models.py`
- Modify: `app/core/config.py`, `app/db/base.py`, `app/core/errors.py`
- Test: `tests/hooks/__init__.py`, `tests/hooks/test_models.py`

**Interfaces:**
- Produces: table `hook_beta`; `Hook` model; `HookStatus` (`SCHEDULED/RUNNING/SUCCEEDED/FAILED/CANCELLED`), `HookType` enums; `HOOK_STATUSES`, `HOOK_TYPES` tuples; config `settings.hook_*`; `HookNotRetryableError`.

- [ ] **Step 1: Create the migration** — `alembic/versions/0018_hook_outbox.py` (confirm `down_revision` is the true head first):

```python
"""hook outbox substrate

Revision ID: 0018
Revises: 0017
Create Date: 2026-06-23
"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import JSONB

revision = "0018"
down_revision = "0017"
branch_labels = None
depends_on = None

_STATUSES = ("scheduled", "running", "succeeded", "failed", "cancelled")
_TYPES = (
    "whatsapp_confirmation", "whatsapp_reminder", "whatsapp_cancellation",
    "whatsapp_postop", "gcal_create", "gcal_update", "gcal_delete",
    "mock_test",
)


def upgrade() -> None:
    op.create_table(
        "hook_beta",
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column("clinic_id", sa.Uuid(), sa.ForeignKey("clinic_beta.id"), nullable=False, index=True),
        sa.Column("hook_type", sa.String(40), nullable=False),
        sa.Column("related_entity_type", sa.String(50), nullable=False),
        sa.Column("related_entity_id", sa.Uuid(), nullable=False),
        sa.Column("payload", JSONB(), nullable=False, server_default="{}"),
        sa.Column("idempotency_key", sa.String(200), nullable=False),
        sa.Column("status", sa.String(20), nullable=False, server_default="scheduled"),
        sa.Column("attempts", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("max_attempts", sa.Integer(), nullable=False, server_default="5"),
        sa.Column("scheduled_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.clock_timestamp()),
        sa.Column("next_attempt_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.clock_timestamp()),
        sa.Column("provider_ref", sa.String(200), nullable=True),
        sa.Column("last_error", sa.Text(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.clock_timestamp()),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.clock_timestamp()),
        sa.Column("executed_at", sa.DateTime(timezone=True), nullable=True),
        sa.CheckConstraint(f"status IN {_STATUSES}", name="ck_hook_beta_status"),
        sa.CheckConstraint(f"hook_type IN {_TYPES}", name="ck_hook_beta_hook_type"),
        sa.UniqueConstraint("idempotency_key", name="uq_hook_beta_idempotency_key"),
    )
    op.create_index("ix_hook_beta_status_next_attempt_at", "hook_beta", ["status", "next_attempt_at"])
    op.create_index("ix_hook_beta_clinic_id_status", "hook_beta", ["clinic_id", "status"])


def downgrade() -> None:
    op.drop_index("ix_hook_beta_clinic_id_status", table_name="hook_beta")
    op.drop_index("ix_hook_beta_status_next_attempt_at", table_name="hook_beta")
    op.drop_table("hook_beta")
```

- [ ] **Step 2: Create the module package** — `app/modules/hooks/__init__.py` (empty file) and `tests/hooks/__init__.py` (empty file).

- [ ] **Step 3: Model + enums** — `app/modules/hooks/models.py`:

```python
import enum
import uuid
from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, Integer, String, Text, func
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column

from app.core.base import Base


class HookStatus(str, enum.Enum):
    SCHEDULED = "scheduled"
    RUNNING = "running"
    SUCCEEDED = "succeeded"
    FAILED = "failed"
    CANCELLED = "cancelled"


class HookType(str, enum.Enum):
    WHATSAPP_CONFIRMATION = "whatsapp_confirmation"
    WHATSAPP_REMINDER = "whatsapp_reminder"
    WHATSAPP_CANCELLATION = "whatsapp_cancellation"
    WHATSAPP_POSTOP = "whatsapp_postop"
    GCAL_CREATE = "gcal_create"
    GCAL_UPDATE = "gcal_update"
    GCAL_DELETE = "gcal_delete"
    MOCK_TEST = "mock_test"  # test-only: exercises the failure path


HOOK_STATUSES = tuple(s.value for s in HookStatus)
HOOK_TYPES = tuple(t.value for t in HookType)
TERMINAL_STATUSES = (HookStatus.SUCCEEDED.value, HookStatus.FAILED.value, HookStatus.CANCELLED.value)


class Hook(Base):
    __tablename__ = "hook_beta"

    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid.uuid4)
    clinic_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("clinic_beta.id"), index=True)
    hook_type: Mapped[str] = mapped_column(String(40))
    related_entity_type: Mapped[str] = mapped_column(String(50))
    related_entity_id: Mapped[uuid.UUID] = mapped_column()
    payload: Mapped[dict] = mapped_column(JSONB, default=dict)
    idempotency_key: Mapped[str] = mapped_column(String(200))
    status: Mapped[str] = mapped_column(String(20), default=HookStatus.SCHEDULED.value)
    attempts: Mapped[int] = mapped_column(Integer, default=0)
    max_attempts: Mapped[int] = mapped_column(Integer, default=5)
    scheduled_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.clock_timestamp())
    next_attempt_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.clock_timestamp())
    provider_ref: Mapped[str | None] = mapped_column(String(200), nullable=True)
    last_error: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.clock_timestamp())
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.clock_timestamp(), onupdate=func.clock_timestamp()
    )
    executed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
```

- [ ] **Step 4: Config** — append to `app/core/config.py` `Settings` (before the `@property`s):

```python
    hook_worker_enabled: bool = True
    hook_poll_interval_seconds: int = 15
    hook_max_attempts: int = 5
    hook_batch_size: int = 20
    hook_stale_running_seconds: int = 300
    hook_tick_secret: str = "dev-tick-secret-change-me"
```

- [ ] **Step 5: Error** — append to `app/core/errors.py` after `ConflictError`:

```python
class HookNotRetryableError(ConflictError):
    code = "hook_not_retryable"
```

- [ ] **Step 6: Register the model** — in `app/db/base.py`, add the import alongside the other model imports:

```python
from app.modules.hooks.models import Hook  # noqa: F401
```

- [ ] **Step 7: Model smoke test** — `tests/hooks/test_models.py`:

```python
from app.modules.hooks.models import HOOK_STATUSES, HOOK_TYPES, HookStatus, HookType


def test_status_and_type_value_tuples_match_enums():
    assert HOOK_STATUSES == ("scheduled", "running", "succeeded", "failed", "cancelled")
    assert "whatsapp_confirmation" in HOOK_TYPES
    assert HookStatus.SCHEDULED.value == "scheduled"
    assert HookType.MOCK_TEST.value == "mock_test"
```

- [ ] **Step 8: Run full suite (migration applies) + lint** — `cd dentist-registry-backend && docker compose up -d && make test && make lint` → all pass (0018 applies during schema build).

- [ ] **Step 9: Commit**

```bash
git add alembic/versions/0018_hook_outbox.py app/modules/hooks/ app/core/config.py app/core/errors.py app/db/base.py tests/hooks/
git commit -m "feat(hooks): hook_beta outbox table, model, config, error (#116)"
```

---

## Task 2: `enqueue_hook` service (transactional, idempotent) + audit

**Files:**
- Create: `app/modules/hooks/service.py`
- Test: `tests/hooks/test_enqueue.py`

**Interfaces:**
- Consumes: `Hook`, `HookType`, `record_audit`.
- Produces: `enqueue_hook(db, *, clinic_id, hook_type, related_entity_type, related_entity_id, payload, idempotency_key, scheduled_at=None, max_attempts=None) -> Hook`. Flush-only; idempotent on `idempotency_key`; audits `hook.enqueued`.

- [ ] **Step 1: Failing tests** — `tests/hooks/test_enqueue.py` (use the repo's existing test fixtures for a `db` session + a seeded clinic; mirror `tests/scheduling/` fixture usage):

```python
import uuid

from app.modules.hooks.models import Hook, HookStatus, HookType
from app.modules.hooks.service import enqueue_hook


def _enqueue(db, clinic_id, key="k1"):
    return enqueue_hook(
        db, clinic_id=clinic_id, hook_type=HookType.MOCK_TEST.value,
        related_entity_type="appointment", related_entity_id=uuid.uuid4(),
        payload={"x": 1}, idempotency_key=key,
    )


def test_enqueue_creates_scheduled_hook(db, clinic):
    h = _enqueue(db, clinic.id)
    db.flush()
    assert h.status == HookStatus.SCHEDULED.value
    assert h.attempts == 0 and h.payload == {"x": 1}


def test_enqueue_is_idempotent_on_key(db, clinic):
    a = _enqueue(db, clinic.id, key="dup")
    db.flush()
    b = _enqueue(db, clinic.id, key="dup")
    db.flush()
    assert a.id == b.id
    assert db.query(Hook).filter_by(idempotency_key="dup").count() == 1
```

- [ ] **Step 2: Run → fail** — `.venv/bin/pytest tests/hooks/test_enqueue.py -v` → FAIL (no `service`).

- [ ] **Step 3: Implement** — `app/modules/hooks/service.py`:

```python
import datetime as dt
import uuid

from sqlalchemy import select
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.orm import Session

from app.core.config import settings
from app.modules.audit.service import record_audit
from app.modules.hooks.models import Hook


def enqueue_hook(
    db: Session,
    *,
    clinic_id: uuid.UUID,
    hook_type: str,
    related_entity_type: str,
    related_entity_id: uuid.UUID,
    payload: dict,
    idempotency_key: str,
    scheduled_at: dt.datetime | None = None,
    max_attempts: int | None = None,
) -> Hook:
    """Insert a scheduled hook in the caller's transaction (flush-only; caller commits).

    Idempotent on idempotency_key: a second enqueue with the same key returns the
    existing row and inserts nothing.
    """
    values = {
        "clinic_id": clinic_id,
        "hook_type": hook_type,
        "related_entity_type": related_entity_type,
        "related_entity_id": related_entity_id,
        "payload": payload,
        "idempotency_key": idempotency_key,
        "status": "scheduled",
        "attempts": 0,
        "max_attempts": max_attempts or settings.hook_max_attempts,
    }
    if scheduled_at is not None:
        values["scheduled_at"] = scheduled_at
        values["next_attempt_at"] = scheduled_at
    stmt = (
        pg_insert(Hook)
        .values(**values)
        .on_conflict_do_nothing(index_elements=["idempotency_key"])
        .returning(Hook.id)
    )
    inserted_id = db.execute(stmt).scalar_one_or_none()
    hook = db.execute(
        select(Hook).where(Hook.idempotency_key == idempotency_key)
    ).scalar_one()
    if inserted_id is not None:
        record_audit(
            db, action="hook.enqueued", entity_type="hook", entity_id=hook.id,
            clinic_id=clinic_id, new={"hook_type": hook_type},
        )
    db.flush()
    return hook
```

- [ ] **Step 4: Run → pass + lint** — `.venv/bin/pytest tests/hooks/test_enqueue.py -v && make test && make lint` → all pass.

- [ ] **Step 5: Commit**

```bash
git add app/modules/hooks/service.py tests/hooks/test_enqueue.py
git commit -m "feat(hooks): transactional idempotent enqueue_hook (#116)"
```

---

## Task 3: backoff util + handler & validator registries (mock providers)

**Files:**
- Create: `app/modules/hooks/backoff.py`, `app/modules/hooks/handlers.py`
- Test: `tests/hooks/test_backoff.py`, `tests/hooks/test_handlers.py`

**Interfaces:**
- Produces:
  - `backoff_seconds(attempt: int, *, base: int = 60, factor: int = 2, cap: int = 3600, jitter: bool = True) -> int`
  - `HandlerResult` dataclass (`ok: bool`, `provider_ref: str | None`, `error: str | None`)
  - `dispatch(hook) -> HandlerResult` (mock; logs; `MOCK_TEST` → failure)
  - `validate(db, hook) -> tuple[bool, str | None]` (re-validation registry; default True)
  - `FAILING_TEST_HOOK_TYPE = "mock_test"`

- [ ] **Step 1: Failing tests** — `tests/hooks/test_backoff.py`:

```python
from app.modules.hooks.backoff import backoff_seconds


def test_backoff_grows_exponentially_without_jitter():
    assert backoff_seconds(1, jitter=False) == 60
    assert backoff_seconds(2, jitter=False) == 120
    assert backoff_seconds(3, jitter=False) == 240


def test_backoff_is_capped():
    assert backoff_seconds(20, jitter=False) == 3600


def test_backoff_with_jitter_within_10pct():
    base = backoff_seconds(2, jitter=False)
    val = backoff_seconds(2, jitter=True)
    assert base <= val <= int(base * 1.1)
```

`tests/hooks/test_handlers.py`:

```python
from app.modules.hooks.handlers import HandlerResult, dispatch
from app.modules.hooks.models import Hook, HookType


def _hook(hook_type):
    return Hook(hook_type=hook_type, related_entity_type="appointment", payload={}, idempotency_key="x")


def test_mock_handler_succeeds_with_provider_ref():
    res = dispatch(_hook(HookType.WHATSAPP_CONFIRMATION.value))
    assert isinstance(res, HandlerResult) and res.ok and res.provider_ref


def test_mock_test_hook_type_fails():
    res = dispatch(_hook(HookType.MOCK_TEST.value))
    assert res.ok is False and res.error
```

- [ ] **Step 2: Run → fail.**

- [ ] **Step 3: Implement `backoff.py`:**

```python
import random


def backoff_seconds(attempt: int, *, base: int = 60, factor: int = 2, cap: int = 3600, jitter: bool = True) -> int:
    """Exponential backoff for retry `attempt` (1-based), capped, with optional +0–10% jitter."""
    raw = min(cap, base * (factor ** (attempt - 1)))
    if jitter:
        raw = int(raw + random.uniform(0, raw * 0.1))
    return raw
```

- [ ] **Step 4: Implement `handlers.py`:**

```python
import logging
import uuid
from dataclasses import dataclass

from sqlalchemy.orm import Session

from app.modules.hooks.models import Hook, HookType

logger = logging.getLogger("app.hooks")
FAILING_TEST_HOOK_TYPE = HookType.MOCK_TEST.value


@dataclass
class HandlerResult:
    ok: bool
    provider_ref: str | None = None
    error: str | None = None


def dispatch(hook: Hook) -> HandlerResult:
    """Mock/log dispatch for this slice. Real providers (SP5.2/5.3) replace the bodies.

    `mock_test` always fails (exercises the retry/terminal path in tests).
    """
    if hook.hook_type == FAILING_TEST_HOOK_TYPE:
        return HandlerResult(ok=False, error="mock_test_forced_failure")
    logger.info("hook.dispatch.mock", extra={"hook_type": hook.hook_type, "entity_id": str(hook.related_entity_id)})
    return HandlerResult(ok=True, provider_ref=f"mock:{uuid.uuid4()}")


def validate(db: Session, hook: Hook) -> tuple[bool, str | None]:
    """Re-validate that the side effect still makes sense (Golden Rule 8.3).

    Mock handlers have no real precondition; default valid. SP5.2/5.3 add per-type
    checks here (e.g. appointment still confirmed) by extending _VALIDATORS.
    """
    validator = _VALIDATORS.get(hook.hook_type)
    if validator is None:
        return True, None
    return validator(db, hook)


_VALIDATORS: dict[str, object] = {}  # hook_type -> Callable[[Session, Hook], tuple[bool, str | None]]
```

- [ ] **Step 5: Run → pass + lint** — `.venv/bin/pytest tests/hooks/test_backoff.py tests/hooks/test_handlers.py -v && make lint`.

- [ ] **Step 6: Commit**

```bash
git add app/modules/hooks/backoff.py app/modules/hooks/handlers.py tests/hooks/test_backoff.py tests/hooks/test_handlers.py
git commit -m "feat(hooks): backoff util + mock handler/validator registries (#116)"
```

---

## Task 4: `run_due_hooks` worker (claim → validate → dispatch → settle) + stale reclaim

**Files:**
- Create: `app/modules/hooks/worker.py`
- Test: `tests/hooks/test_worker.py`, `tests/hooks/test_worker_concurrency.py`

**Interfaces:**
- Consumes: `Hook`, `HookStatus`, `dispatch`, `validate`, `backoff_seconds`, `record_audit`, `SessionLocal`.
- Produces:
  - `run_due_hooks(db: Session, batch_size: int | None = None) -> int` (returns #processed)
  - `reclaim_stale_running(db: Session) -> int`
  - `run_worker_loop()` (blocking; used by the lifespan task)

- [ ] **Step 1: Failing tests** — `tests/hooks/test_worker.py`:

```python
import datetime as dt
import uuid

from app.modules.hooks.models import Hook, HookStatus, HookType
from app.modules.hooks.service import enqueue_hook
from app.modules.hooks.worker import run_due_hooks


def _due(db, clinic, hook_type, key):
    h = enqueue_hook(
        db, clinic_id=clinic.id, hook_type=hook_type,
        related_entity_type="appointment", related_entity_id=uuid.uuid4(),
        payload={}, idempotency_key=key,
    )
    db.commit()
    return h


def test_successful_hook_marked_succeeded(db, clinic):
    h = _due(db, clinic, HookType.WHATSAPP_CONFIRMATION.value, "ok1")
    run_due_hooks(db)
    db.refresh(h)
    assert h.status == HookStatus.SUCCEEDED.value
    assert h.provider_ref and h.executed_at is not None


def test_failing_hook_retries_then_terminal(db, clinic):
    h = _due(db, clinic, HookType.MOCK_TEST.value, "fail1")
    h.max_attempts = 2
    db.commit()
    run_due_hooks(db)            # attempt 1 -> reschedule
    db.refresh(h)
    assert h.status == HookStatus.SCHEDULED.value and h.attempts == 1
    h.next_attempt_at = dt.datetime.now(dt.timezone.utc)  # force due again
    db.commit()
    run_due_hooks(db)            # attempt 2 -> terminal failed
    db.refresh(h)
    assert h.status == HookStatus.FAILED.value and h.attempts == 2


def test_not_yet_due_hook_is_skipped(db, clinic):
    h = enqueue_hook(
        db, clinic_id=clinic.id, hook_type=HookType.WHATSAPP_CONFIRMATION.value,
        related_entity_type="appointment", related_entity_id=uuid.uuid4(),
        payload={}, idempotency_key="future",
        scheduled_at=dt.datetime.now(dt.timezone.utc) + dt.timedelta(hours=1),
    )
    db.commit()
    assert run_due_hooks(db) == 0
    db.refresh(h)
    assert h.status == HookStatus.SCHEDULED.value
```

`tests/hooks/test_worker_concurrency.py`:

```python
import uuid

from app.core.database import SessionLocal
from app.modules.hooks.models import Hook, HookStatus, HookType
from app.modules.hooks.service import enqueue_hook
from app.modules.hooks.worker import run_due_hooks


def test_skip_locked_prevents_double_execution(db, clinic):
    # Enqueue one due hook, then claim it in a separate locked session so the
    # second runner sees zero claimable rows (SKIP LOCKED), not a duplicate.
    h = enqueue_hook(
        db, clinic_id=clinic.id, hook_type=HookType.WHATSAPP_CONFIRMATION.value,
        related_entity_type="appointment", related_entity_id=uuid.uuid4(),
        payload={}, idempotency_key="conc1",
    )
    db.commit()

    other = SessionLocal()
    try:
        locked = other.execute(
            __import__("sqlalchemy").select(Hook)
            .where(Hook.status == "scheduled")
            .with_for_update(skip_locked=True)
        ).scalars().all()
        assert len(locked) == 1            # first runner holds the row
        processed = run_due_hooks(db)      # second runner: nothing claimable
        assert processed == 0
    finally:
        other.rollback()
        other.close()
```

- [ ] **Step 2: Run → fail.**

- [ ] **Step 3: Implement `worker.py`:**

```python
import datetime as dt
import logging
import time

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.database import SessionLocal
from app.modules.audit.service import record_audit
from app.modules.hooks.backoff import backoff_seconds
from app.modules.hooks.handlers import dispatch, validate
from app.modules.hooks.models import Hook, HookStatus

logger = logging.getLogger("app.hooks.worker")


def _now() -> dt.datetime:
    return dt.datetime.now(dt.timezone.utc)


def _claim(db: Session, batch_size: int) -> list[Hook]:
    hooks = db.execute(
        select(Hook)
        .where(Hook.status == HookStatus.SCHEDULED.value, Hook.next_attempt_at <= _now())
        .order_by(Hook.next_attempt_at)
        .limit(batch_size)
        .with_for_update(skip_locked=True)
    ).scalars().all()
    for h in hooks:
        h.status = HookStatus.RUNNING.value
    db.commit()  # release the claim lock; rows now marked running
    return hooks


def _settle(db: Session, hook: Hook) -> None:
    ok_valid, reason = validate(db, hook)
    if not ok_valid:
        hook.status = HookStatus.CANCELLED.value
        hook.last_error = reason
        record_audit(db, action="hook.cancelled", entity_type="hook", entity_id=hook.id,
                     clinic_id=hook.clinic_id, reason=reason)
        db.commit()
        return
    result = dispatch(hook)
    if result.ok:
        hook.status = HookStatus.SUCCEEDED.value
        hook.provider_ref = result.provider_ref
        hook.executed_at = _now()
        record_audit(db, action="hook.succeeded", entity_type="hook", entity_id=hook.id,
                     clinic_id=hook.clinic_id)
    else:
        hook.attempts += 1
        hook.last_error = result.error
        if hook.attempts < hook.max_attempts:
            hook.status = HookStatus.SCHEDULED.value
            hook.next_attempt_at = _now() + dt.timedelta(seconds=backoff_seconds(hook.attempts))
            record_audit(db, action="hook.retried", entity_type="hook", entity_id=hook.id,
                         clinic_id=hook.clinic_id, new={"attempts": hook.attempts})
        else:
            hook.status = HookStatus.FAILED.value
            record_audit(db, action="hook.failed", entity_type="hook", entity_id=hook.id,
                         clinic_id=hook.clinic_id, new={"attempts": hook.attempts})
    db.commit()


def run_due_hooks(db: Session, batch_size: int | None = None) -> int:
    claimed = _claim(db, batch_size or settings.hook_batch_size)
    for hook in claimed:
        try:
            _settle(db, hook)
        except Exception:  # never let one hook kill the batch; leave it running for stale-reclaim
            db.rollback()
            logger.exception("hook.settle.error", extra={"hook_id": str(hook.id)})
    return len(claimed)


def reclaim_stale_running(db: Session) -> int:
    cutoff = _now() - dt.timedelta(seconds=settings.hook_stale_running_seconds)
    stale = db.execute(
        select(Hook).where(Hook.status == HookStatus.RUNNING.value, Hook.updated_at < cutoff)
        .with_for_update(skip_locked=True)
    ).scalars().all()
    for h in stale:
        h.status = HookStatus.SCHEDULED.value
        h.next_attempt_at = _now()
    db.commit()
    return len(stale)


def run_worker_loop() -> None:  # pragma: no cover - exercised via lifespan, not unit tests
    logger.info("hook.worker.loop.start", extra={"interval": settings.hook_poll_interval_seconds})
    while True:
        db = SessionLocal()
        try:
            reclaim_stale_running(db)
            run_due_hooks(db)
        except Exception:
            logger.exception("hook.worker.loop.error")
        finally:
            db.close()
        time.sleep(settings.hook_poll_interval_seconds)
```

- [ ] **Step 4: Run → pass + lint** — `.venv/bin/pytest tests/hooks/test_worker.py tests/hooks/test_worker_concurrency.py -v && make test && make lint`.

- [ ] **Step 5: Commit**

```bash
git add app/modules/hooks/worker.py tests/hooks/test_worker.py tests/hooks/test_worker_concurrency.py
git commit -m "feat(hooks): polling worker with SKIP LOCKED claim, retry, stale reclaim (#116)"
```

---

## Task 5: internal tick endpoint (secret-guarded) + lifespan loop + mounting

**Files:**
- Create: `app/modules/hooks/deps.py`
- Modify: `app/main.py`
- Test: `tests/hooks/test_tick.py`

**Interfaces:**
- Consumes: `run_due_hooks`, `reclaim_stale_running`, `settings.hook_tick_secret`, `settings.hook_worker_enabled`.
- Produces: `POST /internal/hooks/tick` (header `X-Hook-Tick-Secret`); FastAPI lifespan that starts `run_worker_loop` in a daemon thread when `hook_worker_enabled`.

- [ ] **Step 1: Failing test** — `tests/hooks/test_tick.py` (use the repo's FastAPI `TestClient` fixture pattern from `tests/`):

```python
from app.core.config import settings


def test_tick_requires_secret(client):
    assert client.post("/internal/hooks/tick").status_code == 401


def test_tick_with_secret_runs(client):
    res = client.post("/internal/hooks/tick", headers={"X-Hook-Tick-Secret": settings.hook_tick_secret})
    assert res.status_code == 200
    assert "processed" in res.json()
```

- [ ] **Step 2: Run → fail.**

- [ ] **Step 3: Secret dep** — `app/modules/hooks/deps.py`:

```python
from fastapi import Header

from app.core.config import settings
from app.core.errors import ForbiddenError


def require_internal_tick(x_hook_tick_secret: str | None = Header(default=None)) -> None:
    if not x_hook_tick_secret or x_hook_tick_secret != settings.hook_tick_secret:
        raise ForbiddenError("Invalid tick secret.", )
```

> Note: `ForbiddenError` maps to 403. The test expects 401 → instead raise `fastapi.HTTPException(status_code=401)`. Use this body:

```python
from fastapi import Header, HTTPException

from app.core.config import settings


def require_internal_tick(x_hook_tick_secret: str | None = Header(default=None)) -> None:
    if not x_hook_tick_secret or x_hook_tick_secret != settings.hook_tick_secret:
        raise HTTPException(status_code=401, detail="Invalid tick secret.")
```

- [ ] **Step 4: Internal router** — add to `app/modules/hooks/router.py` (created fully in Task 6; for now create the file with just the internal router):

```python
from fastapi import APIRouter, Depends

from app.core.deps import DbSession
from app.modules.hooks import worker
from app.modules.hooks.deps import require_internal_tick

internal_router = APIRouter(prefix="/internal/hooks", tags=["hooks-internal"])


@internal_router.post("/tick", dependencies=[Depends(require_internal_tick)])
def tick(db: DbSession):
    reclaimed = worker.reclaim_stale_running(db)
    processed = worker.run_due_hooks(db)
    return {"reclaimed": reclaimed, "processed": processed}
```

- [ ] **Step 5: Mount + lifespan** — modify `app/main.py`:

```python
import threading
from contextlib import asynccontextmanager

from app.modules.hooks.router import internal_router as hooks_internal_router
from app.modules.hooks.worker import run_worker_loop


@asynccontextmanager
async def _lifespan(app: FastAPI):
    if settings.hook_worker_enabled:
        threading.Thread(target=run_worker_loop, name="hook-worker", daemon=True).start()
    yield


def create_app() -> FastAPI:
    configure_logging()
    app = FastAPI(title="Dentist Registry API", lifespan=_lifespan)
    # ... existing middleware + handlers + routers ...
    app.include_router(hooks_internal_router)  # NOTE: no /api/v1 prefix — internal
    return app
```

> In tests, set `settings.hook_worker_enabled = False` in the test config/fixture so the loop thread does not run during the suite (the tick endpoint is tested directly).

- [ ] **Step 6: Run → pass + lint** — `.venv/bin/pytest tests/hooks/test_tick.py -v && make test && make lint`.

- [ ] **Step 7: Commit**

```bash
git add app/modules/hooks/deps.py app/modules/hooks/router.py app/main.py tests/hooks/test_tick.py
git commit -m "feat(hooks): secret-guarded /internal/hooks/tick + lifespan worker loop (#116)"
```

---

## Task 6: recovery API (list / retry / cancel) + schemas

**Files:**
- Modify: `app/modules/hooks/router.py`
- Create: `app/modules/hooks/schemas.py`
- Modify: `app/modules/hooks/service.py` (add `list_hooks`, `manual_retry`, `cancel_hook`)
- Test: `tests/hooks/test_recovery_api.py`

**Interfaces:**
- Consumes: `Hook`, `HookStatus`, `TERMINAL_STATUSES`, `CurrentMembership`, `HookNotRetryableError`, `record_audit`.
- Produces:
  - `GET /api/v1/clinics/{clinic_id}/integrations/hooks?status=&limit=&offset=` → `HookListPage`
  - `POST /api/v1/clinics/{clinic_id}/integrations/hooks/{hook_id}/retry` → `HookRead`
  - `POST /api/v1/clinics/{clinic_id}/integrations/hooks/{hook_id}/cancel` → `HookRead`
  - service: `list_hooks(db, clinic_id, status, limit, offset)`, `manual_retry(db, *, clinic_id, hook_id, actor_user_id)`, `cancel_hook(db, *, clinic_id, hook_id, actor_user_id)`

- [ ] **Step 1: Failing tests** — `tests/hooks/test_recovery_api.py` (reuse the repo's authenticated-client + seeded-clinic fixtures; `failed_hook` helper sets status directly):

```python
import uuid

from app.modules.hooks.models import Hook, HookStatus, HookType


def _make_hook(db, clinic, status):
    h = Hook(clinic_id=clinic.id, hook_type=HookType.MOCK_TEST.value,
             related_entity_type="appointment", related_entity_id=uuid.uuid4(),
             payload={}, idempotency_key=f"k-{uuid.uuid4()}", status=status, attempts=5, max_attempts=5)
    db.add(h); db.commit(); db.refresh(h)
    return h


def test_list_hooks_filters_by_status(client, db, clinic, auth_headers):
    _make_hook(db, clinic, HookStatus.FAILED.value)
    _make_hook(db, clinic, HookStatus.SUCCEEDED.value)
    res = client.get(f"/api/v1/clinics/{clinic.id}/integrations/hooks?status=failed", headers=auth_headers)
    assert res.status_code == 200
    body = res.json()
    assert body["total"] >= 1 and all(h["status"] == "failed" for h in body["items"])


def test_retry_failed_hook_reschedules(client, db, clinic, auth_headers):
    h = _make_hook(db, clinic, HookStatus.FAILED.value)
    res = client.post(f"/api/v1/clinics/{clinic.id}/integrations/hooks/{h.id}/retry", headers=auth_headers)
    assert res.status_code == 200 and res.json()["status"] == "scheduled"
    db.refresh(h)
    assert h.status == "scheduled" and h.attempts == 0


def test_retry_non_failed_hook_409(client, db, clinic, auth_headers):
    h = _make_hook(db, clinic, HookStatus.SUCCEEDED.value)
    res = client.post(f"/api/v1/clinics/{clinic.id}/integrations/hooks/{h.id}/retry", headers=auth_headers)
    assert res.status_code == 409 and res.json()["error"]["code"] == "hook_not_retryable"
```

- [ ] **Step 2: Run → fail.**

- [ ] **Step 3: Schemas** — `app/modules/hooks/schemas.py`:

```python
import datetime as dt
import uuid

from pydantic import BaseModel, ConfigDict


class HookRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: uuid.UUID
    hook_type: str
    related_entity_type: str
    related_entity_id: uuid.UUID
    status: str
    attempts: int
    max_attempts: int
    provider_ref: str | None
    last_error: str | None
    scheduled_at: dt.datetime
    next_attempt_at: dt.datetime
    executed_at: dt.datetime | None
    created_at: dt.datetime


class HookListPage(BaseModel):
    items: list[HookRead]
    total: int
```

- [ ] **Step 4: Service functions** — append to `app/modules/hooks/service.py`:

```python
from sqlalchemy import func as sa_func

from app.core.errors import HookNotRetryableError, NotFoundError
from app.modules.hooks.models import HookStatus


def _get_hook(db: Session, clinic_id: uuid.UUID, hook_id: uuid.UUID) -> Hook:
    hook = db.execute(
        select(Hook).where(Hook.id == hook_id, Hook.clinic_id == clinic_id)
    ).scalar_one_or_none()
    if hook is None:
        raise NotFoundError("Hook not found.")
    return hook


def list_hooks(db: Session, clinic_id: uuid.UUID, status: str | None, limit: int, offset: int):
    base = select(Hook).where(Hook.clinic_id == clinic_id)
    if status:
        base = base.where(Hook.status == status)
    total = db.execute(
        select(sa_func.count()).select_from(base.subquery())
    ).scalar_one()
    items = db.execute(
        base.order_by(Hook.created_at.desc()).limit(limit).offset(offset)
    ).scalars().all()
    return items, total


def manual_retry(db: Session, *, clinic_id: uuid.UUID, hook_id: uuid.UUID, actor_user_id: uuid.UUID) -> Hook:
    hook = _get_hook(db, clinic_id, hook_id)
    if hook.status != HookStatus.FAILED.value:
        raise HookNotRetryableError("Only failed hooks can be retried.")
    hook.status = HookStatus.SCHEDULED.value
    hook.attempts = 0
    hook.last_error = None
    hook.next_attempt_at = dt.datetime.now(dt.timezone.utc)
    record_audit(db, action="hook.manual_retried", entity_type="hook", entity_id=hook.id,
                 clinic_id=clinic_id, actor_user_id=actor_user_id)
    db.commit()
    db.refresh(hook)
    return hook


def cancel_hook(db: Session, *, clinic_id: uuid.UUID, hook_id: uuid.UUID, actor_user_id: uuid.UUID) -> Hook:
    hook = _get_hook(db, clinic_id, hook_id)
    if hook.status in (HookStatus.SUCCEEDED.value, HookStatus.CANCELLED.value):
        raise HookNotRetryableError("Hook is already in a terminal state.")
    hook.status = HookStatus.CANCELLED.value
    record_audit(db, action="hook.cancelled", entity_type="hook", entity_id=hook.id,
                 clinic_id=clinic_id, actor_user_id=actor_user_id, reason="manual_cancel")
    db.commit()
    db.refresh(hook)
    return hook
```

- [ ] **Step 5: Routes** — append the clinic-scoped router to `app/modules/hooks/router.py`:

```python
import uuid

from fastapi import Query

from app.modules.hooks import service
from app.modules.hooks.schemas import HookListPage, HookRead
from app.modules.members.deps import CurrentMembership

router = APIRouter(prefix="/clinics", tags=["hooks"])
_BASE = "/{clinic_id}/integrations/hooks"


@router.get(_BASE, response_model=HookListPage)
def list_hooks(clinic_id: uuid.UUID, db: DbSession, membership: CurrentMembership,
               status: str | None = Query(default=None), limit: int = Query(default=50, le=200),
               offset: int = Query(default=0, ge=0)):
    items, total = service.list_hooks(db, clinic_id, status, limit, offset)
    return HookListPage(items=[HookRead.model_validate(h) for h in items], total=total)


@router.post(_BASE + "/{hook_id}/retry", response_model=HookRead)
def retry_hook(clinic_id: uuid.UUID, hook_id: uuid.UUID, db: DbSession, membership: CurrentMembership):
    return service.manual_retry(db, clinic_id=clinic_id, hook_id=hook_id, actor_user_id=membership.user_id)


@router.post(_BASE + "/{hook_id}/cancel", response_model=HookRead)
def cancel_hook(clinic_id: uuid.UUID, hook_id: uuid.UUID, db: DbSession, membership: CurrentMembership):
    return service.cancel_hook(db, clinic_id=clinic_id, hook_id=hook_id, actor_user_id=membership.user_id)
```

- [ ] **Step 6: Mount the clinic router** — in `app/main.py`, alongside the other `/api/v1` routers:

```python
from app.modules.hooks.router import router as hooks_router
app.include_router(hooks_router, prefix="/api/v1")
```

- [ ] **Step 7: Run → pass + lint** — `.venv/bin/pytest tests/hooks/test_recovery_api.py -v && make test && make lint`.

- [ ] **Step 8: Commit**

```bash
git add app/modules/hooks/router.py app/modules/hooks/schemas.py app/modules/hooks/service.py app/main.py tests/hooks/test_recovery_api.py
git commit -m "feat(hooks): clinic-scoped recovery API (list/retry/cancel) (#116)"
```

---

## Task 7: wire enqueue into appointment confirmation + request cancellation

**Files:**
- Modify: `app/modules/scheduling/booking.py`
- Test: `tests/scheduling/test_hook_wiring.py`

**Interfaces:**
- Consumes: `enqueue_hook`, `get_settings`, `HookType`.
- Produces: confirmation hooks enqueued in `_materialize_appointment` (gated on `whatsapp_enabled` / `google_calendar_enabled`, delayed by `post_confirmation_hook_delay_minutes`); cancellation hooks in `cancel_request` (gated on `whatsapp_enabled`).

- [ ] **Step 1: Failing tests** — `tests/scheduling/test_hook_wiring.py` (reuse scheduling fixtures that confirm an appointment; enable settings):

```python
from app.modules.hooks.models import Hook, HookType


def test_confirmation_enqueues_whatsapp_hook_when_enabled(db, clinic, confirm_appointment, enable_whatsapp):
    appt = confirm_appointment()  # fixture: drives create+approve (or direct-booking) to a confirmed appt
    hooks = db.query(Hook).filter_by(related_entity_id=appt.id,
                                     hook_type=HookType.WHATSAPP_CONFIRMATION.value).all()
    assert len(hooks) == 1
    assert hooks[0].status == "scheduled"


def test_confirmation_enqueues_nothing_when_disabled(db, clinic, confirm_appointment):
    appt = confirm_appointment()  # whatsapp_enabled defaults False, google_calendar_enabled False
    assert db.query(Hook).filter_by(related_entity_id=appt.id).count() == 0


def test_rolled_back_confirmation_leaves_no_hook(db, clinic):
    # If the business txn never commits, the hook must not persist (transactional outbox).
    before = db.query(Hook).count()
    db.rollback()
    assert db.query(Hook).count() == before
```

- [ ] **Step 2: Run → fail.**

- [ ] **Step 3: Add the enqueue helper + wire confirmation** — in `app/modules/scheduling/booking.py`, add imports and a private helper, then call it inside `_materialize_appointment` right before `return appt`:

```python
# add to imports
import datetime as dt
from app.modules.clinics.service import get_settings
from app.modules.hooks.models import HookType
from app.modules.hooks.service import enqueue_hook


def _enqueue_confirmation_hooks(db, *, clinic_id, appt) -> None:
    s = get_settings(db, clinic_id)
    payload = {
        "appointment_id": str(appt.id),
        "patient_id": str(appt.patient_id),
        "doctor_id": str(appt.doctor_id),
        "start_datetime": appt.start_datetime.isoformat(),
    }
    delay = dt.timedelta(minutes=s.post_confirmation_hook_delay_minutes)
    scheduled_at = dt.datetime.now(dt.timezone.utc) + delay
    if s.whatsapp_enabled:
        enqueue_hook(
            db, clinic_id=clinic_id, hook_type=HookType.WHATSAPP_CONFIRMATION.value,
            related_entity_type="appointment", related_entity_id=appt.id,
            payload=payload, idempotency_key=f"appt:{appt.id}:whatsapp_confirmation",
            scheduled_at=scheduled_at,
        )
    if s.google_calendar_enabled:
        enqueue_hook(
            db, clinic_id=clinic_id, hook_type=HookType.GCAL_CREATE.value,
            related_entity_type="appointment", related_entity_id=appt.id,
            payload=payload, idempotency_key=f"appt:{appt.id}:gcal_create",
            scheduled_at=scheduled_at,
        )
```

Then inside `_materialize_appointment`, immediately before `return appt`:

```python
    _enqueue_confirmation_hooks(db, clinic_id=clinic_id, appt=appt)
    return appt
```

- [ ] **Step 4: Wire cancellation** — in `cancel_request`, after setting `req.status = "cancelled"` and before `db.commit()`:

```python
    s = get_settings(db, clinic_id)
    if s.whatsapp_enabled:
        enqueue_hook(
            db, clinic_id=clinic_id, hook_type=HookType.WHATSAPP_CANCELLATION.value,
            related_entity_type="appointment_request", related_entity_id=req.id,
            payload={"request_id": str(req.id), "patient_id": str(req.patient_id)},
            idempotency_key=f"req:{req.id}:whatsapp_cancellation",
        )
```

- [ ] **Step 5: Run → pass + lint** — `.venv/bin/pytest tests/scheduling/test_hook_wiring.py -v && make test && make lint` → all pass. (Existing scheduling tests must stay green — confirmation with default settings enqueues nothing.)

- [ ] **Step 6: Commit**

```bash
git add app/modules/scheduling/booking.py tests/scheduling/test_hook_wiring.py
git commit -m "feat(hooks): enqueue confirmation/cancellation hooks in booking workflow (#116)"
```

---

## Task 8: env example + docs

**Files:**
- Modify: `.env.example` (if present), `README.md`
- Modify (docs repo, this worktree): `Entities/17-hook.md`, `tech stack/register-tech-stack.md`

- [ ] **Step 1: Env example** — add to `dentist-registry-backend/.env.example` (create the keys if the file exists; otherwise skip):

```
HOOK_WORKER_ENABLED=true
HOOK_POLL_INTERVAL_SECONDS=15
HOOK_MAX_ATTEMPTS=5
HOOK_BATCH_SIZE=20
HOOK_STALE_RUNNING_SECONDS=300
HOOK_TICK_SECRET=change-me
```

- [ ] **Step 2: Backend README** — add a "Hooks / background worker" section: what `hook_beta` is, the dual-trigger model (in-process loop + `POST /internal/hooks/tick`), how to run locally (`HOOK_WORKER_ENABLED=true` runs the loop; or `curl -XPOST localhost:8000/internal/hooks/tick -H "X-Hook-Tick-Secret: ..."`), and that providers are mocked until SP5.2/5.3.

- [ ] **Step 3: Docs repo (in this worktree)** — annotate `Entities/17-hook.md` with the realized columns/states and the dual-trigger note; in `tech stack/register-tech-stack.md` Background Jobs section, record the in-process-loop + external-cron (cron-job.org) decision + free-tier rationale + the `HOOK_WORKER_ENABLED` upgrade path.

- [ ] **Step 4: Commit (backend repo)**

```bash
git add README.md .env.example 2>/dev/null; git commit -m "docs(hooks): README + env example for hook substrate (#116)"
```

> The docs-repo edits are committed on the `docs/sp5-integrations-decomp` worktree branch by the planning session, not here.

---

## Self-Review (completed by plan author)

- **Spec coverage:** §2 outbox/worker/mock → Tasks 1–5; §3 data model → Task 1; §4 enqueue seam → Tasks 2,7; §5 execution flow → Tasks 3,4; §6 API + tick → Tasks 5,6; §7 audit → every task's `record_audit`; §8 FE → frontend plan; §9 testing → tests in each task (concurrency in Task 4, txn-atomicity + wiring in Task 7, tick auth in Task 5); §11 docs → Task 8. No gaps.
- **Type consistency:** `enqueue_hook` signature identical in Tasks 2 & 7; `run_due_hooks(db, batch_size=None)` consistent Tasks 4 & 5; `HandlerResult`/`dispatch`/`validate` consistent Tasks 3 & 4; status strings via `HookStatus.*.value` throughout; error code `hook_not_retryable` consistent Tasks 1 & 6.
- **Placeholder scan:** none — every code/command step is concrete. Fixture names (`db`, `clinic`, `client`, `auth_headers`, `confirm_appointment`, `enable_whatsapp`) reference the repo's existing pytest fixtures; the implementer wires any missing helper to the established `tests/` conftest pattern.
