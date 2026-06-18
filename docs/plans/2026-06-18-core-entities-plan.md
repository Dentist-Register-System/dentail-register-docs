# Core Entities (SP2) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the rich Doctor, Assistant, and Patient entities — doctor/assistant invite→activation lifecycle and patient CRUD with fast `pg_trgm` search + a non-blocking duplicate warning — on top of SP1's auth/tenancy/audit layer.

**Architecture:** Three new feature modules (`doctors`, `assistants`, `patients`) behind the existing SP1 dependency chain (`current_membership` + `require_role`). `doctor_beta`/`assistant_beta` are first-class rows with a nullable `linked_user_id` set on activation; `clinic_invite_beta` is extended with `doctor_id`/`assistant_id` so an invite carries the entity it activates. Patient search + duplicate detection share one `pg_trgm` GIN index. Every mutation writes an `audit_event_beta` row in the same transaction. Delivered as three full-stack vertical slices: **Doctor → Assistant → Patient**, backend-first within each.

**Tech Stack:** FastAPI + SQLAlchemy 2.x (sync) + Alembic + Postgres (`pg_trgm`); pytest on Postgres :5433. Next.js App Router + TypeScript + TanStack Query + React Hook Form + Zod + shadcn/ui + react-i18next; Vitest + RTL and Playwright.

**Spec:** `docs/specs/2026-06-18-core-entities-design.md`.

## Global Constraints

- **Repos:** backend `~/Documents/register_workspace/dentist-registry-backend`; frontend `~/Documents/register_workspace/dentist-registry-frontend`. Never push to `main`; one feature branch + PR per slice via `gh-personal`. Pre-flight every git op: confirm `github-personal` remote + `rohan2jos@gmail.com`.
- **Backend import discipline:** one-way `core/ ← modules/ ← main`. Cross-module calls go through the other module's **service** only — never its models/router. Break import cycles (e.g. `doctors` ↔ `invites`) with function-local imports. Routers are thin: parse → call service → shape response.
- **Conventions:** sync SQLAlchemy 2.x, UUID PKs, tz-aware timestamps, `_beta` table suffix. Enums created via raw DDL with `create_type=False` on columns (per migration `0002`). Uniform error envelope `{ "error": { "code", "message", "details" } }`. Audit written in-transaction via `record_audit` (never fire-and-forget); the service does the single `db.commit()`.
- **RLS:** enable Row Level Security on every new table; do not grant `anon`/`authenticated` (tables stay off the Supabase Data API). Run `get_advisors` after schema changes; resolve findings.
- **i18n-first:** zero hardcoded user-facing strings — all via `t('key')`; add every new key to **both** `en.json` and `hi.json` (parity enforced by `tests/e2e/i18n.spec.ts`). Build Zod schemas inside components with `t()`. Errors shown via `t('apiErrors.<code>')` (never the backend English message). Roles/statuses are stable enums (the i18n contract).
- **Design system:** semantic tokens only (no raw colours / Tailwind palette utilities); light/dark/system; mobile-first; WCAG 2.1 AA. New shadcn primitives hardened to `Design/02`.
- **Deps:** permissive-OSS only (MIT/Apache/BSD/ISC). `pg_trgm` is a built-in Postgres contrib extension (no new package). No secrets committed.
- **Migrations:** current head is `0003`. This plan adds `0004` (doctor), `0005` (assistant), `0006` (patient). Each migration enables RLS on the table it creates.
- **Backend tests:** pytest against Postgres :5433 (never SQLite); per-test transactional rollback (`db_session` fixture). Authenticated requests use the `auth_client` fixture (signs JWTs locally; never calls real Supabase).
- **Frontend tests note (AGENTS.md):** this is not the Next.js you know — check `node_modules/next/dist/docs/` if an App Router API behaves unexpectedly. Playwright e2e runs locally/pre-merge (CI = typecheck + build).

---

# SLICE 1 — DOCTOR (backend + frontend)

Branch: `sp2-doctors`. Establishes the entity + invite-activation pattern reused by Assistant.

## Task 1: Doctor model + migration `0004` + RLS + registry

**Files:**
- Create: `app/modules/doctors/__init__.py`, `app/modules/doctors/models.py`
- Modify: `app/modules/invites/models.py` (add `doctor_id` column)
- Modify: `app/db/base.py` (import `Doctor`)
- Create: `alembic/versions/0004_doctors.py`
- Test: `tests/doctors/__init__.py`, `tests/doctors/test_model.py`

**Interfaces:**
- Produces: `Doctor` model (`doctor_beta`) with `id, clinic_id, linked_user_id, name, phone, email, specialty, status (DoctorStatus{invited,active,inactive}), created_by, created_at, updated_at`; `ClinicInvite.doctor_id` (nullable FK → `doctor_beta.id`).

- [ ] **Step 1: Doctor model**

`app/modules/doctors/models.py`:
```python
import enum
import uuid
from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, Index, String, func
from sqlalchemy import Enum as SAEnum
from sqlalchemy.orm import Mapped, mapped_column

from app.core.base import Base


class DoctorStatus(str, enum.Enum):
    invited = "invited"
    active = "active"
    inactive = "inactive"


class Doctor(Base):
    __tablename__ = "doctor_beta"
    __table_args__ = (
        Index(
            "uq_doctor_clinic_user",
            "clinic_id",
            "linked_user_id",
            unique=True,
            postgresql_where=mapped_column("linked_user_id").isnot(None),
        ),
    )

    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid.uuid4)
    clinic_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("clinic_beta.id"), index=True)
    linked_user_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("app_user_beta.id"), nullable=True
    )
    name: Mapped[str] = mapped_column(String(200))
    phone: Mapped[str] = mapped_column(String(32))
    email: Mapped[str | None] = mapped_column(String(320), nullable=True)
    specialty: Mapped[str | None] = mapped_column(String(200), nullable=True)
    status: Mapped[DoctorStatus] = mapped_column(
        SAEnum(DoctorStatus, name="doctor_status"), default=DoctorStatus.invited
    )
    created_by: Mapped[uuid.UUID] = mapped_column(ForeignKey("app_user_beta.id"))
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.clock_timestamp()
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.clock_timestamp(),
        onupdate=func.clock_timestamp(),
    )
```
> Note: the partial-unique-index `postgresql_where` is expressed in the migration with `sa.text("linked_user_id IS NOT NULL")` (Step 4); the model `Index` is documentation/metadata. If the `mapped_column(...).isnot(...)` expression is awkward at import time, use `text("linked_user_id IS NOT NULL")` from `sqlalchemy` in `__table_args__` instead.

- [ ] **Step 2: Add `doctor_id` to the invite model**

In `app/modules/invites/models.py`, add this column to `ClinicInvite` (after `clinic_id`):
```python
    doctor_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("doctor_beta.id"), nullable=True
    )
```

- [ ] **Step 3: Register the model for Alembic**

In `app/db/base.py` add:
```python
from app.modules.doctors.models import Doctor  # noqa: F401
```

- [ ] **Step 4: Migration `0004`**

`alembic/versions/0004_doctors.py`:
```python
"""doctors

Revision ID: 0004
Revises: 0003
"""
from collections.abc import Sequence

import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

from alembic import op

revision: str = "0004"
down_revision: str | None = "0003"
branch_labels: Sequence[str] | None = None
depends_on: Sequence[str] | None = None


def upgrade() -> None:
    op.execute("CREATE TYPE doctor_status AS ENUM ('invited', 'active', 'inactive')")
    op.create_table(
        "doctor_beta",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("clinic_id", sa.Uuid(), nullable=False),
        sa.Column("linked_user_id", sa.Uuid(), nullable=True),
        sa.Column("name", sa.String(length=200), nullable=False),
        sa.Column("phone", sa.String(length=32), nullable=False),
        sa.Column("email", sa.String(length=320), nullable=True),
        sa.Column("specialty", sa.String(length=200), nullable=True),
        sa.Column(
            "status",
            postgresql.ENUM("invited", "active", "inactive", name="doctor_status", create_type=False),
            nullable=False,
        ),
        sa.Column("created_by", sa.Uuid(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("clock_timestamp()"), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.text("clock_timestamp()"), nullable=False),
        sa.ForeignKeyConstraint(["clinic_id"], ["clinic_beta.id"], name=op.f("fk_doctor_beta_clinic_id_clinic_beta")),
        sa.ForeignKeyConstraint(["linked_user_id"], ["app_user_beta.id"], name=op.f("fk_doctor_beta_linked_user_id_app_user_beta")),
        sa.ForeignKeyConstraint(["created_by"], ["app_user_beta.id"], name=op.f("fk_doctor_beta_created_by_app_user_beta")),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_doctor_beta")),
    )
    op.create_index(op.f("ix_doctor_beta_clinic_id"), "doctor_beta", ["clinic_id"], unique=False)
    op.create_index(
        "uq_doctor_clinic_user", "doctor_beta", ["clinic_id", "linked_user_id"],
        unique=True, postgresql_where=sa.text("linked_user_id IS NOT NULL"),
    )
    op.add_column("clinic_invite_beta", sa.Column("doctor_id", sa.Uuid(), nullable=True))
    op.create_foreign_key(
        op.f("fk_clinic_invite_beta_doctor_id_doctor_beta"),
        "clinic_invite_beta", "doctor_beta", ["doctor_id"], ["id"],
    )
    op.execute("ALTER TABLE doctor_beta ENABLE ROW LEVEL SECURITY")


def downgrade() -> None:
    op.drop_constraint(op.f("fk_clinic_invite_beta_doctor_id_doctor_beta"), "clinic_invite_beta", type_="foreignkey")
    op.drop_column("clinic_invite_beta", "doctor_id")
    op.drop_index("uq_doctor_clinic_user", table_name="doctor_beta")
    op.drop_index(op.f("ix_doctor_beta_clinic_id"), table_name="doctor_beta")
    op.drop_table("doctor_beta")
    op.execute("DROP TYPE IF EXISTS doctor_status")
```

- [ ] **Step 5: Run migration up/down to verify reversibility**

Run: `make migrate` (or `ALEMBIC_DB_URL=$TEST_DATABASE_URL alembic upgrade head`). Expected: applies cleanly. Then `alembic downgrade 0003 && alembic upgrade head` round-trips with no error.

- [ ] **Step 6: Model smoke test**

`tests/doctors/test_model.py`:
```python
from app.modules.doctors.models import Doctor, DoctorStatus


def test_doctor_defaults(db_session):
    from app.modules.clinics.models import Clinic
    clinic = Clinic(name="C")
    db_session.add(clinic)
    db_session.flush()
    d = Doctor(clinic_id=clinic.id, name="Dr A", phone="123", created_by=clinic.id)
    db_session.add(d)
    db_session.flush()
    assert d.status == DoctorStatus.invited
    assert d.linked_user_id is None
```
> `created_by` here is a throwaway uuid for the smoke test (FK is deferred within the rolled-back tx); real flows pass the actor's `app_user.id`.

Run: `make test ARGS=tests/doctors/test_model.py` → PASS.

- [ ] **Step 7: Commit**
```bash
git add -A && git commit -m "feat(doctors): doctor_beta model + migration 0004 + invite.doctor_id"
```

## Task 2: Doctors service + invite extension + activation + router

**Files:**
- Create: `app/modules/doctors/schemas.py`, `app/modules/doctors/service.py`, `app/modules/doctors/router.py`
- Modify: `app/modules/invites/service.py` (extend `create_invite`; link doctor on `accept_invite`)
- Modify: `app/modules/members/service.py` (add `set_member_status_for_user`)
- Modify: `app/main.py` (mount the doctors router)
- Test: `tests/doctors/test_doctors.py`

**Interfaces:**
- Consumes: `record_audit`, `ensure_user`, `get_current_membership`/`require_role`, `invites.service.create_invite`.
- Produces:
  - `invites.service.create_invite(db, *, clinic_id, role, created_by, ttl_hours=72, doctor_id=None, assistant_id=None, commit=True) -> ClinicInvite`
  - `members.service.set_member_status_for_user(db, *, clinic_id, user_id, status) -> None`
  - `doctors.service.create_doctor(db, *, clinic_id, actor_user_id, data: DoctorCreate) -> tuple[Doctor, ClinicInvite]`
  - `doctors.service.list_doctors(db, clinic_id, status=None) -> list[Doctor]`
  - `doctors.service.get_doctor(db, clinic_id, doctor_id) -> Doctor`
  - `doctors.service.update_doctor(db, *, clinic_id, doctor_id, actor_user_id, data: DoctorUpdate) -> Doctor`
  - `doctors.service.link_user_to_doctor(db, *, doctor_id, user_id) -> None` (called from `accept_invite`)
  - Endpoints under `/api/v1/clinics/{clinic_id}/doctors`.

- [ ] **Step 1: Schemas**

`app/modules/doctors/schemas.py`:
```python
import datetime as dt
import uuid

from pydantic import BaseModel, ConfigDict

from app.modules.doctors.models import DoctorStatus


class DoctorCreate(BaseModel):
    name: str
    phone: str
    email: str | None = None
    specialty: str | None = None


class DoctorUpdate(BaseModel):
    name: str | None = None
    phone: str | None = None
    email: str | None = None
    specialty: str | None = None
    status: DoctorStatus | None = None


class DoctorRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    clinic_id: uuid.UUID
    linked_user_id: uuid.UUID | None
    name: str
    phone: str
    email: str | None
    specialty: str | None
    status: str
    created_at: dt.datetime


class DoctorCreateResult(BaseModel):
    doctor: DoctorRead
    invite_token: str
```

- [ ] **Step 2: Extend `create_invite` and add doctor-linking in `accept_invite`**

In `app/modules/invites/service.py`, replace `create_invite` signature/body to add optional entity FKs + `commit`, and add the linking branch in `accept_invite`:
```python
def create_invite(
    db: Session,
    *,
    clinic_id: uuid.UUID,
    role: MemberRole,
    created_by: uuid.UUID,
    ttl_hours: int = 72,
    doctor_id: uuid.UUID | None = None,
    assistant_id: uuid.UUID | None = None,
    commit: bool = True,
) -> ClinicInvite:
    expires_at = dt.datetime.now(tz=dt.timezone.utc) + dt.timedelta(hours=ttl_hours)
    invite = ClinicInvite(
        clinic_id=clinic_id, role=role, token=secrets.token_urlsafe(32),
        created_by=created_by, status=InviteStatus.pending, expires_at=expires_at,
        doctor_id=doctor_id, assistant_id=assistant_id,
    )
    db.add(invite)
    db.flush()
    record_audit(db, action="clinic_invite.created", entity_type="clinic_invite",
                 entity_id=invite.id, clinic_id=clinic_id, actor_user_id=created_by,
                 new={"role": role.value})
    if commit:
        db.commit()
        db.refresh(invite)
    return invite
```
In `accept_invite`, after `db.flush()` (once `member` + invite status are set) and **before** the audit/commit, add:
```python
    # SP2: if the invite carries a rich entity, link it to this user + activate.
    if invite.doctor_id is not None:
        from app.modules.doctors.service import link_user_to_doctor  # local import: breaks doctors↔invites cycle
        link_user_to_doctor(db, doctor_id=invite.doctor_id, user_id=user.id)
    if invite.assistant_id is not None:
        from app.modules.assistants.service import link_user_to_assistant
        link_user_to_assistant(db, assistant_id=invite.assistant_id, user_id=user.id)
```
> The `assistants` import only resolves once Slice 2 exists; until then `invite.assistant_id` is always `None`, so the branch is never taken. (Optional: guard the assistant import in a `try/except ImportError` during Slice 1.)

- [ ] **Step 3: `set_member_status_for_user` in members service**

In `app/modules/members/service.py` add:
```python
def set_member_status_for_user(db, *, clinic_id, user_id, status) -> None:
    from app.modules.members.models import ClinicMember
    member = db.execute(
        select(ClinicMember).where(
            ClinicMember.clinic_id == clinic_id, ClinicMember.user_id == user_id
        )
    ).scalar_one_or_none()
    if member is not None:
        member.status = status
        db.flush()
```
(Ensure `from sqlalchemy import select` is imported in that file.)

- [ ] **Step 4: Doctors service**

`app/modules/doctors/service.py`:
```python
import uuid

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.errors import NotFoundError
from app.modules.audit.service import record_audit
from app.modules.doctors.models import Doctor, DoctorStatus
from app.modules.doctors.schemas import DoctorCreate, DoctorUpdate
from app.modules.invites import service as invites_service
from app.modules.invites.models import ClinicInvite
from app.modules.members import service as members_service
from app.modules.members.models import MemberRole, MemberStatus


def create_doctor(db, *, clinic_id, actor_user_id, data: DoctorCreate):
    doctor = Doctor(
        clinic_id=clinic_id, name=data.name, phone=data.phone,
        email=data.email, specialty=data.specialty,
        status=DoctorStatus.invited, created_by=actor_user_id,
    )
    db.add(doctor)
    db.flush()
    record_audit(db, action="doctor.created", entity_type="doctor",
                 entity_id=doctor.id, clinic_id=clinic_id, actor_user_id=actor_user_id,
                 new={"name": doctor.name, "specialty": doctor.specialty})
    invite = invites_service.create_invite(
        db, clinic_id=clinic_id, role=MemberRole.doctor,
        created_by=actor_user_id, doctor_id=doctor.id, commit=False,
    )
    db.commit()
    db.refresh(doctor)
    db.refresh(invite)
    return doctor, invite


def list_doctors(db, clinic_id, status: DoctorStatus | None = None):
    stmt = select(Doctor).where(Doctor.clinic_id == clinic_id)
    if status is not None:
        stmt = stmt.where(Doctor.status == status)
    return list(db.execute(stmt.order_by(Doctor.created_at.desc())).scalars().all())


def get_doctor(db, clinic_id, doctor_id) -> Doctor:
    doctor = db.get(Doctor, doctor_id)
    if doctor is None or doctor.clinic_id != clinic_id:
        raise NotFoundError("Doctor not found.")
    return doctor


def update_doctor(db, *, clinic_id, doctor_id, actor_user_id, data: DoctorUpdate) -> Doctor:
    doctor = get_doctor(db, clinic_id, doctor_id)
    changes = data.model_dump(exclude_unset=True)
    previous = {k: getattr(doctor, k) for k in changes}
    new_status = changes.pop("status", None)
    for k, v in changes.items():
        setattr(doctor, k, v)
    if new_status is not None:
        doctor.status = new_status
        # Departure/return: keep history, mirror access on the linked membership.
        if doctor.linked_user_id is not None:
            member_status = (
                MemberStatus.active if new_status == DoctorStatus.active else MemberStatus.inactive
            )
            members_service.set_member_status_for_user(
                db, clinic_id=clinic_id, user_id=doctor.linked_user_id, status=member_status
            )
    db.flush()
    action = "doctor.status_changed" if new_status is not None else "doctor.updated"
    record_audit(db, action=action, entity_type="doctor", entity_id=doctor.id,
                 clinic_id=clinic_id, actor_user_id=actor_user_id,
                 previous=previous,
                 new={**changes, **({"status": new_status.value} if new_status else {})})
    db.commit()
    db.refresh(doctor)
    return doctor


def link_user_to_doctor(db, *, doctor_id, user_id) -> None:
    """Called in-transaction from invites.accept_invite; no commit here."""
    doctor = db.get(Doctor, doctor_id)
    if doctor is None:
        return
    doctor.linked_user_id = user_id
    doctor.status = DoctorStatus.active
    db.flush()
    record_audit(db, action="doctor.activated", entity_type="doctor", entity_id=doctor.id,
                 clinic_id=doctor.clinic_id, actor_user_id=user_id, new={"status": "active"})
```

- [ ] **Step 5: Router**

`app/modules/doctors/router.py`:
```python
import uuid

from fastapi import APIRouter, Depends, status

from app.core.deps import DbSession
from app.modules.doctors import service
from app.modules.doctors.models import DoctorStatus
from app.modules.doctors.schemas import (
    DoctorCreate, DoctorCreateResult, DoctorRead, DoctorUpdate,
)
from app.modules.members.deps import CurrentMembership, require_role
from app.modules.members.models import MemberRole

router = APIRouter(prefix="/clinics", tags=["doctors"])
_can_manage = require_role(MemberRole.owner, MemberRole.practice_manager)


@router.post("/{clinic_id}/doctors", response_model=DoctorCreateResult, status_code=status.HTTP_201_CREATED)
def create_doctor(clinic_id: uuid.UUID, data: DoctorCreate, db: DbSession, membership=Depends(_can_manage)):
    doctor, invite = service.create_doctor(db, clinic_id=clinic_id, actor_user_id=membership.user_id, data=data)
    return DoctorCreateResult(doctor=DoctorRead.model_validate(doctor), invite_token=invite.token)


@router.get("/{clinic_id}/doctors", response_model=list[DoctorRead])
def list_doctors(clinic_id: uuid.UUID, db: DbSession, membership: CurrentMembership, status: DoctorStatus | None = None):
    return service.list_doctors(db, clinic_id, status)


@router.get("/{clinic_id}/doctors/{doctor_id}", response_model=DoctorRead)
def get_doctor(clinic_id: uuid.UUID, doctor_id: uuid.UUID, db: DbSession, membership: CurrentMembership):
    return service.get_doctor(db, clinic_id, doctor_id)


@router.patch("/{clinic_id}/doctors/{doctor_id}", response_model=DoctorRead)
def update_doctor(clinic_id: uuid.UUID, doctor_id: uuid.UUID, data: DoctorUpdate, db: DbSession, membership=Depends(_can_manage)):
    return service.update_doctor(db, clinic_id=clinic_id, doctor_id=doctor_id, actor_user_id=membership.user_id, data=data)
```
Mount in `app/main.py` alongside the other module routers:
```python
from app.modules.doctors.router import router as doctors_router
app.include_router(doctors_router, prefix="/api/v1")
```

- [ ] **Step 6: Tests (write first where practical, then make green)**

`tests/doctors/test_doctors.py` — covers create+authz, activation, deactivation-revokes-access, cross-clinic, audit:
```python
OWNER = "11111111-1111-1111-1111-111111111111"
DOC = "22222222-2222-2222-2222-222222222222"
OUTSIDER = "33333333-3333-3333-3333-333333333333"


def _clinic(client):
    return client.post("/api/v1/clinics", json={"name": "C"}).json()["id"]


def test_owner_creates_doctor_and_issues_invite(auth_client):
    owner, _ = auth_client(sub=OWNER)
    cid = _clinic(owner)
    resp = owner.post(f"/api/v1/clinics/{cid}/doctors",
                      json={"name": "Dr A", "phone": "555", "specialty": "Ortho"})
    assert resp.status_code == 201
    body = resp.json()
    assert body["doctor"]["status"] == "invited"
    assert body["doctor"]["linked_user_id"] is None
    assert body["invite_token"]


def test_assistant_cannot_create_doctor(auth_client):
    owner, _ = auth_client(sub=OWNER)
    cid = _clinic(owner)
    token = owner.post(f"/api/v1/clinics/{cid}/invites", json={"role": "assistant"}).json()["token"]
    asst, _ = auth_client(sub=DOC)
    asst.post("/api/v1/clinics/join", json={"token": token})
    resp = asst.post(f"/api/v1/clinics/{cid}/doctors", json={"name": "X", "phone": "1"})
    assert resp.status_code == 403


def test_doctor_invite_activation_links_user_and_member(auth_client):
    owner, _ = auth_client(sub=OWNER)
    cid = _clinic(owner)
    token = owner.post(f"/api/v1/clinics/{cid}/doctors",
                       json={"name": "Dr A", "phone": "555"}).json()["invite_token"]
    doc, _ = auth_client(sub=DOC)
    join = doc.post("/api/v1/clinics/join", json={"token": token})
    assert join.status_code == 200 and join.json()["role"] == "doctor"
    # doctor row is now active + linked
    listed = owner.get(f"/api/v1/clinics/{cid}/doctors").json()
    assert listed[0]["status"] == "active"
    assert listed[0]["linked_user_id"] is not None
    # the linked user now has access (can read the clinic)
    assert doc.get(f"/api/v1/clinics/{cid}/doctors").status_code == 200


def test_deactivate_doctor_revokes_member_access(auth_client):
    owner, _ = auth_client(sub=OWNER)
    cid = _clinic(owner)
    token = owner.post(f"/api/v1/clinics/{cid}/doctors", json={"name": "Dr A", "phone": "5"}).json()["invite_token"]
    doc, _ = auth_client(sub=DOC)
    doc.post("/api/v1/clinics/join", json={"token": token})
    did = owner.get(f"/api/v1/clinics/{cid}/doctors").json()[0]["id"]
    assert owner.patch(f"/api/v1/clinics/{cid}/doctors/{did}", json={"status": "inactive"}).status_code == 200
    # access revoked: membership no longer active → 403
    assert doc.get(f"/api/v1/clinics/{cid}/doctors").status_code == 403


def test_cross_clinic_doctor_isolation(auth_client):
    owner_a, _ = auth_client(sub=OWNER)
    cid_a = _clinic(owner_a)
    did = owner_a.post(f"/api/v1/clinics/{cid_a}/doctors", json={"name": "A", "phone": "1"}).json()["doctor"]["id"]
    outsider, _ = auth_client(sub=OUTSIDER)
    _clinic(outsider)  # outsider owns a different clinic
    assert outsider.get(f"/api/v1/clinics/{cid_a}/doctors/{did}").status_code == 403


def test_doctor_create_writes_audit(auth_client, db_session):
    from sqlalchemy import select
    from app.modules.audit.models import AuditEvent
    owner, _ = auth_client(sub=OWNER)
    cid = _clinic(owner)
    owner.post(f"/api/v1/clinics/{cid}/doctors", json={"name": "Dr A", "phone": "5"})
    actions = set(db_session.execute(select(AuditEvent.action)).scalars().all())
    assert {"doctor.created", "clinic_invite.created"} <= actions
```
Run: `make test ARGS=tests/doctors/` → all PASS. Run full suite `make test` to confirm no SP1 regressions (the `create_invite` change is backward-compatible).

- [ ] **Step 7: Commit**
```bash
git add -A && git commit -m "feat(doctors): create-with-invite, activation linking, deactivation, CRUD + tests"
```

## Task 3: Doctor frontend (feature + i18n + tests)

**Files:**
- Create: `src/features/doctors/api.ts`, `src/features/doctors/hooks.ts`, `src/features/doctors/doctor-list.tsx`, `src/features/doctors/add-doctor-dialog.tsx`
- Create (if absent): `src/components/ui/dialog.tsx`, `src/components/ui/badge.tsx`, `src/components/ui/table.tsx` (shadcn primitives, semantic tokens)
- Create: `src/app/doctors/page.tsx` (route, behind `AuthGate`)
- Modify: `src/i18n/locales/en.json`, `src/i18n/locales/hi.json` (add `doctors.*` keys + `apiErrors` additions)
- Test: `tests/e2e/doctors.spec.ts`

**Interfaces:**
- Consumes: `apiFetch`, `ApiError`, `useTranslation`, TanStack Query.
- Produces: `useDoctors(clinicId)`, `useCreateDoctor(clinicId)`, `useUpdateDoctor(clinicId)`; `/doctors` route rendering list + add dialog.

- [ ] **Step 1: API layer**

`src/features/doctors/api.ts`:
```typescript
import { apiFetch } from "@/lib/api-client";

export type Doctor = {
  id: string; clinic_id: string; linked_user_id: string | null;
  name: string; phone: string; email: string | null;
  specialty: string | null; status: string; created_at: string;
};
export type DoctorCreateResult = { doctor: Doctor; invite_token: string };

export const fetchDoctors = (clinicId: string) =>
  apiFetch<Doctor[]>(`/api/v1/clinics/${clinicId}/doctors`);

export const createDoctor = (clinicId: string, input: {
  name: string; phone: string; email?: string; specialty?: string;
}) => apiFetch<DoctorCreateResult>(`/api/v1/clinics/${clinicId}/doctors`, {
  method: "POST", body: JSON.stringify(input),
});

export const updateDoctor = (clinicId: string, id: string, input: Record<string, unknown>) =>
  apiFetch<Doctor>(`/api/v1/clinics/${clinicId}/doctors/${id}`, {
    method: "PATCH", body: JSON.stringify(input),
  });
```

- [ ] **Step 2: Hooks**

`src/features/doctors/hooks.ts`:
```typescript
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { createDoctor, fetchDoctors, updateDoctor } from "@/features/doctors/api";

export function useDoctors(clinicId: string) {
  return useQuery({ queryKey: ["doctors", clinicId], queryFn: () => fetchDoctors(clinicId) });
}
export function useCreateDoctor(clinicId: string) {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (input: { name: string; phone: string; email?: string; specialty?: string }) =>
      createDoctor(clinicId, input),
    onSuccess: () => qc.invalidateQueries({ queryKey: ["doctors", clinicId] }),
  });
}
export function useUpdateDoctor(clinicId: string) {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: ({ id, input }: { id: string; input: Record<string, unknown> }) =>
      updateDoctor(clinicId, id, input),
    onSuccess: () => qc.invalidateQueries({ queryKey: ["doctors", clinicId] }),
  });
}
```

- [ ] **Step 3: i18n keys (both locales)**

Add to `en.json` (and the Hindi equivalents to `hi.json` — keep key parity):
```json
"doctors": {
  "title": "Doctors",
  "add": "Add doctor",
  "empty": "No doctors yet.",
  "name": "Name", "phone": "Phone", "email": "Email", "specialty": "Specialty",
  "status": "Status",
  "create": "Create",
  "inviteCreated": "Doctor created. Share this invite link:",
  "copy": "Copy",
  "deactivate": "Deactivate", "activate": "Activate",
  "confirmDeactivate": "Deactivate this doctor? They will lose access until reactivated."
},
"doctorStatus": { "invited": "Invited", "active": "Active", "inactive": "Inactive" }
```
Add to `apiErrors` in both locales (used later by patients too): no new code needed for doctors beyond existing `forbidden`/`validation_error`/`not_found`.

- [ ] **Step 4: shadcn primitives (only if missing)**

If `src/components/ui/dialog.tsx`, `badge.tsx`, or `table.tsx` don't exist, add them from shadcn using semantic tokens only (`bg-card`, `text-foreground`, `border-border`, `bg-primary`, etc. — never raw colours). Verify against `dentail-register-docs/Design/02-design-system.md`. Mobile-first; AA contrast.

- [ ] **Step 5: List + Add dialog components**

`src/features/doctors/doctor-list.tsx` (`"use client"`): renders a table of doctors (name, specialty, status badge via `t('doctorStatus.'+status)`), an "Add doctor" button opening the dialog, and a deactivate/activate action (calls `useUpdateDoctor` with `{status}`, confirms via dialog). `src/features/doctors/add-doctor-dialog.tsx`: RHF + Zod form (schema built inside the component with `t()` for messages), fields name/phone/email/specialty; on success shows `t('doctors.inviteCreated')` + the `invite_token` with a copy button. All strings via `t()`. Errors via `t('apiErrors.'+code, {defaultValue: t('apiErrors.default')})`.

- [ ] **Step 6: Route**

`src/app/doctors/page.tsx`: wrap `<DoctorList/>` in `<AuthGate>`; read the active clinic id from `useMe()` (first membership), matching how `HomeShell` resolves clinic.

- [ ] **Step 7: Verify + e2e**

`tests/e2e/doctors.spec.ts` (Supabase + backend mocked, following `tests/e2e/auth.spec.ts` patterns): renders the doctors list, opens Add dialog, submits, asserts the invite link is shown; switches locale and asserts a Hindi string.
Run: `cp .env.local.example .env.local && npx tsc --noEmit && npm run build && npm run test:e2e -- doctors.spec.ts i18n.spec.ts` → green (i18n parity holds).

- [ ] **Step 8: Commit + open Slice 1 PR**
```bash
git add -A && git commit -m "feat(doctors): doctors management UI (list, add+invite link, deactivate); i18n"
git push -u origin sp2-doctors
gh-personal pr create --title "SP2 Slice 1: Doctor entity (backend + frontend)" \
  --body "Implements Slice 1 of docs/plans/2026-06-18-core-entities-plan.md. Closes Dentist-Register-System/dentail-register-docs#<doctor-subissue>."
```

---

# SLICE 2 — ASSISTANT (backend + frontend)

Branch: `sp2-assistants`. A mechanical mirror of Slice 1: substitute `doctor→assistant`, `Doctor→Assistant`, `doctor_status→assistant_status`, `specialty→title`, `MemberRole.doctor→MemberRole.assistant`, migration `0004→0005`, `doctor_id→assistant_id`. Below are the non-obvious specifics; produce each file by applying that substitution to the Slice-1 equivalent.

## Task 4: Assistant model + migration `0005` + registry

**Files:** `app/modules/assistants/__init__.py`, `app/modules/assistants/models.py`; modify `app/modules/invites/models.py` (add `assistant_id`); modify `app/db/base.py`; `alembic/versions/0005_assistants.py`; `tests/assistants/__init__.py`, `tests/assistants/test_model.py`.

- [ ] **Step 1: Model** — copy `doctors/models.py` → `assistants/models.py`; rename class `Assistant`, table `assistant_beta`, enum `AssistantStatus`/`assistant_status`, index `uq_assistant_clinic_user`; replace `specialty` with `title: Mapped[str | None] = mapped_column(String(200), nullable=True)`.
- [ ] **Step 2: Invite column** — add to `ClinicInvite`:
```python
    assistant_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("assistant_beta.id"), nullable=True
    )
```
- [ ] **Step 3: Registry** — add `from app.modules.assistants.models import Assistant  # noqa: F401` to `app/db/base.py`.
- [ ] **Step 4: Migration `0005`** — copy `0004` with `revision="0005"`, `down_revision="0004"`; `assistant_status` enum; `assistant_beta` table (with `title` instead of `specialty`); `uq_assistant_clinic_user` partial unique index; `add_column("clinic_invite_beta", sa.Column("assistant_id", ...))` + FK to `assistant_beta`; `ENABLE ROW LEVEL SECURITY` on `assistant_beta`. Mirror the downgrade.
- [ ] **Step 5:** Run `make migrate`; round-trip `alembic downgrade 0004 && alembic upgrade head`.
- [ ] **Step 6:** `tests/assistants/test_model.py` — mirror of doctor model test (`title` instead of `specialty`). Run → PASS.
- [ ] **Step 7:** Commit: `feat(assistants): assistant_beta model + migration 0005 + invite.assistant_id`.

## Task 5: Assistants service + activation + router

**Files:** `app/modules/assistants/{schemas,service,router}.py`; modify `app/main.py`; `tests/assistants/test_assistants.py`. (The `accept_invite` assistant-linking branch and `set_member_status_for_user` already exist from Slice 1 — confirm the `assistants` import in `accept_invite` now resolves; remove any temporary `try/except ImportError` guard.)

- [ ] **Step 1: Schemas** — mirror `doctors/schemas.py`: `AssistantCreate/Update/Read/CreateResult` with `title` instead of `specialty`.
- [ ] **Step 2: Service** — mirror `doctors/service.py`: `create_assistant` (role `MemberRole.assistant`, `assistant_id=...`), `list_assistants`, `get_assistant`, `update_assistant`, `link_user_to_assistant`. Audit actions `assistant.created/activated/updated/status_changed`.
- [ ] **Step 3: Router** — mirror `doctors/router.py` at `/clinics/{clinic_id}/assistants`; same `_can_manage = require_role(owner, practice_manager)`. Mount in `app/main.py`.
- [ ] **Step 4: Tests** — mirror `tests/doctors/test_doctors.py` (create+authz: an assistant/doctor member cannot create assistants → 403; activation links user + member; deactivation revokes access; cross-clinic isolation; audit rows). Run `make test ARGS=tests/assistants/` → PASS; run full `make test` → no regressions.
- [ ] **Step 5:** Commit: `feat(assistants): create-with-invite, activation, deactivation, CRUD + tests`.

## Task 6: Assistant frontend

**Files:** `src/features/assistants/{api,hooks,assistant-list,add-assistant-dialog}.tsx/ts`; `src/app/assistants/page.tsx`; modify `en.json`/`hi.json` (`assistants.*`, `assistantStatus.*`); `tests/e2e/assistants.spec.ts`.

- [ ] **Step 1–6:** Mirror Slice 1 Task 3 (`title` field instead of `specialty`; endpoints `/assistants`; keys `assistants.*`/`assistantStatus.*`). Reuse the `dialog`/`badge`/`table` primitives from Slice 1. All strings via `t()`; key parity in both locales.
- [ ] **Step 7:** Verify: `npx tsc --noEmit && npm run build && npm run test:e2e -- assistants.spec.ts i18n.spec.ts` → green.
- [ ] **Step 8:** Commit + open Slice 2 PR (`sp2-assistants`), closing the assistant sub-issue.

---

# SLICE 3 — PATIENT (backend + frontend)

Branch: `sp2-patients`. Independent of doctors/assistants. Introduces `pg_trgm` for fast search + duplicate detection.

## Task 7: Patient model + migration `0006` (pg_trgm + trigram index) + registry

**Files:** `app/modules/patients/{__init__,models}.py`; modify `app/db/base.py`; `alembic/versions/0006_patients.py`; `tests/patients/{__init__,test_model}.py`.

**Interfaces:**
- Produces: `Patient` model (`patient_beta`) with `id, clinic_id, name, phone, phone_normalized, age, referral_source, medical_conditions, chief_complaint, notes, created_by, created_at, updated_at`; `pg_trgm` extension + GIN trigram index on `name`; btree index on `phone_normalized`.

- [ ] **Step 1: Model**

`app/modules/patients/models.py`:
```python
import uuid
from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, Integer, String, Text, func
from sqlalchemy.orm import Mapped, mapped_column

from app.core.base import Base


class Patient(Base):
    __tablename__ = "patient_beta"

    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid.uuid4)
    clinic_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("clinic_beta.id"), index=True)
    name: Mapped[str] = mapped_column(String(200))
    phone: Mapped[str] = mapped_column(String(32))
    phone_normalized: Mapped[str] = mapped_column(String(32), index=True)
    age: Mapped[int] = mapped_column(Integer)
    referral_source: Mapped[str | None] = mapped_column(String(200), nullable=True)
    medical_conditions: Mapped[str | None] = mapped_column(Text, nullable=True)
    chief_complaint: Mapped[str | None] = mapped_column(Text, nullable=True)
    notes: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_by: Mapped[uuid.UUID] = mapped_column(ForeignKey("app_user_beta.id"))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.clock_timestamp())
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.clock_timestamp(), onupdate=func.clock_timestamp()
    )
```

- [ ] **Step 2: Registry** — add `from app.modules.patients.models import Patient  # noqa: F401` to `app/db/base.py`.

- [ ] **Step 3: Migration `0006`**

`alembic/versions/0006_patients.py` (`revision="0006"`, `down_revision="0005"`):
```python
def upgrade() -> None:
    op.execute("CREATE EXTENSION IF NOT EXISTS pg_trgm")
    op.create_table(
        "patient_beta",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("clinic_id", sa.Uuid(), nullable=False),
        sa.Column("name", sa.String(length=200), nullable=False),
        sa.Column("phone", sa.String(length=32), nullable=False),
        sa.Column("phone_normalized", sa.String(length=32), nullable=False),
        sa.Column("age", sa.Integer(), nullable=False),
        sa.Column("referral_source", sa.String(length=200), nullable=True),
        sa.Column("medical_conditions", sa.Text(), nullable=True),
        sa.Column("chief_complaint", sa.Text(), nullable=True),
        sa.Column("notes", sa.Text(), nullable=True),
        sa.Column("created_by", sa.Uuid(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("clock_timestamp()"), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.text("clock_timestamp()"), nullable=False),
        sa.ForeignKeyConstraint(["clinic_id"], ["clinic_beta.id"], name=op.f("fk_patient_beta_clinic_id_clinic_beta")),
        sa.ForeignKeyConstraint(["created_by"], ["app_user_beta.id"], name=op.f("fk_patient_beta_created_by_app_user_beta")),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_patient_beta")),
    )
    op.create_index(op.f("ix_patient_beta_clinic_id"), "patient_beta", ["clinic_id"], unique=False)
    op.create_index(op.f("ix_patient_beta_phone_normalized"), "patient_beta", ["phone_normalized"], unique=False)
    op.create_index("ix_patient_beta_name_trgm", "patient_beta", ["name"],
                    postgresql_using="gin", postgresql_ops={"name": "gin_trgm_ops"})
    op.execute("ALTER TABLE patient_beta ENABLE ROW LEVEL SECURITY")


def downgrade() -> None:
    op.drop_index("ix_patient_beta_name_trgm", table_name="patient_beta")
    op.drop_index(op.f("ix_patient_beta_phone_normalized"), table_name="patient_beta")
    op.drop_index(op.f("ix_patient_beta_clinic_id"), table_name="patient_beta")
    op.drop_table("patient_beta")
    # leave pg_trgm installed (harmless; other features may use it)
```

- [ ] **Step 4:** Run `make migrate`; round-trip `alembic downgrade 0005 && alembic upgrade head`.
- [ ] **Step 5:** `tests/patients/test_model.py` — smoke test inserting a patient and asserting defaults. Run → PASS.
- [ ] **Step 6:** Commit: `feat(patients): patient_beta model + migration 0006 (pg_trgm + trigram index)`.

## Task 8: Patients service (normalize, duplicate-check, search) + router

**Files:** `app/modules/patients/{schemas,service,router}.py`; modify `app/main.py`; modify `app/core/errors.py` (add `DuplicateWarningError`); `tests/patients/test_patients.py`.

**Interfaces:**
- Produces:
  - `patients.service.normalize_phone(phone: str) -> str` (digits only)
  - `patients.service.find_duplicates(db, *, clinic_id, name, phone, age) -> list[Patient]`
  - `patients.service.create_patient(db, *, clinic_id, actor_user_id, data: PatientCreate) -> Patient` (raises `DuplicateWarningError` when matches exist and not acknowledged)
  - `patients.service.search_patients(db, *, clinic_id, q, limit, offset) -> list[Patient]`
  - `get_patient`, `update_patient`, `delete_patient`
  - Endpoints under `/api/v1/clinics/{clinic_id}/patients` + `.../patients/duplicate-check`.
  - New error code `duplicate_warning` (HTTP 409).

- [ ] **Step 1: Error type**

In `app/core/errors.py` add:
```python
class DuplicateWarningError(DomainError):
    status_code: ClassVar[int] = 409
    code: ClassVar[str] = "duplicate_warning"
```

- [ ] **Step 2: Schemas**

`app/modules/patients/schemas.py`:
```python
import datetime as dt
import uuid

from pydantic import BaseModel, ConfigDict


class PatientCreate(BaseModel):
    name: str
    phone: str
    age: int
    referral_source: str | None = None
    medical_conditions: str | None = None
    chief_complaint: str | None = None
    notes: str | None = None
    acknowledge_duplicates: bool = False


class PatientUpdate(BaseModel):
    name: str | None = None
    phone: str | None = None
    age: int | None = None
    referral_source: str | None = None
    medical_conditions: str | None = None
    chief_complaint: str | None = None
    notes: str | None = None


class DuplicateCheckRequest(BaseModel):
    name: str
    phone: str
    age: int


class PatientRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: uuid.UUID
    clinic_id: uuid.UUID
    name: str
    phone: str
    age: int
    referral_source: str | None
    medical_conditions: str | None
    chief_complaint: str | None
    notes: str | None
    created_at: dt.datetime


class DuplicateMatches(BaseModel):
    matches: list[PatientRead]
```

- [ ] **Step 3: Service**

`app/modules/patients/service.py`:
```python
import re
import uuid

from sqlalchemy import func, or_, select
from sqlalchemy.orm import Session

from app.core.errors import DuplicateWarningError, NotFoundError
from app.modules.audit.service import record_audit
from app.modules.patients.models import Patient
from app.modules.patients.schemas import PatientCreate, PatientUpdate

SIMILARITY_THRESHOLD = 0.4
AGE_WINDOW = 2


def normalize_phone(phone: str) -> str:
    return re.sub(r"\D", "", phone or "")


def find_duplicates(db, *, clinic_id, name, phone, age) -> list[Patient]:
    pn = normalize_phone(phone)
    name_age = (
        func.similarity(Patient.name, name) > SIMILARITY_THRESHOLD
    ) & (func.abs(Patient.age - age) <= AGE_WINDOW)
    stmt = select(Patient).where(
        Patient.clinic_id == clinic_id,
        or_(Patient.phone_normalized == pn, name_age),
    ).order_by(func.similarity(Patient.name, name).desc()).limit(10)
    return list(db.execute(stmt).scalars().all())


def create_patient(db, *, clinic_id, actor_user_id, data: PatientCreate) -> Patient:
    matches = find_duplicates(db, clinic_id=clinic_id, name=data.name, phone=data.phone, age=data.age)
    if matches and not data.acknowledge_duplicates:
        raise DuplicateWarningError(
            "Possible duplicate patient(s) found.",
            {"matches": [{"id": str(m.id), "name": m.name, "phone": m.phone, "age": m.age} for m in matches]},
        )
    patient = Patient(
        clinic_id=clinic_id, name=data.name, phone=data.phone,
        phone_normalized=normalize_phone(data.phone), age=data.age,
        referral_source=data.referral_source, medical_conditions=data.medical_conditions,
        chief_complaint=data.chief_complaint, notes=data.notes, created_by=actor_user_id,
    )
    db.add(patient)
    db.flush()
    record_audit(db, action="patient.created", entity_type="patient", entity_id=patient.id,
                 clinic_id=clinic_id, actor_user_id=actor_user_id, new={"name": patient.name})
    if matches:  # created despite a warning
        record_audit(db, action="patient.duplicate_override", entity_type="patient", entity_id=patient.id,
                     clinic_id=clinic_id, actor_user_id=actor_user_id,
                     new={"override_of": [str(m.id) for m in matches]})
    db.commit()
    db.refresh(patient)
    return patient


def search_patients(db, *, clinic_id, q: str | None, limit: int = 20, offset: int = 0) -> list[Patient]:
    stmt = select(Patient).where(Patient.clinic_id == clinic_id)
    if q:
        pn = normalize_phone(q)
        conditions = [func.similarity(Patient.name, q) > 0.2]
        if pn:
            conditions.append(Patient.phone_normalized.like(f"%{pn}%"))
        stmt = stmt.where(or_(*conditions)).order_by(func.similarity(Patient.name, q).desc())
    else:
        stmt = stmt.order_by(Patient.created_at.desc())
    return list(db.execute(stmt.limit(limit).offset(offset)).scalars().all())


def get_patient(db, clinic_id, patient_id) -> Patient:
    patient = db.get(Patient, patient_id)
    if patient is None or patient.clinic_id != clinic_id:
        raise NotFoundError("Patient not found.")
    return patient


def update_patient(db, *, clinic_id, patient_id, actor_user_id, data: PatientUpdate) -> Patient:
    patient = get_patient(db, clinic_id, patient_id)
    changes = data.model_dump(exclude_unset=True)
    previous = {k: getattr(patient, k) for k in changes}
    for k, v in changes.items():
        setattr(patient, k, v)
    if "phone" in changes:
        patient.phone_normalized = normalize_phone(patient.phone)
    db.flush()
    record_audit(db, action="patient.updated", entity_type="patient", entity_id=patient.id,
                 clinic_id=clinic_id, actor_user_id=actor_user_id, previous=previous, new=changes)
    db.commit()
    db.refresh(patient)
    return patient


def delete_patient(db, *, clinic_id, patient_id, actor_user_id) -> None:
    patient = get_patient(db, clinic_id, patient_id)
    snapshot = {"name": patient.name, "phone": patient.phone, "age": patient.age}
    record_audit(db, action="patient.deleted", entity_type="patient", entity_id=patient.id,
                 clinic_id=clinic_id, actor_user_id=actor_user_id, previous=snapshot)
    db.delete(patient)
    db.commit()
```

- [ ] **Step 4: Router**

`app/modules/patients/router.py`:
```python
import uuid

from fastapi import APIRouter, status

from app.core.deps import DbSession
from app.modules.members.deps import CurrentMembership
from app.modules.patients import service
from app.modules.patients.schemas import (
    DuplicateCheckRequest, DuplicateMatches, PatientCreate, PatientRead, PatientUpdate,
)

router = APIRouter(prefix="/clinics", tags=["patients"])


@router.post("/{clinic_id}/patients", response_model=PatientRead, status_code=status.HTTP_201_CREATED)
def create_patient(clinic_id: uuid.UUID, data: PatientCreate, db: DbSession, membership: CurrentMembership):
    return service.create_patient(db, clinic_id=clinic_id, actor_user_id=membership.user_id, data=data)


@router.post("/{clinic_id}/patients/duplicate-check", response_model=DuplicateMatches)
def duplicate_check(clinic_id: uuid.UUID, data: DuplicateCheckRequest, db: DbSession, membership: CurrentMembership):
    matches = service.find_duplicates(db, clinic_id=clinic_id, name=data.name, phone=data.phone, age=data.age)
    return DuplicateMatches(matches=[PatientRead.model_validate(m) for m in matches])


@router.get("/{clinic_id}/patients", response_model=list[PatientRead])
def search_patients(clinic_id: uuid.UUID, db: DbSession, membership: CurrentMembership,
                    q: str | None = None, limit: int = 20, offset: int = 0):
    return service.search_patients(db, clinic_id=clinic_id, q=q, limit=limit, offset=offset)


@router.get("/{clinic_id}/patients/{patient_id}", response_model=PatientRead)
def get_patient(clinic_id: uuid.UUID, patient_id: uuid.UUID, db: DbSession, membership: CurrentMembership):
    return service.get_patient(db, clinic_id, patient_id)


@router.patch("/{clinic_id}/patients/{patient_id}", response_model=PatientRead)
def update_patient(clinic_id: uuid.UUID, patient_id: uuid.UUID, data: PatientUpdate, db: DbSession, membership: CurrentMembership):
    return service.update_patient(db, clinic_id=clinic_id, patient_id=patient_id, actor_user_id=membership.user_id, data=data)


@router.delete("/{clinic_id}/patients/{patient_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_patient(clinic_id: uuid.UUID, patient_id: uuid.UUID, db: DbSession, membership: CurrentMembership, confirm: bool = False):
    if not confirm:
        from app.core.errors import DomainError
        raise DomainError("Deletion requires confirm=true.")
    service.delete_patient(db, clinic_id=clinic_id, patient_id=patient_id, actor_user_id=membership.user_id)
```
Mount in `app/main.py`.

- [ ] **Step 5: Tests**

`tests/patients/test_patients.py` — covers create, duplicate handshake (phone-exact + fuzzy-name+age), warn-not-block, search, delete-with-confirm, audit, cross-clinic isolation:
```python
OWNER = "11111111-1111-1111-1111-111111111111"
OTHER = "99999999-9999-9999-9999-999999999999"


def _clinic(client):
    return client.post("/api/v1/clinics", json={"name": "C"}).json()["id"]


def _new(client, cid, **kw):
    body = {"name": "Asha Rao", "phone": "+91 98765 43210", "age": 30, **kw}
    return client.post(f"/api/v1/clinics/{cid}/patients", json=body)


def test_create_patient(auth_client):
    owner, _ = auth_client(sub=OWNER)
    cid = _clinic(owner)
    assert _new(owner, cid).status_code == 201


def test_duplicate_phone_warns_then_allows_override(auth_client):
    owner, _ = auth_client(sub=OWNER)
    cid = _clinic(owner)
    assert _new(owner, cid).status_code == 201
    # same phone (different formatting) → warning, not blocked
    dup = owner.post(f"/api/v1/clinics/{cid}/patients",
                     json={"name": "Asha R", "phone": "9876543210", "age": 31})
    assert dup.status_code == 409
    assert dup.json()["error"]["code"] == "duplicate_warning"
    assert dup.json()["error"]["details"]["matches"]
    # resubmit acknowledging → created
    ok = owner.post(f"/api/v1/clinics/{cid}/patients",
                    json={"name": "Asha R", "phone": "9876543210", "age": 31, "acknowledge_duplicates": True})
    assert ok.status_code == 201


def test_fuzzy_name_plus_age_warns(auth_client):
    owner, _ = auth_client(sub=OWNER)
    cid = _clinic(owner)
    _new(owner, cid, name="Rajesh Kumar", phone="111", age=40)
    dup = owner.post(f"/api/v1/clinics/{cid}/patients",
                     json={"name": "Rajesh Kumr", "phone": "222", "age": 41})
    assert dup.status_code == 409  # similar name + age within 2


def test_no_warning_for_distinct_patient(auth_client):
    owner, _ = auth_client(sub=OWNER)
    cid = _clinic(owner)
    _new(owner, cid, name="Asha Rao", phone="111", age=30)
    ok = _new(owner, cid, name="Bhavna Singh", phone="222", age=55)
    assert ok.status_code == 201


def test_search_by_name_and_phone(auth_client):
    owner, _ = auth_client(sub=OWNER)
    cid = _clinic(owner)
    _new(owner, cid, name="Asha Rao", phone="+91 98765 43210", age=30)
    assert len(owner.get(f"/api/v1/clinics/{cid}/patients?q=asha").json()) >= 1
    assert len(owner.get(f"/api/v1/clinics/{cid}/patients?q=98765").json()) >= 1


def test_delete_requires_confirm_and_audits(auth_client, db_session):
    from sqlalchemy import select
    from app.modules.audit.models import AuditEvent
    owner, _ = auth_client(sub=OWNER)
    cid = _clinic(owner)
    pid = _new(owner, cid).json()["id"]
    assert owner.delete(f"/api/v1/clinics/{cid}/patients/{pid}").status_code == 400  # no confirm
    assert owner.delete(f"/api/v1/clinics/{cid}/patients/{pid}?confirm=true").status_code == 204
    actions = set(db_session.execute(select(AuditEvent.action)).scalars().all())
    assert "patient.deleted" in actions


def test_cross_clinic_patient_isolation(auth_client):
    owner, _ = auth_client(sub=OWNER)
    cid = _clinic(owner)
    pid = _new(owner, cid).json()["id"]
    other, _ = auth_client(sub=OTHER)
    _clinic(other)
    assert other.get(f"/api/v1/clinics/{cid}/patients/{pid}").status_code == 403
```
Run: `make test ARGS=tests/patients/` → PASS; full `make test` green.

- [ ] **Step 6:** Commit: `feat(patients): CRUD, pg_trgm search, duplicate-warning handshake + tests`.

## Task 9: Patient frontend (search + duplicate-warning UI)

**Files:** `src/features/patients/{api,hooks,patient-search,add-patient-form,duplicate-warning}.tsx/ts`; `src/app/patients/page.tsx`; modify `en.json`/`hi.json` (`patients.*`, `apiErrors.duplicate_warning`); `tests/e2e/patients.spec.ts`.

**Interfaces:**
- Consumes: `apiFetch`, `ApiError`, TanStack Query, `useTranslation`, RHF + Zod.
- Produces: `usePatientSearch(clinicId, q)`, `useCreatePatient(clinicId)`, `useDuplicateCheck(clinicId)`; `/patients` route with search + add form + non-blocking duplicate panel.

- [ ] **Step 1: API**

`src/features/patients/api.ts`:
```typescript
import { apiFetch } from "@/lib/api-client";

export type Patient = {
  id: string; clinic_id: string; name: string; phone: string; age: number;
  referral_source: string | null; medical_conditions: string | null;
  chief_complaint: string | null; notes: string | null; created_at: string;
};
export type PatientInput = {
  name: string; phone: string; age: number;
  referral_source?: string; medical_conditions?: string; chief_complaint?: string; notes?: string;
  acknowledge_duplicates?: boolean;
};

export const searchPatients = (clinicId: string, q: string) =>
  apiFetch<Patient[]>(`/api/v1/clinics/${clinicId}/patients?q=${encodeURIComponent(q)}`);

export const duplicateCheck = (clinicId: string, input: { name: string; phone: string; age: number }) =>
  apiFetch<{ matches: Patient[] }>(`/api/v1/clinics/${clinicId}/patients/duplicate-check`, {
    method: "POST", body: JSON.stringify(input),
  });

export const createPatient = (clinicId: string, input: PatientInput) =>
  apiFetch<Patient>(`/api/v1/clinics/${clinicId}/patients`, {
    method: "POST", body: JSON.stringify(input),
  });
```

- [ ] **Step 2: Hooks** — `usePatientSearch` (`useQuery`, keyed `["patients", clinicId, q]`, `enabled` always; debounce `q` in the component), `useCreatePatient` (`useMutation`, invalidates `["patients", clinicId]`), `useDuplicateCheck` (`useMutation`).

- [ ] **Step 3: i18n keys (both locales)**

Add to `en.json` (+ Hindi in `hi.json`, parity):
```json
"patients": {
  "title": "Patients", "search": "Search by name or phone", "add": "Add patient",
  "empty": "No patients found.",
  "name": "Name", "phone": "Phone", "age": "Age",
  "referralSource": "Referral source", "medicalConditions": "Medical conditions",
  "chiefComplaint": "Chief complaint", "notes": "Notes",
  "create": "Create", "createAnyway": "Create anyway", "cancel": "Cancel",
  "duplicateWarningTitle": "Possible duplicate patient(s)",
  "duplicateWarningBody": "These existing patients look similar. Review before creating.",
  "delete": "Delete", "confirmDelete": "Type the patient name to confirm deletion."
}
```
Add to `apiErrors` (both locales): `"duplicate_warning": "Possible duplicate patient — please review."`

- [ ] **Step 4: Duplicate-warning component** — `src/features/patients/duplicate-warning.tsx`: given `matches: Patient[]`, render a non-blocking panel (semantic tokens; `bg-muted`/`text-foreground`/`border-border`) titled `t('patients.duplicateWarningTitle')` listing each match (name · phone · age) with a `t('patients.createAnyway')` button and a cancel.

- [ ] **Step 5: Add form + search** — `add-patient-form.tsx`: RHF + Zod (schema built with `t()`; name/phone/age required). On submit, first call `useDuplicateCheck`; if matches → render `<DuplicateWarning>` and hold; "Create anyway" calls `createPatient` with `acknowledge_duplicates: true`. Also handle a server `409 duplicate_warning` (read `err.details.matches`) as a fallback. `patient-search.tsx`: debounced search input (`t('patients.search')`) → results list; "Add patient" opens the form.

- [ ] **Step 6: Route** — `src/app/patients/page.tsx`: `<AuthGate>` + `<PatientSearch/>`, clinic id from `useMe()`.

- [ ] **Step 7: Verify + e2e** — `tests/e2e/patients.spec.ts` (mocked backend): search renders results; adding a duplicate shows the warning panel; "Create anyway" succeeds; locale switch shows Hindi. Run `npx tsc --noEmit && npm run build && npm run test:e2e -- patients.spec.ts i18n.spec.ts` → green.

- [ ] **Step 8:** Commit + open Slice 3 PR (`sp2-patients`), closing the patient sub-issue.

---

## Post-implementation (after all three slices merge)

- [ ] Run `mcp__supabase__get_advisors` (security + performance) against project `wxwasnshmnttiixvzeod`; resolve any findings on the three new tables (expect: RLS enabled, not exposed to Data API).
- [ ] Update the GitHub Project #1 Status for epic #8 and its sub-issues as each slice moves Executing → In Review → Completed.
- [ ] Update each repo's `CLAUDE.md` if any new cross-cutting convention emerged (e.g. the `pg_trgm` search pattern, the entity↔member linking rule).

## Self-Review (performed by plan author)

- **Spec coverage:** §4 data model → Tasks 1/4/7; §5 lifecycles → Tasks 2/5/8; §6 dup+search → Task 8; §7 API → Tasks 2/5/8 routers; §8 authz → `_can_manage` guards + `CurrentMembership`; §9 audit → `record_audit` in every service; §10 frontend → Tasks 3/6/9; §12 testing → test steps each task; §13 migrations/RLS → Tasks 1/4/7 + post-impl advisors. All covered.
- **Type consistency:** `create_invite` extended signature used identically by doctors/assistants services; `link_user_to_doctor`/`link_user_to_assistant` names match the deferred imports in `accept_invite`; `set_member_status_for_user` defined in Task 2, reused in Task 5; `DuplicateWarningError`/code `duplicate_warning` consistent across service, error class, tests, and frontend `apiErrors` key.
- **Placeholder scan:** no TBDs; the only "mirror" instructions (Slice 2) give an explicit substitution table and point at concrete Slice-1 files, with the non-obvious deltas spelled out in full.
