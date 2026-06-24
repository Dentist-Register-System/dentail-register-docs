# Appointment Day-of Lifecycle — Backend Plan (#139)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Add arrival/no-show/completion/cancel transitions on confirmed appointments — state-validated, idempotent, first-wins, audited — and fix the capacity rule so the new statuses don't cause overbooking.

**Architecture:** A migration adds nullable lifecycle columns; `count_consumers` is widened so only `cancelled` releases capacity; a lifecycle service performs each transition under a row lock; thin endpoints expose them with role-scoped authz.

**Tech Stack:** FastAPI, SQLAlchemy 2.x, pytest. PG :5433. Spec: `docs/specs/2026-06-24-appointment-day-of-lifecycle-design.md`.

## Global Constraints
- Migration applied to Supabase by the **controller** (not in the PR's automated steps); implementers validate on **local PG :5433** only. Never ports 5434/8001/3001.
- Every transition: lock the appointment row, validate source state (else `ConflictError`), mutate + audit in one transaction. **First-committed-transition-wins.** `uv run ruff check .` + `make test` green per commit. Worktree isolation; branch→PR→squash via `gh-personal`; backend merges on green.
- **Capacity:** an appointment consumes its slot in statuses `confirmed/arrived/completed/no_show`; only `cancelled` (and later `rescheduled`) release.
- Authz: arrival/no-show/completion → owner/assistant (any) or doctor (own); cancel → owner/assistant only.

---

### Task 1: Migration — lifecycle columns

**Files:** Create `alembic/versions/XXXX_appointment_lifecycle.py`; Modify `app/modules/scheduling/models.py` (Appointment).

- [ ] **Step 1:** Add to `Appointment` model (all nullable): `arrived_at: Mapped[datetime|None]`, `no_show_reason: Mapped[str|None]`, `no_show_at: Mapped[datetime|None]`, `completed_by: Mapped[uuid.UUID|None]`, `completed_at: Mapped[datetime|None]`, `completion_notes: Mapped[str|None]`, `cancel_reason: Mapped[str|None]`, `cancelled_at: Mapped[datetime|None]`, `cancelled_by: Mapped[uuid.UUID|None]`.
- [ ] **Step 2:** Generate the Alembic migration adding these columns to `appointment_beta` (all NULL; no `status` change — it stays `String(20)`). `make migrate` against local :5433; verify columns exist.
- [ ] **Step 3: Commit** `feat(db): appointment lifecycle columns (#139)`.

---

### Task 2: Capacity fix — `count_consumers` (overbooking guard)

**Files:** Modify `app/modules/scheduling/booking.py` (`count_consumers`, ~81–90); Test `tests/scheduling/test_capacity_lifecycle.py`.

- [ ] **Step 1: Write the failing test**

```python
# tests/scheduling/test_capacity_lifecycle.py
from app.modules.scheduling import booking
# capacity = 1 by default; seed a confirmed appointment on a slot
def test_arrived_completed_noshow_keep_capacity(db, clinic, slot_with_confirmed_appt):
    appt = slot_with_confirmed_appt
    for new in ("arrived", "completed", "no_show"):
        appt.status = new; db.flush()
        assert booking.count_consumers(db, appt.slot_id) == 1   # still consumes
def test_cancelled_releases_capacity(db, clinic, slot_with_confirmed_appt):
    appt = slot_with_confirmed_appt
    appt.status = "cancelled"; db.flush()
    assert booking.count_consumers(db, appt.slot_id) == 0       # released
```

- [ ] **Step 2: Run → fail** (today only `"confirmed"` counts, so arrived/completed/no_show would read 0).

- [ ] **Step 3: Implement** — widen the appointment branch:

```python
# booking.py  count_consumers — appointment branch
.where(Appointment.slot_id == slot_id,
       Appointment.status.in_(("confirmed", "arrived", "completed", "no_show")))
```

- [ ] **Step 4: Run → pass.** **Step 5: Commit** `fix(capacity): occupied statuses consume slot; only cancelled releases (#139)`.

---

### Task 3: Lifecycle service — transitions (lock → validate → audit)

**Files:** Create `app/modules/scheduling/lifecycle.py`; Test `tests/scheduling/test_lifecycle_transitions.py`.

**Interfaces:** `mark_arrived`, `undo_arrival`, `mark_no_show(reason)`, `undo_no_show`, `complete(notes=None)`, `edit_completion(notes)`, `cancel_appointment(reason, notify=True)` — each `(db, *, clinic_id, appointment_id, actor_user_id, ...) -> Appointment`.

- [ ] **Step 1: Write failing tests** (representative)

```python
# tests/scheduling/test_lifecycle_transitions.py
import pytest
from app.core.errors import ConflictError, ValidationError
from app.modules.scheduling import lifecycle

def test_arrive_then_undo(db, clinic, confirmed_appt, owner):
    a = lifecycle.mark_arrived(db, clinic_id=clinic.id, appointment_id=confirmed_appt.id, actor_user_id=owner.id)
    assert a.status == "arrived" and a.arrived_at is not None
    a = lifecycle.undo_arrival(db, clinic_id=clinic.id, appointment_id=a.id, actor_user_id=owner.id)
    assert a.status == "confirmed"

def test_no_show_requires_reason(db, clinic, confirmed_appt, owner):
    with pytest.raises(ValidationError):
        lifecycle.mark_no_show(db, clinic_id=clinic.id, appointment_id=confirmed_appt.id, actor_user_id=owner.id, reason="")

def test_complete_allows_empty_notes(db, clinic, confirmed_appt, owner):
    a = lifecycle.complete(db, clinic_id=clinic.id, appointment_id=confirmed_appt.id, actor_user_id=owner.id, notes=None)
    assert a.status == "completed" and a.completed_by == owner.id and a.completed_at is not None

def test_cancel_sets_fields_and_audits(db, clinic, confirmed_appt, owner):
    a = lifecycle.cancel_appointment(db, clinic_id=clinic.id, appointment_id=confirmed_appt.id, actor_user_id=owner.id, reason="patient called")
    assert a.status == "cancelled" and a.cancel_reason == "patient called"

def test_invalid_source_state_rejected(db, clinic, completed_appt, owner):
    with pytest.raises(ConflictError):
        lifecycle.mark_arrived(db, clinic_id=clinic.id, appointment_id=completed_appt.id, actor_user_id=owner.id)
```

- [ ] **Step 2: Run → fail** (module missing).

- [ ] **Step 3: Implement** — one locked, validated, audited helper pattern; apply to all transitions:

```python
# app/modules/scheduling/lifecycle.py
import datetime as dt
from sqlalchemy import select
from app.core.errors import ConflictError, ValidationError
from app.modules.audit.service import record_audit
from app.modules.scheduling.models import Appointment

def _locked(db, clinic_id, appointment_id) -> Appointment:
    appt = db.execute(
        select(Appointment).where(Appointment.id == appointment_id,
                                  Appointment.clinic_id == clinic_id).with_for_update()
    ).scalar_one_or_none()
    if appt is None:
        from app.core.errors import NotFoundError
        raise NotFoundError("Appointment not found.")
    return appt

def _transition(db, *, clinic_id, appointment_id, actor_user_id, allowed_from, to, action, apply, payload):
    appt = _locked(db, clinic_id, appointment_id)
    if appt.status not in allowed_from:
        raise ConflictError("This appointment is no longer in a state that allows this action.")
    old = appt.status
    apply(appt)
    appt.status = to
    record_audit(db, action=action, entity_type="appointment", entity_id=appt.id,
                 clinic_id=clinic_id, actor_user_id=actor_user_id,
                 old={"status": old}, new={"status": to, **payload})
    db.commit(); db.refresh(appt); return appt

def mark_arrived(db, *, clinic_id, appointment_id, actor_user_id):
    return _transition(db, clinic_id=clinic_id, appointment_id=appointment_id, actor_user_id=actor_user_id,
        allowed_from=("confirmed",), to="arrived", action="appointment.arrived",
        apply=lambda a: setattr(a, "arrived_at", dt.datetime.now()), payload={})

def undo_arrival(db, *, clinic_id, appointment_id, actor_user_id):
    return _transition(db, clinic_id=clinic_id, appointment_id=appointment_id, actor_user_id=actor_user_id,
        allowed_from=("arrived",), to="confirmed", action="appointment.arrival_undone",
        apply=lambda a: setattr(a, "arrived_at", None), payload={})

def mark_no_show(db, *, clinic_id, appointment_id, actor_user_id, reason):
    if not (reason or "").strip():
        raise ValidationError("A reason is required to mark no-show.")
    return _transition(db, clinic_id=clinic_id, appointment_id=appointment_id, actor_user_id=actor_user_id,
        allowed_from=("confirmed",), to="no_show", action="appointment.no_show",
        apply=lambda a: (setattr(a, "no_show_reason", reason), setattr(a, "no_show_at", dt.datetime.now())),
        payload={"reason": reason})

def undo_no_show(db, *, clinic_id, appointment_id, actor_user_id):
    return _transition(db, clinic_id=clinic_id, appointment_id=appointment_id, actor_user_id=actor_user_id,
        allowed_from=("no_show",), to="confirmed", action="appointment.no_show_undone",
        apply=lambda a: (setattr(a, "no_show_reason", None), setattr(a, "no_show_at", None)), payload={})

def complete(db, *, clinic_id, appointment_id, actor_user_id, notes=None):
    return _transition(db, clinic_id=clinic_id, appointment_id=appointment_id, actor_user_id=actor_user_id,
        allowed_from=("confirmed", "arrived"), to="completed", action="appointment.completed",
        apply=lambda a: (setattr(a, "completed_by", actor_user_id),
                         setattr(a, "completed_at", dt.datetime.now()),
                         setattr(a, "completion_notes", notes)), payload={})

def cancel_appointment(db, *, clinic_id, appointment_id, actor_user_id, reason, notify=True):
    if not (reason or "").strip():
        raise ValidationError("A reason is required to cancel.")
    return _transition(db, clinic_id=clinic_id, appointment_id=appointment_id, actor_user_id=actor_user_id,
        allowed_from=("confirmed",), to="cancelled", action="appointment.cancelled",
        apply=lambda a: (setattr(a, "cancel_reason", reason),
                         setattr(a, "cancelled_at", dt.datetime.now()),
                         setattr(a, "cancelled_by", actor_user_id)),
        payload={"reason": reason, "notify": notify})   # notify recorded, NOT sent (SP5 stub)

def edit_completion(db, *, clinic_id, appointment_id, actor_user_id, notes):
    appt = _locked(db, clinic_id, appointment_id)
    if appt.status != "completed":
        raise ConflictError("Only a completed appointment's notes can be edited.")
    appt.completion_notes = notes
    record_audit(db, action="appointment.completion_edited", entity_type="appointment",
                 entity_id=appt.id, clinic_id=clinic_id, actor_user_id=actor_user_id, new={"notes_set": notes is not None})
    db.commit(); db.refresh(appt); return appt
```

> NOTE: match `record_audit` kwargs + `Appointment` field names already in the codebase; `dt.datetime.now()` mirrors existing naive-local usage (`is_expired`). Capacity needs no manual bookkeeping here — §4 (Task 2) handles it via status.

- [ ] **Step 4: Run → pass** (all transitions + invalid-source + reason-required + empty-notes-ok).
- [ ] **Step 5: Commit** `feat(scheduling): appointment lifecycle transitions service (#139)`.

---

### Task 4: Authz + endpoints + concurrency/authz tests

**Files:** Modify `app/modules/scheduling/router.py`; Test `tests/scheduling/test_lifecycle_endpoints.py`.

**Interfaces:** `POST /clinics/{id}/appointments/{appt_id}/{arrive|undo-arrival|no-show|undo-no-show|complete|cancel}` + `PATCH …/{appt_id}/completion-notes`.

- [ ] **Step 1: Write failing tests** — happy paths per action; **authz**: doctor on own appt can arrive/complete; doctor on *another* doctor's appt → 403; doctor **cancel** → 403 (→ #141); owner/assistant cancel ok. **Concurrency**: two concurrent `complete` + `cancel` on the same appt → exactly one wins, the other 409 (`ConflictError`). 422 when no-show/cancel reason missing.

- [ ] **Step 2–4:** Add `authorize_run_day(db, appt, membership)` (owner/assistant any; doctor iff `get_doctor(...).linked_user_id == membership.user_id`) and `authorize_cancel(membership)` (owner/assistant only — else `ForbiddenError`). Thin routes parse body → authorize → call `lifecycle.*` → return `AppointmentRead` (extend it with the new nullable fields). `make test` green.

- [ ] **Step 5: Commit** `feat(api): appointment lifecycle endpoints + authz (#139)`.

---

## Self-Review (vs spec)
- Migration (§3) → T1; capacity guard (§4) → T2; transitions/locks/validate/audit (§5/§6) → T3; authz + endpoints + concurrency (§6) → T4. ✅
- Cancel releases capacity via status (no manual slot bookkeeping); arrival/no-show/completion don't → T2 regression. ✅
- Completion never blocked; no-show/cancel reason required → T3. ✅
- Placeholder scan: full transition code + tests; verify-NOTE on audit/model field names. ✅

## README
Update `dentist-registry-backend/README.md` (appointment lifecycle endpoints + the capacity rule) in the PR.
