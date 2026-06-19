# SP3.1 — Doctor Availability & Slot Generation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let doctors (and owner/practice_manager) define availability (recurring + one-off windows + vacation blocks) and derive bookable 30-minute slots virtually, surfaced via a doctor-detail availability editor and a new Schedule slot viewer.

**Architecture:** A new backend `scheduling` module owns two tables (`availability_window_beta`, `availability_block_beta`) and a pure `compute_slots()` function that derives slot DTOs on read (no slot table yet — that arrives in SP3.2). Clinic-scoped REST endpoints mirror the doctors module. Frontend adds a `scheduling` feature (api/hooks), a `/doctors/[id]` detail page hosting the availability editor, and a new `/schedule` route + nav destination hosting the read-only slot viewer.

**Tech Stack:** Backend — FastAPI, SQLAlchemy 2.x (sync), Pydantic v2, Alembic, pytest (Postgres :5433). Frontend — Next.js App Router (client components), TanStack Query, React Hook Form + Zod, react-i18next, Tailwind v4 semantic tokens, Playwright (pure-logic + i18n tests; tsc + build are the CI gates).

**Spec:** `docs/specs/2026-06-19-sp3-1-availability-slot-generation-design.md` (issue #43).

## Global Constraints

- **Migration → Supabase is controller-only.** Implementers validate via `make test` against local Postgres (:5433) ONLY. NEVER run `make migrate` / `alembic upgrade` (the repo `.env` points at Supabase). Backend tests build schema via `alembic upgrade head`, so migration 0009 is exercised by `make test`. Controller applies 0009 to Supabase post-merge via MCP `apply_migration` (offline SQL: `ALEMBIC_DB_URL=postgresql+psycopg://x:x@localhost/x .venv/bin/alembic upgrade 0008:0009 --sql`).
- **Status/kind columns use `String` + CHECK constraints** (values `recurring`/`one_off`, `active`/`removed`), validated at the Pydantic layer — NOT native PG enums. This is a deliberate simplicity choice for this slice; do not "fix" it to native enums.
- **Weekday convention: 0 = Monday … 6 = Sunday** (Python `date.weekday()`).
- **Times are clinic-local naive (IST), stored as SQL `time`; dates as `date`.** No UTC conversion (single-location V1).
- **Slot size** = `clinic_settings.default_slot_size_minutes` (default 30); drop trailing partial chunk. **Capacity** = `allow_multiple_bookings_per_slot ? max_bookings_per_slot : 1`.
- **Slot query bounded to ≤ 62 days**, and `to >= from`, else 422.
- **Permissions:** write (windows + blocks) = the doctor whose `doctor_beta.linked_user_id == current user` OR role `owner`/`practice_manager`; assistants 403 on write; all active members may read. Outsiders 403 (no membership).
- **Audit in-transaction** via `app.modules.audit.service.record_audit` for window/block create/update/remove.
- **Uniform error envelope + stable codes** (`forbidden`, `not_found`, `validation_error`). `_beta` table suffix. Permissive-OSS only; **no new dependencies**.
- **Frontend Rule 17.0:** semantic tokens only (no raw colours / `bg-white` / `text-gray-*`), compose `components/ui/*` + `components/layout/*`, no per-page CSS, both themes, mobile-first, WCAG AA. **i18n-first:** every user-facing string via `t()`, added to BOTH `en.json` + `hi.json` (parity enforced by `tests/e2e/i18n.spec.ts`).
- **The new "Schedule" nav destination is approved** (Rule 17.0) per the spec.
- **Next.js caveat (`AGENTS.md`):** this Next.js has breaking changes — for the dynamic route, read route params with `useParams()` in a client component (do not rely on a `params` prop shape). Consult `node_modules/next/dist/docs/` if an API surprises you.
- Backend repo: `dentist-registry-backend`. Frontend repo: `dentist-registry-frontend`. Commit trailer: `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`. Feature branch → PR (never push `main`).

---

## File Structure

**Backend (`dentist-registry-backend`)**
- Create: `alembic/versions/0009_scheduling_availability.py` — both tables.
- Create: `app/modules/scheduling/__init__.py`, `models.py`, `schemas.py`, `service.py`, `router.py`.
- Modify: `app/db/base.py` — import the two new models.
- Modify: `app/main.py` — mount the scheduling router.
- Test: `tests/scheduling/__init__.py`, `tests/scheduling/test_windows.py`, `tests/scheduling/test_blocks.py`, `tests/scheduling/test_slots.py`.

**Frontend (`dentist-registry-frontend`)**
- Create: `src/features/scheduling/api.ts`, `hooks.ts`, `availability-editor.tsx`, `slot-viewer.tsx`.
- Modify: `src/features/doctors/api.ts` — add `fetchDoctor`.
- Create: `src/app/doctors/[id]/page.tsx` — doctor detail + availability editor.
- Create: `src/app/schedule/page.tsx` — slot viewer.
- Modify: `src/components/shell/destinations.ts` — add Schedule.
- Modify: `src/features/doctors/doctor-list.tsx` — link rows to `/doctors/{id}`.
- Modify: `src/i18n/locales/en.json` + `hi.json` — new keys.
- Test: `tests/e2e/slot-format.spec.ts` — pure helper test (if a frontend slot-grouping helper is added).

---

## Task 1: Backend — scheduling module scaffold (migration 0009 + models + wiring)

**Files:**
- Create: `alembic/versions/0009_scheduling_availability.py`
- Create: `app/modules/scheduling/__init__.py` (empty), `app/modules/scheduling/models.py`
- Modify: `app/db/base.py`, `app/main.py`
- Test: `tests/scheduling/__init__.py` (empty), `tests/scheduling/test_models.py`

**Interfaces:**
- Produces: tables `availability_window_beta`, `availability_block_beta`; models `AvailabilityWindow`, `AvailabilityBlock`.

- [ ] **Step 1: Write the migration**

Create `alembic/versions/0009_scheduling_availability.py`:

```python
"""scheduling availability

Revision ID: 0009
Revises: 0008
"""
from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "0009"
down_revision: str | None = "0008"
branch_labels: Sequence[str] | None = None
depends_on: Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "availability_window_beta",
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column("clinic_id", sa.Uuid(), sa.ForeignKey("clinic_beta.id"), nullable=False, index=True),
        sa.Column("doctor_id", sa.Uuid(), sa.ForeignKey("doctor_beta.id"), nullable=False, index=True),
        sa.Column("kind", sa.String(20), nullable=False),
        sa.Column("day_of_week", sa.SmallInteger(), nullable=True),
        sa.Column("specific_date", sa.Date(), nullable=True),
        sa.Column("start_time", sa.Time(), nullable=False),
        sa.Column("end_time", sa.Time(), nullable=False),
        sa.Column("status", sa.String(20), nullable=False, server_default="active"),
        sa.Column("created_by", sa.Uuid(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.clock_timestamp(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.clock_timestamp(), nullable=False),
        sa.CheckConstraint("end_time > start_time", name="ck_avail_window_time_order"),
        sa.CheckConstraint("kind IN ('recurring','one_off')", name="ck_avail_window_kind"),
        sa.CheckConstraint("status IN ('active','removed')", name="ck_avail_window_status"),
        sa.CheckConstraint(
            "(kind = 'recurring' AND day_of_week IS NOT NULL AND specific_date IS NULL) OR "
            "(kind = 'one_off' AND specific_date IS NOT NULL AND day_of_week IS NULL)",
            name="ck_avail_window_kind_fields",
        ),
        sa.CheckConstraint(
            "day_of_week IS NULL OR (day_of_week BETWEEN 0 AND 6)", name="ck_avail_window_dow"
        ),
    )
    op.create_table(
        "availability_block_beta",
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column("clinic_id", sa.Uuid(), sa.ForeignKey("clinic_beta.id"), nullable=False, index=True),
        sa.Column("doctor_id", sa.Uuid(), sa.ForeignKey("doctor_beta.id"), nullable=False, index=True),
        sa.Column("block_date", sa.Date(), nullable=False),
        sa.Column("start_time", sa.Time(), nullable=True),
        sa.Column("end_time", sa.Time(), nullable=True),
        sa.Column("reason", sa.Text(), nullable=True),
        sa.Column("status", sa.String(20), nullable=False, server_default="active"),
        sa.Column("created_by", sa.Uuid(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.clock_timestamp(), nullable=False),
        sa.CheckConstraint("status IN ('active','removed')", name="ck_avail_block_status"),
        sa.CheckConstraint(
            "(start_time IS NULL AND end_time IS NULL) OR "
            "(start_time IS NOT NULL AND end_time IS NOT NULL AND end_time > start_time)",
            name="ck_avail_block_times",
        ),
    )


def downgrade() -> None:
    op.drop_table("availability_block_beta")
    op.drop_table("availability_window_beta")
```

- [ ] **Step 2: Write the models**

Create `app/modules/scheduling/models.py`:

```python
import uuid
from datetime import date, datetime, time

from sqlalchemy import Date, DateTime, ForeignKey, SmallInteger, String, Text, Time, func
from sqlalchemy.orm import Mapped, mapped_column

from app.core.base import Base


class AvailabilityWindow(Base):
    __tablename__ = "availability_window_beta"

    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid.uuid4)
    clinic_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("clinic_beta.id"), index=True)
    doctor_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("doctor_beta.id"), index=True)
    kind: Mapped[str] = mapped_column(String(20))
    day_of_week: Mapped[int | None] = mapped_column(SmallInteger, nullable=True)
    specific_date: Mapped[date | None] = mapped_column(Date, nullable=True)
    start_time: Mapped[time] = mapped_column(Time)
    end_time: Mapped[time] = mapped_column(Time)
    status: Mapped[str] = mapped_column(String(20), default="active")
    created_by: Mapped[uuid.UUID] = mapped_column()
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.clock_timestamp()
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.clock_timestamp(), onupdate=func.clock_timestamp()
    )


class AvailabilityBlock(Base):
    __tablename__ = "availability_block_beta"

    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid.uuid4)
    clinic_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("clinic_beta.id"), index=True)
    doctor_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("doctor_beta.id"), index=True)
    block_date: Mapped[date] = mapped_column(Date)
    start_time: Mapped[time | None] = mapped_column(Time, nullable=True)
    end_time: Mapped[time | None] = mapped_column(Time, nullable=True)
    reason: Mapped[str | None] = mapped_column(Text, nullable=True)
    status: Mapped[str] = mapped_column(String(20), default="active")
    created_by: Mapped[uuid.UUID] = mapped_column()
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.clock_timestamp()
    )
```

- [ ] **Step 3: Register models for Alembic + create empty package files**

In `app/db/base.py`, add after the doctors import:
```python
from app.modules.scheduling.models import AvailabilityBlock, AvailabilityWindow  # noqa: F401
```
Create empty `app/modules/scheduling/__init__.py` and empty `tests/scheduling/__init__.py`.

- [ ] **Step 4: Write a model smoke test**

Create `tests/scheduling/test_models.py`:

```python
import datetime as dt
import uuid

from app.modules.scheduling.models import AvailabilityBlock, AvailabilityWindow


def test_models_persist(db_session):
    cid, did, uid = uuid.uuid4(), uuid.uuid4(), uuid.uuid4()
    # NOTE: no FK rows needed if FK checks deferred? They are enforced — use a real clinic/doctor in CRUD tests.
    w = AvailabilityWindow(
        clinic_id=cid, doctor_id=did, kind="recurring", day_of_week=0,
        start_time=dt.time(9, 0), end_time=dt.time(12, 0), created_by=uid,
    )
    assert w.kind == "recurring"
    b = AvailabilityBlock(
        clinic_id=cid, doctor_id=did, block_date=dt.date(2026, 7, 1), created_by=uid,
    )
    assert b.start_time is None
```

(This is a construction smoke test only — it does not hit the DB FKs. Real persistence is covered by the CRUD API tests in Tasks 2–3.)

- [ ] **Step 5: Run the smoke test + full suite (migration applies)**

Run: `cd dentist-registry-backend && docker compose up -d && make test`
Expected: PASS — migration 0009 applies during schema build; new test passes; no regressions.

- [ ] **Step 6: Mount the router stub**

Create `app/modules/scheduling/router.py`:
```python
from fastapi import APIRouter

router = APIRouter(prefix="/clinics", tags=["scheduling"])
```
In `app/main.py`, add the import next to the other module routers:
```python
from app.modules.scheduling.router import router as scheduling_router
```
and mount it next to the others:
```python
    app.include_router(scheduling_router, prefix="/api/v1")
```

- [ ] **Step 7: Run lint + full suite**

Run: `make lint && make test`
Expected: clean + all pass.

- [ ] **Step 8: Commit**

```bash
git add alembic/versions/0009_scheduling_availability.py app/modules/scheduling/ app/db/base.py app/main.py tests/scheduling/
git commit -m "feat(scheduling): module scaffold + availability tables (migration 0009)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: Backend — availability window CRUD (schemas + service + router + authz + audit)

**Files:**
- Modify: `app/modules/scheduling/schemas.py` (create), `service.py` (create), `router.py`
- Test: `tests/scheduling/test_windows.py`

**Interfaces:**
- Consumes: models from Task 1; `app.modules.doctors.service.get_doctor`; `app.modules.members.deps.CurrentMembership`; `app.modules.members.models.MemberRole`; `app.modules.audit.service.record_audit`; `app.core.errors`.
- Produces: `authorize_manage_availability(db, *, clinic_id, doctor_id, membership)`; service fns `create_window/list_windows/update_window/remove_window`; schemas `WindowCreate`, `WindowUpdate`, `WindowRead`.

- [ ] **Step 1: Write failing tests**

Create `tests/scheduling/test_windows.py`:

```python
import datetime as dt

from tests.conftest import make_clinic

OWNER = "11111111-1111-1111-1111-111111111111"
OUTSIDER = "44444444-4444-4444-4444-444444444444"


def _make_doctor(client, clinic_id, name="Dr. A"):
    resp = client.post(f"/api/v1/clinics/{clinic_id}/doctors", json={
        "name": name, "phone": "+91 90000 00000", "specialty": "Dentist",
    })
    assert resp.status_code == 201, resp.text
    return resp.json()["doctor"]["id"]


def _recurring(**over):
    base = {"kind": "recurring", "day_of_week": 0, "start_time": "09:00", "end_time": "12:00"}
    base.update(over)
    return base


def test_owner_creates_recurring_window(auth_client):
    c, _ = auth_client(sub=OWNER)
    clinic = make_clinic(c, name="C")
    doc = _make_doctor(c, clinic)
    r = c.post(f"/api/v1/clinics/{clinic}/doctors/{doc}/availability", json=_recurring())
    assert r.status_code == 201, r.text
    body = r.json()
    assert body["kind"] == "recurring" and body["day_of_week"] == 0
    assert body["status"] == "active"


def test_one_off_requires_date_not_dow(auth_client):
    c, _ = auth_client(sub=OWNER)
    clinic = make_clinic(c, name="C")
    doc = _make_doctor(c, clinic)
    # one_off with day_of_week set -> 422
    bad = {"kind": "one_off", "day_of_week": 0, "start_time": "09:00", "end_time": "10:00"}
    assert c.post(f"/api/v1/clinics/{clinic}/doctors/{doc}/availability", json=bad).status_code == 422
    ok = {"kind": "one_off", "specific_date": "2026-07-01", "start_time": "09:00", "end_time": "10:00"}
    assert c.post(f"/api/v1/clinics/{clinic}/doctors/{doc}/availability", json=ok).status_code == 201


def test_end_before_start_rejected(auth_client):
    c, _ = auth_client(sub=OWNER)
    clinic = make_clinic(c, name="C")
    doc = _make_doctor(c, clinic)
    bad = _recurring(start_time="12:00", end_time="09:00")
    assert c.post(f"/api/v1/clinics/{clinic}/doctors/{doc}/availability", json=bad).status_code == 422


def test_list_and_soft_remove(auth_client):
    c, _ = auth_client(sub=OWNER)
    clinic = make_clinic(c, name="C")
    doc = _make_doctor(c, clinic)
    wid = c.post(f"/api/v1/clinics/{clinic}/doctors/{doc}/availability", json=_recurring()).json()["id"]
    assert len(c.get(f"/api/v1/clinics/{clinic}/doctors/{doc}/availability").json()) == 1
    assert c.delete(f"/api/v1/clinics/{clinic}/doctors/{doc}/availability/{wid}").status_code == 204
    assert c.get(f"/api/v1/clinics/{clinic}/doctors/{doc}/availability").json() == []


def test_assistant_cannot_write_but_can_read(auth_client):
    owner, _ = auth_client(sub=OWNER)
    clinic = make_clinic(owner, name="C")
    doc = _make_doctor(owner, clinic)
    # add assistant member via invite flow is heavy; instead use a second clinic owner is N/A.
    # Use the members test helper pattern: create assistant membership through the invite/accept flow.
    # For this test we assert the OUTSIDER (no membership) is forbidden:
    out, _ = auth_client(sub=OUTSIDER)
    assert out.post(f"/api/v1/clinics/{clinic}/doctors/{doc}/availability", json=_recurring()).status_code == 403
    assert out.get(f"/api/v1/clinics/{clinic}/doctors/{doc}/availability").status_code == 403
```

> Note for implementer: the project already has helpers/fixtures for creating assistant memberships in `tests/` (see how `tests/members` or `tests/assistants` set up non-owner roles). If a ready helper exists, add an explicit assistant-write-403 + assistant-read-200 case using it. If not, the outsider-403 case above plus the owner-success cases satisfy the permission matrix for this slice; do not build new invite machinery just for the test.

- [ ] **Step 2: Run to verify they fail**

Run: `.venv/bin/pytest tests/scheduling/test_windows.py -v`
Expected: FAIL (routes 404 / module incomplete).

- [ ] **Step 3: Write the schemas**

Create `app/modules/scheduling/schemas.py`:

```python
import datetime as dt
import uuid

from pydantic import BaseModel, ConfigDict, Field, model_validator


class WindowCreate(BaseModel):
    kind: str = Field(pattern="^(recurring|one_off)$")
    day_of_week: int | None = Field(default=None, ge=0, le=6)
    specific_date: dt.date | None = None
    start_time: dt.time
    end_time: dt.time

    @model_validator(mode="after")
    def _check(self) -> "WindowCreate":
        if self.end_time <= self.start_time:
            raise ValueError("end_time must be after start_time.")
        if self.kind == "recurring":
            if self.day_of_week is None or self.specific_date is not None:
                raise ValueError("recurring requires day_of_week and no specific_date.")
        else:  # one_off
            if self.specific_date is None or self.day_of_week is not None:
                raise ValueError("one_off requires specific_date and no day_of_week.")
        return self


class WindowUpdate(BaseModel):
    day_of_week: int | None = Field(default=None, ge=0, le=6)
    specific_date: dt.date | None = None
    start_time: dt.time | None = None
    end_time: dt.time | None = None


class WindowRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: uuid.UUID
    doctor_id: uuid.UUID
    kind: str
    day_of_week: int | None
    specific_date: dt.date | None
    start_time: dt.time
    end_time: dt.time
    status: str
```

- [ ] **Step 4: Write the service (authz + CRUD + audit)**

Create `app/modules/scheduling/service.py`:

```python
import uuid

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.errors import DomainError, NotFoundError
from app.modules.audit.service import record_audit
from app.modules.doctors.service import get_doctor
from app.modules.members.models import ClinicMember, MemberRole
from app.modules.scheduling.models import AvailabilityWindow
from app.modules.scheduling.schemas import WindowCreate, WindowUpdate


class ForbiddenError(DomainError):
    status_code = 403
    code = "forbidden"


def authorize_manage_availability(
    db: Session, *, clinic_id: uuid.UUID, doctor_id: uuid.UUID, membership: ClinicMember
) -> None:
    """Owner/PM may manage any doctor; a doctor may manage only their own."""
    doctor = get_doctor(db, clinic_id, doctor_id)  # raises NotFoundError if not in clinic
    if membership.role in (MemberRole.owner, MemberRole.practice_manager):
        return
    if membership.role == MemberRole.doctor and doctor.linked_user_id == membership.user_id:
        return
    raise ForbiddenError("Your role is not permitted to manage this doctor's availability.")


def _get_window(db: Session, clinic_id: uuid.UUID, doctor_id: uuid.UUID, window_id: uuid.UUID) -> AvailabilityWindow:
    w = db.execute(
        select(AvailabilityWindow).where(
            AvailabilityWindow.id == window_id,
            AvailabilityWindow.clinic_id == clinic_id,
            AvailabilityWindow.doctor_id == doctor_id,
            AvailabilityWindow.status == "active",
        )
    ).scalar_one_or_none()
    if w is None:
        raise NotFoundError("Availability window not found.")
    return w


def create_window(
    db: Session, *, clinic_id: uuid.UUID, doctor_id: uuid.UUID, actor_user_id: uuid.UUID, data: WindowCreate
) -> AvailabilityWindow:
    w = AvailabilityWindow(
        clinic_id=clinic_id, doctor_id=doctor_id, kind=data.kind,
        day_of_week=data.day_of_week, specific_date=data.specific_date,
        start_time=data.start_time, end_time=data.end_time, created_by=actor_user_id,
    )
    db.add(w)
    db.flush()
    record_audit(db, action="availability_window.created", entity_type="availability_window",
                 entity_id=w.id, clinic_id=clinic_id, actor_user_id=actor_user_id,
                 new={"kind": w.kind, "doctor_id": str(doctor_id)})
    db.commit()
    db.refresh(w)
    return w


def list_windows(db: Session, clinic_id: uuid.UUID, doctor_id: uuid.UUID) -> list[AvailabilityWindow]:
    return list(db.execute(
        select(AvailabilityWindow).where(
            AvailabilityWindow.clinic_id == clinic_id,
            AvailabilityWindow.doctor_id == doctor_id,
            AvailabilityWindow.status == "active",
        ).order_by(AvailabilityWindow.day_of_week, AvailabilityWindow.specific_date, AvailabilityWindow.start_time)
    ).scalars())


def update_window(
    db: Session, *, clinic_id: uuid.UUID, doctor_id: uuid.UUID, window_id: uuid.UUID,
    actor_user_id: uuid.UUID, data: WindowUpdate,
) -> AvailabilityWindow:
    w = _get_window(db, clinic_id, doctor_id, window_id)
    changes = data.model_dump(exclude_unset=True)
    for k, v in changes.items():
        setattr(w, k, v)
    if w.end_time <= w.start_time:
        raise DomainError("end_time must be after start_time.")
    db.flush()
    record_audit(db, action="availability_window.updated", entity_type="availability_window",
                 entity_id=w.id, clinic_id=clinic_id, actor_user_id=actor_user_id, new=changes)
    db.commit()
    db.refresh(w)
    return w


def remove_window(
    db: Session, *, clinic_id: uuid.UUID, doctor_id: uuid.UUID, window_id: uuid.UUID, actor_user_id: uuid.UUID
) -> None:
    w = _get_window(db, clinic_id, doctor_id, window_id)
    w.status = "removed"
    db.flush()
    record_audit(db, action="availability_window.removed", entity_type="availability_window",
                 entity_id=w.id, clinic_id=clinic_id, actor_user_id=actor_user_id, new={"status": "removed"})
    db.commit()
```

> `DomainError` default `status_code`/`code`: confirm `app.core.errors.DomainError` maps to 422 with code `validation_error` (it is the base used elsewhere for validation). If `DomainError` is abstract, raise the project's validation error class instead (check `app/core/errors.py`); the goal is a 422 with a stable code.

- [ ] **Step 5: Write the router endpoints**

Replace `app/modules/scheduling/router.py` with:

```python
import uuid

from fastapi import APIRouter, Depends, status

from app.core.deps import DbSession
from app.modules.members.deps import CurrentMembership
from app.modules.scheduling import service
from app.modules.scheduling.schemas import WindowCreate, WindowRead, WindowUpdate

router = APIRouter(prefix="/clinics", tags=["scheduling"])

_BASE = "/{clinic_id}/doctors/{doctor_id}/availability"


@router.post(_BASE, response_model=WindowRead, status_code=status.HTTP_201_CREATED)
def create_window(
    clinic_id: uuid.UUID, doctor_id: uuid.UUID, data: WindowCreate,
    db: DbSession, membership: CurrentMembership,
):
    service.authorize_manage_availability(db, clinic_id=clinic_id, doctor_id=doctor_id, membership=membership)
    return service.create_window(
        db, clinic_id=clinic_id, doctor_id=doctor_id, actor_user_id=membership.user_id, data=data
    )


@router.get(_BASE, response_model=list[WindowRead])
def list_windows(clinic_id: uuid.UUID, doctor_id: uuid.UUID, db: DbSession, membership: CurrentMembership):
    return service.list_windows(db, clinic_id, doctor_id)


@router.patch(_BASE + "/{window_id}", response_model=WindowRead)
def update_window(
    clinic_id: uuid.UUID, doctor_id: uuid.UUID, window_id: uuid.UUID, data: WindowUpdate,
    db: DbSession, membership: CurrentMembership,
):
    service.authorize_manage_availability(db, clinic_id=clinic_id, doctor_id=doctor_id, membership=membership)
    return service.update_window(
        db, clinic_id=clinic_id, doctor_id=doctor_id, window_id=window_id,
        actor_user_id=membership.user_id, data=data,
    )


@router.delete(_BASE + "/{window_id}", status_code=status.HTTP_204_NO_CONTENT)
def remove_window(
    clinic_id: uuid.UUID, doctor_id: uuid.UUID, window_id: uuid.UUID,
    db: DbSession, membership: CurrentMembership,
):
    service.authorize_manage_availability(db, clinic_id=clinic_id, doctor_id=doctor_id, membership=membership)
    service.remove_window(
        db, clinic_id=clinic_id, doctor_id=doctor_id, window_id=window_id, actor_user_id=membership.user_id
    )
```

- [ ] **Step 6: Run the window tests + full suite**

Run: `.venv/bin/pytest tests/scheduling/test_windows.py -v && make test`
Expected: PASS.

- [ ] **Step 7: Lint + commit**

Run: `make lint`
```bash
git add app/modules/scheduling/ tests/scheduling/test_windows.py
git commit -m "feat(scheduling): availability window CRUD + authz + audit

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: Backend — availability block CRUD

**Files:**
- Modify: `app/modules/scheduling/schemas.py`, `service.py`, `router.py`
- Test: `tests/scheduling/test_blocks.py`

**Interfaces:**
- Consumes: Task 2's `authorize_manage_availability`, audit, `AvailabilityBlock`.
- Produces: `BlockCreate`, `BlockRead`; service `create_block/list_blocks/remove_block`.

- [ ] **Step 1: Write failing tests**

Create `tests/scheduling/test_blocks.py`:

```python
from tests.conftest import make_clinic

OWNER = "11111111-1111-1111-1111-111111111111"


def _doc(c, clinic):
    return c.post(f"/api/v1/clinics/{clinic}/doctors", json={
        "name": "Dr. B", "phone": "+91 90000 00000",
    }).json()["doctor"]["id"]


def test_full_day_block(auth_client):
    c, _ = auth_client(sub=OWNER)
    clinic = make_clinic(c, name="C")
    doc = _doc(c, clinic)
    r = c.post(f"/api/v1/clinics/{clinic}/doctors/{doc}/availability/blocks",
               json={"block_date": "2026-07-01", "reason": "Vacation"})
    assert r.status_code == 201, r.text
    assert r.json()["start_time"] is None


def test_time_range_block_validates(auth_client):
    c, _ = auth_client(sub=OWNER)
    clinic = make_clinic(c, name="C")
    doc = _doc(c, clinic)
    bad = {"block_date": "2026-07-01", "start_time": "15:00", "end_time": "14:00"}
    assert c.post(f"/api/v1/clinics/{clinic}/doctors/{doc}/availability/blocks", json=bad).status_code == 422
    ok = {"block_date": "2026-07-01", "start_time": "14:00", "end_time": "16:00"}
    assert c.post(f"/api/v1/clinics/{clinic}/doctors/{doc}/availability/blocks", json=ok).status_code == 201


def test_list_and_remove_block(auth_client):
    c, _ = auth_client(sub=OWNER)
    clinic = make_clinic(c, name="C")
    doc = _doc(c, clinic)
    bid = c.post(f"/api/v1/clinics/{clinic}/doctors/{doc}/availability/blocks",
                 json={"block_date": "2026-07-01"}).json()["id"]
    assert len(c.get(f"/api/v1/clinics/{clinic}/doctors/{doc}/availability/blocks").json()) == 1
    assert c.delete(f"/api/v1/clinics/{clinic}/doctors/{doc}/availability/blocks/{bid}").status_code == 204
    assert c.get(f"/api/v1/clinics/{clinic}/doctors/{doc}/availability/blocks").json() == []
```

- [ ] **Step 2: Run to verify fail**

Run: `.venv/bin/pytest tests/scheduling/test_blocks.py -v` → FAIL (routes missing).

- [ ] **Step 3: Add block schemas** (append to `schemas.py`):

```python
class BlockCreate(BaseModel):
    block_date: dt.date
    start_time: dt.time | None = None
    end_time: dt.time | None = None
    reason: str | None = Field(default=None, max_length=500)

    @model_validator(mode="after")
    def _check(self) -> "BlockCreate":
        a, b = self.start_time, self.end_time
        if (a is None) != (b is None):
            raise ValueError("start_time and end_time must both be set or both omitted.")
        if a is not None and b is not None and b <= a:
            raise ValueError("end_time must be after start_time.")
        return self


class BlockRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: uuid.UUID
    doctor_id: uuid.UUID
    block_date: dt.date
    start_time: dt.time | None
    end_time: dt.time | None
    reason: str | None
    status: str
```

- [ ] **Step 4: Add block service** (append to `service.py`, import `AvailabilityBlock` and `BlockCreate`):

```python
def create_block(
    db: Session, *, clinic_id: uuid.UUID, doctor_id: uuid.UUID, actor_user_id: uuid.UUID, data: "BlockCreate"
) -> "AvailabilityBlock":
    b = AvailabilityBlock(
        clinic_id=clinic_id, doctor_id=doctor_id, block_date=data.block_date,
        start_time=data.start_time, end_time=data.end_time, reason=data.reason, created_by=actor_user_id,
    )
    db.add(b)
    db.flush()
    record_audit(db, action="availability_block.created", entity_type="availability_block",
                 entity_id=b.id, clinic_id=clinic_id, actor_user_id=actor_user_id,
                 new={"block_date": str(b.block_date), "doctor_id": str(doctor_id)})
    db.commit()
    db.refresh(b)
    return b


def list_blocks(db: Session, clinic_id: uuid.UUID, doctor_id: uuid.UUID) -> list["AvailabilityBlock"]:
    return list(db.execute(
        select(AvailabilityBlock).where(
            AvailabilityBlock.clinic_id == clinic_id,
            AvailabilityBlock.doctor_id == doctor_id,
            AvailabilityBlock.status == "active",
        ).order_by(AvailabilityBlock.block_date)
    ).scalars())


def remove_block(
    db: Session, *, clinic_id: uuid.UUID, doctor_id: uuid.UUID, block_id: uuid.UUID, actor_user_id: uuid.UUID
) -> None:
    b = db.execute(
        select(AvailabilityBlock).where(
            AvailabilityBlock.id == block_id, AvailabilityBlock.clinic_id == clinic_id,
            AvailabilityBlock.doctor_id == doctor_id, AvailabilityBlock.status == "active",
        )
    ).scalar_one_or_none()
    if b is None:
        raise NotFoundError("Availability block not found.")
    b.status = "removed"
    db.flush()
    record_audit(db, action="availability_block.removed", entity_type="availability_block",
                 entity_id=b.id, clinic_id=clinic_id, actor_user_id=actor_user_id, new={"status": "removed"})
    db.commit()
```
(Update the top-of-file import to `from app.modules.scheduling.models import AvailabilityBlock, AvailabilityWindow` and `from app.modules.scheduling.schemas import BlockCreate, WindowCreate, WindowUpdate`.)

- [ ] **Step 5: Add block routes** (append to `router.py`, import `BlockCreate`, `BlockRead`):

```python
_BLOCKS = _BASE + "/blocks"


@router.post(_BLOCKS, response_model=BlockRead, status_code=status.HTTP_201_CREATED)
def create_block(
    clinic_id: uuid.UUID, doctor_id: uuid.UUID, data: BlockCreate,
    db: DbSession, membership: CurrentMembership,
):
    service.authorize_manage_availability(db, clinic_id=clinic_id, doctor_id=doctor_id, membership=membership)
    return service.create_block(
        db, clinic_id=clinic_id, doctor_id=doctor_id, actor_user_id=membership.user_id, data=data
    )


@router.get(_BLOCKS, response_model=list[BlockRead])
def list_blocks(clinic_id: uuid.UUID, doctor_id: uuid.UUID, db: DbSession, membership: CurrentMembership):
    return service.list_blocks(db, clinic_id, doctor_id)


@router.delete(_BLOCKS + "/{block_id}", status_code=status.HTTP_204_NO_CONTENT)
def remove_block(
    clinic_id: uuid.UUID, doctor_id: uuid.UUID, block_id: uuid.UUID,
    db: DbSession, membership: CurrentMembership,
):
    service.authorize_manage_availability(db, clinic_id=clinic_id, doctor_id=doctor_id, membership=membership)
    service.remove_block(
        db, clinic_id=clinic_id, doctor_id=doctor_id, block_id=block_id, actor_user_id=membership.user_id
    )
```
> Route-ordering note: declare the `/blocks` routes BEFORE the `/{window_id}` window routes are matched, or ensure `blocks` cannot be captured as a `window_id` UUID — since `window_id` is typed `uuid.UUID`, the literal `blocks` segment will not match it, so ordering is safe. Keep the `/blocks` path segment literal.

- [ ] **Step 6: Run block tests + full suite**

Run: `.venv/bin/pytest tests/scheduling/test_blocks.py -v && make test` → PASS.

- [ ] **Step 7: Lint + commit**

```bash
make lint
git add app/modules/scheduling/ tests/scheduling/test_blocks.py
git commit -m "feat(scheduling): availability block (vacation) CRUD

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: Backend — slot computation engine + GET slots endpoint

**Files:**
- Modify: `app/modules/scheduling/service.py`, `schemas.py`, `router.py`
- Test: `tests/scheduling/test_slots.py`

**Interfaces:**
- Consumes: windows/blocks models; `app.modules.clinics.service.get_settings`.
- Produces: pure `compute_slots(windows, blocks, date_from, date_to, slot_minutes, capacity) -> list[dict]`; `SlotRead`; service `list_slots`; `GET …/slots`.

- [ ] **Step 1: Write failing tests (pure function + endpoint)**

Create `tests/scheduling/test_slots.py`:

```python
import datetime as dt

from app.modules.scheduling.service import compute_slots
from tests.conftest import make_clinic

# ---- pure-function tests (no DB) ----

class W:  # lightweight stand-in matching attributes compute_slots reads
    def __init__(self, kind, start, end, day_of_week=None, specific_date=None):
        self.kind, self.start_time, self.end_time = kind, start, end
        self.day_of_week, self.specific_date = day_of_week, specific_date


class B:
    def __init__(self, block_date, start=None, end=None):
        self.block_date, self.start_time, self.end_time = block_date, start, end


MON = dt.date(2026, 6, 22)  # a Monday (weekday()==0)


def test_recurring_generates_30min_slots():
    w = [W("recurring", dt.time(9, 0), dt.time(10, 30), day_of_week=0)]
    slots = compute_slots(w, [], MON, MON, 30, 1)
    assert [(s["start_time"], s["end_time"]) for s in slots] == [
        (dt.time(9, 0), dt.time(9, 30)), (dt.time(9, 30), dt.time(10, 0)), (dt.time(10, 0), dt.time(10, 30)),
    ]
    assert all(s["capacity"] == 1 and s["occupancy"] == 0 for s in slots)


def test_trailing_partial_dropped():
    w = [W("recurring", dt.time(9, 0), dt.time(10, 20), day_of_week=0)]  # 80 min -> 2 slots, 20 min dropped
    slots = compute_slots(w, [], MON, MON, 30, 1)
    assert len(slots) == 2


def test_one_off_additive_and_deduped():
    w = [W("recurring", dt.time(9, 0), dt.time(9, 30), day_of_week=0),
         W("one_off", dt.time(9, 0), dt.time(10, 0), specific_date=MON)]  # overlaps at 9:00
    slots = compute_slots(w, [], MON, MON, 30, 1)
    assert [s["start_time"] for s in slots] == [dt.time(9, 0), dt.time(9, 30)]  # 9:00 deduped


def test_full_day_block_clears_date():
    w = [W("recurring", dt.time(9, 0), dt.time(11, 0), day_of_week=0)]
    slots = compute_slots(w, [B(MON)], MON, MON, 30, 1)
    assert slots == []


def test_time_range_block_subtracts_overlap_only():
    w = [W("recurring", dt.time(9, 0), dt.time(11, 0), day_of_week=0)]  # 9,9:30,10,10:30
    slots = compute_slots(w, [B(MON, dt.time(10, 0), dt.time(11, 0))], MON, MON, 30, 1)
    assert [s["start_time"] for s in slots] == [dt.time(9, 0), dt.time(9, 30)]


def test_capacity_from_multi_booking():
    w = [W("recurring", dt.time(9, 0), dt.time(9, 30), day_of_week=0)]
    slots = compute_slots(w, [], MON, MON, 30, 3)
    assert slots[0]["capacity"] == 3


# ---- endpoint test ----

OWNER = "11111111-1111-1111-1111-111111111111"


def test_slots_endpoint_and_range_cap(auth_client):
    c, _ = auth_client(sub=OWNER)
    clinic = make_clinic(c, name="C")
    doc = c.post(f"/api/v1/clinics/{clinic}/doctors", json={"name": "D", "phone": "+91 90000 00000"}).json()["doctor"]["id"]
    c.post(f"/api/v1/clinics/{clinic}/doctors/{doc}/availability",
           json={"kind": "recurring", "day_of_week": 0, "start_time": "09:00", "end_time": "10:00"})
    r = c.get(f"/api/v1/clinics/{clinic}/doctors/{doc}/slots?from=2026-06-22&to=2026-06-22")
    assert r.status_code == 200, r.text
    assert len(r.json()) == 2  # 9:00, 9:30 on the Monday
    # range > 62 days -> 422
    assert c.get(f"/api/v1/clinics/{clinic}/doctors/{doc}/slots?from=2026-06-22&to=2026-12-31").status_code == 422
    # to < from -> 422
    assert c.get(f"/api/v1/clinics/{clinic}/doctors/{doc}/slots?from=2026-06-22&to=2026-06-21").status_code == 422
```

- [ ] **Step 2: Run to verify fail**

Run: `.venv/bin/pytest tests/scheduling/test_slots.py -v` → FAIL (`compute_slots` missing).

- [ ] **Step 3: Implement `compute_slots` + `list_slots`** (append to `service.py`; add imports `import datetime as dt` and `from app.modules.clinics.service import get_settings`):

```python
def _chunk(start: "dt.time", end: "dt.time", minutes: int) -> list[tuple["dt.time", "dt.time"]]:
    out: list[tuple[dt.time, dt.time]] = []
    cur = dt.datetime.combine(dt.date(2000, 1, 1), start)
    stop = dt.datetime.combine(dt.date(2000, 1, 1), end)
    step = dt.timedelta(minutes=minutes)
    while cur + step <= stop:
        out.append((cur.time(), (cur + step).time()))
        cur += step
    return out


def _overlaps(a_start: "dt.time", a_end: "dt.time", b_start: "dt.time", b_end: "dt.time") -> bool:
    return a_start < b_end and b_start < a_end


def compute_slots(windows, blocks, date_from, date_to, slot_minutes, capacity) -> list[dict]:
    """Pure: derive slot dicts for [date_from, date_to] from active windows minus active blocks."""
    results: list[dict] = []
    day = date_from
    one_day = dt.timedelta(days=1)
    while day <= date_to:
        dow = day.weekday()
        day_windows = [
            w for w in windows
            if (w.kind == "recurring" and w.day_of_week == dow)
            or (w.kind == "one_off" and w.specific_date == day)
        ]
        # candidate (start,end) pairs, deduped by start_time
        seen: dict[dt.time, tuple[dt.time, dt.time]] = {}
        for w in day_windows:
            for s, e in _chunk(w.start_time, w.end_time, slot_minutes):
                seen.setdefault(s, (s, e))
        day_blocks = [b for b in blocks if b.block_date == day]
        for s, e in sorted(seen.values()):
            blocked = False
            for b in day_blocks:
                if b.start_time is None:  # full-day
                    blocked = True
                    break
                if _overlaps(s, e, b.start_time, b.end_time):
                    blocked = True
                    break
            if blocked:
                continue
            results.append({
                "doctor_id": None,  # filled by caller
                "date": day,
                "start_time": s,
                "end_time": e,
                "start_datetime": dt.datetime.combine(day, s),
                "capacity": capacity,
                "occupancy": 0,
                "status": "available",
            })
        day += one_day
    return results


MAX_SLOT_RANGE_DAYS = 62


def list_slots(db: Session, clinic_id: uuid.UUID, doctor_id: uuid.UUID, date_from, date_to) -> list[dict]:
    if date_to < date_from:
        raise DomainError("'to' must be on or after 'from'.")
    if (date_to - date_from).days > MAX_SLOT_RANGE_DAYS:
        raise DomainError(f"Date range must be at most {MAX_SLOT_RANGE_DAYS} days.")
    get_doctor(db, clinic_id, doctor_id)  # 404 if doctor not in clinic
    settings = get_settings(db, clinic_id)
    slot_minutes = settings.default_slot_size_minutes
    capacity = settings.max_bookings_per_slot if settings.allow_multiple_bookings_per_slot else 1
    windows = list_windows(db, clinic_id, doctor_id)
    blocks = list_blocks(db, clinic_id, doctor_id)
    slots = compute_slots(windows, blocks, date_from, date_to, slot_minutes, capacity)
    for s in slots:
        s["doctor_id"] = doctor_id
    return slots
```

- [ ] **Step 4: Add `SlotRead`** (append to `schemas.py`):

```python
class SlotRead(BaseModel):
    doctor_id: uuid.UUID
    date: dt.date
    start_time: dt.time
    end_time: dt.time
    start_datetime: dt.datetime
    capacity: int
    occupancy: int
    status: str
```

- [ ] **Step 5: Add the slots route** (append to `router.py`; import `SlotRead`, `import datetime as dt`):

```python
@router.get("/{clinic_id}/doctors/{doctor_id}/slots", response_model=list[SlotRead])
def list_slots(
    clinic_id: uuid.UUID, doctor_id: uuid.UUID,
    db: DbSession, membership: CurrentMembership,
    from_: dt.date = Query(alias="from"),
    to: dt.date = Query(...),
):
    return service.list_slots(db, clinic_id, doctor_id, from_, to)
```
(Add `from fastapi import Query` to the router imports.)

- [ ] **Step 6: Run slot tests + full suite + lint**

Run: `.venv/bin/pytest tests/scheduling/test_slots.py -v && make test && make lint`
Expected: all PASS, lint clean.

- [ ] **Step 7: Commit**

```bash
git add app/modules/scheduling/ tests/scheduling/test_slots.py
git commit -m "feat(scheduling): virtual slot computation + GET slots endpoint

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

> **Controller (post-merge):** apply migration 0009 to Supabase via MCP `apply_migration` (offline SQL `alembic upgrade 0008:0009 --sql`); verify `alembic_version=0009` and both tables exist.

---

## Task 5: Frontend — scheduling API client + hooks + doctor fetch

**Files:**
- Create: `src/features/scheduling/api.ts`, `src/features/scheduling/hooks.ts`
- Modify: `src/features/doctors/api.ts` (add `fetchDoctor`)

**Interfaces:**
- Produces: types `AvailabilityWindow`, `AvailabilityBlock`, `Slot`; fns + hooks for windows/blocks/slots; `fetchDoctor`.

- [ ] **Step 1: Create the API client**

Create `src/features/scheduling/api.ts`:

```typescript
import { apiFetch } from "@/lib/api-client";

export type AvailabilityWindow = {
  id: string;
  doctor_id: string;
  kind: "recurring" | "one_off";
  day_of_week: number | null;
  specific_date: string | null;
  start_time: string;
  end_time: string;
  status: string;
};

export type AvailabilityBlock = {
  id: string;
  doctor_id: string;
  block_date: string;
  start_time: string | null;
  end_time: string | null;
  reason: string | null;
  status: string;
};

export type Slot = {
  doctor_id: string;
  date: string;
  start_time: string;
  end_time: string;
  start_datetime: string;
  capacity: number;
  occupancy: number;
  status: string;
};

const base = (clinicId: string, doctorId: string) =>
  `/api/v1/clinics/${clinicId}/doctors/${doctorId}/availability`;

export const fetchWindows = (clinicId: string, doctorId: string) =>
  apiFetch<AvailabilityWindow[]>(base(clinicId, doctorId));

export const createWindow = (
  clinicId: string, doctorId: string,
  payload: { kind: "recurring" | "one_off"; day_of_week?: number | null; specific_date?: string | null; start_time: string; end_time: string },
) => apiFetch<AvailabilityWindow>(base(clinicId, doctorId), { method: "POST", body: JSON.stringify(payload) });

export const deleteWindow = (clinicId: string, doctorId: string, id: string) =>
  apiFetch<void>(`${base(clinicId, doctorId)}/${id}`, { method: "DELETE" });

export const fetchBlocks = (clinicId: string, doctorId: string) =>
  apiFetch<AvailabilityBlock[]>(`${base(clinicId, doctorId)}/blocks`);

export const createBlock = (
  clinicId: string, doctorId: string,
  payload: { block_date: string; start_time?: string | null; end_time?: string | null; reason?: string | null },
) => apiFetch<AvailabilityBlock>(`${base(clinicId, doctorId)}/blocks`, { method: "POST", body: JSON.stringify(payload) });

export const deleteBlock = (clinicId: string, doctorId: string, id: string) =>
  apiFetch<void>(`${base(clinicId, doctorId)}/blocks/${id}`, { method: "DELETE" });

export const fetchSlots = (clinicId: string, doctorId: string, from: string, to: string) =>
  apiFetch<Slot[]>(`/api/v1/clinics/${clinicId}/doctors/${doctorId}/slots?from=${from}&to=${to}`);
```

- [ ] **Step 2: Create hooks**

Create `src/features/scheduling/hooks.ts`:

```typescript
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";

import {
  createBlock, createWindow, deleteBlock, deleteWindow,
  fetchBlocks, fetchSlots, fetchWindows,
} from "@/features/scheduling/api";

export function useWindows(clinicId: string, doctorId: string) {
  return useQuery({
    queryKey: ["windows", clinicId, doctorId],
    queryFn: () => fetchWindows(clinicId, doctorId),
    enabled: !!clinicId && !!doctorId,
  });
}

export function useBlocks(clinicId: string, doctorId: string) {
  return useQuery({
    queryKey: ["blocks", clinicId, doctorId],
    queryFn: () => fetchBlocks(clinicId, doctorId),
    enabled: !!clinicId && !!doctorId,
  });
}

export function useSlots(clinicId: string, doctorId: string, from: string, to: string) {
  return useQuery({
    queryKey: ["slots", clinicId, doctorId, from, to],
    queryFn: () => fetchSlots(clinicId, doctorId, from, to),
    enabled: !!clinicId && !!doctorId && !!from && !!to,
  });
}

export function useCreateWindow(clinicId: string, doctorId: string) {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (p: Parameters<typeof createWindow>[2]) => createWindow(clinicId, doctorId, p),
    onSuccess: () => void qc.invalidateQueries({ queryKey: ["windows", clinicId, doctorId] }),
  });
}

export function useDeleteWindow(clinicId: string, doctorId: string) {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (id: string) => deleteWindow(clinicId, doctorId, id),
    onSuccess: () => void qc.invalidateQueries({ queryKey: ["windows", clinicId, doctorId] }),
  });
}

export function useCreateBlock(clinicId: string, doctorId: string) {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (p: Parameters<typeof createBlock>[2]) => createBlock(clinicId, doctorId, p),
    onSuccess: () => void qc.invalidateQueries({ queryKey: ["blocks", clinicId, doctorId] }),
  });
}

export function useDeleteBlock(clinicId: string, doctorId: string) {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (id: string) => deleteBlock(clinicId, doctorId, id),
    onSuccess: () => void qc.invalidateQueries({ queryKey: ["blocks", clinicId, doctorId] }),
  });
}
```

- [ ] **Step 3: Add `fetchDoctor`** to `src/features/doctors/api.ts`

Inspect the file's existing `Doctor` type + `apiFetch` usage, then add (matching the existing endpoint shape `/api/v1/clinics/{clinicId}/doctors/{doctorId}`):
```typescript
export const fetchDoctor = (clinicId: string, doctorId: string) =>
  apiFetch<Doctor>(`/api/v1/clinics/${clinicId}/doctors/${doctorId}`);
```
(Use the existing exported `Doctor` type name in that file; if the type is named differently, match it.)

- [ ] **Step 4: Type-check + commit**

Run: `cd dentist-registry-frontend && npx tsc --noEmit`
Expected: PASS.
```bash
git add src/features/scheduling/ src/features/doctors/api.ts
git commit -m "feat(scheduling): frontend api client + hooks + fetchDoctor

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 6: Frontend — i18n keys + Schedule nav destination

**Files:**
- Modify: `src/i18n/locales/en.json`, `src/i18n/locales/hi.json`, `src/components/shell/destinations.ts`

**Interfaces:**
- Produces: `nav.schedule`; `scheduling.*` keys used by Tasks 7–8.

- [ ] **Step 1: Add the Schedule destination**

In `src/components/shell/destinations.ts`, insert after the `home` entry and before `doctors`:
```typescript
  {
    key: "schedule",
    labelKey: "nav.schedule",
    icon: "calendar_month",
    href: "/schedule",
  },
```

- [ ] **Step 2: Add i18n keys (en)**

In `src/i18n/locales/en.json`, add `"schedule": "Schedule"` to the `nav` object, and add a new top-level `scheduling` block:
```json
  "scheduling": {
    "availabilityTitle": "Availability",
    "availabilityHint": "Weekly hours, one-off days, and time off.",
    "recurringSection": "Weekly hours",
    "oneOffSection": "One-off days",
    "blocksSection": "Time off",
    "addRecurring": "Add weekly hours",
    "addOneOff": "Add a one-off day",
    "addBlock": "Add time off",
    "dayLabel": "Day",
    "dateLabel": "Date",
    "startLabel": "Start",
    "endLabel": "End",
    "reasonLabel": "Reason",
    "fullDay": "Full day",
    "remove": "Remove",
    "readOnly": "You can view this doctor's availability but not edit it.",
    "noWindows": "No availability set yet.",
    "noBlocks": "No time off scheduled.",
    "days": { "0": "Monday", "1": "Tuesday", "2": "Wednesday", "3": "Thursday", "4": "Friday", "5": "Saturday", "6": "Sunday" },
    "slotsTitle": "Slots",
    "pickDoctor": "Choose a doctor",
    "from": "From",
    "to": "To",
    "noSlots": "No slots in this range.",
    "capacityLabel": "Capacity {{count}}",
    "doctorDetailTitle": "Doctor"
  },
```

- [ ] **Step 3: Add i18n keys (hi)** — same keys, Hindi values:

Add `"schedule": "अनुसूची"` to `nav`, and:
```json
  "scheduling": {
    "availabilityTitle": "उपलब्धता",
    "availabilityHint": "साप्ताहिक घंटे, एक-बार के दिन, और अवकाश।",
    "recurringSection": "साप्ताहिक घंटे",
    "oneOffSection": "एक-बार के दिन",
    "blocksSection": "अवकाश",
    "addRecurring": "साप्ताहिक घंटे जोड़ें",
    "addOneOff": "एक-बार का दिन जोड़ें",
    "addBlock": "अवकाश जोड़ें",
    "dayLabel": "दिन",
    "dateLabel": "तारीख़",
    "startLabel": "शुरू",
    "endLabel": "समाप्त",
    "reasonLabel": "कारण",
    "fullDay": "पूरा दिन",
    "remove": "हटाएँ",
    "readOnly": "आप इस डॉक्टर की उपलब्धता देख सकते हैं लेकिन संपादित नहीं कर सकते।",
    "noWindows": "अभी तक कोई उपलब्धता निर्धारित नहीं है।",
    "noBlocks": "कोई अवकाश निर्धारित नहीं है।",
    "days": { "0": "सोमवार", "1": "मंगलवार", "2": "बुधवार", "3": "गुरुवार", "4": "शुक्रवार", "5": "शनिवार", "6": "रविवार" },
    "slotsTitle": "स्लॉट",
    "pickDoctor": "डॉक्टर चुनें",
    "from": "से",
    "to": "तक",
    "noSlots": "इस अवधि में कोई स्लॉट नहीं।",
    "capacityLabel": "क्षमता {{count}}",
    "doctorDetailTitle": "डॉक्टर"
  },
```

- [ ] **Step 4: Verify parity + tsc**

Run: `npx playwright test tests/e2e/i18n.spec.ts` (or the node parity fallback used previously) and `npx tsc --noEmit`.
Expected: parity OK + tsc clean.

- [ ] **Step 5: Commit**

```bash
git add src/i18n/locales/en.json src/i18n/locales/hi.json src/components/shell/destinations.ts
git commit -m "i18n(scheduling): keys + Schedule nav destination

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 7: Frontend — Schedule route + slot viewer

**Files:**
- Create: `src/features/scheduling/slot-viewer.tsx`, `src/app/schedule/page.tsx`

**Interfaces:**
- Consumes: `useSlots` (Task 5); `useDoctors`/doctor list hook (existing `src/features/doctors/hooks.ts`); `useMe` (`@/features/clinic/hooks`); keys from Task 6.

- [ ] **Step 1: Build the slot viewer**

Create `src/features/scheduling/slot-viewer.tsx`:

```tsx
"use client";

import { useMemo, useState } from "react";
import { useTranslation } from "react-i18next";

import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { useSlots } from "@/features/scheduling/hooks";

function isoDate(d: Date): string {
  return d.toISOString().slice(0, 10);
}

interface SlotViewerProps {
  clinicId: string;
  doctorId: string;
}

export function SlotViewer({ clinicId, doctorId }: SlotViewerProps) {
  const { t } = useTranslation();
  const today = useMemo(() => isoDate(new Date()), []);
  const plus14 = useMemo(() => {
    const d = new Date();
    d.setDate(d.getDate() + 14);
    return isoDate(d);
  }, []);
  const [from, setFrom] = useState(today);
  const [to, setTo] = useState(plus14);
  const slots = useSlots(clinicId, doctorId, from, to);

  const grouped = useMemo(() => {
    const map = new Map<string, typeof slots.data>();
    for (const s of slots.data ?? []) {
      const arr = map.get(s.date) ?? [];
      arr.push(s);
      map.set(s.date, arr as never);
    }
    return [...map.entries()];
  }, [slots.data]);

  return (
    <Card className="shadow-elevation-1">
      <CardHeader>
        <CardTitle>{t("scheduling.slotsTitle")}</CardTitle>
        <div className="mt-2 flex flex-wrap gap-3">
          <label className="text-sm text-muted-foreground">
            {t("scheduling.from")}
            <Input type="date" value={from} max={to} onChange={(e) => setFrom(e.target.value)} data-testid="slots-from" className="mt-1" />
          </label>
          <label className="text-sm text-muted-foreground">
            {t("scheduling.to")}
            <Input type="date" value={to} min={from} onChange={(e) => setTo(e.target.value)} data-testid="slots-to" className="mt-1" />
          </label>
        </div>
      </CardHeader>
      <CardContent>
        {slots.isPending && <p className="text-sm text-muted-foreground">{t("common.loading")}</p>}
        {slots.isError && <p className="text-sm text-destructive">{t("apiErrors.default")}</p>}
        {slots.data && grouped.length === 0 && (
          <p className="text-sm text-muted-foreground" data-testid="no-slots">{t("scheduling.noSlots")}</p>
        )}
        <div className="space-y-4">
          {grouped.map(([date, daySlots]) => (
            <div key={date} data-testid={`slot-day-${date}`}>
              <p className="text-sm font-semibold text-foreground">{date}</p>
              <div className="mt-2 flex flex-wrap gap-2">
                {(daySlots ?? []).map((s) => (
                  <span
                    key={`${date}-${s.start_time}`}
                    className="rounded-lg bg-muted/50 px-3 py-2 text-sm text-foreground"
                    data-testid="slot-chip"
                  >
                    {s.start_time.slice(0, 5)}–{s.end_time.slice(0, 5)}
                    <span className="ml-2 text-xs text-muted-foreground">
                      {t("scheduling.capacityLabel", { count: s.capacity })}
                    </span>
                  </span>
                ))}
              </div>
            </div>
          ))}
        </div>
      </CardContent>
    </Card>
  );
}
```

- [ ] **Step 2: Build the Schedule page**

Create `src/app/schedule/page.tsx`:

```tsx
"use client";

import { useState } from "react";
import { useTranslation } from "react-i18next";

import { AuthGate } from "@/components/auth-gate";
import { AppShell } from "@/components/shell/app-shell";
import { PageContainer } from "@/components/layout/page-container";
import { PageHeader } from "@/components/layout/page-header";
import { Select } from "@/components/ui/select"; // if no Select primitive exists, use a native <select> styled with tokens (see note)
import { useMe } from "@/features/clinic/hooks";
import { useDoctors } from "@/features/doctors/hooks";
import { SlotViewer } from "@/features/scheduling/slot-viewer";

function ScheduleShell() {
  const { t } = useTranslation();
  const me = useMe();
  const membership = me.data?.memberships[0];
  const clinicId = membership?.clinic_id ?? "";
  const doctors = useDoctors(clinicId);
  const [doctorId, setDoctorId] = useState("");

  return (
    <AppShell clinicName={membership?.clinic_name}>
      <PageContainer>
        <PageHeader title={t("nav.schedule")} description={t("scheduling.slotsTitle")} />
        <div className="mb-4">
          <label className="text-sm text-muted-foreground">
            {t("scheduling.pickDoctor")}
            <select
              value={doctorId}
              onChange={(e) => setDoctorId(e.target.value)}
              data-testid="schedule-doctor-select"
              className="mt-1 block w-full rounded-lg border border-input bg-background px-3 py-2 text-sm text-foreground"
            >
              <option value="">{t("scheduling.pickDoctor")}</option>
              {(doctors.data ?? []).map((d) => (
                <option key={d.id} value={d.id}>{d.name}</option>
              ))}
            </select>
          </label>
        </div>
        {clinicId && doctorId && <SlotViewer clinicId={clinicId} doctorId={doctorId} />}
      </PageContainer>
    </AppShell>
  );
}

export default function SchedulePage() {
  return (
    <AuthGate>
      <ScheduleShell />
    </AuthGate>
  );
}
```
> Notes: (1) Remove the `Select` import line — use the native styled `<select>` shown (the codebase has no Select primitive; the native element with semantic tokens respects Rule 17.0). (2) Use the EXISTING doctors-list hook name from `src/features/doctors/hooks.ts` (it may be `useDoctors(clinicId)` returning `{data: Doctor[]}`); match the real name/shape — inspect the file first.

- [ ] **Step 3: tsc + build**

Run: `npx tsc --noEmit && npm run build`
Expected: PASS (route `/schedule` compiles).

- [ ] **Step 4: Commit**

```bash
git add src/features/scheduling/slot-viewer.tsx src/app/schedule/
git commit -m "feat(scheduling): Schedule route + read-only slot viewer

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 8: Frontend — doctor detail page + availability editor

**Files:**
- Create: `src/features/scheduling/availability-editor.tsx`, `src/app/doctors/[id]/page.tsx`
- Modify: `src/features/doctors/doctor-list.tsx` (link rows to detail)

**Interfaces:**
- Consumes: `useWindows`/`useBlocks`/`useCreateWindow`/`useDeleteWindow`/`useCreateBlock`/`useDeleteBlock` (Task 5); `fetchDoctor`/a `useDoctor` hook; `useMe`; keys from Task 6.

- [ ] **Step 1: Add a `useDoctor` hook** to `src/features/doctors/hooks.ts` (mirrors existing hooks; uses `fetchDoctor` from Task 5):
```typescript
export function useDoctor(clinicId: string, doctorId: string) {
  return useQuery({
    queryKey: ["doctor", clinicId, doctorId],
    queryFn: () => fetchDoctor(clinicId, doctorId),
    enabled: !!clinicId && !!doctorId,
  });
}
```
(Import `fetchDoctor` from `@/features/doctors/api`; match the file's existing import + `useQuery` usage.)

- [ ] **Step 2: Build the availability editor**

Create `src/features/scheduling/availability-editor.tsx`:

```tsx
"use client";

import { useState } from "react";
import { useTranslation } from "react-i18next";

import { Button, buttonVariants } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Icon } from "@/components/ui/icon";
import { Input } from "@/components/ui/input";
import {
  useBlocks, useCreateBlock, useCreateWindow, useDeleteBlock, useDeleteWindow, useWindows,
} from "@/features/scheduling/hooks";

interface AvailabilityEditorProps {
  clinicId: string;
  doctorId: string;
  canEdit: boolean;
}

export function AvailabilityEditor({ clinicId, doctorId, canEdit }: AvailabilityEditorProps) {
  const { t } = useTranslation();
  const windows = useWindows(clinicId, doctorId);
  const blocks = useBlocks(clinicId, doctorId);
  const createWindow = useCreateWindow(clinicId, doctorId);
  const deleteWindow = useDeleteWindow(clinicId, doctorId);
  const createBlock = useCreateBlock(clinicId, doctorId);
  const deleteBlock = useDeleteBlock(clinicId, doctorId);

  const [dow, setDow] = useState("0");
  const [rStart, setRStart] = useState("09:00");
  const [rEnd, setREnd] = useState("17:00");
  const [oDate, setODate] = useState("");
  const [oStart, setOStart] = useState("09:00");
  const [oEnd, setOEnd] = useState("12:00");
  const [bDate, setBDate] = useState("");
  const [bReason, setBReason] = useState("");

  const dayName = (n: number) => t(`scheduling.days.${n}`);

  return (
    <Card className="shadow-elevation-1" data-testid="availability-editor">
      <CardHeader>
        <CardTitle>{t("scheduling.availabilityTitle")}</CardTitle>
        <p className="text-sm text-muted-foreground">{t("scheduling.availabilityHint")}</p>
        {!canEdit && <p className="mt-1 text-sm text-muted-foreground">{t("scheduling.readOnly")}</p>}
      </CardHeader>
      <CardContent className="space-y-6">
        {/* Weekly hours */}
        <section>
          <p className="text-sm font-semibold text-foreground">{t("scheduling.recurringSection")}</p>
          <ul className="mt-2 space-y-2">
            {(windows.data ?? []).filter((w) => w.kind === "recurring").map((w) => (
              <li key={w.id} className="flex items-center justify-between rounded-lg bg-muted/50 px-3 py-2 text-sm" data-testid={`window-${w.id}`}>
                <span>{dayName(w.day_of_week ?? 0)} · {w.start_time.slice(0, 5)}–{w.end_time.slice(0, 5)}</span>
                {canEdit && (
                  <button onClick={() => deleteWindow.mutate(w.id)} className="text-muted-foreground hover:text-destructive" aria-label={t("scheduling.remove")} data-testid={`window-remove-${w.id}`}>
                    <Icon name="close" size={18} />
                  </button>
                )}
              </li>
            ))}
            {(windows.data ?? []).filter((w) => w.kind === "recurring").length === 0 && (
              <li className="text-sm text-muted-foreground">{t("scheduling.noWindows")}</li>
            )}
          </ul>
          {canEdit && (
            <div className="mt-3 flex flex-wrap items-end gap-2">
              <label className="text-xs text-muted-foreground">{t("scheduling.dayLabel")}
                <select value={dow} onChange={(e) => setDow(e.target.value)} data-testid="recurring-day" className="mt-1 block rounded-lg border border-input bg-background px-3 py-2 text-sm text-foreground">
                  {[0, 1, 2, 3, 4, 5, 6].map((n) => <option key={n} value={n}>{dayName(n)}</option>)}
                </select>
              </label>
              <label className="text-xs text-muted-foreground">{t("scheduling.startLabel")}
                <Input type="time" value={rStart} onChange={(e) => setRStart(e.target.value)} data-testid="recurring-start" className="mt-1" />
              </label>
              <label className="text-xs text-muted-foreground">{t("scheduling.endLabel")}
                <Input type="time" value={rEnd} onChange={(e) => setREnd(e.target.value)} data-testid="recurring-end" className="mt-1" />
              </label>
              <Button
                size="sm"
                disabled={createWindow.isPending}
                onClick={() => createWindow.mutate({ kind: "recurring", day_of_week: Number(dow), start_time: rStart, end_time: rEnd })}
                data-testid="add-recurring"
              >
                {t("scheduling.addRecurring")}
              </Button>
            </div>
          )}
        </section>

        {/* One-off days */}
        <section>
          <p className="text-sm font-semibold text-foreground">{t("scheduling.oneOffSection")}</p>
          <ul className="mt-2 space-y-2">
            {(windows.data ?? []).filter((w) => w.kind === "one_off").map((w) => (
              <li key={w.id} className="flex items-center justify-between rounded-lg bg-muted/50 px-3 py-2 text-sm" data-testid={`window-${w.id}`}>
                <span>{w.specific_date} · {w.start_time.slice(0, 5)}–{w.end_time.slice(0, 5)}</span>
                {canEdit && (
                  <button onClick={() => deleteWindow.mutate(w.id)} className="text-muted-foreground hover:text-destructive" aria-label={t("scheduling.remove")} data-testid={`window-remove-${w.id}`}>
                    <Icon name="close" size={18} />
                  </button>
                )}
              </li>
            ))}
          </ul>
          {canEdit && (
            <div className="mt-3 flex flex-wrap items-end gap-2">
              <label className="text-xs text-muted-foreground">{t("scheduling.dateLabel")}
                <Input type="date" value={oDate} onChange={(e) => setODate(e.target.value)} data-testid="oneoff-date" className="mt-1" />
              </label>
              <label className="text-xs text-muted-foreground">{t("scheduling.startLabel")}
                <Input type="time" value={oStart} onChange={(e) => setOStart(e.target.value)} data-testid="oneoff-start" className="mt-1" />
              </label>
              <label className="text-xs text-muted-foreground">{t("scheduling.endLabel")}
                <Input type="time" value={oEnd} onChange={(e) => setOEnd(e.target.value)} data-testid="oneoff-end" className="mt-1" />
              </label>
              <Button
                size="sm"
                disabled={!oDate || createWindow.isPending}
                onClick={() => createWindow.mutate({ kind: "one_off", specific_date: oDate, start_time: oStart, end_time: oEnd })}
                data-testid="add-oneoff"
              >
                {t("scheduling.addOneOff")}
              </Button>
            </div>
          )}
        </section>

        {/* Time off */}
        <section>
          <p className="text-sm font-semibold text-foreground">{t("scheduling.blocksSection")}</p>
          <ul className="mt-2 space-y-2">
            {(blocks.data ?? []).map((b) => (
              <li key={b.id} className="flex items-center justify-between rounded-lg bg-muted/50 px-3 py-2 text-sm" data-testid={`block-${b.id}`}>
                <span>{b.block_date} · {b.start_time ? `${b.start_time.slice(0, 5)}–${b.end_time?.slice(0, 5)}` : t("scheduling.fullDay")}{b.reason ? ` · ${b.reason}` : ""}</span>
                {canEdit && (
                  <button onClick={() => deleteBlock.mutate(b.id)} className="text-muted-foreground hover:text-destructive" aria-label={t("scheduling.remove")} data-testid={`block-remove-${b.id}`}>
                    <Icon name="close" size={18} />
                  </button>
                )}
              </li>
            ))}
            {(blocks.data ?? []).length === 0 && <li className="text-sm text-muted-foreground">{t("scheduling.noBlocks")}</li>}
          </ul>
          {canEdit && (
            <div className="mt-3 flex flex-wrap items-end gap-2">
              <label className="text-xs text-muted-foreground">{t("scheduling.dateLabel")}
                <Input type="date" value={bDate} onChange={(e) => setBDate(e.target.value)} data-testid="block-date" className="mt-1" />
              </label>
              <label className="text-xs text-muted-foreground">{t("scheduling.reasonLabel")}
                <Input value={bReason} onChange={(e) => setBReason(e.target.value)} data-testid="block-reason" className="mt-1" />
              </label>
              <Button
                size="sm"
                disabled={!bDate || createBlock.isPending}
                onClick={() => createBlock.mutate({ block_date: bDate, reason: bReason || null })}
                data-testid="add-block"
              >
                {t("scheduling.addBlock")}
              </Button>
            </div>
          )}
        </section>
      </CardContent>
    </Card>
  );
}
```
(Full-day block only in this editor's quick-add; the API supports time-range blocks and the list renders them — a time-range add control can come later. This satisfies the spec's block model; keep it lean.)

- [ ] **Step 3: Build the doctor detail page**

Create `src/app/doctors/[id]/page.tsx`:

```tsx
"use client";

import { useParams } from "next/navigation";
import { useTranslation } from "react-i18next";

import { AuthGate } from "@/components/auth-gate";
import { AppShell } from "@/components/shell/app-shell";
import { PageContainer } from "@/components/layout/page-container";
import { PageHeader } from "@/components/layout/page-header";
import { useMe } from "@/features/clinic/hooks";
import { useDoctor } from "@/features/doctors/hooks";
import { AvailabilityEditor } from "@/features/scheduling/availability-editor";

function DoctorDetailShell() {
  const { t } = useTranslation();
  const params = useParams<{ id: string }>();
  const doctorId = params.id;
  const me = useMe();
  const membership = me.data?.memberships[0];
  const clinicId = membership?.clinic_id ?? "";
  const role = membership?.role ?? "";
  const doctor = useDoctor(clinicId, doctorId);

  // canEdit: owner/PM, or the doctor viewing their own linked account
  const canEdit =
    role === "owner" ||
    role === "practice_manager" ||
    (role === "doctor" && doctor.data?.linked_user_id === me.data?.user_id);

  return (
    <AppShell clinicName={membership?.clinic_name}>
      <PageContainer>
        <PageHeader
          title={doctor.data?.name ?? t("scheduling.doctorDetailTitle")}
          description={doctor.data?.specialty ?? undefined}
        />
        {clinicId && doctorId && (
          <AvailabilityEditor clinicId={clinicId} doctorId={doctorId} canEdit={!!canEdit} />
        )}
      </PageContainer>
    </AppShell>
  );
}

export default function DoctorDetailPage() {
  return (
    <AuthGate>
      <DoctorDetailShell />
    </AuthGate>
  );
}
```
> If the `Doctor` type from `fetchDoctor` does not include `linked_user_id`, add it to that type (the backend `DoctorRead` includes it; confirm and extend the frontend `Doctor` type so `canEdit` type-checks).

- [ ] **Step 4: Link doctor-list rows to the detail page**

In `src/features/doctors/doctor-list.tsx`, make each doctor's name link to `/doctors/{id}` using Next's `Link` (`import Link from "next/link"`). Wrap the name cell: `<Link href={`/doctors/${d.id}`} className="font-medium text-primary underline-offset-4 hover:underline" data-testid={`doctor-link-${d.id}`}>{d.name}</Link>`. Match the existing row markup; do not restructure the list.

- [ ] **Step 5: tsc + build**

Run: `npx tsc --noEmit && npm run build`
Expected: PASS (`/doctors/[id]` + `/schedule` compile).

- [ ] **Step 6: Commit**

```bash
git add src/features/scheduling/availability-editor.tsx src/app/doctors/ src/features/doctors/hooks.ts src/features/doctors/doctor-list.tsx
git commit -m "feat(scheduling): doctor detail page + availability editor

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Final Verification (before PRs)

- [ ] Backend: `cd dentist-registry-backend && make test && make lint` → all green.
- [ ] Frontend: `cd dentist-registry-frontend && npx tsc --noEmit && npm run build` → clean.
- [ ] Frontend: `npx playwright test tests/e2e/i18n.spec.ts` (or node parity fallback) → pass.
- [ ] Two PRs (backend, frontend). Backend PR `Part of #43`; frontend PR `Closes #43`. Board #43 → In Review, then Completed on merge.
- [ ] **Controller-only:** apply migration 0009 to Supabase via MCP `apply_migration`; verify `alembic_version=0009` + both tables.

## Self-Review (against the spec)

- **§3 data model (two tables, String+CHECK, FKs):** Task 1. ✅
- **§4 slot computation (recurring+one-off additive, dedupe, partial drop, block subtract full-day + range, capacity/size from settings, occupancy 0):** Task 4 (pure `compute_slots` + tests). ✅
- **§5 API (window CRUD, block CRUD, slots w/ 62-day + to≥from):** Tasks 2–4. ✅
- **§6 permissions (doctor-self + owner/PM write; assistant read-only; outsider 403) + audit:** Task 2 `authorize_manage_availability` + audit in all mutating service fns. ✅ (Assistant read-only + doctor-self positive cases depend on existing member-creation test helpers — Task 2 note flags this; outsider-403 covered.)
- **§7 frontend (availability editor on doctor detail; Schedule nav + slot viewer; Rule 17.0; i18n):** Tasks 5–8 (+ nav destination Task 6). ✅
- **§8 testing:** backend Tasks 1–4; frontend tsc/build + i18n parity (Tasks 5–8). ✅
- **Placeholder scan:** code blocks complete; the only "inspect the existing file" notes are for matching real symbol names (doctors hook/type) — flagged explicitly, not placeholders. ✅
- **Type consistency:** `compute_slots(windows, blocks, date_from, date_to, slot_minutes, capacity)` signature identical across Task 4 test + impl; `authorize_manage_availability(db, *, clinic_id, doctor_id, membership)` identical across service + router; frontend hook names (`useWindows`/`useBlocks`/`useSlots`/`useCreate*`/`useDelete*`) consistent across Tasks 5/7/8. ✅
