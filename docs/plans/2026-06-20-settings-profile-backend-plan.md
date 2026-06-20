# Settings & Profile — BACKEND Slice Implementation Plan (#35)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Backend support for the Settings/Profile first pass — expose & edit the user's own profile (Full Name) and add an editable doctor License Number + a self doctor-profile update endpoint.

**Architecture:** Reuse the **existing `AppUser.name`** column as "Full Name" (no new user column). Add one new column `doctor_beta.license_number`. Extend `GET /me` with `name` + `joined_at`; add `PATCH /me/profile` (self) and `PATCH /clinics/{id}/doctors/me` (self doctor update, mirroring the existing `create_self_doctor`). In-transaction audit on each mutation. This is the BACKEND slice; the frontend UI is a separate plan built afterward.

**Tech Stack:** FastAPI, SQLAlchemy 2.x (sync), Pydantic v2, Alembic, pytest (local Postgres :5433).

## Global Constraints

- **`AppUser.name` already exists** (nullable, unused) → it IS "Full Name". Do NOT add a new user column.
- **Only new column:** `doctor_beta.license_number` (`String(100)`, nullable). One Alembic revision **0011** (down_revision **0010**).
- **Migrations are controller-applied to Supabase via MCP after merge.** Implementers add the revision + model and validate with **`make test`** only — NEVER run `make migrate`/alembic against the configured DB (repo `.env` points at Supabase).
- Uniform error envelope `{error:{code,message,details}}`; raise `NotFoundError` (from `app/core/errors.py`) for missing records. Audit every mutation in-transaction via `record_audit` (signature: `record_audit(db, *, action, entity_type, entity_id, clinic_id=None, actor_user_id=None, previous=None, new=None, reason=None)`).
- Self endpoints act only on the authenticated caller's own records. No new dependencies. Commit trailer `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`. Feature branch → PR (never push `main`).

---

## File Structure
- Modify: `app/modules/auth/schemas.py` (MeRead += name/joined_at; new ProfileUpdate/ProfileRead).
- Modify: `app/modules/auth/router.py` (`/me` returns name/joined_at; new `PATCH /me/profile`).
- Modify: `app/modules/auth/service.py` (new `update_profile`).
- Modify: `app/modules/doctors/models.py` (Doctor += license_number).
- Create: `alembic/versions/0011_doctor_license.py`.
- Modify: `app/modules/doctors/schemas.py` (DoctorRead/DoctorUpdate += license_number; new DoctorSelfUpdate).
- Modify: `app/modules/doctors/router.py` (`PATCH /{clinic_id}/doctors/me`).
- Modify: `app/modules/doctors/service.py` (new `update_self_doctor`).
- Test: `tests/auth/test_me.py`, `tests/doctors/test_self_profile.py`.
- Docs (docs repo): Entities.

---

## Task 1: Profile on `/me` + `PATCH /me/profile`

**Files:** Modify `app/modules/auth/schemas.py`, `app/modules/auth/router.py`, `app/modules/auth/service.py`; Test `tests/auth/test_me.py`.

**Interfaces:**
- Produces: `MeRead` gains `name: str | None`, `joined_at: datetime | None`; `PATCH /me/profile` body `ProfileUpdate { name?: str }` → `ProfileRead { user_id, name, email, phone, joined_at }`; `auth.service.update_profile(db, *, user, data) -> AppUser`.

- [ ] **Step 1: Write failing tests** — append to `tests/auth/test_me.py`:
```python
def test_me_includes_name_and_joined_at(auth_client) -> None:
    c, _ = auth_client(sub=OWNER)
    make_clinic(c, name="C")
    body = c.get("/api/v1/me").json()
    assert "name" in body
    assert body["joined_at"] is not None


def test_update_profile_sets_name(auth_client) -> None:
    c, _ = auth_client(sub=OWNER)
    make_clinic(c, name="C")
    resp = c.patch("/api/v1/me/profile", json={"name": "Dr. Sayali Patil"})
    assert resp.status_code == 200
    assert resp.json()["name"] == "Dr. Sayali Patil"
    assert c.get("/api/v1/me").json()["name"] == "Dr. Sayali Patil"


def test_update_profile_requires_auth(client) -> None:
    assert client.patch("/api/v1/me/profile", json={"name": "X"}).status_code == 401


def test_update_profile_unknown_user_404(auth_client) -> None:
    c, _ = auth_client(sub="22222222-2222-2222-2222-222222222222")
    # No onboarding => no AppUser row yet.
    assert c.patch("/api/v1/me/profile", json={"name": "X"}).status_code == 404
```

- [ ] **Step 2: Run → fail** — `cd dentist-registry-backend && make test` (or `docker compose up -d && .venv/bin/pytest tests/auth/test_me.py -v`). Expect failures (404 route missing / KeyError name).

- [ ] **Step 3: Schemas** — in `app/modules/auth/schemas.py`, add `from datetime import datetime` and `from pydantic import BaseModel, Field`; extend `MeRead` and add the two schemas:
```python
class MeRead(BaseModel):
    user_id: uuid.UUID | None
    email: str | None
    phone: str | None
    needs_onboarding: bool
    memberships: list[MembershipRead]
    doctor_id: uuid.UUID | None = None
    name: str | None = None
    joined_at: datetime | None = None


class ProfileUpdate(BaseModel):
    name: str | None = Field(default=None, max_length=200)


class ProfileRead(BaseModel):
    user_id: uuid.UUID
    name: str | None
    email: str | None
    phone: str | None
    joined_at: datetime
```

- [ ] **Step 4: Service** — in `app/modules/auth/service.py`, add imports `from app.modules.audit.service import record_audit` and `from app.modules.auth.schemas import ProfileUpdate`, and:
```python
def update_profile(db: Session, *, user: AppUser, data: ProfileUpdate) -> AppUser:
    changes = data.model_dump(exclude_unset=True)
    previous = {k: getattr(user, k) for k in changes}
    for k, v in changes.items():
        setattr(user, k, v)
    db.flush()
    record_audit(
        db,
        action="profile.updated",
        entity_type="app_user",
        entity_id=user.id,
        actor_user_id=user.id,
        previous=previous,
        new=changes,
    )
    return user
```
(If `Session` isn't imported there yet, add `from sqlalchemy.orm import Session`.)

- [ ] **Step 5: Router** — in `app/modules/auth/router.py`: add imports `from app.core.errors import NotFoundError`, `from app.modules.auth import service` (and `ProfileRead, ProfileUpdate` to the schemas import). In the `me()` handler, add `name` + `joined_at` to the **user-found** return:
```python
    return MeRead(
        user_id=user.id, email=user.email, phone=user.phone,
        needs_onboarding=len(memberships) == 0, memberships=memberships,
        doctor_id=doctor_id, name=user.name, joined_at=user.created_at,
    )
```
(The no-user branch leaves `name`/`joined_at` at their defaults.) Add the new endpoint:
```python
@router.patch("/me/profile", response_model=ProfileRead)
def update_my_profile(data: ProfileUpdate, auth: CurrentAuth, db: DbSession) -> ProfileRead:
    user = get_user_by_auth_id(db, uuid.UUID(auth.sub))
    if user is None:
        raise NotFoundError("User not found.")
    user = service.update_profile(db, user=user, data=data)
    return ProfileRead(
        user_id=user.id, name=user.name, email=user.email,
        phone=user.phone, joined_at=user.created_at,
    )
```
(Keep the existing `from app.modules.auth.service import get_user_by_auth_id` import working — either import the module as `service` and call `service.get_user_by_auth_id`, or keep both; ensure `update_profile` is reachable.)

- [ ] **Step 6: Run → pass** — `make test` (or `pytest tests/auth/test_me.py -v`). All green.

- [ ] **Step 7: Commit**
```bash
git add app/modules/auth/ tests/auth/test_me.py
git commit -m "feat(auth): expose name+joined_at on /me and add PATCH /me/profile

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: Doctor `license_number` + self doctor-update endpoint (+ migration 0011)

**Files:** Modify `app/modules/doctors/models.py`, `schemas.py`, `router.py`, `service.py`; Create `alembic/versions/0011_doctor_license.py`; Test `tests/doctors/test_self_profile.py`.

**Interfaces:**
- Consumes: `get_my_doctor(db, clinic_id, user_id)` (existing).
- Produces: `doctor_beta.license_number`; `DoctorRead.license_number`; `DoctorUpdate.license_number`; `DoctorSelfUpdate { name?, phone?, specialty?, license_number? }`; `PATCH /clinics/{clinic_id}/doctors/me`; `doctors.service.update_self_doctor(db, *, clinic_id, user_id, data) -> Doctor`.

- [ ] **Step 1: Write failing tests** — append to `tests/doctors/test_self_profile.py` (uses the existing `auth_client`/`make_clinic` fixtures; `OWNER` constant if present, else define `OWNER = "11111111-1111-1111-1111-111111111111"`):
```python
def test_self_update_doctor_fields(auth_client) -> None:
    c, _ = auth_client(sub=OWNER)
    clinic = make_clinic(c, name="C")
    c.post(f"/api/v1/clinics/{clinic}/doctors/me", json={"name": "Dr. A", "phone": "+91 90000 00000"})
    resp = c.patch(
        f"/api/v1/clinics/{clinic}/doctors/me",
        json={"name": "Dr. Sayali", "specialty": "Cosmetic Dentist", "license_number": "A-12345"},
    )
    assert resp.status_code == 200
    body = resp.json()
    assert body["name"] == "Dr. Sayali"
    assert body["specialty"] == "Cosmetic Dentist"
    assert body["license_number"] == "A-12345"


def test_self_update_doctor_without_profile_404(auth_client) -> None:
    c, _ = auth_client(sub=OWNER)
    clinic = make_clinic(c, name="C")
    assert c.patch(f"/api/v1/clinics/{clinic}/doctors/me", json={"specialty": "X"}).status_code == 404


def test_admin_update_sets_license(auth_client) -> None:
    c, _ = auth_client(sub=OWNER)
    clinic = make_clinic(c, name="C")
    did = c.post(
        f"/api/v1/clinics/{clinic}/doctors", json={"name": "Dr. B", "phone": "+91 90000 00001"}
    ).json()["doctor"]["id"]
    resp = c.patch(f"/api/v1/clinics/{clinic}/doctors/{did}", json={"license_number": "B-999"})
    assert resp.status_code == 200
    assert resp.json()["license_number"] == "B-999"
```
(If `OWNER`/`make_clinic` aren't already imported in this file, add `from tests.conftest import make_clinic` and the `OWNER` constant, mirroring `tests/auth/test_me.py`.)

- [ ] **Step 2: Run → fail** — `make test` (or `pytest tests/doctors/test_self_profile.py -v`). Expect failures (route 404 / unknown field).

- [ ] **Step 3: Model column** — in `app/modules/doctors/models.py`, add after the `specialty` column:
```python
    license_number: Mapped[str | None] = mapped_column(String(100), nullable=True)
```

- [ ] **Step 4: Migration** — create `alembic/versions/0011_doctor_license.py`:
```python
"""doctor license number

Revision ID: 0011
Revises: 0010
Create Date: 2026-06-20

"""
from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "0011"
down_revision: str | None = "0010"
branch_labels: Sequence[str] | None = None
depends_on: Sequence[str] | None = None


def upgrade() -> None:
    op.add_column("doctor_beta", sa.Column("license_number", sa.String(length=100), nullable=True))


def downgrade() -> None:
    op.drop_column("doctor_beta", "license_number")
```

- [ ] **Step 5: Schemas** — in `app/modules/doctors/schemas.py`: add `license_number: str | None = None` to **`DoctorRead`** and to **`DoctorUpdate`**; add the self-update schema:
```python
class DoctorSelfUpdate(BaseModel):
    name: str | None = Field(default=None, min_length=1, max_length=200)
    phone: str | None = Field(default=None, min_length=1, max_length=32)
    specialty: str | None = Field(default=None, max_length=200)
    license_number: str | None = Field(default=None, max_length=100)
```

- [ ] **Step 6: Service** — in `app/modules/doctors/service.py`, add:
```python
def update_self_doctor(
    db: Session, *, clinic_id: uuid.UUID, user_id: uuid.UUID, data: DoctorSelfUpdate
) -> Doctor:
    doctor = get_my_doctor(db, clinic_id, user_id)
    if doctor is None:
        raise NotFoundError("Doctor profile not found.")
    changes = data.model_dump(exclude_unset=True)
    previous = {k: getattr(doctor, k) for k in changes}
    for k, v in changes.items():
        setattr(doctor, k, v)
    db.flush()
    record_audit(
        db,
        action="doctor.updated",
        entity_type="doctor",
        entity_id=doctor.id,
        clinic_id=clinic_id,
        actor_user_id=user_id,
        previous=previous,
        new=changes,
    )
    return doctor
```
(Add `DoctorSelfUpdate` to the schemas import; `record_audit`/`NotFoundError`/`get_my_doctor` are already imported/defined in this module.)

- [ ] **Step 7: Router** — in `app/modules/doctors/router.py`, add `DoctorSelfUpdate` to the schemas import, and add the handler **immediately after `create_self_doctor`** (so the literal `/me` is matched before `/{doctor_id}`):
```python
@router.patch("/{clinic_id}/doctors/me", response_model=DoctorRead)
def update_self_doctor(
    clinic_id: uuid.UUID,
    data: DoctorSelfUpdate,
    db: DbSession,
    membership: CurrentMembership,
):
    return service.update_self_doctor(
        db, clinic_id=clinic_id, user_id=membership.user_id, data=data
    )
```

- [ ] **Step 8: Run → pass** — `make test`. All green (incl. Task 1 tests).

- [ ] **Step 9: Commit**
```bash
git add app/modules/doctors/ alembic/versions/0011_doctor_license.py tests/doctors/test_self_profile.py
git commit -m "feat(doctors): license_number + self doctor-profile update endpoint (migration 0011)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: Docs — Entities (docs repo)

**Files (in `dentail-register-docs`):** the Entities reference (e.g. `Entities/…` / PRD entities section).

- [ ] **Step 1:** `git checkout main && git pull --ff-only && git checkout -b docs/settings-profile-backend-35`.
- [ ] **Step 2:** Note in the Entities doc: `AppUser.name` is the user's **Full Name** (now surfaced on `/me` + editable via `PATCH /me/profile`); `Doctor.license_number` (nullable) added; new self endpoints `PATCH /me/profile` and `PATCH /clinics/{id}/doctors/me`. Reference `docs/specs/2026-06-20-settings-profile-design.md` (#35).
- [ ] **Step 3: Commit** (docs repo) with the trailer.

---

## Migration handoff (controller, after merge)
Generate offline SQL and apply 0011 to Supabase via MCP:
```bash
ALEMBIC_DB_URL=postgresql+psycopg://x:x@localhost/x .venv/bin/alembic upgrade 0010:0011 --sql
```
then Supabase MCP `apply_migration` with that DDL (`ALTER TABLE doctor_beta ADD COLUMN license_number varchar(100)`). Implementers do NOT apply to Supabase.

## Final Verification (before PRs)
- [ ] `make test` green (auth + doctors suites).
- [ ] Frontend untouched (this is the backend slice). Backend PR `Part of #35`.

## Self-Review (against the spec §3)
- **AppUser.name surfaced + editable:** Task 1 (MeRead.name/joined_at + PATCH /me/profile). Uses existing column — no new user migration. ✅
- **Doctor.license_number (new column + migration):** Task 2 (model + 0011 + DoctorRead/Update). ✅
- **Self doctor edit (name/specialty/license):** Task 2 `PATCH /clinics/{id}/doctors/me` + `update_self_doctor` (self-only via `get_my_doctor`; 404 when no profile). ✅
- **Admin doctor edit gains license:** Task 2 (DoctorUpdate += license_number; existing `update_doctor` setattr loop carries it). ✅
- **Audit + uniform errors:** every mutation calls `record_audit`; `NotFoundError` for missing. ✅
- **Migration controller-applied:** Global Constraints + Migration handoff. ✅
- **Out of scope (avatar/email/phone change/preferences/clinic tz):** no tasks touch them. ✅
- **Placeholder scan:** all code blocks complete with real signatures (record_audit verified, fixtures `auth_client`/`make_clinic` verified, head 0010→0011 verified). ✅
- **Type consistency:** `ProfileUpdate`/`ProfileRead`/`update_profile`/`DoctorSelfUpdate`/`update_self_doctor` names consistent across schemas/router/service/tests. ✅
