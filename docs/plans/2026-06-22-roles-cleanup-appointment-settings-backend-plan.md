# Role Cleanup + Appointment Settings — Backend Implementation Plan (#96)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the `practice_manager` role, add the `allow_staff_approval` setting + configurable/"Never" request expiry, make approve/reject settings-aware, and auto-approve pending requests when a clinic switches to Direct Booking.

**Architecture:** Backend slice of #91. Spec: `docs/specs/2026-06-22-roles-cleanup-appointment-settings-design.md`. One Alembic migration (0015) adds a boolean column and makes two expiry columns nullable; the rest is service/router/schema edits. No Postgres enum recreation (0 `practice_manager` rows verified 2026-06-22).

**Tech Stack:** FastAPI, SQLAlchemy 2.x (sync), Pydantic v2, Alembic, pytest against Postgres on host port 5433.

## Global Constraints

- New role set: `owner`, `doctor`, `assistant`. `practice_manager` removed from `MemberRole` and all code; the Postgres `member_role` enum value is left in place (no enum migration, no data migration).
- Permission model: **Owner** = always allowed (every action). **Assigned doctor** (`doctor_beta.linked_user_id == user`) = always approve/reject own requests. **Assistant** = approve/reject only when `allow_staff_approval` is true. **Other doctors** never approve/reject another doctor's request.
- Admin-power split: manage doctors + manage availability → `(owner, assistant)`; invites, manage assistants, edit clinic settings (PATCH) → `(owner)`. Coordinators (create/cancel/resend request) → `(owner, assistant)`.
- `allow_staff_approval` default **false** (new and existing clinics).
- `appointment_request_expiry_minutes` nullable: integer minutes, or **NULL = Never**. Default 120. `appointment_request_beta.expires_at` nullable (NULL = never expires).
- **GET** `/clinics/{id}/settings` readable by any active member; **PATCH** owner-only.
- Switching `scheduling_workflow` → `direct_booking` auto-approves all pending requests in the same transaction.
- Audit every mutation in-transaction via `record_audit`. Module boundaries: cross-module calls go through services; avoid circular imports with local imports where needed.
- Quality gate per task: `uv run ruff check .` clean + `make test` green. Never commit secrets / `.env`.

---

### Task 1: Migration 0015 + model changes (settings column + nullable expiry)

**Files:**
- Create: `alembic/versions/0015_appointment_settings.py`
- Modify: `app/modules/clinics/models.py:55` (expiry nullable), `app/modules/clinics/models.py` (add `allow_staff_approval`)
- Modify: `app/modules/scheduling/models.py:76` (`expires_at` nullable)
- Test: `tests/clinics/test_appointment_settings.py` (new)

**Interfaces:**
- Produces: `ClinicSettings.allow_staff_approval: Mapped[bool]` (default False); `ClinicSettings.appointment_request_expiry_minutes: Mapped[int | None]`; `AppointmentRequest.expires_at: Mapped[datetime | None]`.

- [ ] **Step 1: Write the failing test**

```python
# tests/clinics/test_appointment_settings.py
import uuid as _uuid

from app.modules.clinics.models import ClinicSettings
from app.modules.clinics.service import get_settings
from tests.conftest import make_clinic


def test_new_clinic_settings_defaults(auth_client, db_session):
    c, _ = auth_client(sub="11111111-1111-1111-1111-111111111111")
    clinic = make_clinic(c, name="C")
    s = get_settings(db_session, _uuid.UUID(clinic))
    assert s.allow_staff_approval is False
    assert s.appointment_request_expiry_minutes == 120


def test_expiry_minutes_accepts_null(auth_client, db_session):
    c, _ = auth_client(sub="11111111-1111-1111-1111-111111111111")
    clinic = make_clinic(c, name="C")
    s = get_settings(db_session, _uuid.UUID(clinic))
    s.appointment_request_expiry_minutes = None
    db_session.flush()
    db_session.refresh(s)
    assert s.appointment_request_expiry_minutes is None
```

- [ ] **Step 2: Run test to verify it fails**

Run: `make test PYTEST_ARGS="tests/clinics/test_appointment_settings.py -v"` (or `uv run pytest tests/clinics/test_appointment_settings.py -v`)
Expected: FAIL — `allow_staff_approval` attribute does not exist / NOT NULL violation on null expiry.

- [ ] **Step 3: Write the migration**

```python
# alembic/versions/0015_appointment_settings.py
"""appointment settings: allow_staff_approval + nullable expiry

Revision ID: 0015
Revises: 0014
"""
from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "0015"
down_revision: str | None = "0014"
branch_labels: Sequence[str] | None = None
depends_on: Sequence[str] | None = None


def upgrade() -> None:
    op.add_column(
        "clinic_settings_beta",
        sa.Column(
            "allow_staff_approval",
            sa.Boolean(),
            nullable=False,
            server_default=sa.false(),
        ),
    )
    op.alter_column(
        "clinic_settings_beta",
        "appointment_request_expiry_minutes",
        existing_type=sa.Integer(),
        nullable=True,
    )
    op.alter_column(
        "appointment_request_beta",
        "expires_at",
        existing_type=sa.DateTime(timezone=False),
        nullable=True,
    )


def downgrade() -> None:
    op.alter_column(
        "appointment_request_beta",
        "expires_at",
        existing_type=sa.DateTime(timezone=False),
        nullable=False,
    )
    op.alter_column(
        "clinic_settings_beta",
        "appointment_request_expiry_minutes",
        existing_type=sa.Integer(),
        nullable=False,
    )
    op.drop_column("clinic_settings_beta", "allow_staff_approval")
```

- [ ] **Step 4: Update the models**

In `app/modules/clinics/models.py`, add after line 59 (`google_calendar_enabled`) and change line 55:

```python
    appointment_request_expiry_minutes: Mapped[int | None] = mapped_column(Integer, default=120)
    # ...
    allow_staff_approval: Mapped[bool] = mapped_column(Boolean, default=False)
```

(Place `allow_staff_approval` alongside the other booleans; keep `Boolean` imported — it already is.)

In `app/modules/scheduling/models.py:76`, change:

```python
    expires_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=False), nullable=True)
```

- [ ] **Step 5: Apply migration locally and run the test**

Run: `make migrate` (applies `alembic upgrade head` against local PG 5433) then `make test PYTEST_ARGS="tests/clinics/test_appointment_settings.py -v"`
Expected: PASS. (The test schema fixture in `tests/conftest.py` runs `command.upgrade(cfg, "head")`, so 0015 is applied to the test DB automatically.)

- [ ] **Step 6: Lint + commit**

```bash
uv run ruff check .
git add alembic/versions/0015_appointment_settings.py app/modules/clinics/models.py app/modules/scheduling/models.py tests/clinics/test_appointment_settings.py
git commit -m "feat(settings): allow_staff_approval column + nullable request expiry (#96)"
```

---

### Task 2: Remove practice_manager + apply new role grants

**Files:**
- Modify: `app/modules/members/models.py:12-16` (drop enum member)
- Modify: `app/modules/doctors/router.py:20`, `app/modules/scheduling/service.py:21`, `app/modules/scheduling/booking.py:26,33-37,306-308`, `app/modules/assistants/router.py:18`, `app/modules/invites/router.py:13`, `app/modules/clinics/router.py:20-21`
- Modify tests (changed behavior): `tests/doctors/test_doctors.py:25-32`, `tests/scheduling/test_windows.py:114-140`, `tests/clinics/test_address.py:182-193`
- Test: `tests/members/test_role_removal.py` (new)

**Interfaces:**
- Consumes: nothing from Task 1.
- Produces: `MemberRole` = {owner, doctor, assistant}. Role-grant constants used by Task 4.

- [ ] **Step 1: Write the failing test**

```python
# tests/members/test_role_removal.py
from app.modules.members.models import MemberRole
from tests.conftest import make_clinic


def test_practice_manager_removed_from_enum():
    assert not hasattr(MemberRole, "practice_manager")
    assert {m.value for m in MemberRole} == {"owner", "doctor", "assistant"}


def test_invite_with_removed_role_is_rejected(auth_client):
    owner, _ = auth_client(sub="11111111-1111-1111-1111-111111111111")
    cid = make_clinic(owner, name="C")
    resp = owner.post(f"/api/v1/clinics/{cid}/invites", json={"role": "practice_manager"})
    assert resp.status_code in (400, 422)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `uv run pytest tests/members/test_role_removal.py -v`
Expected: FAIL — `MemberRole.practice_manager` still exists.

- [ ] **Step 3: Remove the enum member**

`app/modules/members/models.py:12-16`:

```python
class MemberRole(str, enum.Enum):
    owner = "owner"
    doctor = "doctor"
    assistant = "assistant"
```

- [ ] **Step 4: Update role grants across routers/services**

`app/modules/doctors/router.py:20`:
```python
_can_manage = require_role(MemberRole.owner, MemberRole.assistant)
```

`app/modules/assistants/router.py:18`:
```python
_can_manage = require_role(MemberRole.owner)
```

`app/modules/invites/router.py:13`:
```python
_can_invite = require_role(MemberRole.owner)
```

`app/modules/clinics/router.py:20-21`:
```python
_settings_admin = require_role(MemberRole.owner)
_clinic_admin = require_role(MemberRole.owner)
```

`app/modules/scheduling/service.py:21` (inside `authorize_manage_availability`):
```python
    if membership.role in (MemberRole.owner, MemberRole.assistant):
        return
```

`app/modules/scheduling/booking.py:26`:
```python
_COORDINATORS = (MemberRole.owner, MemberRole.assistant)
```

`app/modules/scheduling/booking.py:33-37` (`authorize_create`) message + `:306-308` (`authorize_coordinate`) message — drop "practice managers":
```python
def authorize_create(membership: ClinicMember) -> None:
    if membership.role not in _COORDINATORS:
        raise ForbiddenError("Only assistants or owners may create requests.")
```
```python
def authorize_coordinate(membership: ClinicMember) -> None:
    if membership.role not in _COORDINATORS:
        raise ForbiddenError("Only assistants or owners may do this.")
```

- [ ] **Step 5: Update tests whose behavior changed**

In `tests/doctors/test_doctors.py`, replace `test_assistant_cannot_create_doctor` (lines 25-32) with the new grant:
```python
def test_assistant_can_create_doctor(auth_client):
    owner, _ = auth_client(sub="11111111-1111-1111-1111-111111111111")
    cid = make_clinic(owner, name="C")
    token = owner.post(f"/api/v1/clinics/{cid}/invites", json={"role": "assistant"}).json()["token"]
    asst, _ = auth_client(sub="22222222-2222-2222-2222-222222222222")
    asst.post("/api/v1/clinics/join", json={"token": token})
    resp = asst.post(f"/api/v1/clinics/{cid}/doctors", json={"name": "D", "phone": "+91 90000 00000"})
    assert resp.status_code == 201
```
(Ensure `from tests.conftest import make_clinic` is present in that file.)

In `tests/scheduling/test_windows.py`, update `test_assistant_cannot_write_but_can_read` (lines 114-140) so the assistant write now succeeds (keep the outsider 403 assertions):
```python
    # assistant write → 201 (assistants manage doctor availability post-#91)
    assert asst.post(url, json=_recurring()).status_code == 201
    # assistant read → 200
    assert asst.get(url).status_code == 200
    # Outsider (account but no membership) → 403
    assert out.post(url, json=_recurring()).status_code == 403
    assert out.get(url).status_code == 403
```
Rename the function to `test_assistant_can_write_and_read`.

In `tests/clinics/test_address.py`, delete `test_patch_clinic_pm_can_update` (lines 182-193) entirely — the practice_manager role and its clinic-patch grant no longer exist (owner-only patch is already covered by `test_patch_clinic_non_owner_returns_403`).

- [ ] **Step 6: Run the affected suites**

Run: `uv run pytest tests/members/test_role_removal.py tests/doctors/test_doctors.py tests/scheduling/test_windows.py tests/clinics/test_address.py tests/assistants tests/invites -v`
Expected: PASS. (Assistant create-assistant and doctor-member delete-doctor stay 403 — those are unchanged and must still pass.)

- [ ] **Step 7: Lint + commit**

```bash
uv run ruff check .
git add app/modules tests
git commit -m "feat(roles): remove practice_manager; assistants manage doctors/availability (#96)"
```

---

### Task 3: Schema fields + GET settings readable by members

**Files:**
- Modify: `app/modules/clinics/schemas.py:161-192` (Read/Update fields + expiry validator)
- Modify: `app/modules/clinics/router.py:60-64` (GET dependency)
- Test: `tests/clinics/test_settings.py` (add cases)

**Interfaces:**
- Consumes: `allow_staff_approval` model column (Task 1).
- Produces: `ClinicSettingsRead.allow_staff_approval: bool`, `ClinicSettingsRead.appointment_request_expiry_minutes: int | None`; `ClinicSettingsUpdate.allow_staff_approval: bool | None`.

- [ ] **Step 1: Write the failing test**

Append to `tests/clinics/test_settings.py`:
```python
def test_member_can_read_settings_owner_only_patch(auth_client):
    owner, _ = auth_client(sub="11111111-1111-1111-1111-111111111111")
    cid = make_clinic(owner, name="C")
    token = owner.post(f"/api/v1/clinics/{cid}/invites", json={"role": "assistant"}).json()["token"]
    asst, _ = auth_client(sub="22222222-2222-2222-2222-222222222222")
    asst.post("/api/v1/clinics/join", json={"token": token})
    # member can GET settings
    r = asst.get(f"/api/v1/clinics/{cid}/settings")
    assert r.status_code == 200
    assert r.json()["allow_staff_approval"] is False
    # but cannot PATCH
    assert asst.patch(f"/api/v1/clinics/{cid}/settings",
                      json={"allow_staff_approval": True}).status_code == 403


def test_owner_sets_allow_staff_approval(auth_client):
    owner, _ = auth_client(sub="11111111-1111-1111-1111-111111111111")
    cid = make_clinic(owner, name="C")
    r = owner.patch(f"/api/v1/clinics/{cid}/settings", json={"allow_staff_approval": True})
    assert r.status_code == 200 and r.json()["allow_staff_approval"] is True
```
(Ensure `from tests.conftest import make_clinic` is imported in this file.)

- [ ] **Step 2: Run to verify failure**

Run: `uv run pytest tests/clinics/test_settings.py -v`
Expected: FAIL — `allow_staff_approval` not in response / GET returns 403 for assistant.

- [ ] **Step 3: Add schema fields + expiry validator**

`app/modules/clinics/schemas.py` — `ClinicSettingsRead` (after line 172) and change line 167:
```python
    appointment_request_expiry_minutes: int | None
    # ...
    allow_staff_approval: bool
```
`ClinicSettingsUpdate` — change line 179 and add a field + validator:
```python
    appointment_request_expiry_minutes: int | None = None
    # ...
    allow_staff_approval: bool | None = None

    @field_validator("appointment_request_expiry_minutes")
    @classmethod
    def validate_expiry(cls, v: int | None) -> int | None:
        if v is not None and v < 1:
            raise ValueError("appointment_request_expiry_minutes must be >= 1 or null.")
        return v
```

- [ ] **Step 4: Relax GET settings to any member**

`app/modules/clinics/router.py:60-64`:
```python
@router.get("/{clinic_id}/settings", response_model=ClinicSettingsRead)
def get_settings(
    clinic_id: uuid.UUID, db: DbSession, membership: CurrentMembership
) -> ClinicSettingsRead:
    return service.get_settings(db, clinic_id)
```
(`CurrentMembership` is already imported on line 15. Leave PATCH on `_settings_admin`.)

- [ ] **Step 5: Run the test**

Run: `uv run pytest tests/clinics/test_settings.py -v`
Expected: PASS.

- [ ] **Step 6: Lint + commit**

```bash
uv run ruff check .
git add app/modules/clinics tests/clinics/test_settings.py
git commit -m "feat(settings): expose allow_staff_approval + nullable expiry; member-readable GET (#96)"
```

---

### Task 4: Settings-aware approve/reject authorization

**Files:**
- Modify: `app/modules/scheduling/booking.py:236-242` (`authorize_decide` signature + logic)
- Modify: `app/modules/scheduling/router.py:190-215` (pass settings)
- Modify tests: `tests/scheduling/test_approval.py:42-60` (owner now allowed)
- Test: `tests/scheduling/test_decide_authz.py` (new — full matrix)

**Interfaces:**
- Consumes: `allow_staff_approval` (Task 1/3), `MemberRole` (Task 2), `get_settings` (existing import in booking.py line 17).
- Produces: `authorize_decide(db, *, clinic_id, request, membership, settings) -> None`.

- [ ] **Step 1: Write the failing test (matrix)**

```python
# tests/scheduling/test_decide_authz.py
from tests.conftest import make_clinic

OWNER = "11111111-1111-1111-1111-111111111111"
DOC_B_USER = "22222222-2222-2222-2222-222222222222"
ASST_USER = "33333333-3333-3333-3333-333333333333"
MON_9 = "2026-06-22T09:00:00"


def _clinic_doctor_approval(owner):
    clinic = make_clinic(owner, name="C")
    owner.patch(f"/api/v1/clinics/{clinic}/settings", json={"scheduling_workflow": "doctor_approval"})
    return clinic


def _make_doctor_with_availability(owner, clinic):
    doc = owner.post(f"/api/v1/clinics/{clinic}/doctors",
                     json={"name": "D", "phone": "+91 90000 00000"}).json()["doctor"]["id"]
    owner.post(f"/api/v1/clinics/{clinic}/doctors/{doc}/availability",
               json={"kind": "recurring", "day_of_week": 0, "start_time": "09:00", "end_time": "10:00"})
    return doc


def _pending_request(owner, clinic, doc):
    pat = owner.post(f"/api/v1/clinics/{clinic}/patients",
                     json={"name": "P", "phone": "+91 98888 00000", "age": 30}).json()["id"]
    return owner.post(f"/api/v1/clinics/{clinic}/doctors/{doc}/appointment-requests",
                      json={"patient_id": pat, "start_datetime": MON_9}).json()["id"]


def _add_member(owner, clinic, role, sub):
    token = owner.post(f"/api/v1/clinics/{clinic}/invites", json={"role": role}).json()["token"]
    joiner, _ = None, None  # placeholder; replaced below
    return token


def test_owner_can_approve_any_request(auth_client):
    owner, _ = auth_client(sub=OWNER)
    clinic = _clinic_doctor_approval(owner)
    doc = _make_doctor_with_availability(owner, clinic)  # not linked to owner
    rid = _pending_request(owner, clinic, doc)
    assert owner.post(f"/api/v1/clinics/{clinic}/appointment-requests/{rid}/approve").status_code == 200


def test_assistant_blocked_when_toggle_off(auth_client):
    owner, _ = auth_client(sub=OWNER)
    clinic = _clinic_doctor_approval(owner)
    doc = _make_doctor_with_availability(owner, clinic)
    rid = _pending_request(owner, clinic, doc)
    token = owner.post(f"/api/v1/clinics/{clinic}/invites", json={"role": "assistant"}).json()["token"]
    asst, _ = auth_client(sub=ASST_USER)
    asst.post("/api/v1/clinics/join", json={"token": token})
    assert asst.post(f"/api/v1/clinics/{clinic}/appointment-requests/{rid}/approve").status_code == 403


def test_assistant_allowed_when_toggle_on(auth_client):
    owner, _ = auth_client(sub=OWNER)
    clinic = _clinic_doctor_approval(owner)
    owner.patch(f"/api/v1/clinics/{clinic}/settings", json={"allow_staff_approval": True})
    doc = _make_doctor_with_availability(owner, clinic)
    rid = _pending_request(owner, clinic, doc)
    token = owner.post(f"/api/v1/clinics/{clinic}/invites", json={"role": "assistant"}).json()["token"]
    asst, _ = auth_client(sub=ASST_USER)
    asst.post("/api/v1/clinics/join", json={"token": token})
    assert asst.post(f"/api/v1/clinics/{clinic}/appointment-requests/{rid}/approve").status_code == 200


def test_other_doctor_cannot_approve_even_toggle_on(auth_client):
    owner, _ = auth_client(sub=OWNER)
    clinic = _clinic_doctor_approval(owner)
    owner.patch(f"/api/v1/clinics/{clinic}/settings", json={"allow_staff_approval": True})
    doc = _make_doctor_with_availability(owner, clinic)  # assigned doctor (unlinked)
    rid = _pending_request(owner, clinic, doc)
    # Doctor B joins as a doctor and links a separate self-profile
    token = owner.post(f"/api/v1/clinics/{clinic}/invites", json={"role": "doctor"}).json()["token"]
    doc_b, _ = auth_client(sub=DOC_B_USER)
    doc_b.post("/api/v1/clinics/join", json={"token": token})
    doc_b.post(f"/api/v1/clinics/{clinic}/doctors/me",
               json={"name": "Dr. B", "phone": "+91 90000 00001"})
    # Doctor B is not the assigned doctor and is not an assistant → 403
    assert doc_b.post(f"/api/v1/clinics/{clinic}/appointment-requests/{rid}/approve").status_code == 403
```
(Remove the unused `_add_member` helper before committing — it's a leftover stub.)

- [ ] **Step 2: Run to verify failure**

Run: `uv run pytest tests/scheduling/test_decide_authz.py -v`
Expected: FAIL — owner currently 403 on approve; assistant-on path errors (signature lacks `settings`).

- [ ] **Step 3: Rewrite `authorize_decide`**

`app/modules/scheduling/booking.py:236-242`:
```python
def authorize_decide(
    db: Session,
    *,
    clinic_id: uuid.UUID,
    request: AppointmentRequest,
    membership: ClinicMember,
    settings,
) -> None:
    """Owner always; assigned doctor always; assistant iff allow_staff_approval; else 403."""
    if membership.role == MemberRole.owner:
        return
    doctor = get_doctor(db, clinic_id, request.doctor_id)
    if doctor.linked_user_id == membership.user_id:
        return
    if membership.role == MemberRole.assistant and settings.allow_staff_approval:
        return
    raise ForbiddenError("Your role is not permitted to approve or reject this request.")
```

- [ ] **Step 4: Pass settings from the router**

`app/modules/scheduling/router.py` — in `approve_request` (190-201) and `reject_request` (204-215), load settings and pass it. Add `from app.modules.clinics import service as clinic_service` at the top of the file, then:
```python
    req = booking.get_request(db, clinic_id, request_id)
    settings = clinic_service.get_settings(db, clinic_id)
    booking.authorize_decide(
        db, clinic_id=clinic_id, request=req, membership=membership, settings=settings
    )
```
(Apply the same two added lines in both approve and reject handlers.)

- [ ] **Step 5: Fix the existing approval tests that assumed owner-forbidden**

`tests/scheduling/test_approval.py` — replace `test_owner_cannot_approve` (42-49) and `test_owner_cannot_reject` (52-60):
```python
def test_owner_can_approve(auth_client):
    c, _ = auth_client(sub=OWNER)
    clinic, doc, pat, rid = _setup(c)
    # owner is superuser → may approve any request (post-#91)
    assert (
        c.post(f"/api/v1/clinics/{clinic}/appointment-requests/{rid}/approve").status_code
        == 200
    )


def test_owner_can_reject(auth_client):
    c, _ = auth_client(sub=OWNER)
    clinic, doc, pat, rid = _setup(c)
    assert (
        c.post(f"/api/v1/clinics/{clinic}/appointment-requests/{rid}/reject").status_code
        == 200
    )
```

- [ ] **Step 6: Run approval + matrix suites**

Run: `uv run pytest tests/scheduling/test_decide_authz.py tests/scheduling/test_approval.py -v`
Expected: PASS.

- [ ] **Step 7: Lint + commit**

```bash
uv run ruff check .
git add app/modules/scheduling tests/scheduling/test_decide_authz.py tests/scheduling/test_approval.py
git commit -m "feat(scheduling): settings-aware approve/reject authz (owner/doctor/assistant) (#96)"
```

---

### Task 5: Request expiry "Never"

**Files:**
- Modify: `app/modules/scheduling/booking.py:160-162` (create), `:232-233` (`is_expired`), `:340-343` (resend)
- Modify: `app/modules/scheduling/schemas.py` (`RequestRead` / `RequestListItem` / `PatientScheduleItem` — `expires_at: datetime | None`)
- Test: `tests/scheduling/test_expiry_never.py` (new)

**Interfaces:**
- Consumes: nullable `expires_at` (Task 1), nullable `appointment_request_expiry_minutes` (Task 1).
- Produces: `is_expired` null-safe; create/resend honor NULL = Never.

- [ ] **Step 1: Write the failing test**

```python
# tests/scheduling/test_expiry_never.py
import uuid as _uuid

from app.modules.scheduling import booking
from app.modules.scheduling.models import AppointmentRequest
from tests.conftest import make_clinic

OWNER = "11111111-1111-1111-1111-111111111111"
MON_9 = "2026-06-22T09:00:00"


def _setup_never(c, db_session):
    clinic = make_clinic(c, name="C")
    c.patch(f"/api/v1/clinics/{clinic}/settings",
            json={"scheduling_workflow": "doctor_approval",
                  "appointment_request_expiry_minutes": None})
    doc = c.post(f"/api/v1/clinics/{clinic}/doctors",
                 json={"name": "D", "phone": "+91 90000 00000"}).json()["doctor"]["id"]
    pat = c.post(f"/api/v1/clinics/{clinic}/patients",
                 json={"name": "P", "phone": "+91 98888 00000", "age": 30}).json()["id"]
    c.post(f"/api/v1/clinics/{clinic}/doctors/{doc}/availability",
           json={"kind": "recurring", "day_of_week": 0, "start_time": "09:00", "end_time": "10:00"})
    rid = c.post(f"/api/v1/clinics/{clinic}/doctors/{doc}/appointment-requests",
                 json={"patient_id": pat, "start_datetime": MON_9}).json()["id"]
    return clinic, rid


def test_never_expiry_creates_null_and_not_expired(auth_client, db_session):
    c, _ = auth_client(sub=OWNER)
    clinic, rid = _setup_never(c, db_session)
    req = db_session.get(AppointmentRequest, _uuid.UUID(rid))
    assert req.expires_at is None
    assert booking.is_expired(req) is False


def test_never_expiry_request_can_be_approved(auth_client):
    c, _ = auth_client(sub=OWNER)
    clinic, rid = _setup_never(c, None)
    assert c.post(f"/api/v1/clinics/{clinic}/appointment-requests/{rid}/approve").status_code == 200
```

- [ ] **Step 2: Run to verify failure**

Run: `uv run pytest tests/scheduling/test_expiry_never.py -v`
Expected: FAIL — `create_request` does `now() + timedelta(minutes=None)` → TypeError.

- [ ] **Step 3: Make create/resend/is_expired null-safe**

`app/modules/scheduling/booking.py` — `create_request` (replace lines 160-162):
```python
    settings = get_settings(db, clinic_id)
    expiry_minutes = settings.appointment_request_expiry_minutes
    expires_at = (
        None if expiry_minutes is None
        else dt.datetime.now() + dt.timedelta(minutes=expiry_minutes)
    )
```
`is_expired` (232-233):
```python
def is_expired(req: AppointmentRequest) -> bool:
    return (
        req.status == "pending"
        and req.expires_at is not None
        and dt.datetime.now() > req.expires_at
    )
```
`resend_request` (replace lines 340-343):
```python
    settings = get_settings(db, clinic_id)
    minutes = settings.appointment_request_expiry_minutes
    req.expires_at = (
        None if minutes is None else dt.datetime.now() + dt.timedelta(minutes=minutes)
    )
```
And the resend audit line (351) must not call `.isoformat()` on None:
```python
        new={"expires_at": req.expires_at.isoformat() if req.expires_at else None},
```

- [ ] **Step 4: Make `expires_at` optional in the schemas**

In `app/modules/scheduling/schemas.py`, change the `expires_at` field type from `datetime` to `datetime | None` wherever it appears in response models (`RequestRead`, `RequestListItem`, and `PatientScheduleItem` if present). Search the file for `expires_at` and update each.

- [ ] **Step 5: Run the test + the existing requests-list/patient-appointments suites**

Run: `uv run pytest tests/scheduling/test_expiry_never.py tests/scheduling/test_requests_list.py tests/scheduling/test_patient_appointments.py -v`
Expected: PASS.

- [ ] **Step 6: Lint + commit**

```bash
uv run ruff check .
git add app/modules/scheduling tests/scheduling/test_expiry_never.py
git commit -m "feat(scheduling): support Never expiry (nullable expires_at) (#96)"
```

---

### Task 6: Auto-approve pending on switch to Direct Booking

**Files:**
- Modify: `app/modules/scheduling/booking.py` (add `auto_approve_pending`)
- Modify: `app/modules/clinics/service.py:140-164` (`update_settings` detects transition)
- Test: `tests/clinics/test_auto_approve_on_switch.py` (new)

**Interfaces:**
- Consumes: `_materialize_appointment` (booking), `get_settings`.
- Produces: `booking.auto_approve_pending(db, *, clinic_id, actor_user_id) -> int`.

- [ ] **Step 1: Write the failing test**

```python
# tests/clinics/test_auto_approve_on_switch.py
from tests.conftest import make_clinic

OWNER = "11111111-1111-1111-1111-111111111111"
MON_9 = "2026-06-22T09:00:00"
MON_930 = "2026-06-22T09:30:00"


def _doctor_approval_clinic_with_pending(owner, starts):
    clinic = make_clinic(owner, name="C")
    owner.patch(f"/api/v1/clinics/{clinic}/settings", json={"scheduling_workflow": "doctor_approval"})
    doc = owner.post(f"/api/v1/clinics/{clinic}/doctors",
                     json={"name": "D", "phone": "+91 90000 00000"}).json()["doctor"]["id"]
    pat = owner.post(f"/api/v1/clinics/{clinic}/patients",
                     json={"name": "P", "phone": "+91 98888 00000", "age": 30}).json()["id"]
    owner.post(f"/api/v1/clinics/{clinic}/doctors/{doc}/availability",
               json={"kind": "recurring", "day_of_week": 0, "start_time": "09:00", "end_time": "11:00"})
    for s in starts:
        owner.post(f"/api/v1/clinics/{clinic}/doctors/{doc}/appointment-requests",
                   json={"patient_id": pat, "start_datetime": s})
    return clinic


def test_switch_to_direct_auto_approves_pending(auth_client):
    owner, _ = auth_client(sub=OWNER)
    clinic = _doctor_approval_clinic_with_pending(owner, [MON_9, MON_930])
    assert owner.get(f"/api/v1/clinics/{clinic}/appointment-requests/counts").json()["pending"] == 2
    r = owner.patch(f"/api/v1/clinics/{clinic}/settings", json={"scheduling_workflow": "direct_booking"})
    assert r.status_code == 200
    counts = owner.get(f"/api/v1/clinics/{clinic}/appointment-requests/counts").json()
    assert counts["pending"] == 0
    assert counts["approved"] == 2


def test_switch_with_no_pending_is_noop(auth_client):
    owner, _ = auth_client(sub=OWNER)
    clinic = _doctor_approval_clinic_with_pending(owner, [])
    r = owner.patch(f"/api/v1/clinics/{clinic}/settings", json={"scheduling_workflow": "direct_booking"})
    assert r.status_code == 200
    assert owner.get(f"/api/v1/clinics/{clinic}/appointment-requests/counts").json()["approved"] == 0


def test_switch_away_from_direct_does_not_auto_approve(auth_client):
    owner, _ = auth_client(sub=OWNER)
    clinic = make_clinic(owner, name="C")  # starts as direct_booking (default)
    r = owner.patch(f"/api/v1/clinics/{clinic}/settings", json={"scheduling_workflow": "doctor_approval"})
    assert r.status_code == 200  # no auto-approval path triggered
```

- [ ] **Step 2: Run to verify failure**

Run: `uv run pytest tests/clinics/test_auto_approve_on_switch.py -v`
Expected: FAIL — pending stays 2 after switch (no auto-approval yet).

- [ ] **Step 3: Add `auto_approve_pending` to booking.py**

Append to `app/modules/scheduling/booking.py`:
```python
def auto_approve_pending(
    db: Session, *, clinic_id: uuid.UUID, actor_user_id: uuid.UUID
) -> int:
    """Materialize confirmed appointments for all pending requests (Direct Booking switch).

    Runs inside the caller's transaction (no commit here)."""
    pending = db.execute(
        select(AppointmentRequest)
        .where(
            AppointmentRequest.clinic_id == clinic_id,
            AppointmentRequest.status == "pending",
        )
        .with_for_update()
    ).scalars().all()
    for req in pending:
        slot = db.get(Slot, req.slot_id)
        appt = _materialize_appointment(
            db, clinic_id=clinic_id, req=req, slot=slot,
            actor_user_id=actor_user_id, source="direct_booking",
        )
        record_audit(
            db, action="appointment_request.auto_approved",
            entity_type="appointment_request", entity_id=req.id,
            clinic_id=clinic_id, actor_user_id=actor_user_id,
            new={"appointment_id": str(appt.id)},
        )
    return len(pending)
```

- [ ] **Step 4: Detect the transition in `update_settings`**

`app/modules/clinics/service.py` — rewrite `update_settings` (140-164):
```python
def update_settings(
    db: Session,
    clinic_id: uuid.UUID,
    data: ClinicSettingsUpdate,
    actor_user_id: uuid.UUID,
) -> ClinicSettings:
    settings_row = get_settings(db, clinic_id)
    changes = data.model_dump(exclude_unset=True)
    switching_to_direct = (
        changes.get("scheduling_workflow") == "direct_booking"
        and settings_row.scheduling_workflow != "direct_booking"
    )
    previous = {k: getattr(settings_row, k) for k in changes}
    for k, v in changes.items():
        setattr(settings_row, k, v)
    db.flush()
    if switching_to_direct:
        # Local import avoids a circular import (scheduling.booking imports clinics.service).
        from app.modules.scheduling.booking import auto_approve_pending

        auto_approve_pending(db, clinic_id=clinic_id, actor_user_id=actor_user_id)
    record_audit(
        db,
        action="clinic_settings.updated",
        entity_type="clinic_settings",
        entity_id=settings_row.id,
        clinic_id=clinic_id,
        actor_user_id=actor_user_id,
        previous=previous,
        new=changes,
    )
    db.commit()
    db.refresh(settings_row)
    return settings_row
```

- [ ] **Step 5: Run the test**

Run: `uv run pytest tests/clinics/test_auto_approve_on_switch.py -v`
Expected: PASS.

- [ ] **Step 6: Lint + commit**

```bash
uv run ruff check .
git add app/modules/scheduling/booking.py app/modules/clinics/service.py tests/clinics/test_auto_approve_on_switch.py
git commit -m "feat(scheduling): auto-approve pending on switch to Direct Booking (#96)"
```

---

### Task 7: Full-suite green + ruff

**Files:** none (verification task).

- [ ] **Step 1: Run the entire suite**

Run: `make test`
Expected: ALL PASS. If any pre-existing test still encodes practice_manager or the old owner/assistant rules, fix it per the Global Constraints (do not weaken a test to pass — align it with the new model) and note it in the progress ledger.

- [ ] **Step 2: Ruff**

Run: `uv run ruff check .`
Expected: clean (0 errors).

- [ ] **Step 3: Commit any fixups**

```bash
git add -A
git commit -m "test: align remaining suites with #91 role + settings model (#96)"
```

---

## Self-Review (plan vs spec)

- **Spec §2a role removal** → Task 2 (enum + grants + role-removal test). ✅
- **Spec §2b permission matrix** → Task 2 (grants) + Task 4 (approve/reject matrix). ✅
- **Spec §2c toggle + expiry Never** → Task 1 (column + nullable), Task 3 (schema/expose), Task 5 (Never semantics). ✅
- **Spec §2c Direct-Booking gray-out** → frontend concern (backend just stores; no backend gating needed). ✅
- **Spec §2d auto-approve on switch** → Task 6. ✅
- **Spec §3 migration** → Task 1 (0015). ✅
- **Spec §4b authorize_decide** → Task 4. ✅
- **Spec §4c expiry** → Task 5. ✅
- **Spec §4d GET relax / PATCH owner** → Task 2 (PATCH owner) + Task 3 (GET member). ✅
- **Spec §4e auto-approve** → Task 6. ✅
- **Spec §4f tests** → Tasks 1-6 each add tests; Task 7 full green. ✅
- **Type consistency:** `authorize_decide(..., settings)` defined in Task 4, called in Task 4 router edit; `auto_approve_pending` defined + called in Task 6; `expires_at: datetime | None` model (Task 1) + schemas (Task 5). ✅
- **Placeholder scan:** the `_add_member` stub in Task 4 Step 1 is explicitly flagged for removal; no other TBDs. ✅
