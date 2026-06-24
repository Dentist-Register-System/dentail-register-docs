# Audit/Observability Consistency Pass — Backend Plan (#34)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Fix four audit/observability nits mirrored across the Doctor and Assistant services (+ verify one caller), with test hygiene. Backend-only, no migration, no FE.

**Architecture:** Each fix is applied to **both** `doctors/service.py` and `assistants/service.py` in lock-step so the mirror stays consistent. Nit 1 relies on the invite-accept flow being a single uncommitted transaction (raise → atomic rollback).

**Tech Stack:** FastAPI, SQLAlchemy 2.x, pytest, structlog/logging. PG :5433. Spec: `docs/specs/2026-06-24-audit-observability-consistency-design.md`.

## Global Constraints
- **Backend-only. No migration. No FE.** Touch only `app/modules/{doctors,assistants}/service.py`, `tests/`, and (verify) `app/modules/invites/service.py`. Do NOT touch scheduling/home/shell (parallel-lane isolation).
- Work in a **git worktree**; branch → PR → squash via `gh-personal`; never push `main`; backend merges on green.
- `uv run ruff check .` clean + `make test` green per commit. Never ports 5434/8001/3001. Remove dead code as found.
- Apply each change to **doctor AND assistant** (mirror) in the same task.

---

### Task 1: `link_user_to_*` — log + raise on missing entity (Nit 1) + enum value (Nit 3)

**Files:**
- Modify: `app/modules/doctors/service.py` (`link_user_to_doctor`, ~296–311)
- Modify: `app/modules/assistants/service.py` (`link_user_to_assistant`, ~278–293)
- Test: `tests/doctors/test_link_user.py`, `tests/assistants/test_link_user.py` (or extend existing invite-accept tests)

- [ ] **Step 1: Write the failing test** (doctor; mirror for assistant)

```python
# tests/doctors/test_link_user.py
import pytest
from app.core.errors import NotFoundError
from app.modules.doctors import service

def test_link_user_raises_when_doctor_missing(db, clinic, app_user):
    import uuid
    with pytest.raises(NotFoundError):
        service.link_user_to_doctor(db, doctor_id=uuid.uuid4(), user_id=app_user.id)

def test_accept_invite_rolls_back_when_doctor_deleted(db, clinic, doctor_invite, delete_doctor_entity, accept_invite):
    # invite references a doctor row that has since been deleted
    import pytest
    from app.core.errors import NotFoundError
    with pytest.raises(NotFoundError):
        accept_invite(doctor_invite)
    # membership NOT created, invite still pending (transaction rolled back)
    from app.modules.members.models import ClinicMember
    assert db.query(ClinicMember).filter_by(clinic_id=clinic.id, user_id=doctor_invite.invited_user_id).first() is None
```

- [ ] **Step 2: Run → fail.** `uv run pytest tests/doctors/test_link_user.py -v`

- [ ] **Step 3: Implement (both services)**

```python
# app/modules/doctors/service.py  — link_user_to_doctor
import logging
logger = logging.getLogger(__name__)

def link_user_to_doctor(db, *, doctor_id, user_id) -> None:
    doctor = db.get(Doctor, doctor_id)          # match current fetch
    if doctor is None:
        logger.error("link_user_to_doctor: doctor row missing",
                     extra={"doctor_id": str(doctor_id), "user_id": str(user_id)})
        raise NotFoundError("The doctor profile for this invitation no longer exists.")
    doctor.linked_user_id = user_id             # match current field
    doctor.status = DoctorStatus.active
    record_audit(db, action="doctor.activated", entity_type="doctor", entity_id=doctor.id,
                 clinic_id=doctor.clinic_id, actor_user_id=user_id,
                 new={"status": DoctorStatus.active.value})   # Nit 3: enum value, not "active"
```
Mirror in `assistants/service.py` (`Assistant`, `AssistantStatus.active.value`, "assistant.activated").

> NOTE: match the **current** entity fetch + the linked-user field name + `record_audit` kwargs already used in the file (only the `return`→raise, the log, and the `.value` change are new). Import `NotFoundError` from `app.core.errors` if not already.

- [ ] **Step 4: Run → pass** (both services' tests + the existing invite-accept happy path stays green).

- [ ] **Step 5: Commit** `fix(audit): link_user_to_* raises + logs on missing entity, enum value (#34)`.

---

### Task 2: `update_*` — emit BOTH events on combined edit (Nit 2)

**Files:**
- Modify: `app/modules/doctors/service.py` (`update_doctor`, ~90–128, line 115)
- Modify: `app/modules/assistants/service.py` (`update_assistant`, ~85–125, line 112)
- Test: `tests/doctors/test_update_audit.py`, `tests/assistants/test_update_audit.py`

- [ ] **Step 1: Write the failing test** (doctor; mirror for assistant)

```python
# tests/doctors/test_update_audit.py
from app.modules.doctors import service
from app.modules.audit.models import AuditEvent  # match model

def _actions(db, clinic_id, entity_id):
    rows = db.query(AuditEvent).filter_by(clinic_id=clinic_id, entity_id=entity_id).all()
    return {r.action for r in rows}

def test_status_only_emits_status_changed(db, clinic, active_doctor, owner):
    service.update_doctor(db, clinic_id=clinic.id, doctor_id=active_doctor.id, actor_user_id=owner.id, new_status="inactive")
    assert "doctor.status_changed" in _actions(db, clinic.id, active_doctor.id)
    assert "doctor.updated" not in _actions(db, clinic.id, active_doctor.id)

def test_fields_only_emits_updated(db, clinic, active_doctor, owner):
    service.update_doctor(db, clinic_id=clinic.id, doctor_id=active_doctor.id, actor_user_id=owner.id, name="Dr. New Name")
    acts = _actions(db, clinic.id, active_doctor.id)
    assert "doctor.updated" in acts and "doctor.status_changed" not in acts

def test_combined_emits_both(db, clinic, active_doctor, owner):
    service.update_doctor(db, clinic_id=clinic.id, doctor_id=active_doctor.id, actor_user_id=owner.id,
                          new_status="inactive", name="Dr. New Name")
    acts = _actions(db, clinic.id, active_doctor.id)
    assert "doctor.status_changed" in acts and "doctor.updated" in acts
```

- [ ] **Step 2: Run → fail** (combined currently emits only status_changed).

- [ ] **Step 3: Implement (both services)** — replace the single-action line with two-flag emission:

```python
# app/modules/doctors/service.py — inside update_doctor, replacing line ~115
status_changed = new_status is not None and new_status != old_status
fields_changed = bool(changed_fields)   # the non-status fields actually applied (exclude_unset minus status)
if status_changed:
    record_audit(db, action="doctor.status_changed", entity_type="doctor", entity_id=doctor.id,
                 clinic_id=clinic_id, actor_user_id=actor_user_id,
                 old={"status": old_status.value}, new={"status": new_status.value})
if fields_changed:
    record_audit(db, action="doctor.updated", entity_type="doctor", entity_id=doctor.id,
                 clinic_id=clinic_id, actor_user_id=actor_user_id, new=changed_fields)
```
Mirror in `assistants/service.py`.

> NOTE: derive `old_status`, `changed_fields` from the function's existing update logic (it already computes the status transition + applies fields). Keep existing payload shape for `*.status_changed`; `changed_fields` = the dict of non-status fields that changed. Preserve the existing `db.commit()`/return.

- [ ] **Step 4: Run → pass** (both services).

- [ ] **Step 5: Commit** `fix(audit): emit both status_changed + updated on combined edits (#34)`.

---

### Task 3: Test hygiene (Nit 4)

**Files:**
- Modify: `tests/conftest.py` (or the nearest shared conftest) — add a `_clinic`/`clinic` fixture
- Modify: the doctor/assistant test files that duplicated `_clinic`; scope audit-event queries to the test `clinic_id`

- [ ] **Step 1:** Identify the duplicated `_clinic` helper across doctor/assistant test files (`grep -rn "_clinic" tests/`).
- [ ] **Step 2:** Extract it to a shared `conftest.py` fixture; update the test files to consume the fixture (delete the local copies — no orphan helpers).
- [ ] **Step 3:** Scope every audit-event assertion to the test's clinic: `query(AuditEvent).filter_by(clinic_id=clinic.id, ...)` (never an unfiltered `.all()`).
- [ ] **Step 4:** `make test` green (no behavior change; refactor only).
- [ ] **Step 5: Commit** `test(audit): dedup _clinic fixture + scope audit asserts to clinic_id (#34)`.

---

## Self-Review (vs spec)
- Nit 1 (log+raise+rollback-safe) + Nit 3 (enum value) → Task 1; Nit 2 (both events) → Task 2; Nit 4 (test hygiene) → Task 3. ✅
- Mirrored doctor + assistant in each task; backend-only; no migration. ✅
- Placeholder scan: concrete tests + code; verify-NOTEs flag where to match existing fetch/field/payload, not TBDs. ✅

## README
No README change expected (internal correctness). If audit event semantics are documented anywhere in `dentist-registry-backend/README.md`, note the combined-edit dual-emit.
