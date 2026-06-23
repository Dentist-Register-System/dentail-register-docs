# Member Profile Drawer (#107) — Backend Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add four profile fields (DOB / gender / address / working hours) to doctor & assistant, surface them in reads, extend doctor self-update, and add a brand-new assistant self-update endpoint + `assistant_id` on `/me`.

**Architecture:** Migration `0018` adds the columns to both `*_beta` tables (gender CHECK mirrors patient 0014). Reads gain the fields. `DoctorSelfUpdate` gains them (route `/doctors/me` already exists). Assistants get a new self path mirroring doctors: `get_my_assistant` + `update_self_assistant` + `PATCH /clinics/{id}/assistants/me`. `/me` gains `assistant_id` (mirrors `doctor_id`) so the Settings pane can pre-fill an assistant's own record.

**Tech Stack:** FastAPI, SQLAlchemy 2.x sync, Pydantic v2, Alembic, pytest on Postgres :5433.

## Global Constraints
- Spec: `docs/specs/2026-06-23-member-profile-drawer-design.md`. Backend half of #107.
- New fields (both tables, all nullable): `date_of_birth` DATE; `gender` VARCHAR(10) + CHECK `IN ('male','female','other')`; `address` VARCHAR(500); `working_hours` VARCHAR(200).
- **Self-service edit only** for personal fields: they are settable via the SELF endpoints (`/doctors/me`, `/assistants/me`) — NOT via the owner/manager `DoctorUpdate`/`AssistantUpdate` schemas (leave those field sets unchanged).
- Migration `0018` chains off `0017` (`down_revision="0017"`). Implementers run alembic on LOCAL PG :5433 only; controller applies to Supabase via MCP + bumps `alembic_version`.
- `uv run ruff check .` clean; `make test` green. Absolute imports. In-transaction audit.

## File Structure
- Create: `alembic/versions/0018_member_profile_fields.py`.
- Modify: `app/modules/doctors/models.py`, `app/modules/assistants/models.py` (4 columns each).
- Modify: `app/modules/doctors/schemas.py` (DoctorRead + DoctorSelfUpdate += 4 fields).
- Modify: `app/modules/assistants/schemas.py` (AssistantRead += 4 fields; new AssistantSelfUpdate).
- Modify: `app/modules/assistants/service.py` (get_my_assistant + update_self_assistant).
- Modify: `app/modules/assistants/router.py` (PATCH /assistants/me).
- Modify: `app/modules/auth/schemas.py` + `app/modules/auth/router.py` (MeRead.assistant_id).
- Tests: `tests/doctors/test_self_profile.py` (extend), `tests/assistants/test_assistant_self.py` (new), `tests/auth/` (me assistant_id).

---

### Task 1: Migration 0018 + new fields on both members + reads + doctor self-update

**Files:**
- Create: `alembic/versions/0018_member_profile_fields.py`
- Modify: doctors/models.py, assistants/models.py, doctors/schemas.py, assistants/schemas.py
- Test: `tests/doctors/test_self_profile.py`

**Interfaces:**
- Produces: `Doctor`/`Assistant` models + `DoctorRead`/`AssistantRead` gain `date_of_birth: date | None`, `gender: str | None`, `address: str | None`, `working_hours: str | None`. `DoctorSelfUpdate` gains the same 4 (optional). A shared `_VALID_GENDERS = ("male","female","other")` validator on the writable schemas.

- [ ] **Step 1: Write the failing test** — extend `tests/doctors/test_self_profile.py`:

```python
def test_doctor_self_update_persists_profile_fields(auth_client):
    from tests.conftest import make_clinic
    owner, _ = auth_client(sub="eeee0000-0000-0000-0000-000000000001")
    cid = make_clinic(owner)
    # owner self-creates a doctor profile (existing endpoint)
    owner.post(f"/api/v1/clinics/{cid}/doctors/me", json={"name": "Dr Self", "phone": "+1 555"})
    resp = owner.patch(f"/api/v1/clinics/{cid}/doctors/me", json={
        "date_of_birth": "1990-08-12", "gender": "female",
        "address": "Baner, Pune 411045", "working_hours": "Mon-Sat 10-6",
    })
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["date_of_birth"] == "1990-08-12"
    assert body["gender"] == "female"
    assert body["address"] == "Baner, Pune 411045"
    assert body["working_hours"] == "Mon-Sat 10-6"

def test_doctor_self_update_rejects_bad_gender(auth_client):
    from tests.conftest import make_clinic
    owner, _ = auth_client(sub="eeee0000-0000-0000-0000-000000000002")
    cid = make_clinic(owner)
    owner.post(f"/api/v1/clinics/{cid}/doctors/me", json={"name": "Dr X", "phone": "+1"})
    assert owner.patch(f"/api/v1/clinics/{cid}/doctors/me", json={"gender": "n/a"}).status_code == 422
```

- [ ] **Step 2: Run, verify fail.** `uv run pytest tests/doctors/test_self_profile.py -k profile_fields -v` → FAIL (fields unknown / 200 with missing keys).

- [ ] **Step 3: Migration** `alembic/versions/0018_member_profile_fields.py` (mirror 0014's gender CHECK for BOTH tables):

```python
"""member profile fields: dob/gender/address/working_hours on doctor + assistant

Revision ID: 0018
Revises: 0017
"""
import sqlalchemy as sa
from alembic import op

revision = "0018"
down_revision = "0017"
branch_labels = None
depends_on = None

_TABLES = ("doctor_beta", "assistant_beta")

def upgrade() -> None:
    for tbl in _TABLES:
        op.add_column(tbl, sa.Column("date_of_birth", sa.Date(), nullable=True))
        op.add_column(tbl, sa.Column("gender", sa.String(length=10), nullable=True))
        op.add_column(tbl, sa.Column("address", sa.String(length=500), nullable=True))
        op.add_column(tbl, sa.Column("working_hours", sa.String(length=200), nullable=True))
        op.create_check_constraint(f"ck_{tbl}_gender", tbl, "gender IN ('male','female','other')")

def downgrade() -> None:
    for tbl in _TABLES:
        op.drop_constraint(f"ck_{tbl}_gender", tbl, type_="check")
        for col in ("working_hours", "address", "gender", "date_of_birth"):
            op.drop_column(tbl, col)
```

- [ ] **Step 4: Model columns** — add to `Doctor` and `Assistant` (import `date` from datetime):

```python
    date_of_birth: Mapped[date | None] = mapped_column(Date, nullable=True)
    gender: Mapped[str | None] = mapped_column(String(10), nullable=True)
    address: Mapped[str | None] = mapped_column(String(500), nullable=True)
    working_hours: Mapped[str | None] = mapped_column(String(200), nullable=True)
```

(Add `from datetime import date` and `Date` to the sqlalchemy import.)

- [ ] **Step 5: Schemas** — `DoctorRead` + `AssistantRead` add `date_of_birth: dt.date | None = None`, `gender: str | None = None`, `address: str | None = None`, `working_hours: str | None = None`. `DoctorSelfUpdate` adds the same 4 as optional, plus a gender validator:

```python
from pydantic import field_validator
_VALID_GENDERS = ("male", "female", "other")

# in DoctorSelfUpdate:
    date_of_birth: dt.date | None = None
    gender: str | None = None
    address: str | None = Field(default=None, max_length=500)
    working_hours: str | None = Field(default=None, max_length=200)

    @field_validator("gender")
    @classmethod
    def _gender(cls, v):
        if v is not None and v not in _VALID_GENDERS:
            raise ValueError("invalid gender")
        return v
```

- [ ] **Step 6: Apply migration locally + run tests.** `ALEMBIC_DB_URL=$TEST_DATABASE_URL alembic upgrade head` then `uv run pytest tests/doctors/test_self_profile.py -v` → PASS.

- [ ] **Step 7: Commit**

```bash
git add alembic/versions/0018_member_profile_fields.py app/modules/doctors app/modules/assistants tests/doctors/test_self_profile.py
git commit -m "feat(members): dob/gender/address/working_hours fields + doctor self-update (0018) (#107)"
```

---

### Task 2: Assistant self-update endpoint + `assistant_id` on /me

**Files:**
- Modify: `app/modules/assistants/schemas.py` (AssistantSelfUpdate), `app/modules/assistants/service.py` (get_my_assistant, update_self_assistant), `app/modules/assistants/router.py` (PATCH /assistants/me)
- Modify: `app/modules/auth/schemas.py` (MeRead.assistant_id), `app/modules/auth/router.py` (populate it)
- Test: `tests/assistants/test_assistant_self.py` (new)

**Interfaces:**
- Consumes: the new model fields (Task 1).
- Produces:
  - `AssistantSelfUpdate { name?, phone?, title?, date_of_birth?, gender?, address?, working_hours? }` (gender validator).
  - `service.get_my_assistant(db, clinic_id, user_id) -> Assistant | None` (by `clinic_id` + `linked_user_id == user_id`).
  - `service.update_self_assistant(db, *, clinic_id, user_id, data) -> Assistant` (404 if none; model_dump exclude_unset; audit `assistant.updated`; commit).
  - Route `PATCH /clinics/{clinic_id}/assistants/me` → `AssistantRead` (CurrentMembership, self).
  - `MeRead.assistant_id: uuid.UUID | None` populated like `doctor_id`.

- [ ] **Step 1: Write failing tests** (`tests/assistants/test_assistant_self.py`)

```python
def _setup_joined_assistant(auth_client):
    from tests.conftest import make_clinic
    owner, _ = auth_client(sub="ffff0000-0000-0000-0000-000000000001")
    cid = make_clinic(owner)
    res = owner.post(f"/api/v1/clinics/{cid}/assistants", json={"name": "Asha", "email": "asha@x.com"})
    token = res.json()["invite_token"]
    asst, _ = auth_client(sub="ffff0000-0000-0000-0000-000000000002")
    asst.post("/api/v1/clinics/join", json={"token": token})
    return owner, asst, cid

def test_assistant_self_update_persists(auth_client):
    owner, asst, cid = _setup_joined_assistant(auth_client)
    resp = asst.patch(f"/api/v1/clinics/{cid}/assistants/me", json={
        "title": "Receptionist", "date_of_birth": "1992-03-04",
        "gender": "male", "address": "Pune", "working_hours": "Mon-Fri 9-5",
    })
    assert resp.status_code == 200, resp.text
    b = resp.json()
    assert b["title"] == "Receptionist" and b["gender"] == "male"
    assert b["date_of_birth"] == "1992-03-04" and b["address"] == "Pune"

def test_assistant_self_update_404_when_not_an_assistant(auth_client):
    from tests.conftest import make_clinic
    owner, _ = auth_client(sub="ffff0000-0000-0000-0000-000000000003")
    cid = make_clinic(owner)  # owner is not an assistant
    assert owner.patch(f"/api/v1/clinics/{cid}/assistants/me", json={"title": "X"}).status_code == 404

def test_assistant_self_update_bad_gender_422(auth_client):
    owner, asst, cid = _setup_joined_assistant(auth_client)
    assert asst.patch(f"/api/v1/clinics/{cid}/assistants/me", json={"gender": "nope"}).status_code == 422

def test_me_includes_assistant_id(auth_client):
    owner, asst, cid = _setup_joined_assistant(auth_client)
    me = asst.get("/api/v1/me").json()
    assert me["assistant_id"] is not None
```

- [ ] **Step 2: Run, verify fail.** `uv run pytest tests/assistants/test_assistant_self.py -v`

- [ ] **Step 3: Schema** — add to `assistants/schemas.py`:

```python
class AssistantSelfUpdate(BaseModel):
    name: str | None = Field(default=None, min_length=1, max_length=200)
    phone: str | None = Field(default=None, max_length=32)
    title: str | None = Field(default=None, max_length=200)
    date_of_birth: dt.date | None = None
    gender: str | None = None
    address: str | None = Field(default=None, max_length=500)
    working_hours: str | None = Field(default=None, max_length=200)

    @field_validator("gender")
    @classmethod
    def _gender(cls, v):
        if v is not None and v not in ("male", "female", "other"):
            raise ValueError("invalid gender")
        return v
```

- [ ] **Step 4: Service** — add to `assistants/service.py` (mirror `get_my_doctor`/`update_self_doctor`):

```python
def get_my_assistant(db: Session, clinic_id: uuid.UUID, user_id: uuid.UUID) -> Assistant | None:
    return db.execute(
        select(Assistant).where(
            Assistant.clinic_id == clinic_id, Assistant.linked_user_id == user_id
        )
    ).scalar_one_or_none()

def update_self_assistant(db, *, clinic_id, user_id, data: AssistantSelfUpdate) -> Assistant:
    assistant = get_my_assistant(db, clinic_id, user_id)
    if assistant is None:
        raise NotFoundError("Assistant profile not found.")
    changes = data.model_dump(exclude_unset=True)
    previous = {k: getattr(assistant, k) for k in changes}
    for k, v in changes.items():
        setattr(assistant, k, v)
    db.flush()
    record_audit(db, action="assistant.updated", entity_type="assistant",
                 entity_id=assistant.id, clinic_id=clinic_id, actor_user_id=user_id,
                 previous=previous, new=changes)
    db.commit()
    db.refresh(assistant)
    return assistant
```

(Import `AssistantSelfUpdate`, `NotFoundError`, `record_audit`, `select` as needed.)

- [ ] **Step 5: Route** — add to `assistants/router.py` BEFORE `/{assistant_id}`:

```python
@router.patch("/{clinic_id}/assistants/me", response_model=AssistantRead)
def update_self_assistant(clinic_id: uuid.UUID, data: schemas.AssistantSelfUpdate,
                          db: DbSession, membership: CurrentMembership):
    return service.update_self_assistant(db, clinic_id=clinic_id, user_id=membership.user_id, data=data)
```

(Route order: `/assistants/me` and `/assistants/page` before `/assistants/{assistant_id}`.)

- [ ] **Step 6: `assistant_id` on /me** — in `auth/schemas.py` `MeRead` add `assistant_id: uuid.UUID | None = None`; in `auth/router.py` populate it the same way `doctor_id` is (look up the assistant by the resolved user across their membership clinic — mirror the existing doctor_id composition exactly).

- [ ] **Step 7: Run, verify PASS.** `uv run pytest tests/assistants tests/auth -v` + `uv run ruff check .`

- [ ] **Step 8: Commit**

```bash
git add app/modules/assistants app/modules/auth tests/assistants/test_assistant_self.py
git commit -m "feat(assistants): self-update endpoint (PATCH /assistants/me) + assistant_id on /me (#107)"
```

---

## Self-Review (against the spec)
- §3 migration 0018: four fields both tables + gender CHECK: Task 1. ✅
- §4 reads include fields; DoctorSelfUpdate extended: Task 1. ✅
- §4 NEW assistant self-update (schema+service+route) + 404 + gender 422: Task 2. ✅
- §5d `assistant_id` on /me (so the pane pre-fills assistant self): Task 2. ✅
- §4 owner/manager update schemas UNCHANGED (personal fields not added to DoctorUpdate/AssistantUpdate): confirmed — only Read + Self schemas touched. ✅
- Migration chain 0017→0018; controller applies to Supabase: Global Constraints. ✅
- Type consistency: field names `date_of_birth`/`gender`/`address`/`working_hours` identical across models/reads/self-schemas; `get_my_assistant`/`update_self_assistant` mirror the doctor names. ✅
- Placeholder scan: concrete SQL/schemas/tests; no TBD. ✅
