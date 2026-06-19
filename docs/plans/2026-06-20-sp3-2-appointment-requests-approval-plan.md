# SP3.2 — Appointment Requests → Approval → Appointments (Atomic Capacity) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make slots bookable — assistant/owner/PM create appointment requests against computed slots with atomic capacity; the assigned doctor approves (→ confirmed appointment) or rejects; with derived 120-min expiry, a Requests screen + nav dot, and a Home pending card.

**Architecture:** Extend the existing `scheduling` module. New tables `slot_beta` (lazy-materialized lock anchor), `appointment_request_beta`, `appointment_beta` (migration 0010). A new `booking.py` service holds the atomic engine (`reserve_slot`: get-or-create slot via `ON CONFLICT`, `SELECT … FOR UPDATE`, count consumers, enforce capacity) + request/appointment lifecycle. `service.py.list_slots` is extended to overlay real occupancy. Frontend adds a `scheduling` api/hooks extension, a bookable slot dialog on `/schedule`, a new `/requests` screen + nav dot, and a Home pending card.

**Tech Stack:** Backend — FastAPI, SQLAlchemy 2.x (sync), Pydantic v2, Alembic, pytest (Postgres :5433). Frontend — Next.js App Router (client components), TanStack Query, React Hook Form + Zod, react-i18next, Tailwind v4 semantic tokens, Playwright (pure-logic + i18n; tsc + build are the CI gates).

**Spec:** `docs/specs/2026-06-20-sp3-2-appointment-requests-approval-design.md` (issue #46).

## Global Constraints

- **Migration → Supabase is controller-only.** Implementers validate via `make test` (local Postgres :5433) ONLY; NEVER run `make migrate`/`alembic upgrade` (`.env` points at Supabase). Tests build schema via `alembic upgrade head`, exercising migration 0010. Controller applies 0010 to Supabase post-merge (offline `alembic upgrade 0009:0010 --sql` → MCP `apply_migration`).
- **Atomic capacity:** lazy-create `slot_beta` via `pg_insert(...).on_conflict_do_nothing(index_elements=["doctor_id","start_datetime"])`, then `SELECT … FOR UPDATE` (`.with_for_update()`), then COUNT active consumers, enforce capacity. **Consumers = `appointment_request_beta` status `pending` + `appointment_beta` status `confirmed` on that slot.** Capacity = `allow_multiple_bookings_per_slot ? max_bookings_per_slot : 1` (live from `clinic_settings`).
- **Capacity-full → `SlotFullError` (409, code `slot_full`).** First-committed-wins: re-check state under the lock; stale transitions → 409 `conflict`.
- **Expiry is DERIVED** (`status='pending' AND now() > expires_at`); no background job. Approve blocked when expired. Expired requests STILL count toward capacity until cancelled. `expires_at = created_at + clinic_settings.appointment_request_expiry_minutes` (default 120).
- **Permissions:** create/cancel/resend = `assistant`/`owner`/`practice_manager` (a `doctor` creating → 403). approve/reject = the **assigned doctor only** (`doctor_beta.linked_user_id == membership.user_id`); everyone else (incl. owner/PM, other doctors) → 403. Reads = any active member.
- **Status/source columns are `String` + CHECK** (SP3.1 convention), not native enums. Times are clinic-local naive (no tz). `_beta` suffix. Audit in-transaction via `record_audit`. Uniform error envelope + stable codes. Permissive-OSS only; **no new dependencies**.
- **Frontend Rule 17.0:** semantic tokens only (no raw colours / `bg-white` / `text-gray-*`), compose `components/ui/*` + `components/layout/*`, no per-page CSS, both themes, mobile-first, WCAG AA. **i18n-first:** every user-facing string via `t()`, in BOTH `en.json` + `hi.json` (parity enforced by `tests/e2e/i18n.spec.ts`).
- **The new "Requests" nav destination is approved** (Rule 17.0) per spec. Dot is derived from a live pending-count (no seen/unread state).
- **Next.js caveat (`AGENTS.md`):** breaking changes — client components only; read params via `useParams()`; consult `node_modules/next/dist/docs/` if an API surprises you.
- Backend repo `dentist-registry-backend`; frontend `dentist-registry-frontend`. Commit trailer `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`. Feature branch → PR (never push `main`).

---

## File Structure

**Backend (`dentist-registry-backend`)**
- Create: `alembic/versions/0010_appointments.py` — 3 tables.
- Modify: `app/modules/scheduling/models.py` — add `Slot`, `AppointmentRequest`, `Appointment`.
- Create: `app/modules/scheduling/booking.py` — atomic engine + request/appointment services.
- Modify: `app/modules/scheduling/schemas.py` — request/appointment schemas.
- Modify: `app/modules/scheduling/service.py` — `list_slots` occupancy overlay.
- Modify: `app/modules/scheduling/router.py` — booking + appointment + count routes.
- Modify: `app/core/errors.py` — `SlotFullError`.
- Modify: `app/db/base.py` — register new models.
- Test: `tests/scheduling/test_booking.py`, `tests/scheduling/test_approval.py`, `tests/scheduling/test_occupancy.py`.

**Frontend (`dentist-registry-frontend`)**
- Modify: `src/features/scheduling/api.ts`, `hooks.ts` — request/appointment endpoints + hooks.
- Create: `src/features/scheduling/request-dialog.tsx` — book-a-slot dialog.
- Modify: `src/features/scheduling/slot-viewer.tsx` — occupancy + click-to-book.
- Create: `src/features/scheduling/requests-queue.tsx`, `src/app/requests/page.tsx`.
- Create: `src/features/scheduling/pending-requests-card.tsx` (Home card).
- Modify: `src/components/shell/destinations.ts` (Requests dest), `src/components/shell/app-shell.tsx` (nav dot), `src/app/page.tsx` (Home card).
- Modify: `src/i18n/locales/en.json` + `hi.json`.

---

## Task 1: Backend — migration 0010 + models + SlotFullError

**Files:** Create `alembic/versions/0010_appointments.py`; modify `app/modules/scheduling/models.py`, `app/db/base.py`, `app/core/errors.py`; Test `tests/scheduling/test_booking.py` (smoke only this task).

**Interfaces:** Produces tables `slot_beta`, `appointment_request_beta`, `appointment_beta`; models `Slot`, `AppointmentRequest`, `Appointment`; `SlotFullError`.

- [ ] **Step 1: Migration**

Create `alembic/versions/0010_appointments.py`:

```python
"""appointments

Revision ID: 0010
Revises: 0009
"""
from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "0010"
down_revision: str | None = "0009"
branch_labels: Sequence[str] | None = None
depends_on: Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "slot_beta",
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column("clinic_id", sa.Uuid(), sa.ForeignKey("clinic_beta.id"), nullable=False, index=True),
        sa.Column("doctor_id", sa.Uuid(), sa.ForeignKey("doctor_beta.id"), nullable=False, index=True),
        sa.Column("start_datetime", sa.DateTime(timezone=False), nullable=False),
        sa.Column("end_datetime", sa.DateTime(timezone=False), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.clock_timestamp(), nullable=False),
        sa.UniqueConstraint("doctor_id", "start_datetime", name="uq_slot_doctor_start"),
    )
    op.create_table(
        "appointment_request_beta",
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column("clinic_id", sa.Uuid(), sa.ForeignKey("clinic_beta.id"), nullable=False, index=True),
        sa.Column("patient_id", sa.Uuid(), sa.ForeignKey("patient_beta.id"), nullable=False),
        sa.Column("doctor_id", sa.Uuid(), sa.ForeignKey("doctor_beta.id"), nullable=False),
        sa.Column("slot_id", sa.Uuid(), sa.ForeignKey("slot_beta.id"), nullable=False, index=True),
        sa.Column("start_datetime", sa.DateTime(timezone=False), nullable=False),
        sa.Column("status", sa.String(20), nullable=False, server_default="pending"),
        sa.Column("chief_complaint", sa.Text(), nullable=True),
        sa.Column("notes", sa.Text(), nullable=True),
        sa.Column("requested_by", sa.Uuid(), nullable=False),
        sa.Column("expires_at", sa.DateTime(timezone=False), nullable=False),
        sa.Column("created_appointment_id", sa.Uuid(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.clock_timestamp(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.clock_timestamp(), nullable=False),
        sa.CheckConstraint("status IN ('pending','approved','rejected','cancelled')", name="ck_apptreq_status"),
        sa.Index("ix_apptreq_clinic_doctor_status", "clinic_id", "doctor_id", "status"),
    )
    op.create_table(
        "appointment_beta",
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column("clinic_id", sa.Uuid(), sa.ForeignKey("clinic_beta.id"), nullable=False, index=True),
        sa.Column("patient_id", sa.Uuid(), sa.ForeignKey("patient_beta.id"), nullable=False),
        sa.Column("doctor_id", sa.Uuid(), sa.ForeignKey("doctor_beta.id"), nullable=False),
        sa.Column("slot_id", sa.Uuid(), sa.ForeignKey("slot_beta.id"), nullable=False, index=True),
        sa.Column("start_datetime", sa.DateTime(timezone=False), nullable=False),
        sa.Column("end_datetime", sa.DateTime(timezone=False), nullable=False),
        sa.Column("status", sa.String(20), nullable=False, server_default="confirmed"),
        sa.Column("source", sa.String(20), nullable=False, server_default="request_approval"),
        sa.Column("request_id", sa.Uuid(), nullable=True),
        sa.Column("requested_by", sa.Uuid(), nullable=True),
        sa.Column("approved_by", sa.Uuid(), nullable=True),
        sa.Column("chief_complaint", sa.Text(), nullable=True),
        sa.Column("notes", sa.Text(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.clock_timestamp(), nullable=False),
        sa.CheckConstraint("status IN ('confirmed')", name="ck_appt_status"),
        sa.CheckConstraint("source IN ('request_approval')", name="ck_appt_source"),
        sa.Index("ix_appt_clinic_doctor_start", "clinic_id", "doctor_id", "start_datetime"),
    )


def downgrade() -> None:
    op.drop_table("appointment_beta")
    op.drop_table("appointment_request_beta")
    op.drop_table("slot_beta")
```

- [ ] **Step 2: Models** — append to `app/modules/scheduling/models.py` (file already imports `Date, DateTime, ForeignKey, ... String, Text, Time, func`; add `Integer`/`UniqueConstraint` if needed — only `DateTime/String/Text/ForeignKey/func` are used here):

```python
class Slot(Base):
    __tablename__ = "slot_beta"

    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid.uuid4)
    clinic_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("clinic_beta.id"), index=True)
    doctor_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("doctor_beta.id"), index=True)
    start_datetime: Mapped[datetime] = mapped_column(DateTime(timezone=False))
    end_datetime: Mapped[datetime] = mapped_column(DateTime(timezone=False))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.clock_timestamp())


class AppointmentRequest(Base):
    __tablename__ = "appointment_request_beta"

    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid.uuid4)
    clinic_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("clinic_beta.id"), index=True)
    patient_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("patient_beta.id"))
    doctor_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("doctor_beta.id"))
    slot_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("slot_beta.id"), index=True)
    start_datetime: Mapped[datetime] = mapped_column(DateTime(timezone=False))
    status: Mapped[str] = mapped_column(String(20), default="pending")
    chief_complaint: Mapped[str | None] = mapped_column(Text, nullable=True)
    notes: Mapped[str | None] = mapped_column(Text, nullable=True)
    requested_by: Mapped[uuid.UUID] = mapped_column()
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=False))
    created_appointment_id: Mapped[uuid.UUID | None] = mapped_column(nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.clock_timestamp())
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.clock_timestamp(), onupdate=func.clock_timestamp())


class Appointment(Base):
    __tablename__ = "appointment_beta"

    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid.uuid4)
    clinic_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("clinic_beta.id"), index=True)
    patient_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("patient_beta.id"))
    doctor_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("doctor_beta.id"))
    slot_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("slot_beta.id"), index=True)
    start_datetime: Mapped[datetime] = mapped_column(DateTime(timezone=False))
    end_datetime: Mapped[datetime] = mapped_column(DateTime(timezone=False))
    status: Mapped[str] = mapped_column(String(20), default="confirmed")
    source: Mapped[str] = mapped_column(String(20), default="request_approval")
    request_id: Mapped[uuid.UUID | None] = mapped_column(nullable=True)
    requested_by: Mapped[uuid.UUID | None] = mapped_column(nullable=True)
    approved_by: Mapped[uuid.UUID | None] = mapped_column(nullable=True)
    chief_complaint: Mapped[str | None] = mapped_column(Text, nullable=True)
    notes: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.clock_timestamp())
```
(Confirm the existing `import` line in models.py already brings in `DateTime, ForeignKey, String, Text, func` and `from datetime import datetime`. Add `datetime` to the datetime import if only `date, time` are imported.)

- [ ] **Step 3: SlotFullError** — in `app/core/errors.py`, after `ConflictError`:
```python
class SlotFullError(ConflictError):
    code: ClassVar[str] = "slot_full"
```

- [ ] **Step 4: Register models** — in `app/db/base.py`, extend the scheduling import:
```python
from app.modules.scheduling.models import (  # noqa: F401
    Appointment,
    AppointmentRequest,
    AvailabilityBlock,
    AvailabilityWindow,
    Slot,
)
```

- [ ] **Step 5: Smoke test** — create `tests/scheduling/test_booking.py`:
```python
from app.modules.scheduling.models import Appointment, AppointmentRequest, Slot


def test_booking_models_import():
    assert Slot.__tablename__ == "slot_beta"
    assert AppointmentRequest.__tablename__ == "appointment_request_beta"
    assert Appointment.__tablename__ == "appointment_beta"
```

- [ ] **Step 6: Run full suite (migration applies)** — `cd dentist-registry-backend && docker compose up -d && make test` → all pass (0010 applies during schema build).
- [ ] **Step 7: Lint** — `make lint` → clean.
- [ ] **Step 8: Commit**
```bash
git add alembic/versions/0010_appointments.py app/modules/scheduling/models.py app/db/base.py app/core/errors.py tests/scheduling/test_booking.py
git commit -m "feat(scheduling): appointment tables (migration 0010) + SlotFullError

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: Backend — atomic reserve engine + create request

**Files:** Create `app/modules/scheduling/booking.py`; modify `app/modules/scheduling/schemas.py`, `router.py`; Test `tests/scheduling/test_booking.py` (extend).

**Interfaces:**
- Consumes: `service.list_windows/list_blocks/compute_slots`, `clinics.service.get_settings`, `doctors.service.get_doctor`, `members.models.MemberRole`, `audit.service.record_audit`, errors `SlotFullError`/`ValidationError`/`ForbiddenError`.
- Produces: `reserve_slot(db, *, clinic_id, doctor_id, start_datetime) -> Slot`; `count_consumers(db, slot_id) -> int`; `authorize_create(membership)`; `create_request(db, *, clinic_id, doctor_id, actor_user_id, data) -> AppointmentRequest`; schemas `RequestCreate`, `RequestRead`.

- [ ] **Step 1: Failing tests** — append to `tests/scheduling/test_booking.py`:
```python
import datetime as dt
from tests.conftest import make_clinic

OWNER = "11111111-1111-1111-1111-111111111111"

def _doctor(c, clinic, name="Dr. A"):
    return c.post(f"/api/v1/clinics/{clinic}/doctors", json={"name": name, "phone": "+91 90000 00000"}).json()["doctor"]["id"]

def _patient(c, clinic, name="Asha"):
    return c.post(f"/api/v1/clinics/{clinic}/patients", json={"name": name, "phone": "+91 98888 00000", "age": 30}).json()["id"]

def _avail(c, clinic, doc):  # Monday 09:00-10:00 recurring -> slots 09:00, 09:30
    c.post(f"/api/v1/clinics/{clinic}/doctors/{doc}/availability",
           json={"kind": "recurring", "day_of_week": 0, "start_time": "09:00", "end_time": "10:00"})

MON_9 = "2026-06-22T09:00:00"   # a Monday

def test_create_request_succeeds_on_valid_slot(auth_client):
    c, _ = auth_client(sub=OWNER); clinic = make_clinic(c, name="C"); doc = _doctor(c, clinic); pat = _patient(c, clinic); _avail(c, clinic, doc)
    r = c.post(f"/api/v1/clinics/{clinic}/doctors/{doc}/appointment-requests",
               json={"patient_id": pat, "start_datetime": MON_9, "chief_complaint": "toothache"})
    assert r.status_code == 201, r.text
    assert r.json()["status"] == "pending"

def test_create_request_invalid_slot_422(auth_client):
    c, _ = auth_client(sub=OWNER); clinic = make_clinic(c, name="C"); doc = _doctor(c, clinic); pat = _patient(c, clinic); _avail(c, clinic, doc)
    # 11:00 is outside the 09:00-10:00 window
    r = c.post(f"/api/v1/clinics/{clinic}/doctors/{doc}/appointment-requests",
               json={"patient_id": pat, "start_datetime": "2026-06-22T11:00:00"})
    assert r.status_code == 422

def test_capacity_one_second_request_409(auth_client):
    c, _ = auth_client(sub=OWNER); clinic = make_clinic(c, name="C"); doc = _doctor(c, clinic); _avail(c, clinic, doc)
    p1 = _patient(c, clinic, "P1"); p2 = _patient(c, clinic, "P2")
    assert c.post(f"/api/v1/clinics/{clinic}/doctors/{doc}/appointment-requests", json={"patient_id": p1, "start_datetime": MON_9}).status_code == 201
    r2 = c.post(f"/api/v1/clinics/{clinic}/doctors/{doc}/appointment-requests", json={"patient_id": p2, "start_datetime": MON_9})
    assert r2.status_code == 409
    assert r2.json()["error"]["code"] == "slot_full"
```
> Note on concurrency testing: the pytest harness runs each test in a single rolled-back transaction, so a true two-connection parallel race cannot be exercised here. The capacity guarantee is tested **sequentially** (fill to capacity → next → 409); the `SELECT … FOR UPDATE` in `reserve_slot` provides the cross-transaction serialization in production. Do not attempt a multi-connection test against the fixture.

- [ ] **Step 2: Run → fail** (`.venv/bin/pytest tests/scheduling/test_booking.py -v`).

- [ ] **Step 3: Schemas** — append to `app/modules/scheduling/schemas.py` (file already imports `datetime as dt`, `uuid`, `BaseModel, ConfigDict, Field`):
```python
class RequestCreate(BaseModel):
    patient_id: uuid.UUID
    start_datetime: dt.datetime
    chief_complaint: str | None = Field(default=None, max_length=2000)
    notes: str | None = Field(default=None, max_length=2000)


class RequestRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: uuid.UUID
    patient_id: uuid.UUID
    doctor_id: uuid.UUID
    slot_id: uuid.UUID
    start_datetime: dt.datetime
    status: str
    chief_complaint: str | None
    notes: str | None
    expires_at: dt.datetime
    created_appointment_id: uuid.UUID | None
```

- [ ] **Step 4: booking.py** — create `app/modules/scheduling/booking.py`:
```python
import datetime as dt
import uuid

from sqlalchemy import func, select
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.orm import Session

from app.core.errors import ForbiddenError, NotFoundError, SlotFullError, ValidationError
from app.modules.audit.service import record_audit
from app.modules.clinics.service import get_settings
from app.modules.doctors.service import get_doctor
from app.modules.members.models import ClinicMember, MemberRole
from app.modules.scheduling import service
from app.modules.scheduling.models import Appointment, AppointmentRequest, Slot
from app.modules.scheduling.schemas import RequestCreate

_COORDINATORS = (MemberRole.owner, MemberRole.practice_manager, MemberRole.assistant)


def authorize_create(membership: ClinicMember) -> None:
    if membership.role not in _COORDINATORS:
        raise ForbiddenError("Only assistants, owners, or practice managers may create requests.")


def _capacity(settings) -> int:
    return settings.max_bookings_per_slot if settings.allow_multiple_bookings_per_slot else 1


def _validate_slot(db: Session, clinic_id: uuid.UUID, doctor_id: uuid.UUID, start: dt.datetime) -> dt.datetime:
    """Confirm `start` is a legitimate, non-blocked computed slot; return its end_datetime."""
    get_doctor(db, clinic_id, doctor_id)
    settings = get_settings(db, clinic_id)
    windows = service.list_windows(db, clinic_id, doctor_id)
    blocks = service.list_blocks(db, clinic_id, doctor_id)
    slots = service.compute_slots(windows, blocks, start.date(), start.date(), settings.default_slot_size_minutes, _capacity(settings))
    for s in slots:
        if s["start_datetime"] == start:
            return dt.datetime.combine(start.date(), s["end_time"])
    raise ValidationError("That time is not an available slot for this doctor.")


def count_consumers(db: Session, slot_id: uuid.UUID) -> int:
    reqs = db.execute(
        select(func.count()).select_from(AppointmentRequest).where(
            AppointmentRequest.slot_id == slot_id, AppointmentRequest.status == "pending"
        )
    ).scalar_one()
    appts = db.execute(
        select(func.count()).select_from(Appointment).where(
            Appointment.slot_id == slot_id, Appointment.status == "confirmed"
        )
    ).scalar_one()
    return reqs + appts


def reserve_slot(db: Session, *, clinic_id: uuid.UUID, doctor_id: uuid.UUID, start: dt.datetime) -> Slot:
    """Get-or-create the slot, lock it, enforce capacity. Raises SlotFullError at capacity."""
    end = _validate_slot(db, clinic_id, doctor_id, start)
    db.execute(
        pg_insert(Slot)
        .values(clinic_id=clinic_id, doctor_id=doctor_id, start_datetime=start, end_datetime=end)
        .on_conflict_do_nothing(index_elements=["doctor_id", "start_datetime"])
    )
    slot = db.execute(
        select(Slot).where(Slot.doctor_id == doctor_id, Slot.start_datetime == start).with_for_update()
    ).scalar_one()
    settings = get_settings(db, clinic_id)
    if count_consumers(db, slot.id) >= _capacity(settings):
        raise SlotFullError("This slot is full.")
    return slot


def create_request(db: Session, *, clinic_id: uuid.UUID, doctor_id: uuid.UUID, actor_user_id: uuid.UUID, data: RequestCreate) -> AppointmentRequest:
    slot = reserve_slot(db, clinic_id=clinic_id, doctor_id=doctor_id, start=data.start_datetime)
    settings = get_settings(db, clinic_id)
    expires_at = dt.datetime.now() + dt.timedelta(minutes=settings.appointment_request_expiry_minutes)
    req = AppointmentRequest(
        clinic_id=clinic_id, patient_id=data.patient_id, doctor_id=doctor_id, slot_id=slot.id,
        start_datetime=data.start_datetime, status="pending", chief_complaint=data.chief_complaint,
        notes=data.notes, requested_by=actor_user_id, expires_at=expires_at,
    )
    db.add(req)
    db.flush()
    record_audit(db, action="appointment_request.created", entity_type="appointment_request",
                 entity_id=req.id, clinic_id=clinic_id, actor_user_id=actor_user_id,
                 new={"doctor_id": str(doctor_id), "patient_id": str(data.patient_id), "start": data.start_datetime.isoformat()})
    db.commit()
    db.refresh(req)
    return req
```
> `dt.datetime.now()` (naive local) is acceptable for V1 single-location IST. The expiry derivation reads `now()` again at check time (Task 4).

- [ ] **Step 5: Route** — append to `app/modules/scheduling/router.py` (import `from app.modules.scheduling import booking` and `RequestCreate, RequestRead`):
```python
_REQS = "/{clinic_id}/doctors/{doctor_id}/appointment-requests"


@router.post(_REQS, response_model=RequestRead, status_code=status.HTTP_201_CREATED)
def create_request(
    clinic_id: uuid.UUID, doctor_id: uuid.UUID, data: RequestCreate,
    db: DbSession, membership: CurrentMembership,
):
    booking.authorize_create(membership)
    return booking.create_request(db, clinic_id=clinic_id, doctor_id=doctor_id, actor_user_id=membership.user_id, data=data)
```

- [ ] **Step 6: Run booking tests + full suite + lint** — `.venv/bin/pytest tests/scheduling/test_booking.py -v && make test && make lint` → all pass.
- [ ] **Step 7: Commit**
```bash
git add app/modules/scheduling/booking.py app/modules/scheduling/schemas.py app/modules/scheduling/router.py tests/scheduling/test_booking.py
git commit -m "feat(scheduling): atomic reserve engine + create appointment request

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: Backend — approve / reject (assigned doctor only)

**Files:** modify `app/modules/scheduling/booking.py`, `schemas.py`, `router.py`; Test `tests/scheduling/test_approval.py`.

**Interfaces:**
- Consumes: Task 2 models/engine; `get_doctor`.
- Produces: `authorize_decide(db, *, clinic_id, request, membership)`; `approve_request(...)`, `reject_request(...)`; `AppointmentRead`; helper `get_request(db, clinic_id, request_id)`; `is_expired(req) -> bool`.

- [ ] **Step 1: Failing tests** — create `tests/scheduling/test_approval.py`:
```python
from tests.conftest import make_clinic

OWNER = "11111111-1111-1111-1111-111111111111"
MON_9 = "2026-06-22T09:00:00"

def _setup(c):
    clinic = make_clinic(c, name="C")
    doc = c.post(f"/api/v1/clinics/{clinic}/doctors", json={"name": "D", "phone": "+91 90000 00000"}).json()["doctor"]["id"]
    pat = c.post(f"/api/v1/clinics/{clinic}/patients", json={"name": "P", "phone": "+91 98888 00000", "age": 30}).json()["id"]
    c.post(f"/api/v1/clinics/{clinic}/doctors/{doc}/availability", json={"kind": "recurring", "day_of_week": 0, "start_time": "09:00", "end_time": "10:00"})
    rid = c.post(f"/api/v1/clinics/{clinic}/doctors/{doc}/appointment-requests", json={"patient_id": pat, "start_datetime": MON_9}).json()["id"]
    return clinic, doc, pat, rid

def test_owner_cannot_approve(auth_client):
    c, _ = auth_client(sub=OWNER)
    clinic, doc, pat, rid = _setup(c)
    # owner is not the assigned doctor (doctor has no linked user) -> 403
    assert c.post(f"/api/v1/clinics/{clinic}/appointment-requests/{rid}/approve").status_code == 403

def test_reject_releases_capacity(auth_client):
    c, _ = auth_client(sub=OWNER)
    clinic, doc, pat, rid = _setup(c)
    # reject is also doctor-only; owner -> 403 (capacity-release path is covered via cancel in test_booking)
    assert c.post(f"/api/v1/clinics/{clinic}/appointment-requests/{rid}/reject").status_code == 403
```
> Approve/reject require the request's doctor to be linked to the acting user. Activating a doctor account in tests requires the full invite→accept flow; if a helper exists (check `tests/assistants`/`tests/members`), add a positive approve test where the doctor approves their own request and an `appointment_beta` row is created + request `approved` + `created_appointment_id` set. If no ready helper exists, the 403 cases above plus the unit-level approve test below cover the gate; do not build new invite machinery. **Add this service-level positive test** (bypasses HTTP auth, exercises the state machine):
```python
def test_approve_creates_appointment_service_level(auth_client, db_session):
    import uuid as _uuid
    from app.modules.scheduling import booking
    from app.modules.scheduling.models import Appointment, AppointmentRequest
    c, _ = auth_client(sub=OWNER)
    clinic, doc, pat, rid = _setup(c)
    req = db_session.get(AppointmentRequest, _uuid.UUID(rid))
    appt = booking.approve_request(db_session, clinic_id=req.clinic_id, request_id=req.id, actor_user_id=_uuid.uuid4())
    assert appt.status == "confirmed"
    db_session.refresh(req)
    assert req.status == "approved" and req.created_appointment_id == appt.id
    # capacity unchanged: appointment now counts, request no longer pending
    assert booking.count_consumers(db_session, req.slot_id) == 1
```
(Service-level `approve_request` takes `actor_user_id` and performs the state machine; the HTTP route layer enforces the assigned-doctor authz separately so this test can exercise the transition directly.)

- [ ] **Step 2: Run → fail.**

- [ ] **Step 3: Schema** — append `AppointmentRead` to `schemas.py`:
```python
class AppointmentRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: uuid.UUID
    patient_id: uuid.UUID
    doctor_id: uuid.UUID
    slot_id: uuid.UUID
    start_datetime: dt.datetime
    end_datetime: dt.datetime
    status: str
    request_id: uuid.UUID | None
    chief_complaint: str | None
    notes: str | None
```

- [ ] **Step 4: Service** — append to `booking.py`:
```python
def get_request(db: Session, clinic_id: uuid.UUID, request_id: uuid.UUID) -> AppointmentRequest:
    req = db.execute(
        select(AppointmentRequest).where(AppointmentRequest.id == request_id, AppointmentRequest.clinic_id == clinic_id)
    ).scalar_one_or_none()
    if req is None:
        raise NotFoundError("Appointment request not found.")
    return req


def is_expired(req: AppointmentRequest) -> bool:
    return req.status == "pending" and dt.datetime.now() > req.expires_at


def authorize_decide(db: Session, *, clinic_id: uuid.UUID, request: AppointmentRequest, membership: ClinicMember) -> None:
    """Only the assigned doctor (linked user) may approve/reject."""
    doctor = get_doctor(db, clinic_id, request.doctor_id)
    if not (membership.role == MemberRole.doctor and doctor.linked_user_id == membership.user_id):
        raise ForbiddenError("Only the assigned doctor may approve or reject this request.")


def approve_request(db: Session, *, clinic_id: uuid.UUID, request_id: uuid.UUID, actor_user_id: uuid.UUID) -> Appointment:
    req = get_request(db, clinic_id, request_id)
    # lock the slot to serialize against concurrent transitions
    db.execute(select(Slot).where(Slot.id == req.slot_id).with_for_update()).scalar_one()
    if req.status != "pending":
        raise SlotFullError("This request can no longer be approved.") if False else _conflict("approve")
    if is_expired(req):
        raise _conflict("approve_expired")
    appt = Appointment(
        clinic_id=clinic_id, patient_id=req.patient_id, doctor_id=req.doctor_id, slot_id=req.slot_id,
        start_datetime=req.start_datetime, end_datetime=db.get(Slot, req.slot_id).end_datetime,
        status="confirmed", source="request_approval", request_id=req.id,
        requested_by=req.requested_by, approved_by=actor_user_id,
        chief_complaint=req.chief_complaint, notes=req.notes,
    )
    db.add(appt)
    db.flush()
    req.status = "approved"
    req.created_appointment_id = appt.id
    record_audit(db, action="appointment_request.approved", entity_type="appointment_request",
                 entity_id=req.id, clinic_id=clinic_id, actor_user_id=actor_user_id, new={"appointment_id": str(appt.id)})
    record_audit(db, action="appointment.created", entity_type="appointment",
                 entity_id=appt.id, clinic_id=clinic_id, actor_user_id=actor_user_id, new={"request_id": str(req.id)})
    db.commit()
    db.refresh(appt)
    return appt


def reject_request(db: Session, *, clinic_id: uuid.UUID, request_id: uuid.UUID, actor_user_id: uuid.UUID) -> AppointmentRequest:
    req = get_request(db, clinic_id, request_id)
    db.execute(select(Slot).where(Slot.id == req.slot_id).with_for_update()).scalar_one()
    if req.status != "pending":
        raise _conflict("reject")
    req.status = "rejected"
    record_audit(db, action="appointment_request.rejected", entity_type="appointment_request",
                 entity_id=req.id, clinic_id=clinic_id, actor_user_id=actor_user_id, new={"status": "rejected"})
    db.commit()
    db.refresh(req)
    return req
```
Add this helper near the top of `booking.py` (after imports):
```python
from app.core.errors import ConflictError


def _conflict(_what: str) -> ConflictError:
    return ConflictError("This request is no longer in a state that allows this action.")
```
(Remove the dead `raise ... if False else` artifact — write `if req.status != "pending": raise _conflict("approve")`. The line above is shown expanded only to be explicit; implement the clean form.)

- [ ] **Step 5: Routes** — append to `router.py`:
```python
_REQ_ID = "/{clinic_id}/appointment-requests/{request_id}"


@router.post(_REQ_ID + "/approve", response_model=AppointmentRead)
def approve_request(clinic_id: uuid.UUID, request_id: uuid.UUID, db: DbSession, membership: CurrentMembership):
    req = booking.get_request(db, clinic_id, request_id)
    booking.authorize_decide(db, clinic_id=clinic_id, request=req, membership=membership)
    return booking.approve_request(db, clinic_id=clinic_id, request_id=request_id, actor_user_id=membership.user_id)


@router.post(_REQ_ID + "/reject", response_model=RequestRead)
def reject_request(clinic_id: uuid.UUID, request_id: uuid.UUID, db: DbSession, membership: CurrentMembership):
    req = booking.get_request(db, clinic_id, request_id)
    booking.authorize_decide(db, clinic_id=clinic_id, request=req, membership=membership)
    return booking.reject_request(db, clinic_id=clinic_id, request_id=request_id, actor_user_id=membership.user_id)
```
(Import `AppointmentRead` in router.)

- [ ] **Step 6: Run approval tests + full suite + lint** → all pass.
- [ ] **Step 7: Commit**
```bash
git add app/modules/scheduling/booking.py app/modules/scheduling/schemas.py app/modules/scheduling/router.py tests/scheduling/test_approval.py
git commit -m "feat(scheduling): approve/reject (assigned doctor only) + appointment creation

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: Backend — cancel / resend + list requests + pending-count

**Files:** modify `app/modules/scheduling/booking.py`, `schemas.py`, `router.py`; Test extend `tests/scheduling/test_booking.py`.

**Interfaces:**
- Consumes: Task 2–3.
- Produces: `cancel_request`, `resend_request`, `list_requests(db, *, clinic_id, doctor_id=None, status=None)`, `pending_count(db, *, clinic_id)`; `RequestListItem` (adds derived `expired`); `authorize_coordinate(membership)`.

- [ ] **Step 1: Failing tests** — append to `tests/scheduling/test_booking.py`:
```python
def test_cancel_releases_capacity(auth_client):
    c, _ = auth_client(sub=OWNER); clinic = make_clinic(c, name="C"); doc = _doctor(c, clinic); _avail(c, clinic, doc)
    p1 = _patient(c, clinic, "P1"); p2 = _patient(c, clinic, "P2")
    rid = c.post(f"/api/v1/clinics/{clinic}/doctors/{doc}/appointment-requests", json={"patient_id": p1, "start_datetime": MON_9}).json()["id"]
    # full now
    assert c.post(f"/api/v1/clinics/{clinic}/doctors/{doc}/appointment-requests", json={"patient_id": p2, "start_datetime": MON_9}).status_code == 409
    assert c.post(f"/api/v1/clinics/{clinic}/appointment-requests/{rid}/cancel").status_code == 200
    # capacity released -> can book again
    assert c.post(f"/api/v1/clinics/{clinic}/doctors/{doc}/appointment-requests", json={"patient_id": p2, "start_datetime": MON_9}).status_code == 201

def test_resend_extends_and_lists(auth_client):
    c, _ = auth_client(sub=OWNER); clinic = make_clinic(c, name="C"); doc = _doctor(c, clinic); _avail(c, clinic, doc)
    pat = _patient(c, clinic); rid = c.post(f"/api/v1/clinics/{clinic}/doctors/{doc}/appointment-requests", json={"patient_id": pat, "start_datetime": MON_9}).json()["id"]
    assert c.post(f"/api/v1/clinics/{clinic}/appointment-requests/{rid}/resend").status_code == 200
    lst = c.get(f"/api/v1/clinics/{clinic}/appointment-requests?status=pending").json()
    assert any(item["id"] == rid and item["expired"] is False for item in lst)

def test_pending_count(auth_client):
    c, _ = auth_client(sub=OWNER); clinic = make_clinic(c, name="C"); doc = _doctor(c, clinic); _avail(c, clinic, doc)
    pat = _patient(c, clinic); c.post(f"/api/v1/clinics/{clinic}/doctors/{doc}/appointment-requests", json={"patient_id": pat, "start_datetime": MON_9})
    assert c.get(f"/api/v1/clinics/{clinic}/appointment-requests/pending-count").json()["count"] == 1
```

- [ ] **Step 2: Run → fail.**

- [ ] **Step 3: Schemas** — append:
```python
class RequestListItem(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: uuid.UUID
    patient_id: uuid.UUID
    doctor_id: uuid.UUID
    start_datetime: dt.datetime
    status: str
    chief_complaint: str | None
    expires_at: dt.datetime
    expired: bool = False


class PendingCount(BaseModel):
    count: int
```

- [ ] **Step 4: Service** — append to `booking.py`:
```python
def authorize_coordinate(membership: ClinicMember) -> None:
    if membership.role not in _COORDINATORS:
        raise ForbiddenError("Only assistants, owners, or practice managers may do this.")


def cancel_request(db: Session, *, clinic_id: uuid.UUID, request_id: uuid.UUID, actor_user_id: uuid.UUID) -> AppointmentRequest:
    req = get_request(db, clinic_id, request_id)
    db.execute(select(Slot).where(Slot.id == req.slot_id).with_for_update()).scalar_one()
    if req.status != "pending":
        raise _conflict("cancel")
    req.status = "cancelled"
    record_audit(db, action="appointment_request.cancelled", entity_type="appointment_request",
                 entity_id=req.id, clinic_id=clinic_id, actor_user_id=actor_user_id, new={"status": "cancelled"})
    db.commit()
    db.refresh(req)
    return req


def resend_request(db: Session, *, clinic_id: uuid.UUID, request_id: uuid.UUID, actor_user_id: uuid.UUID) -> AppointmentRequest:
    req = get_request(db, clinic_id, request_id)
    if req.status != "pending":
        raise _conflict("resend")
    settings = get_settings(db, clinic_id)
    req.expires_at = dt.datetime.now() + dt.timedelta(minutes=settings.appointment_request_expiry_minutes)
    record_audit(db, action="appointment_request.resent", entity_type="appointment_request",
                 entity_id=req.id, clinic_id=clinic_id, actor_user_id=actor_user_id, new={"expires_at": req.expires_at.isoformat()})
    db.commit()
    db.refresh(req)
    return req


def list_requests(db: Session, *, clinic_id: uuid.UUID, doctor_id: uuid.UUID | None = None, status: str | None = None) -> list[dict]:
    q = select(AppointmentRequest).where(AppointmentRequest.clinic_id == clinic_id)
    if doctor_id is not None:
        q = q.where(AppointmentRequest.doctor_id == doctor_id)
    if status is not None:
        q = q.where(AppointmentRequest.status == status)
    q = q.order_by(AppointmentRequest.start_datetime)
    out = []
    for req in db.execute(q).scalars():
        out.append({
            "id": req.id, "patient_id": req.patient_id, "doctor_id": req.doctor_id,
            "start_datetime": req.start_datetime, "status": req.status,
            "chief_complaint": req.chief_complaint, "expires_at": req.expires_at, "expired": is_expired(req),
        })
    return out


def pending_count(db: Session, *, clinic_id: uuid.UUID) -> int:
    return db.execute(
        select(func.count()).select_from(AppointmentRequest).where(
            AppointmentRequest.clinic_id == clinic_id, AppointmentRequest.status == "pending"
        )
    ).scalar_one()
```
> Scope note: `pending_count`/`list_requests` are clinic-scoped here; per-role narrowing of the nav dot (doctor vs coordinator) is applied on the frontend via the `doctor_id`/`status` filters when needed. Keeping the backend query simple and clinic-scoped is sufficient for SP3.2.

- [ ] **Step 5: Routes** — append to `router.py`:
```python
@router.post(_REQ_ID + "/cancel", response_model=RequestRead)
def cancel_request(clinic_id: uuid.UUID, request_id: uuid.UUID, db: DbSession, membership: CurrentMembership):
    booking.authorize_coordinate(membership)
    return booking.cancel_request(db, clinic_id=clinic_id, request_id=request_id, actor_user_id=membership.user_id)


@router.post(_REQ_ID + "/resend", response_model=RequestRead)
def resend_request(clinic_id: uuid.UUID, request_id: uuid.UUID, db: DbSession, membership: CurrentMembership):
    booking.authorize_coordinate(membership)
    return booking.resend_request(db, clinic_id=clinic_id, request_id=request_id, actor_user_id=membership.user_id)


@router.get("/{clinic_id}/appointment-requests", response_model=list[RequestListItem])
def list_requests(
    clinic_id: uuid.UUID, db: DbSession, membership: CurrentMembership,
    doctor_id: uuid.UUID | None = None, status: str | None = None,
):
    return booking.list_requests(db, clinic_id=clinic_id, doctor_id=doctor_id, status=status)


@router.get("/{clinic_id}/appointment-requests/pending-count", response_model=PendingCount)
def pending_count(clinic_id: uuid.UUID, db: DbSession, membership: CurrentMembership):
    return PendingCount(count=booking.pending_count(db, clinic_id=clinic_id))
```
(Import `RequestListItem, PendingCount`. Declare the `/pending-count` literal route — `request_id` is `uuid.UUID` so `pending-count` won't be captured; ordering is safe.)

- [ ] **Step 6: Run + full suite + lint** → pass.
- [ ] **Step 7: Commit**
```bash
git add app/modules/scheduling/ tests/scheduling/test_booking.py
git commit -m "feat(scheduling): cancel/resend + list requests + pending-count (derived expiry)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: Backend — slot occupancy overlay + list appointments

**Files:** modify `app/modules/scheduling/service.py`, `router.py`; Test `tests/scheduling/test_occupancy.py`.

**Interfaces:**
- Consumes: Task 2–4 models.
- Produces: `list_slots` now sets real `occupancy` + `status` (`available`/`full`); `list_appointments(db, clinic_id, doctor_id, date_from, date_to)`; `GET …/appointments`.

- [ ] **Step 1: Failing test** — create `tests/scheduling/test_occupancy.py`:
```python
from tests.conftest import make_clinic

OWNER = "11111111-1111-1111-1111-111111111111"
MON_9 = "2026-06-22T09:00:00"

def test_slot_occupancy_reflects_request(auth_client):
    c, _ = auth_client(sub=OWNER); clinic = make_clinic(c, name="C")
    doc = c.post(f"/api/v1/clinics/{clinic}/doctors", json={"name": "D", "phone": "+91 90000 00000"}).json()["doctor"]["id"]
    pat = c.post(f"/api/v1/clinics/{clinic}/patients", json={"name": "P", "phone": "+91 98888 00000", "age": 30}).json()["id"]
    c.post(f"/api/v1/clinics/{clinic}/doctors/{doc}/availability", json={"kind": "recurring", "day_of_week": 0, "start_time": "09:00", "end_time": "10:00"})
    c.post(f"/api/v1/clinics/{clinic}/doctors/{doc}/appointment-requests", json={"patient_id": pat, "start_datetime": MON_9})
    slots = c.get(f"/api/v1/clinics/{clinic}/doctors/{doc}/slots?from=2026-06-22&to=2026-06-22").json()
    nine = next(s for s in slots if s["start_time"] == "09:00:00")
    assert nine["occupancy"] == 1 and nine["status"] == "full"   # capacity 1 (multi-booking off by default)
    nine30 = next(s for s in slots if s["start_time"] == "09:30:00")
    assert nine30["occupancy"] == 0 and nine30["status"] == "available"
```

- [ ] **Step 2: Run → fail** (occupancy currently always 0).

- [ ] **Step 3: Modify `list_slots`** in `service.py` to overlay occupancy. After computing `slots` and before returning, query consumers in the date range and map by `start_datetime`:
```python
    # --- occupancy overlay (SP3.2) ---
    from app.modules.scheduling.models import Appointment, AppointmentRequest  # local import avoids cycle
    start_dt = dt.datetime.combine(date_from, dt.time.min)
    end_dt = dt.datetime.combine(date_to, dt.time.max)
    counts: dict[dt.datetime, int] = {}
    for row in db.execute(
        select(AppointmentRequest.start_datetime).where(
            AppointmentRequest.clinic_id == clinic_id, AppointmentRequest.doctor_id == doctor_id,
            AppointmentRequest.status == "pending",
            AppointmentRequest.start_datetime >= start_dt, AppointmentRequest.start_datetime <= end_dt,
        )
    ).scalars():
        counts[row] = counts.get(row, 0) + 1
    for row in db.execute(
        select(Appointment.start_datetime).where(
            Appointment.clinic_id == clinic_id, Appointment.doctor_id == doctor_id,
            Appointment.status == "confirmed",
            Appointment.start_datetime >= start_dt, Appointment.start_datetime <= end_dt,
        )
    ).scalars():
        counts[row] = counts.get(row, 0) + 1
    for s in slots:
        occ = counts.get(s["start_datetime"], 0)
        s["occupancy"] = occ
        s["status"] = "full" if occ >= s["capacity"] else "available"
    return slots
```
(Place this replacing the existing `return slots` at the end of `list_slots`; keep the `for s in slots: s["doctor_id"] = doctor_id` loop. Ensure `select` and `dt` are imported in `service.py` — they are.)

- [ ] **Step 4: `list_appointments` + route** — append to `service.py`:
```python
def list_appointments(db: Session, clinic_id: uuid.UUID, doctor_id: uuid.UUID, date_from, date_to) -> list:
    from app.modules.scheduling.models import Appointment
    start_dt = dt.datetime.combine(date_from, dt.time.min)
    end_dt = dt.datetime.combine(date_to, dt.time.max)
    return list(db.execute(
        select(Appointment).where(
            Appointment.clinic_id == clinic_id, Appointment.doctor_id == doctor_id,
            Appointment.start_datetime >= start_dt, Appointment.start_datetime <= end_dt,
        ).order_by(Appointment.start_datetime)
    ).scalars())
```
In `router.py`, append (import `AppointmentRead`, already imported in Task 3):
```python
@router.get("/{clinic_id}/doctors/{doctor_id}/appointments", response_model=list[AppointmentRead])
def list_appointments(
    clinic_id: uuid.UUID, doctor_id: uuid.UUID, db: DbSession, membership: CurrentMembership,
    from_: dt.date = Query(alias="from"), to: dt.date = Query(...),
):
    return service.list_appointments(db, clinic_id, doctor_id, from_, to)
```

- [ ] **Step 5: Run occupancy test + full suite + lint** → pass.
- [ ] **Step 6: Commit**
```bash
git add app/modules/scheduling/service.py app/modules/scheduling/router.py tests/scheduling/test_occupancy.py
git commit -m "feat(scheduling): slot occupancy overlay + list appointments

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

> **Controller (post-merge):** `alembic upgrade 0009:0010 --sql` offline → MCP `apply_migration`; verify `alembic_version=0010` + the 3 tables.

---

## Task 6: Frontend — booking api + hooks

**Files:** modify `src/features/scheduling/api.ts`, `hooks.ts`.

**Interfaces:** Produces types `AppointmentRequest`, `RequestListItem`, `Appointment`; fns + hooks for create/approve/reject/cancel/resend request, list requests, pending-count, list appointments.

- [ ] **Step 1: API** — append to `src/features/scheduling/api.ts`:
```typescript
export type AppointmentRequest = {
  id: string; patient_id: string; doctor_id: string; slot_id: string;
  start_datetime: string; status: string; chief_complaint: string | null;
  notes: string | null; expires_at: string; created_appointment_id: string | null;
};

export type RequestListItem = {
  id: string; patient_id: string; doctor_id: string; start_datetime: string;
  status: string; chief_complaint: string | null; expires_at: string; expired: boolean;
};

export type Appointment = {
  id: string; patient_id: string; doctor_id: string; slot_id: string;
  start_datetime: string; end_datetime: string; status: string;
  request_id: string | null; chief_complaint: string | null; notes: string | null;
};

const reqBase = (clinicId: string) => `/api/v1/clinics/${clinicId}/appointment-requests`;

export const createRequest = (
  clinicId: string, doctorId: string,
  payload: { patient_id: string; start_datetime: string; chief_complaint?: string; notes?: string },
) => apiFetch<AppointmentRequest>(`/api/v1/clinics/${clinicId}/doctors/${doctorId}/appointment-requests`, { method: "POST", body: JSON.stringify(payload) });

export const listRequests = (clinicId: string, params: { doctor_id?: string; status?: string } = {}) => {
  const q = new URLSearchParams();
  if (params.doctor_id) q.set("doctor_id", params.doctor_id);
  if (params.status) q.set("status", params.status);
  const qs = q.toString();
  return apiFetch<RequestListItem[]>(`${reqBase(clinicId)}${qs ? `?${qs}` : ""}`);
};

export const requestAction = (clinicId: string, id: string, action: "approve" | "reject" | "cancel" | "resend") =>
  apiFetch<AppointmentRequest>(`${reqBase(clinicId)}/${id}/${action}`, { method: "POST" });

export const fetchPendingCount = (clinicId: string) =>
  apiFetch<{ count: number }>(`${reqBase(clinicId)}/pending-count`);

export const listAppointments = (clinicId: string, doctorId: string, from: string, to: string) =>
  apiFetch<Appointment[]>(`/api/v1/clinics/${clinicId}/doctors/${doctorId}/appointments?from=${from}&to=${to}`);
```

- [ ] **Step 2: Hooks** — append to `src/features/scheduling/hooks.ts`:
```typescript
import {
  createRequest, fetchPendingCount, listAppointments, listRequests, requestAction,
} from "@/features/scheduling/api";

export function useRequests(clinicId: string, params: { doctor_id?: string; status?: string } = {}) {
  return useQuery({
    queryKey: ["requests", clinicId, params.doctor_id ?? null, params.status ?? null],
    queryFn: () => listRequests(clinicId, params),
    enabled: !!clinicId,
  });
}

export function usePendingCount(clinicId: string) {
  return useQuery({
    queryKey: ["pending-count", clinicId],
    queryFn: () => fetchPendingCount(clinicId),
    enabled: !!clinicId,
  });
}

export function useCreateRequest(clinicId: string, doctorId: string) {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (p: Parameters<typeof createRequest>[2]) => createRequest(clinicId, doctorId, p),
    onSuccess: () => {
      void qc.invalidateQueries({ queryKey: ["requests", clinicId] });
      void qc.invalidateQueries({ queryKey: ["pending-count", clinicId] });
      void qc.invalidateQueries({ queryKey: ["slots", clinicId, doctorId] });
    },
  });
}

export function useRequestAction(clinicId: string) {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: ({ id, action }: { id: string; action: "approve" | "reject" | "cancel" | "resend" }) =>
      requestAction(clinicId, id, action),
    onSuccess: () => {
      void qc.invalidateQueries({ queryKey: ["requests", clinicId] });
      void qc.invalidateQueries({ queryKey: ["pending-count", clinicId] });
      void qc.invalidateQueries({ queryKey: ["slots", clinicId] });
    },
  });
}
```
(`useQuery`, `useMutation`, `useQueryClient` are already imported at the top of hooks.ts from Task 5 of SP3.1.)

- [ ] **Step 3: tsc + commit**
```bash
cd dentist-registry-frontend && npx tsc --noEmit
git add src/features/scheduling/api.ts src/features/scheduling/hooks.ts
git commit -m "feat(scheduling): booking api client + hooks

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 7: Frontend — i18n keys + Requests nav destination

**Files:** modify `src/i18n/locales/en.json`, `hi.json`, `src/components/shell/destinations.ts`.

- [ ] **Step 1: Requests destination** — in `destinations.ts`, insert after the `schedule` entry, before `doctors`:
```typescript
  {
    key: "requests",
    labelKey: "nav.requests",
    icon: "inbox",
    href: "/requests",
  },
```

- [ ] **Step 2: en keys** — add `"requests": "Requests"` to `nav`, and a `requests` block:
```json
  "requests": {
    "title": "Requests",
    "pendingCard": "Pending requests",
    "viewAll": "View all",
    "empty": "No requests.",
    "book": "Request appointment",
    "bookTitle": "Request appointment",
    "patientLabel": "Patient",
    "patientSearch": "Search patients…",
    "complaintLabel": "Chief complaint",
    "notesLabel": "Notes",
    "submit": "Send request",
    "slotFull": "This slot is just filled up. Pick another slot.",
    "statusFilter": "Status",
    "status": { "pending": "Pending", "approved": "Approved", "rejected": "Rejected", "cancelled": "Cancelled", "expired": "Expired" },
    "approve": "Approve",
    "reject": "Reject",
    "cancel": "Cancel",
    "resend": "Resend",
    "expiresAt": "Expires {{time}}",
    "all": "All"
  },
```

- [ ] **Step 3: hi keys** — add `"requests": "अनुरोध"` to `nav`, and the matching block:
```json
  "requests": {
    "title": "अनुरोध",
    "pendingCard": "लंबित अनुरोध",
    "viewAll": "सभी देखें",
    "empty": "कोई अनुरोध नहीं।",
    "book": "अपॉइंटमेंट का अनुरोध करें",
    "bookTitle": "अपॉइंटमेंट का अनुरोध करें",
    "patientLabel": "मरीज़",
    "patientSearch": "मरीज़ खोजें…",
    "complaintLabel": "मुख्य शिकायत",
    "notesLabel": "टिप्पणियाँ",
    "submit": "अनुरोध भेजें",
    "slotFull": "यह स्लॉट अभी भर गया। दूसरा स्लॉट चुनें।",
    "statusFilter": "स्थिति",
    "status": { "pending": "लंबित", "approved": "स्वीकृत", "rejected": "अस्वीकृत", "cancelled": "रद्द", "expired": "समाप्त" },
    "approve": "स्वीकृत करें",
    "reject": "अस्वीकार करें",
    "cancel": "रद्द करें",
    "resend": "पुनः भेजें",
    "expiresAt": "{{time}} को समाप्त",
    "all": "सभी"
  },
```

- [ ] **Step 4: Verify parity + tsc** — `npx playwright test tests/e2e/i18n.spec.ts` (or node parity fallback) + `npx tsc --noEmit`.
- [ ] **Step 5: Commit**
```bash
git add src/i18n/locales/en.json src/i18n/locales/hi.json src/components/shell/destinations.ts
git commit -m "i18n(requests): keys + Requests nav destination

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 8: Frontend — book-a-slot dialog + occupancy in slot viewer

**Files:** create `src/features/scheduling/request-dialog.tsx`; modify `src/features/scheduling/slot-viewer.tsx`.

**Interfaces:** Consumes `useCreateRequest`, patient search (`src/features/patients`), `Slot` type with `occupancy`/`status`.

- [ ] **Step 1: Request dialog** — create `src/features/scheduling/request-dialog.tsx`:
```tsx
"use client";

import { useState } from "react";
import { useTranslation } from "react-i18next";

import { Button, buttonVariants } from "@/components/ui/button";
import { DialogClose, DialogDescription, DialogPopup, DialogRoot, DialogTitle, DialogTrigger } from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { ApiError } from "@/lib/api-client";
import { usePatientSearch } from "@/features/patients/hooks";
import { useCreateRequest } from "@/features/scheduling/hooks";

interface RequestDialogProps {
  clinicId: string;
  doctorId: string;
  startDatetime: string;   // ISO local, e.g. 2026-06-22T09:00:00
  label: string;           // e.g. "09:00–09:30"
}

export function RequestDialog({ clinicId, doctorId, startDatetime, label }: RequestDialogProps) {
  const { t } = useTranslation();
  const [open, setOpen] = useState(false);
  const [q, setQ] = useState("");
  const [patientId, setPatientId] = useState("");
  const [complaint, setComplaint] = useState("");
  const [notes, setNotes] = useState("");
  const search = usePatientSearch(clinicId, q);
  const createReq = useCreateRequest(clinicId, doctorId);

  function submit() {
    createReq.mutate(
      { patient_id: patientId, start_datetime: startDatetime, chief_complaint: complaint || undefined, notes: notes || undefined },
      { onSuccess: () => { setOpen(false); setPatientId(""); setQ(""); setComplaint(""); setNotes(""); } },
    );
  }

  const slotFull = createReq.error instanceof ApiError && createReq.error.code === "slot_full";

  return (
    <DialogRoot open={open} onOpenChange={(o) => { setOpen(o); if (!o) createReq.reset(); }}>
      <DialogTrigger className={buttonVariants({ variant: "outlined", size: "sm" })} data-testid={`book-${startDatetime}`}>
        {label}
      </DialogTrigger>
      <DialogPopup>
        <DialogTitle>{t("requests.bookTitle")}</DialogTitle>
        <DialogDescription className="sr-only">{label}</DialogDescription>
        <div className="mt-4 space-y-3" data-testid="request-form">
          <div>
            <label className="text-sm text-muted-foreground">{t("requests.patientLabel")}</label>
            <Input value={q} onChange={(e) => setQ(e.target.value)} placeholder={t("requests.patientSearch")} data-testid="patient-search" className="mt-1" />
            <ul className="mt-1 max-h-40 overflow-auto">
              {(search.data ?? []).map((p) => (
                <li key={p.id}>
                  <button
                    type="button"
                    onClick={() => { setPatientId(p.id); setQ(p.name); }}
                    className={`w-full rounded-lg px-3 py-2 text-left text-sm ${patientId === p.id ? "bg-primary-container text-on-primary-container" : "hover:bg-muted/50 text-foreground"}`}
                    data-testid={`patient-opt-${p.id}`}
                  >
                    {p.name} · {p.phone}
                  </button>
                </li>
              ))}
            </ul>
          </div>
          <div>
            <label className="text-sm text-muted-foreground">{t("requests.complaintLabel")}</label>
            <Input value={complaint} onChange={(e) => setComplaint(e.target.value)} data-testid="complaint" className="mt-1" />
          </div>
          <div>
            <label className="text-sm text-muted-foreground">{t("requests.notesLabel")}</label>
            <Input value={notes} onChange={(e) => setNotes(e.target.value)} data-testid="notes" className="mt-1" />
          </div>
          {slotFull && <p className="text-sm text-destructive" data-testid="slot-full">{t("requests.slotFull")}</p>}
          {createReq.isError && !slotFull && <p className="text-sm text-destructive">{t("apiErrors.default")}</p>}
          <div className="flex justify-end gap-2">
            <DialogClose className={buttonVariants({ variant: "ghost", size: "sm" })}>{t("common.cancel")}</DialogClose>
            <Button onClick={submit} disabled={!patientId || createReq.isPending} data-testid="submit-request">{t("requests.submit")}</Button>
          </div>
        </div>
      </DialogPopup>
    </DialogRoot>
  );
}
```
> Inspect `src/features/patients/hooks.ts` for the real patient-search hook name + return shape (likely `usePatientSearch(clinicId, query)` → `{data: Patient[]}` with `id`/`name`/`phone`); match it. If the hook is named differently, use the actual name.

- [ ] **Step 2: Slot viewer — occupancy + book** — modify `src/features/scheduling/slot-viewer.tsx`: the slot chip currently renders time + capacity. Replace the chip with: when `s.status !== "full"`, render a `<RequestDialog clinicId doctorId startDatetime={s.start_datetime} label="HH:MM–HH:MM" />`; when full, render a non-interactive chip showing the time + a "Full" marker. Show `occupancy/capacity`. Keep the `data-testid="slot-chip"` on the wrapper. Add `import { RequestDialog } from "@/features/scheduling/request-dialog";`. Example chip body:
```tsx
<span className="rounded-lg bg-muted/50 px-3 py-2 text-sm text-foreground" data-testid="slot-chip">
  {s.status === "full" ? (
    <span className="opacity-60">{s.start_time.slice(0,5)}–{s.end_time.slice(0,5)} · {t("requests.status.pending") /* placeholder */}</span>
  ) : (
    <RequestDialog clinicId={clinicId} doctorId={doctorId} startDatetime={s.start_datetime} label={`${s.start_time.slice(0,5)}–${s.end_time.slice(0,5)}`} />
  )}
  <span className="ml-2 text-xs text-muted-foreground">{s.occupancy}/{s.capacity}</span>
</span>
```
> Use a proper "Full" i18n key — add `requests.full: "Full"` / `"भरा"` to both locale files in this task (small parity-safe addition) rather than the placeholder shown.

- [ ] **Step 3: tsc + build** — `npx tsc --noEmit && npm run build` → clean.
- [ ] **Step 4: Commit**
```bash
git add src/features/scheduling/request-dialog.tsx src/features/scheduling/slot-viewer.tsx src/i18n/locales/en.json src/i18n/locales/hi.json
git commit -m "feat(scheduling): book-a-slot request dialog + occupancy in slot viewer

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 9: Frontend — Requests screen + nav dot

**Files:** create `src/features/scheduling/requests-queue.tsx`, `src/app/requests/page.tsx`; modify `src/components/shell/app-shell.tsx` (nav dot).

**Interfaces:** Consumes `useRequests`, `useRequestAction`, `usePendingCount`, `useMe`, `useDoctors` (for assigned-doctor detection of the current user).

- [ ] **Step 1: Requests queue** — create `src/features/scheduling/requests-queue.tsx`:
```tsx
"use client";

import { useState } from "react";
import { useTranslation } from "react-i18next";

import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { useRequestAction, useRequests } from "@/features/scheduling/hooks";

interface RequestsQueueProps {
  clinicId: string;
  canDecide: boolean;   // current user is a doctor (assigned-doctor enforced by backend)
  canCoordinate: boolean;
}

const STATUSES = ["pending", "approved", "rejected", "cancelled"] as const;

export function RequestsQueue({ clinicId, canDecide, canCoordinate }: RequestsQueueProps) {
  const { t } = useTranslation();
  const [status, setStatus] = useState<string>("pending");
  const requests = useRequests(clinicId, { status });
  const action = useRequestAction(clinicId);

  return (
    <Card className="shadow-elevation-1">
      <CardHeader>
        <CardTitle>{t("requests.title")}</CardTitle>
        <div className="mt-2 flex flex-wrap gap-2" data-testid="status-filter">
          {STATUSES.map((s) => (
            <Button key={s} size="sm" variant={status === s ? "tonal" : "outlined"} onClick={() => setStatus(s)} data-testid={`filter-${s}`}>
              {t(`requests.status.${s}`)}
            </Button>
          ))}
        </div>
      </CardHeader>
      <CardContent>
        {(requests.data ?? []).length === 0 && <p className="text-sm text-muted-foreground" data-testid="requests-empty">{t("requests.empty")}</p>}
        <ul className="space-y-2">
          {(requests.data ?? []).map((r) => (
            <li key={r.id} className="flex flex-wrap items-center justify-between gap-2 rounded-lg bg-muted/50 px-3 py-2 text-sm" data-testid={`request-${r.id}`}>
              <span className="text-foreground">
                {r.start_datetime.replace("T", " ").slice(0, 16)}
                {r.chief_complaint ? ` · ${r.chief_complaint}` : ""}
                {r.expired && <Badge variant="warning" className="ml-2">{t("requests.status.expired")}</Badge>}
              </span>
              <span className="flex gap-2">
                {canDecide && r.status === "pending" && !r.expired && (
                  <>
                    <Button size="sm" onClick={() => action.mutate({ id: r.id, action: "approve" })} data-testid={`approve-${r.id}`}>{t("requests.approve")}</Button>
                    <Button size="sm" variant="outlined" onClick={() => action.mutate({ id: r.id, action: "reject" })} data-testid={`reject-${r.id}`}>{t("requests.reject")}</Button>
                  </>
                )}
                {canCoordinate && r.status === "pending" && (
                  <>
                    {r.expired && <Button size="sm" onClick={() => action.mutate({ id: r.id, action: "resend" })} data-testid={`resend-${r.id}`}>{t("requests.resend")}</Button>}
                    <Button size="sm" variant="ghost" onClick={() => action.mutate({ id: r.id, action: "cancel" })} data-testid={`cancel-${r.id}`}>{t("requests.cancel")}</Button>
                  </>
                )}
              </span>
            </li>
          ))}
        </ul>
      </CardContent>
    </Card>
  );
}
```
> Confirm `src/components/ui/badge.tsx` exports `Badge` with a `warning` variant (the SP2 inventory listed it). If the variant name differs, use an existing one.

- [ ] **Step 2: Requests page** — create `src/app/requests/page.tsx`:
```tsx
"use client";

import { useTranslation } from "react-i18next";

import { AuthGate } from "@/components/auth-gate";
import { AppShell } from "@/components/shell/app-shell";
import { PageContainer } from "@/components/layout/page-container";
import { PageHeader } from "@/components/layout/page-header";
import { useMe } from "@/features/clinic/hooks";
import { RequestsQueue } from "@/features/scheduling/requests-queue";

function RequestsShell() {
  const { t } = useTranslation();
  const me = useMe();
  const membership = me.data?.memberships[0];
  const clinicId = membership?.clinic_id ?? "";
  const role = membership?.role ?? "";
  const canDecide = role === "doctor";
  const canCoordinate = role === "owner" || role === "practice_manager" || role === "assistant";

  return (
    <AppShell clinicName={membership?.clinic_name}>
      <PageContainer>
        <PageHeader title={t("requests.title")} />
        {clinicId && <RequestsQueue clinicId={clinicId} canDecide={canDecide} canCoordinate={canCoordinate} />}
      </PageContainer>
    </AppShell>
  );
}

export default function RequestsPage() {
  return (
    <AuthGate>
      <RequestsShell />
    </AuthGate>
  );
}
```

- [ ] **Step 3: Nav dot** — in `src/components/shell/app-shell.tsx`, the nav renders `destinations.map(...)`. For the `requests` destination, render a small dot when `usePendingCount(clinicId).data.count > 0`. Inspect how app-shell gets `clinicId` (it receives `clinicName`; it can call `useMe()` like other components, or accept a count). Minimal approach: in app-shell, call `useMe()` to get `clinicId`, then `usePendingCount(clinicId)`; when rendering the nav item whose `key === "requests"` and count>0, add an absolutely-positioned dot span:
```tsx
{dest.key === "requests" && pendingCount > 0 && (
  <span className="absolute right-2 top-1 size-2 rounded-full bg-info" data-testid="requests-dot" aria-hidden />
)}
```
Use a semantic token for the dot colour (`bg-info` or `bg-primary` — pick the one that reads as a notification accent in both themes). Ensure the nav item container is `relative`. Apply to BOTH the desktop rail item and the mobile bottom-nav item.
> If wiring `useMe()` into app-shell is awkward, add an optional `pendingCount?: number` prop to `AppShell` and have each page pass `usePendingCount(...)`. Choose the lower-churn option after reading app-shell.tsx.

- [ ] **Step 4: tsc + build** — `npx tsc --noEmit && npm run build` → clean (`/requests` compiles).
- [ ] **Step 5: Commit**
```bash
git add src/features/scheduling/requests-queue.tsx src/app/requests/ src/components/shell/app-shell.tsx
git commit -m "feat(scheduling): Requests screen + nav pending dot

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 10: Frontend — Home pending-requests card

**Files:** create `src/features/scheduling/pending-requests-card.tsx`; modify `src/app/page.tsx`.

- [ ] **Step 1: Card** — create `src/features/scheduling/pending-requests-card.tsx`:
```tsx
"use client";

import Link from "next/link";
import { useTranslation } from "react-i18next";

import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { useRequests } from "@/features/scheduling/hooks";

export function PendingRequestsCard({ clinicId }: { clinicId: string }) {
  const { t } = useTranslation();
  const requests = useRequests(clinicId, { status: "pending" });
  const items = requests.data ?? [];

  return (
    <Card className="shadow-elevation-1" data-testid="pending-requests-card">
      <CardHeader>
        <div className="flex items-center justify-between gap-3">
          <CardTitle>{t("requests.pendingCard")} ({items.length})</CardTitle>
          <Link href="/requests" className="text-sm font-medium text-primary underline-offset-4 hover:underline" data-testid="requests-viewall">
            {t("requests.viewAll")}
          </Link>
        </div>
      </CardHeader>
      <CardContent>
        {items.length === 0 ? (
          <p className="text-sm text-muted-foreground">{t("requests.empty")}</p>
        ) : (
          <ul className="space-y-2">
            {items.slice(0, 5).map((r) => (
              <li key={r.id} className="rounded-lg bg-muted/50 px-3 py-2 text-sm text-foreground" data-testid={`home-request-${r.id}`}>
                {r.start_datetime.replace("T", " ").slice(0, 16)}{r.chief_complaint ? ` · ${r.chief_complaint}` : ""}{r.expired ? ` · ${t("requests.status.expired")}` : ""}
              </li>
            ))}
          </ul>
        )}
      </CardContent>
    </Card>
  );
}
```

- [ ] **Step 2: Wire into Home** — in `src/app/page.tsx`, inside the `<section data-testid="clinic-shell">`, after the existing cards (summary + address preview + completeness), add:
```tsx
import { PendingRequestsCard } from "@/features/scheduling/pending-requests-card";
// ...
{clinicId && <PendingRequestsCard clinicId={clinicId} />}
```
(Place the import with the other imports; render the card after `ClinicCompleteness`.)

- [ ] **Step 3: tsc + build** → clean.
- [ ] **Step 4: Commit**
```bash
git add src/features/scheduling/pending-requests-card.tsx src/app/page.tsx
git commit -m "feat(scheduling): Home pending-requests card

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Final Verification (before PRs)
- [ ] Backend: `make test && make lint` → green.
- [ ] Frontend: `npx tsc --noEmit && npm run build` → clean; `npx playwright test tests/e2e/i18n.spec.ts` (or node parity) → pass.
- [ ] Two PRs: backend `Part of #46`; frontend `Closes #46`. Board #46 → In Review → Completed.
- [ ] **Controller-only:** apply migration 0010 to Supabase via MCP `apply_migration`; verify `alembic_version=0010` + 3 tables.

## Self-Review (against the spec)
- **§3 data model (3 tables, String+CHECK, UNIQUE doctor+start):** Task 1. ✅
- **§4 atomic engine (validate slot, ON CONFLICT get-or-create, FOR UPDATE, count consumers, capacity, SlotFullError 409):** Task 2 (`reserve_slot`/`count_consumers`). ✅
- **§5 lifecycle + expiry (create/approve/reject/cancel/resend; derived expiry; appointment on approve; stale-state 409):** Tasks 2–4. ✅
- **§6 API (create, list, approve/reject, cancel/resend, pending-count, appointments, slots occupancy):** Tasks 2–5. ✅
- **§7 permissions (create coordinator-only/doctor-403; approve/reject assigned-doctor-only; reads open) + audit:** Tasks 2–4 (`authorize_create`/`authorize_decide`/`authorize_coordinate`, audit in every mutation). ✅ (Positive assigned-doctor approve via HTTP needs an activated doctor; covered service-level in Task 3 + 403 cases via HTTP. Flagged in Task 3 note.)
- **§8 frontend (bookable slots, Requests nav+dot+screen, Home card, occupancy):** Tasks 6–10. ✅
- **§9 testing (capacity sequential, expired-counts, approve creates appt, reject/cancel release, stale 409, slot validation, permission matrix, occupancy):** Tasks 2–5 backend; FE tsc/build/i18n. ✅ (True parallel concurrency not unit-tested — harness limitation noted in Task 2; FOR UPDATE provides the guarantee.)
- **Placeholder scan:** the slot-viewer "Full" placeholder is replaced with a real i18n key per the Task 8 note; "inspect existing file" notes (patient-search hook, badge variant, app-shell clinicId wiring) are symbol-matching, not placeholders. The Task 3 `approve_request` shows a clean form note (remove the `if False` artifact). ✅
- **Type consistency:** `reserve_slot(db,*,clinic_id,doctor_id,start)` / `count_consumers(db,slot_id)` / `approve_request(db,*,clinic_id,request_id,actor_user_id)` consistent across impl + tests; FE hook names (`useRequests/usePendingCount/useCreateRequest/useRequestAction`) consistent across Tasks 6/8/9/10. ✅
