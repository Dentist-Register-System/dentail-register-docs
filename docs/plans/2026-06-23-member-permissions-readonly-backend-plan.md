# Member Permissions (read-only) — Backend Implementation Plan (#108)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Expose a backend-authoritative, read-only "what can this member do" capability list for a clinic member, derived from role + existing clinic settings — with no new tables, settings, or migration.

**Architecture:** Refactor the three existing scheduling/availability authz guards into reusable *non-raising* predicates, add a pure `resolve_capabilities(role, settings)` resolver that reuses them, resolve a doctor/assistant entity to its effective membership role (owner-doctor → owner), and surface it via two read endpoints under the existing doctors/assistants resources.

**Tech Stack:** FastAPI, SQLAlchemy 2.x (sync), Pydantic v2, pytest. Postgres on host port **5433** (dev). Spec: `docs/specs/2026-06-23-member-permissions-readonly-design.md`.

## Global Constraints

- Permissive-OSS deps only; never commit secrets. No new dependency needed.
- **No database migration. No new columns. No new settings.** Read-only feature.
- Uniform error envelope `{ "error": { "code", "message", "details" } }`; raise via `app.core.errors` (`ForbiddenError`, `NotFoundError`).
- Import discipline: `core/ ← modules/ ← main.py`; cross-module calls go through the other module's `service`. Routers stay thin (parse → service → response).
- Stable machine-readable codes only in API payloads (capability `key`, `group`, `reason_code`, `note_code`, `setting_key`) — never display English (i18n contract).
- `uv run ruff check .` clean and `make test` green before each commit. Dev DB port **5433** only (never 5434/8001/3001 — test-suite reserved).
- Effective role values: `owner` | `doctor` | `assistant`. Capability `group` values: `scheduling` | `patients` | `team_clinic`.

---

### Task 1: Reusable non-raising authz predicates (behavior-preserving refactor)

Extract the boolean core of the three guards so the resolver calls the *same* logic that enforces. Existing raising guards delegate to the new predicates — no behavior change.

**Files:**
- Modify: `app/modules/scheduling/booking.py` (`authorize_decide`, `authorize_create`, `authorize_coordinate`, near `_COORDINATORS`)
- Modify: `app/modules/scheduling/service.py` (`authorize_manage_availability`)
- Test: `tests/scheduling/test_authz_predicates.py` (new)

**Interfaces:**
- Produces:
  - `booking.can_coordinate(role: MemberRole) -> bool`
  - `booking.can_decide(role: MemberRole, *, is_assigned_doctor: bool, settings) -> bool`
  - `service.can_manage_availability(role: MemberRole, *, is_self_doctor: bool, settings) -> bool`

- [ ] **Step 1: Write the failing test**

```python
# tests/scheduling/test_authz_predicates.py
from app.modules.members.models import MemberRole
from app.modules.scheduling import booking
from app.modules.scheduling import service


class _S:  # minimal settings stub
    def __init__(self, approve=False, avail=False):
        self.allow_staff_approval = approve
        self.allow_staff_manage_availability = avail


def test_can_coordinate():
    assert booking.can_coordinate(MemberRole.owner) is True
    assert booking.can_coordinate(MemberRole.assistant) is True
    assert booking.can_coordinate(MemberRole.doctor) is False


def test_can_decide():
    assert booking.can_decide(MemberRole.owner, is_assigned_doctor=False, settings=_S()) is True
    assert booking.can_decide(MemberRole.doctor, is_assigned_doctor=True, settings=_S()) is True
    assert booking.can_decide(MemberRole.doctor, is_assigned_doctor=False, settings=_S()) is False
    assert booking.can_decide(MemberRole.assistant, is_assigned_doctor=False, settings=_S(approve=False)) is False
    assert booking.can_decide(MemberRole.assistant, is_assigned_doctor=False, settings=_S(approve=True)) is True


def test_can_manage_availability():
    assert service.can_manage_availability(MemberRole.owner, is_self_doctor=False, settings=_S()) is True
    assert service.can_manage_availability(MemberRole.doctor, is_self_doctor=True, settings=_S()) is True
    assert service.can_manage_availability(MemberRole.doctor, is_self_doctor=False, settings=_S()) is False
    assert service.can_manage_availability(MemberRole.assistant, is_self_doctor=False, settings=_S(avail=False)) is False
    assert service.can_manage_availability(MemberRole.assistant, is_self_doctor=False, settings=_S(avail=True)) is True
```

- [ ] **Step 2: Run test to verify it fails**

Run: `uv run pytest tests/scheduling/test_authz_predicates.py -v`
Expected: FAIL — `AttributeError: module ... has no attribute 'can_coordinate'`.

- [ ] **Step 3: Add the predicates and delegate from the guards**

```python
# app/modules/scheduling/booking.py  — add near _COORDINATORS / authorize_create
def can_coordinate(role: MemberRole) -> bool:
    return role in _COORDINATORS


def authorize_create(membership: ClinicMember) -> None:
    if not can_coordinate(membership.role):
        raise ForbiddenError("Only assistants or owners may create requests.")


def authorize_coordinate(membership: ClinicMember) -> None:
    if not can_coordinate(membership.role):
        raise ForbiddenError("Only assistants or owners may do this.")


def can_decide(role: MemberRole, *, is_assigned_doctor: bool, settings) -> bool:
    if role == MemberRole.owner:
        return True
    if role == MemberRole.doctor and is_assigned_doctor:
        return True
    if role == MemberRole.assistant and settings.allow_staff_approval:
        return True
    return False
```

```python
# app/modules/scheduling/booking.py — authorize_decide now delegates
def authorize_decide(db, *, clinic_id, request, membership, settings) -> None:
    is_assigned_doctor = False
    if membership.role == MemberRole.doctor:
        doctor = get_doctor(db, clinic_id, request.doctor_id)
        is_assigned_doctor = doctor.linked_user_id == membership.user_id
    if not can_decide(membership.role, is_assigned_doctor=is_assigned_doctor, settings=settings):
        raise ForbiddenError("Your role is not permitted to approve or reject this request.")
```

```python
# app/modules/scheduling/service.py
def can_manage_availability(role: MemberRole, *, is_self_doctor: bool, settings) -> bool:
    if role == MemberRole.owner:
        return True
    if role == MemberRole.doctor:
        return is_self_doctor
    if role == MemberRole.assistant:
        return settings.allow_staff_manage_availability
    return False


def authorize_manage_availability(db, *, clinic_id, doctor_id, membership, settings) -> None:
    is_self_doctor = False
    if membership.role == MemberRole.doctor:
        doctor = get_doctor(db, clinic_id, doctor_id)
        is_self_doctor = doctor.linked_user_id == membership.user_id
    if not can_manage_availability(membership.role, is_self_doctor=is_self_doctor, settings=settings):
        raise ForbiddenError("Your role is not permitted to manage this doctor's availability.")
```

> NOTE for the implementer: keep the *existing* parameter names/order of `authorize_decide` / `authorize_manage_availability` exactly as they are in the file — only the body changes to delegate. Verify the current signatures before editing; the bodies above show the delegation pattern, not necessarily the exact signature.

- [ ] **Step 4: Run the new + existing authz tests**

Run: `uv run pytest tests/scheduling -v`
Expected: PASS (new predicate tests + all existing scheduling/availability authz tests unchanged).

- [ ] **Step 5: Lint + commit**

```bash
uv run ruff check .
git add app/modules/scheduling/booking.py app/modules/scheduling/service.py tests/scheduling/test_authz_predicates.py
git commit -m "refactor(authz): extract non-raising scheduling/availability predicates (#108)"
```

---

### Task 2: Capability schemas + `resolve_capabilities` resolver

**Files:**
- Modify: `app/modules/members/schemas.py` (add `CapabilityRead`, `CapabilitiesRead`)
- Create: `app/modules/members/capabilities.py`
- Test: `tests/members/test_capabilities_resolver.py` (new)

**Interfaces:**
- Produces:
  - `CapabilityRead(key: str, group: str, allowed: bool, reason_code: str|None, note_code: str|None, setting_key: str|None)`
  - `CapabilitiesRead(member_id: UUID, kind: str, effective_role: str, capabilities: list[CapabilityRead])`
  - `capabilities.resolve_capabilities(role: MemberRole, settings) -> list[CapabilityRead]` (6 items, fixed order)

- [ ] **Step 1: Write the failing test**

```python
# tests/members/test_capabilities_resolver.py
from app.modules.members.capabilities import resolve_capabilities
from app.modules.members.models import MemberRole


class _S:
    def __init__(self, approve=False, avail=False):
        self.allow_staff_approval = approve
        self.allow_staff_manage_availability = avail


def _by_key(caps):
    return {c.key: c for c in caps}


KEYS = ["approve_requests", "book_appointments", "manage_availability",
        "manage_patients", "manage_doctors", "clinic_administration"]


def test_owner_all_allowed():
    caps = _by_key(resolve_capabilities(MemberRole.owner, _S()))
    assert [c for c in KEYS] == [k for k in caps]  # all 6, fixed order
    assert all(caps[k].allowed for k in KEYS)
    assert all(caps[k].reason_code is None for k in KEYS)


def test_doctor_mapping():
    caps = _by_key(resolve_capabilities(MemberRole.doctor, _S()))
    assert caps["approve_requests"].allowed and caps["approve_requests"].note_code == "assigned_requests_only"
    assert caps["manage_availability"].allowed and caps["manage_availability"].note_code == "own_schedule_only"
    assert not caps["book_appointments"].allowed and caps["book_appointments"].reason_code == "coordination_by_staff"
    assert caps["manage_patients"].allowed
    assert not caps["manage_doctors"].allowed and caps["manage_doctors"].reason_code == "doctors_dont_manage_team"
    assert not caps["clinic_administration"].allowed and caps["clinic_administration"].reason_code == "owner_only"


def test_assistant_settings_gated():
    off = _by_key(resolve_capabilities(MemberRole.assistant, _S(approve=False, avail=False)))
    assert not off["approve_requests"].allowed
    assert off["approve_requests"].reason_code == "staff_approval_disabled"
    assert off["approve_requests"].setting_key == "scheduling"
    assert not off["manage_availability"].allowed
    assert off["manage_availability"].reason_code == "staff_availability_disabled"
    assert off["manage_availability"].setting_key == "scheduling"
    # assistant always-allowed rows
    assert off["book_appointments"].allowed and off["manage_patients"].allowed and off["manage_doctors"].allowed
    assert not off["clinic_administration"].allowed and off["clinic_administration"].reason_code == "owner_only"

    on = _by_key(resolve_capabilities(MemberRole.assistant, _S(approve=True, avail=True)))
    assert on["approve_requests"].allowed and on["approve_requests"].reason_code is None
    assert on["manage_availability"].allowed and on["manage_availability"].reason_code is None


def test_no_drift_vs_predicates():
    # resolver allowed-ness agrees with the enforcement predicates
    from app.modules.scheduling.booking import can_coordinate, can_decide
    from app.modules.scheduling.service import can_manage_availability
    for role in (MemberRole.owner, MemberRole.doctor, MemberRole.assistant):
        for s in (_S(False, False), _S(True, True)):
            caps = _by_key(resolve_capabilities(role, s))
            assert caps["book_appointments"].allowed == can_coordinate(role)
            assert caps["manage_availability"].allowed == can_manage_availability(
                role, is_self_doctor=(role == MemberRole.doctor), settings=s)
            assert caps["approve_requests"].allowed == can_decide(
                role, is_assigned_doctor=(role == MemberRole.doctor), settings=s)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `uv run pytest tests/members/test_capabilities_resolver.py -v`
Expected: FAIL — `ModuleNotFoundError: app.modules.members.capabilities`.

- [ ] **Step 3: Add schemas**

```python
# app/modules/members/schemas.py  (append)
import uuid
from pydantic import BaseModel


class CapabilityRead(BaseModel):
    key: str
    group: str
    allowed: bool
    reason_code: str | None = None
    note_code: str | None = None
    setting_key: str | None = None


class CapabilitiesRead(BaseModel):
    member_id: uuid.UUID
    kind: str
    effective_role: str
    capabilities: list[CapabilityRead]
```

- [ ] **Step 4: Implement the resolver**

```python
# app/modules/members/capabilities.py
from app.modules.members.models import MemberRole
from app.modules.members.schemas import CapabilityRead


def resolve_capabilities(role: MemberRole, settings) -> list[CapabilityRead]:
    owner = role == MemberRole.owner
    doctor = role == MemberRole.doctor
    assistant = role == MemberRole.assistant

    def cap(key, group, allowed, *, reason=None, note=None, setting=None):
        return CapabilityRead(
            key=key, group=group, allowed=allowed,
            reason_code=None if allowed else reason,
            note_code=note if allowed else None,
            setting_key=setting,
        )

    # 1. approve_requests (scheduling)
    if owner:
        approve = cap("approve_requests", "scheduling", True)
    elif doctor:
        approve = cap("approve_requests", "scheduling", True, note="assigned_requests_only")
    else:  # assistant — setting-gated
        approve = cap("approve_requests", "scheduling", settings.allow_staff_approval,
                      reason="staff_approval_disabled", setting="scheduling")

    # 2. book_appointments (scheduling) — coordinators only
    book = cap("book_appointments", "scheduling", owner or assistant, reason="coordination_by_staff")

    # 3. manage_availability (scheduling)
    if owner:
        avail = cap("manage_availability", "scheduling", True)
    elif doctor:
        avail = cap("manage_availability", "scheduling", True, note="own_schedule_only")
    else:  # assistant — setting-gated
        avail = cap("manage_availability", "scheduling", settings.allow_staff_manage_availability,
                    reason="staff_availability_disabled", setting="scheduling")

    # 4. manage_patients (patients) — any active member
    patients = cap("manage_patients", "patients", True)

    # 5. manage_doctors (team_clinic) — owner + assistant
    doctors = cap("manage_doctors", "team_clinic", owner or assistant, reason="doctors_dont_manage_team")

    # 6. clinic_administration (team_clinic) — owner only
    admin = cap("clinic_administration", "team_clinic", owner, reason="owner_only")

    return [approve, book, avail, patients, doctors, admin]
```

- [ ] **Step 5: Run tests**

Run: `uv run pytest tests/members/test_capabilities_resolver.py -v`
Expected: PASS (all 4 tests incl. the no-drift guard).

- [ ] **Step 6: Lint + commit**

```bash
uv run ruff check .
git add app/modules/members/schemas.py app/modules/members/capabilities.py tests/members/test_capabilities_resolver.py
git commit -m "feat(members): capability resolver + read schemas (#108)"
```

---

### Task 3: Effective-role resolution + `get_member_capabilities` service

**Files:**
- Modify: `app/modules/members/service.py`
- Test: `tests/members/test_member_capabilities_service.py` (new)

**Interfaces:**
- Consumes: `resolve_capabilities` (Task 2); `get_doctor`/`get_assistant` (doctors/assistants service); `get_settings` (clinics service); `ClinicMember` (members model).
- Produces: `service.get_member_capabilities(db, *, clinic_id: UUID, kind: str, member_id: UUID) -> CapabilitiesRead` (`kind` ∈ `"doctor"|"assistant"`).

- [ ] **Step 1: Write the failing test** (uses existing clinic/doctor/assistant fixtures; adapt fixture names to the repo's conftest)

```python
# tests/members/test_member_capabilities_service.py
import pytest
from app.modules.members import service


def test_assistant_member_capabilities(db, clinic, assistant_member):  # assistant linked to a user
    out = service.get_member_capabilities(
        db, clinic_id=clinic.id, kind="assistant", member_id=assistant_member.id)
    assert out.kind == "assistant"
    assert out.effective_role == "assistant"
    assert {c.key for c in out.capabilities} == {
        "approve_requests", "book_appointments", "manage_availability",
        "manage_patients", "manage_doctors", "clinic_administration"}


def test_owner_doctor_resolves_to_owner(db, clinic, owner_doctor):  # doctor row linked to the owner user
    out = service.get_member_capabilities(
        db, clinic_id=clinic.id, kind="doctor", member_id=owner_doctor.id)
    assert out.effective_role == "owner"
    assert all(c.allowed for c in out.capabilities)


def test_unknown_member_404(db, clinic):
    import uuid
    from app.core.errors import NotFoundError
    with pytest.raises(NotFoundError):
        service.get_member_capabilities(db, clinic_id=clinic.id, kind="doctor", member_id=uuid.uuid4())
```

- [ ] **Step 2: Run test to verify it fails**

Run: `uv run pytest tests/members/test_member_capabilities_service.py -v`
Expected: FAIL — `AttributeError: module 'app.modules.members.service' has no attribute 'get_member_capabilities'`.

- [ ] **Step 3: Implement the service**

```python
# app/modules/members/service.py  (append; add imports at top)
import uuid
from sqlalchemy import select
from app.core.errors import NotFoundError
from app.modules.members.models import ClinicMember, MemberRole, MemberStatus
from app.modules.members.capabilities import resolve_capabilities
from app.modules.members.schemas import CapabilitiesRead
from app.modules.clinics.service import get_settings
from app.modules.doctors.service import get_doctor
from app.modules.assistants.service import get_assistant


def _effective_role(db, clinic_id: uuid.UUID, linked_user_id, nominal: MemberRole) -> MemberRole:
    if linked_user_id is None:
        return nominal
    membership = db.execute(
        select(ClinicMember).where(
            ClinicMember.clinic_id == clinic_id,
            ClinicMember.user_id == linked_user_id,
            ClinicMember.status == MemberStatus.active,
        )
    ).scalar_one_or_none()
    return membership.role if membership is not None else nominal


def get_member_capabilities(db, *, clinic_id: uuid.UUID, kind: str, member_id: uuid.UUID) -> CapabilitiesRead:
    if kind == "doctor":
        member = get_doctor(db, clinic_id, member_id)   # raises NotFoundError if absent
        nominal = MemberRole.doctor
    elif kind == "assistant":
        member = get_assistant(db, clinic_id, member_id)
        nominal = MemberRole.assistant
    else:
        raise NotFoundError("Unknown member kind.")
    role = _effective_role(db, clinic_id, member.linked_user_id, nominal)
    settings = get_settings(db, clinic_id)
    return CapabilitiesRead(
        member_id=member.id, kind=kind, effective_role=role.value,
        capabilities=resolve_capabilities(role, settings),
    )
```

> NOTE: confirm `get_doctor`/`get_assistant`/`get_settings` signatures (`(db, clinic_id, id)` / `(db, clinic_id)`) before wiring; they're used this way in `scheduling/booking.py` and `scheduling/service.py`.

- [ ] **Step 4: Run tests**

Run: `uv run pytest tests/members/test_member_capabilities_service.py -v`
Expected: PASS.

- [ ] **Step 5: Lint + commit**

```bash
uv run ruff check .
git add app/modules/members/service.py tests/members/test_member_capabilities_service.py
git commit -m "feat(members): resolve member effective role + capabilities service (#108)"
```

---

### Task 4: Read endpoints (doctors + assistants) + authz tests

**Files:**
- Modify: `app/modules/doctors/router.py` (add capabilities route)
- Modify: `app/modules/assistants/router.py` (add capabilities route)
- Test: `tests/members/test_capabilities_endpoint.py` (new)

**Interfaces:**
- Consumes: `service.get_member_capabilities` (Task 3); `CurrentMembership`, `DbSession`.
- Produces:
  - `GET /api/v1/clinics/{clinic_id}/doctors/{doctor_id}/capabilities -> CapabilitiesRead`
  - `GET /api/v1/clinics/{clinic_id}/assistants/{assistant_id}/capabilities -> CapabilitiesRead`

- [ ] **Step 1: Write the failing test**

```python
# tests/members/test_capabilities_endpoint.py
def test_member_can_read_capabilities(client, clinic, assistant_member, member_auth_headers):
    r = client.get(
        f"/api/v1/clinics/{clinic.id}/assistants/{assistant_member.id}/capabilities",
        headers=member_auth_headers)
    assert r.status_code == 200
    body = r.json()
    assert body["kind"] == "assistant"
    assert len(body["capabilities"]) == 6


def test_non_member_forbidden(client, clinic, assistant_member, other_clinic_auth_headers):
    r = client.get(
        f"/api/v1/clinics/{clinic.id}/assistants/{assistant_member.id}/capabilities",
        headers=other_clinic_auth_headers)
    assert r.status_code == 403


def test_unknown_member_404(client, clinic, member_auth_headers):
    import uuid
    r = client.get(
        f"/api/v1/clinics/{clinic.id}/doctors/{uuid.uuid4()}/capabilities",
        headers=member_auth_headers)
    assert r.status_code == 404
```

- [ ] **Step 2: Run test to verify it fails**

Run: `uv run pytest tests/members/test_capabilities_endpoint.py -v`
Expected: FAIL — 404 route not found / AttributeError.

- [ ] **Step 3: Add the routes (thin)**

```python
# app/modules/doctors/router.py  (add)
import uuid
from app.modules.members import service as members_service
from app.modules.members.schemas import CapabilitiesRead

@router.get("/{clinic_id}/doctors/{doctor_id}/capabilities", response_model=CapabilitiesRead)
def doctor_capabilities(clinic_id: uuid.UUID, doctor_id: uuid.UUID, db: DbSession, membership: CurrentMembership):
    return members_service.get_member_capabilities(db, clinic_id=clinic_id, kind="doctor", member_id=doctor_id)
```

```python
# app/modules/assistants/router.py  (add)
import uuid
from app.modules.members import service as members_service
from app.modules.members.schemas import CapabilitiesRead

@router.get("/{clinic_id}/assistants/{assistant_id}/capabilities", response_model=CapabilitiesRead)
def assistant_capabilities(clinic_id: uuid.UUID, assistant_id: uuid.UUID, db: DbSession, membership: CurrentMembership):
    return members_service.get_member_capabilities(db, clinic_id=clinic_id, kind="assistant", member_id=assistant_id)
```

> NOTE: place the new routes so they don't collide with existing `/{clinic_id}/doctors/{doctor_id}` paths; FastAPI matches the longer literal suffix `/capabilities` fine. `membership: CurrentMembership` is the auth gate (any active member; cross-clinic → 403 via `get_current_membership`).

- [ ] **Step 4: Run tests + full suite**

Run: `uv run pytest tests/members -v && make test`
Expected: PASS (new endpoint tests + whole suite green).

- [ ] **Step 5: Lint + commit**

```bash
uv run ruff check .
git add app/modules/doctors/router.py app/modules/assistants/router.py tests/members/test_capabilities_endpoint.py
git commit -m "feat(api): member capabilities read endpoints (#108)"
```

---

## Self-Review (plan vs spec)

- §3 inventory (6 caps, exact role×settings) → Task 2 resolver + tests. ✅
- §4a reusable predicates (no FE drift) → Task 1 + no-drift test in Task 2. ✅
- §4b resolver → Task 2. ✅
- §4c effective-role (owner-doctor → owner) → Task 3 `_effective_role`. ✅
- §4d endpoints + auth (member only, 403/404) → Task 4. ✅
- §4e DTOs → Task 2 schemas. ✅
- §4f tests (matrix, effective-role, endpoint authz, no-drift, regressions) → Tasks 1–4. ✅
- No migration / no new settings → confirmed (no Alembic step). ✅
- Placeholder scan: every code step has concrete code + commands. Signature-verify NOTEs flag the two spots to confirm against the live file, not placeholders. ✅
- Type consistency: `CapabilityRead`/`CapabilitiesRead`/`resolve_capabilities`/`get_member_capabilities` names + fields identical across Tasks 2–4. ✅

## README

Per the one-README-per-repo practice, update `dentist-registry-backend/README.md` in the FE/BE work (mention the capabilities endpoints) as part of whichever PR lands them — not a separate task.
