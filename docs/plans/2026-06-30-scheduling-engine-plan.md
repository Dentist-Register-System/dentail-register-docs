# Scheduling Engine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Consolidate every scheduling decision (request state transitions, booking disposition, slot occupancy, day-availability resolution) into one engine — `app/modules/scheduling/engine.py` — so nothing else decides, behavior is preserved (proven by a characterization net), and future lifecycle states become a 3–5 line edit to one transition table.

**Architecture:** Mirror the Permissions engine exactly. A pure `scheduling/engine.py` holds status enums, a `TRANSITIONS` table, a typed `Decision` (`__bool__` raises), and three composing public gates (`authorize_transition`, `authorize_booking`, `resolve_slots`) so a caller makes ONE call to decide. `booking.py`/`service.py`/`reads.py`/`rules.py` demote to plumbing that asks the engine. A CI bypass-guard locks it.

**Tech Stack:** Python 3, FastAPI, SQLAlchemy 2.x, pytest vs Postgres :5433, ruff, `uv`. No new dependencies.

## Global Constraints

- Repo `dentist-registry-backend`. Tests: `docker compose up -d` then `uv run pytest`; lint `uv run ruff check .`. Every new file carries the Sentinel header docstring (copy the format from `app/modules/scheduling/rules.py:1-10`).
- **The engine is PURE:** no DB, no I/O, no `datetime.now()` inside decision functions — callers pass facts in (counts, `expired: bool`, `now`). Repos count and hold locks/transactions; the engine only decides (Sentinel Rule 13).
- **One call to decide:** a caller never composes two engine answers. The gate composes permission + state + capacity and returns one `Decision`.
- **Behavior-preserving:** the characterization net (Task 1) must be green against today's code before the engine is wired, and stay green after — except the single ruled blocks-fix (Task 6), surfaced explicitly.
- **No migration:** enum *values* equal today's strings (`"pending"`, `"approved"`, `"rejected"`, `"cancelled"`, `"confirmed"`, `"direct_booking"`, `"request_approval"`); DB columns stay `String`. If any task thinks it needs a schema change, STOP and flag.
- Permission delegation goes through the permission engine's public gate only: `from app.modules.permissions import Action, can` (Sentinel Rule 12).
- Spec: `dentail-register-docs/docs/specs/2026-06-30-scheduling-engine-design.md`.

---

### Task 1: Characterization net — pin today's behavior

**Files:**
- Create: `tests/scheduling/characterization/__init__.py` (empty)
- Create: `tests/scheduling/characterization/test_decision_behaviors.py`

**Interfaces:**
- Consumes (today's code, unchanged): `app.modules.scheduling.rules.capacity`, `rules.is_expired`; `app.modules.scheduling.service.compute_slots`; the request action funcs in `booking.py` (`approve_request`/`reject_request`/`cancel_request`/`resend_request`) via the existing service/router test helpers.
- Produces: a green baseline asserting current outputs for the four decision families, so later tasks prove equivalence.

- [ ] **Step 1: Pin the capacity + expiry predicates (pure, no DB)**

```python
# tests/scheduling/characterization/test_decision_behaviors.py
import datetime as dt
from types import SimpleNamespace
import pytest
from app.modules.scheduling import rules

def _settings(multi=False, maxb=1):
    return SimpleNamespace(allow_multiple_bookings_per_slot=multi, max_bookings_per_slot=maxb)

@pytest.mark.parametrize("multi,maxb,expected", [
    (False, 1, 1), (False, 5, 1), (True, 3, 3), (True, 1, 1),
])
def test_capacity_today(multi, maxb, expected):
    assert rules.capacity(_settings(multi, maxb)) == expected

def test_is_expired_today_only_pending_and_past():
    past = dt.datetime.now() - dt.timedelta(hours=1)
    future = dt.datetime.now() + dt.timedelta(hours=1)
    mk = lambda status, exp: SimpleNamespace(status=status, expires_at=exp)
    assert rules.is_expired(mk("pending", past)) is True
    assert rules.is_expired(mk("pending", future)) is False
    assert rules.is_expired(mk("pending", None)) is False
    assert rules.is_expired(mk("approved", past)) is False  # non-pending never expires
```

- [ ] **Step 2: Run — must pass against current code**

Run: `docker compose up -d && uv run pytest tests/scheduling/characterization/test_decision_behaviors.py -q`
Expected: PASS. (If `capacity`/`is_expired` differ from the above, the assertions are wrong — fix the test to match TODAY's code; that is the characterization.)

- [ ] **Step 3: Pin the day-resolver divergence (the bug, made explicit)**

Add a test that resolves a day where the doctor has a window AND a full-day block, via BOTH paths, and records that they disagree today. Read `service.compute_slots` and `reads.get_day_schedule`/`day_windows` signatures first. Build one recurring window + one full-day block for a date, then:

```python
def test_resolver_paths_disagree_on_blocks_today(db, seed_clinic):
    # compute_slots applies the block → that day has NO available slots
    # reads.get_day_schedule's day_windows ignores blocks → still lists the window
    # Pin BOTH outputs exactly as they are today. This test DOCUMENTS the divergence;
    # Task 6 will flip the diary onto compute_slots and this expectation changes (ruled).
    ...  # implementer: seed via existing scheduling test fixtures, assert both current outputs
```

Use the existing scheduling test fixtures/factories (look in `tests/scheduling/` for how requests/windows/blocks are seeded). Assert the CURRENT outputs of both paths — including the divergence. Mark the test name `_today` so Task 6 can supersede it.

- [ ] **Step 4: Pin the request-action state guard + disposition matrix**

Using the existing scheduling integration-test fixtures (find the pattern in `tests/scheduling/`), assert for the four actions that a `pending` request proceeds and a non-`pending` request raises the current conflict error, and that the `direct_booking` vs `doctor_approval` workflow yields confirmed-now vs pending. Pin the EXACT error code/envelope today's code returns (read `booking.py` `_conflict()` to get it).

```python
@pytest.mark.parametrize("action", ["approve", "reject", "cancel", "resend"])
def test_non_pending_request_is_rejected_today(db, seed_pending_request, action):
    # set the request status to "approved", invoke the action, assert today's conflict error code
    ...
```

- [ ] **Step 5: Run the full net — green baseline**

Run: `uv run pytest tests/scheduling/characterization/ -q`
Expected: PASS (the baseline). Commit.

- [ ] **Step 6: Commit**

```bash
git add tests/scheduling/characterization/
git commit -m "test(scheduling): characterization net — pin current decision behavior before extraction"
```

---

### Task 2: The engine core — enums, Decision, TRANSITIONS, assert_actionable

**Files:**
- Create: `app/modules/scheduling/engine.py`
- Test: `tests/scheduling/test_engine_state.py`

**Interfaces:**
- Consumes: `app.modules.members.models.MemberRole`, `app.modules.permissions.Action`.
- Produces: `RequestStatus`, `AppointmentStatus`, `RequestAction` (str enums); `Decision(allowed, reason, next_state)` with raising `__bool__`; `TRANSITIONS: dict[(RequestStatus, RequestAction), _Rule]`; `assert_actionable(status, action, *, expired) -> Decision`; reason codes `REASON_NOT_ACTIONABLE`, `REASON_EXPIRED`, `REASON_SLOT_FULL`, `REASON_SLOT_NOT_AVAILABLE`.

- [ ] **Step 1: Write the failing test**

```python
# tests/scheduling/test_engine_state.py
import pytest
from app.modules.scheduling import engine as e

def test_decision_has_no_truth_value():
    with pytest.raises(TypeError):
        bool(e.Decision(True))

def test_pending_allows_all_four_actions():
    for action in e.RequestAction:
        d = e.assert_actionable(e.RequestStatus.pending, action, expired=False)
        assert d.allowed is True
        assert d.next_state == e.TRANSITIONS[(e.RequestStatus.pending, action)].to

def test_non_pending_is_not_actionable():
    for status in (e.RequestStatus.approved, e.RequestStatus.rejected, e.RequestStatus.cancelled):
        d = e.assert_actionable(status, e.RequestAction.approve, expired=False)
        assert d.allowed is False and d.reason == e.REASON_NOT_ACTIONABLE

def test_expiry_blocks_approve_only():
    assert e.assert_actionable(e.RequestStatus.pending, e.RequestAction.approve, expired=True).reason == e.REASON_EXPIRED
    # reject/cancel/resend ignore expiry (correct as-is)
    for action in (e.RequestAction.reject, e.RequestAction.cancel, e.RequestAction.resend):
        assert e.assert_actionable(e.RequestStatus.pending, action, expired=True).allowed is True

def test_enum_values_are_wire_compatible():
    assert e.RequestStatus.pending.value == "pending"
    assert e.RequestStatus.approved.value == "approved"
    assert e.AppointmentStatus.confirmed.value == "confirmed"
```

- [ ] **Step 2: Run to verify it fails**

Run: `uv run pytest tests/scheduling/test_engine_state.py -q`
Expected: FAIL — `ModuleNotFoundError: app.modules.scheduling.engine`.

- [ ] **Step 3: Write the engine core**

```python
# app/modules/scheduling/engine.py
"""Sentinel rules (full set: Rules/sentinel-rules.md). Core, in-file so they propagate:
  • Each scheduling decision lives in exactly ONE engine; callers ask — they never
    compare request status or capacity outside scheduling/engine.py.
  • One source of truth per decision. No dead code. No imports inside functions.
  • Honest tests only — real assertions, no placeholders.

Scheduling — THE engine. The one place a scheduling decision is made: request state
transitions, booking disposition, slot occupancy, day-availability resolution. Pure:
no DB, no I/O — callers pass facts (counts, expired, now) in; the engine only decides.
Future lifecycle states are new rows in TRANSITIONS — edited here, nowhere else.
"""

from dataclasses import dataclass
from enum import Enum

from app.modules.members.models import MemberRole
from app.modules.permissions import Action, can
from app.modules.scheduling.rules import capacity


class RequestStatus(str, Enum):
    pending = "pending"
    approved = "approved"
    rejected = "rejected"
    cancelled = "cancelled"


class AppointmentStatus(str, Enum):
    confirmed = "confirmed"


class RequestAction(str, Enum):
    approve = "approve"
    reject = "reject"
    cancel = "cancel"
    resend = "resend"


# Stable, translatable denial reason codes (Golden Rule 16.2).
REASON_NOT_ACTIONABLE = "request_not_actionable"
REASON_EXPIRED = "request_expired"
REASON_SLOT_FULL = "slot_full"
REASON_SLOT_NOT_AVAILABLE = "slot_not_available"


@dataclass(frozen=True)
class Decision:
    """A scheduling decision. Check `.allowed` explicitly — `__bool__` raises so a
    bare `if authorize_*(...)` (forgetting `.allowed`) fails loudly instead of
    silently allowing. `next_state` carries the resulting status for the workflow."""

    allowed: bool
    reason: str | None = None
    next_state: "RequestStatus | None" = None

    def __bool__(self) -> bool:
        raise TypeError(
            "Decision has no truth value — check `.allowed` explicitly. "
            "A bare `if authorize_*(...)` would silently allow."
        )


_ALLOW_FIELDS = {"reason": None}


@dataclass(frozen=True)
class _Rule:
    to: RequestStatus
    perm: Action  # the permission action delegated to the permission engine
    expiry_blocks: bool  # does an expired request block this action? (approve only)
    checks_capacity: bool  # is slot capacity checked? (approve only)


# The whole appointment-request state machine, as data. Add a row to add a transition.
TRANSITIONS: dict[tuple[RequestStatus, RequestAction], _Rule] = {
    (RequestStatus.pending, RequestAction.approve): _Rule(
        RequestStatus.approved, Action.DECIDE_BOOKING, expiry_blocks=True, checks_capacity=True
    ),
    (RequestStatus.pending, RequestAction.reject): _Rule(
        RequestStatus.rejected, Action.DECIDE_BOOKING, expiry_blocks=False, checks_capacity=False
    ),
    (RequestStatus.pending, RequestAction.cancel): _Rule(
        RequestStatus.cancelled, Action.COORDINATE_BOOKING, expiry_blocks=False, checks_capacity=False
    ),
    (RequestStatus.pending, RequestAction.resend): _Rule(
        RequestStatus.pending, Action.COORDINATE_BOOKING, expiry_blocks=False, checks_capacity=False
    ),
}


def assert_actionable(status: RequestStatus, action: RequestAction, *, expired: bool) -> Decision:
    """State-machine gate only: is `action` legal on a request in `status` (given expiry)?
    Permission and capacity are layered on by `authorize_transition`."""
    rule = TRANSITIONS.get((status, action))
    if rule is None:
        return Decision(False, REASON_NOT_ACTIONABLE)
    if rule.expiry_blocks and expired:
        return Decision(False, REASON_EXPIRED)
    return Decision(True, next_state=rule.to)
```

- [ ] **Step 4: Run to verify it passes**

Run: `uv run pytest tests/scheduling/test_engine_state.py -q && uv run ruff check app/modules/scheduling/engine.py`
Expected: PASS · ruff clean.

- [ ] **Step 5: Commit**

```bash
git add app/modules/scheduling/engine.py tests/scheduling/test_engine_state.py
git commit -m "feat(scheduling): engine core — status enums, typed Decision, TRANSITIONS, assert_actionable"
```

---

### Task 3: occupancy, initial_disposition, and the composing gates

**Files:**
- Modify: `app/modules/scheduling/engine.py` (append functions)
- Test: `tests/scheduling/test_engine_gates.py`

**Interfaces:**
- Consumes: Task 2's `engine` names; `rules.capacity`; `permissions.can`.
- Produces: `occupancy(other_consumers, settings) -> Decision`; `initial_disposition(settings, *, force_direct=False) -> RequestStatus`; `authorize_transition(*, status, action, role, settings, is_assigned, expired, other_consumers=0) -> Decision`; `authorize_booking(*, role, settings, is_own_doctor, slot_available, other_consumers) -> Decision`; `may_decide(role, settings, *, is_assigned) -> bool`.

- [ ] **Step 1: Write the failing test**

```python
# tests/scheduling/test_engine_gates.py
from types import SimpleNamespace
from app.modules.members.models import MemberRole
from app.modules.scheduling import engine as e

def _s(workflow="doctor_approval", asa=True, multi=False, maxb=1):
    return SimpleNamespace(
        scheduling_workflow=workflow, allow_staff_approval=asa,
        allow_staff_manage_availability=True,
        allow_multiple_bookings_per_slot=multi, max_bookings_per_slot=maxb,
    )

def test_occupancy_uses_capacity():
    assert e.occupancy(0, _s()).allowed is True
    assert e.occupancy(1, _s()).allowed is False and e.occupancy(1, _s()).reason == e.REASON_SLOT_FULL
    assert e.occupancy(2, _s(multi=True, maxb=3)).allowed is True  # room for 3

def test_disposition_direct_vs_approval():
    assert e.initial_disposition(_s(workflow="direct_booking")) == e.RequestStatus.approved
    assert e.initial_disposition(_s(workflow="doctor_approval")) == e.RequestStatus.pending
    assert e.initial_disposition(_s(workflow="doctor_approval"), force_direct=True) == e.RequestStatus.approved

def test_authorize_transition_composes_permission_state_capacity():
    # owner approving a pending, not-expired, roomy slot → allowed, next_state approved
    d = e.authorize_transition(status=e.RequestStatus.pending, action=e.RequestAction.approve,
                               role=MemberRole.owner, settings=_s(), is_assigned=False,
                               expired=False, other_consumers=0)
    assert d.allowed is True and d.next_state == e.RequestStatus.approved
    # assistant approving when staff-approval OFF → denied with the permission reason
    d2 = e.authorize_transition(status=e.RequestStatus.pending, action=e.RequestAction.approve,
                                role=MemberRole.assistant, settings=_s(asa=False), is_assigned=False,
                                expired=False, other_consumers=0)
    assert d2.allowed is False
    # full slot blocks approve
    d3 = e.authorize_transition(status=e.RequestStatus.pending, action=e.RequestAction.approve,
                                role=MemberRole.owner, settings=_s(), is_assigned=False,
                                expired=False, other_consumers=1)
    assert d3.allowed is False and d3.reason == e.REASON_SLOT_FULL
    # non-pending → not actionable, permission never consulted
    d4 = e.authorize_transition(status=e.RequestStatus.approved, action=e.RequestAction.approve,
                                role=MemberRole.owner, settings=_s(), is_assigned=False,
                                expired=False, other_consumers=0)
    assert d4.allowed is False and d4.reason == e.REASON_NOT_ACTIONABLE

def test_may_decide_is_permission_slice():
    assert e.may_decide(MemberRole.owner, _s(), is_assigned=False) is True
    assert e.may_decide(MemberRole.assistant, _s(asa=False), is_assigned=False) is False
```

- [ ] **Step 2: Run to verify it fails**

Run: `uv run pytest tests/scheduling/test_engine_gates.py -q`
Expected: FAIL — `AttributeError: module ... has no attribute 'occupancy'`.

- [ ] **Step 3: Append the functions to `engine.py`**

```python
def occupancy(other_consumers: int, settings) -> Decision:
    """Is there room for one more booking, given `other_consumers` already holding the
    slot? The repo counts (pending requests + confirmed appointments, self-excluded
    where relevant); the engine owns only the `>= capacity` comparison (Rule 13)."""
    if other_consumers >= capacity(settings):
        return Decision(False, REASON_SLOT_FULL)
    return Decision(True)


def initial_disposition(settings, *, force_direct: bool = False) -> RequestStatus:
    """Does a new booking auto-confirm (direct-booking workflow or a forced direct
    booking) or wait for doctor approval? Replaces the scattered `== "direct_booking"`."""
    if force_direct or settings.scheduling_workflow == "direct_booking":
        return RequestStatus.approved
    return RequestStatus.pending


def authorize_transition(
    *, status: RequestStatus, action: RequestAction, role: MemberRole, settings,
    is_assigned: bool, expired: bool, other_consumers: int = 0,
) -> Decision:
    """THE gate for approve/reject/cancel/resend — one call to decide. Composes:
    state (TRANSITIONS + expiry) → permission (delegated to the permission engine,
    Rule 12) → capacity (approve only). Returns one typed Decision."""
    state = assert_actionable(status, action, expired=expired)
    if not state.allowed:
        return state
    rule = TRANSITIONS[(status, action)]
    perm = can(role, settings, rule.perm, is_self=is_assigned)
    if not perm.allowed:
        return Decision(False, perm.reason)
    if rule.checks_capacity and not occupancy(other_consumers, settings).allowed:
        return Decision(False, REASON_SLOT_FULL)
    return Decision(True, next_state=rule.to)


def authorize_booking(
    *, role: MemberRole, settings, is_own_doctor: bool, slot_available: bool, other_consumers: int,
) -> Decision:
    """THE gate for creating a new booking — one call. Composes permission
    (CREATE_BOOKING) → slot validity → capacity, and carries the disposition
    (pending vs auto-confirmed) as `next_state`."""
    perm = can(role, settings, Action.CREATE_BOOKING, is_self=is_own_doctor)
    if not perm.allowed:
        return Decision(False, perm.reason)
    if not slot_available:
        return Decision(False, REASON_SLOT_NOT_AVAILABLE)
    if not occupancy(other_consumers, settings).allowed:
        return Decision(False, REASON_SLOT_FULL)
    return Decision(True, next_state=initial_disposition(settings, force_direct=False))


def may_decide(role: MemberRole, settings, *, is_assigned: bool) -> bool:
    """The per-row 'can this user decide bookings here' flag — the permission slice
    only (behavior-preserving; the FE list already gates on status). Single home for
    the two previously-inlined copies."""
    return can(role, settings, Action.DECIDE_BOOKING, is_self=is_assigned).allowed
```

- [ ] **Step 4: Run to verify it passes**

Run: `uv run pytest tests/scheduling/test_engine_gates.py -q && uv run ruff check app/modules/scheduling/engine.py`
Expected: PASS · ruff clean.

- [ ] **Step 5: Commit**

```bash
git add app/modules/scheduling/engine.py tests/scheduling/test_engine_gates.py
git commit -m "feat(scheduling): occupancy, disposition, and the composing gates (one call to decide)"
```

---

### Task 4: `resolve_slots` — the one availability+occupancy resolver

**Files:**
- Modify: `app/modules/scheduling/engine.py` (move the pure resolver in) and `app/modules/scheduling/service.py` (re-export / delegate)
- Test: `tests/scheduling/test_engine_resolver.py`

**Interfaces:**
- Produces: `resolve_slots(windows, blocks, date_from, date_to, slot_minutes, capacity_n) -> list[Slot-shaped dict]` — the promotion of today's `service.compute_slots` (`service.py:289-351`) into the engine, with its `_chunk`/`_overlaps`/window-for-day predicate as private helpers.
- Consumes: today's `compute_slots` behavior (read it fully first).

- [ ] **Step 1: Read the current `compute_slots`**

Read `app/modules/scheduling/service.py:274-351` in full — `_chunk`, `_overlaps`, the window-for-day filter (`:304-310`), full-day block match (`:318`), interval overlap (`:321`), and the returned slot shape. The engine version must produce byte-identical output for the same inputs.

- [ ] **Step 2: Write the failing test (characterization-style, against the NEW location)**

```python
# tests/scheduling/test_engine_resolver.py
import datetime as dt
from app.modules.scheduling import engine as e

def test_recurring_window_chunks_into_slots():
    # one 09:00-10:00 recurring Monday window, 30-min slots, no blocks → two slots
    win = _recurring(day_of_week=0, start="09:00", end="10:00")  # helper builds the window shape
    slots = e.resolve_slots([win], [], dt.date(2026, 6, 29), dt.date(2026, 6, 29), 30, 1)
    assert len(slots) == 2

def test_full_day_block_removes_all_slots():
    win = _recurring(day_of_week=0, start="09:00", end="10:00")
    block = _full_day_block(dt.date(2026, 6, 29))
    slots = e.resolve_slots([win], [block], dt.date(2026, 6, 29), dt.date(2026, 6, 29), 30, 1)
    assert all(s["status"] == "blocked" for s in slots) or slots == []  # match compute_slots' today behavior
```

(Implementer: set `_recurring`/`_full_day_block` to build the exact window/block objects `compute_slots` expects, and set the assertions to match today's `compute_slots` output — verify by calling the old `service.compute_slots` with the same inputs in the test and asserting `resolve_slots(...) == service.compute_slots(...)`.)

- [ ] **Step 3: Run to verify it fails**

Run: `uv run pytest tests/scheduling/test_engine_resolver.py -q`
Expected: FAIL — `resolve_slots` undefined.

- [ ] **Step 4: Move the resolver into the engine; make `service` delegate**

- Cut `_chunk`, `_overlaps`, and `compute_slots` from `service.py` into `engine.py` as `_chunk`, `_overlaps`, and `resolve_slots` (same bodies, same slot output shape). Keep the window-for-day predicate as a private `_window_active_on(window, day)` helper inside the engine.
- In `service.py`, replace the old `compute_slots` with a one-line delegation so existing callers keep working unchanged:

```python
# service.py — compute_slots is now the engine's resolver (single source).
from app.modules.scheduling.engine import resolve_slots

def compute_slots(windows, blocks, date_from, date_to, slot_minutes, capacity):
    return resolve_slots(windows, blocks, date_from, date_to, slot_minutes, capacity)
```

(This keeps `_validate_slot` and `list_slots` green with zero behavior change — they still call `service.compute_slots`, which now routes to the engine. The diary flip is Task 6.)

- [ ] **Step 5: Run resolver test + the existing scheduling suite + the characterization net**

Run: `uv run pytest tests/scheduling/ -q && uv run ruff check app/modules/scheduling/`
Expected: PASS (resolver byte-identical; nothing else changed).

- [ ] **Step 6: Commit**

```bash
git add app/modules/scheduling/engine.py app/modules/scheduling/service.py tests/scheduling/test_engine_resolver.py
git commit -m "feat(scheduling): resolve_slots is the one availability+occupancy resolver (service delegates)"
```

---

### Task 5: Flip the state-machine + disposition call sites onto the engine

**Files:**
- Modify: `app/modules/scheduling/booking.py` (approve/reject/cancel/resend guards `:299/:331/:358/:381`, create disposition `:227`, the `count_consumers`/approve self-exclusion `:306`, the two per-row `can_decide` `:468`, and `auto_approve_pending`)
- Modify: `app/modules/scheduling/reads.py` (per-row `can_decide` `:100`)
- Modify: `app/modules/clinics/service.py` (workflow-switch backfill branch `:162`)

**Interfaces:** Consumes Task 2–3 engine gates. No new test file — the characterization net (Task 1) + existing scheduling suite are the proof.

- [ ] **Step 1: Replace each `status != "pending"` guard with the engine gate**

In each of `approve_request`/`reject_request`/`cancel_request`/`resend_request`, replace the inline `if req.status != "pending": raise _conflict()` (and, in approve, the inline expiry + capacity checks) with ONE call:

```python
# example: approve_request
decision = engine.authorize_transition(
    status=engine.RequestStatus(req.status), action=engine.RequestAction.approve,
    role=membership.role, settings=settings,
    is_assigned=(req.doctor_id == viewer_doctor_id),   # identity fact  # sched-exempt: identity, not a decision
    expired=rules.is_expired(req),
    other_consumers=count_consumers(db, req.slot_id) - 1,  # self-excluded
)
if not decision.allowed:
    raise _engine_error(decision.reason)   # maps reason → today's error envelope (see Step 2)
```

For reject/cancel/resend pass the matching `RequestAction`; they pass `other_consumers=0` (capacity not checked) and `expired=rules.is_expired(req)` (ignored for those actions by the table). Remove the now-dead inline `authorize_decide`/`authorize_coordinate` permission calls — `authorize_transition` composes permission internally.

- [ ] **Step 2: Map engine reasons to the existing error envelope (no client-visible change)**

Add a small `_engine_error(reason)` helper in `booking.py` that returns the SAME exception type + code the old inline guards raised (read `_conflict()` and the permission `ForbiddenError` paths to match exactly): `REASON_NOT_ACTIONABLE`/`REASON_EXPIRED`/`REASON_SLOT_FULL` → the old conflict/validation error; a permission reason → the old `ForbiddenError`. The characterization net asserts the wire response is unchanged.

- [ ] **Step 3: Flip create-disposition and the backfill**

- In `create_request` (`booking.py:~227`), replace `if force_direct or settings.scheduling_workflow == "direct_booking":` with `if engine.initial_disposition(settings, force_direct=force_direct) == engine.RequestStatus.approved:`.
- In `clinics/service.py:162`, replace the `changes.get("scheduling_workflow") == "direct_booking" and ...` branch's decision with the engine: gate the backfill on `engine.initial_disposition(new_settings) == engine.RequestStatus.approved` (keep the "was not already direct" guard as plain data comparison of the stored value — that's a state read, not a scheduling decision; mark `# sched-exempt:` if the guard names the literal).

- [ ] **Step 4: De-duplicate the two per-row `can_decide` computations**

Replace the inline `can(..., Action.DECIDE_BOOKING, ...)` at `booking.py:468-471` and `reads.py:100-103` with `engine.may_decide(membership.role, settings, is_assigned=(r.doctor_id == viewer_doctor_id))`. (The `# authz-exempt`/`# sched-exempt` marker on the identity compare stays.)

- [ ] **Step 5: Run the characterization net + full scheduling suite**

Run: `uv run pytest tests/scheduling/ tests/clinics/ -q`
Expected: PASS — behavior preserved. If the net goes red, STOP: a flip changed behavior. Diagnose (root-cause, don't patch the test) and bring genuine behavior changes to the user.

- [ ] **Step 6: Commit**

```bash
git add app/modules/scheduling/booking.py app/modules/scheduling/reads.py app/modules/clinics/service.py
git commit -m "refactor(scheduling): flip state/disposition/can_decide call sites onto the engine"
```

---

### Task 6: Flip the diary onto `resolve_slots` — the ruled blocks-fix

**Files:**
- Modify: `app/modules/scheduling/reads.py` (`get_day_schedule`/`day_windows` `:149-178`)
- Modify: `tests/scheduling/characterization/test_decision_behaviors.py` (supersede the `_today` divergence test)

**Interfaces:** Consumes `engine.resolve_slots`.

- [ ] **Step 1: Surface the divergence to the user (BLOCKING)**

The diary (`reads.py day_windows`) ignores blocks; `resolve_slots` applies them. Routing the diary through `resolve_slots` makes a full-day-blocked doctor stop showing as available — a behavior change. Per the spec (§8) and Golden Rule 2.1, present the exact case (the Task-1 Step-3 characterization test) to the user and confirm the ruling: **diary adopts the block-applying resolver.** Do not proceed until confirmed.

- [ ] **Step 2: Flip the diary**

Replace `day_windows`'s block-ignoring window list with `engine.resolve_slots(...)` (same windows+blocks the schedule already loads), so the diary's availability reflects blocks. Keep the response shape identical; only blocked days change.

- [ ] **Step 3: Supersede the characterization test**

Update the `test_resolver_paths_disagree_on_blocks_today` test: rename to `test_diary_now_respects_blocks` and assert the diary and `resolve_slots` now AGREE (the blocked day shows no availability). This is the one ruled, labelled behavior change.

- [ ] **Step 4: Run**

Run: `uv run pytest tests/scheduling/ -q`
Expected: PASS (the superseded test now asserts agreement).

- [ ] **Step 5: Commit**

```bash
git add app/modules/scheduling/reads.py tests/scheduling/characterization/test_decision_behaviors.py
git commit -m "fix(scheduling): diary respects availability blocks (one resolver) — ruled behavior fix"
```

---

### Task 7: The CI bypass-guard

**Files:**
- Create: `tests/scheduling/test_no_bypass.py`
- Modify: scheduling files to add `# sched-exempt:` markers on identity-fact / state-read compares the guard would flag.

**Interfaces:** Mirror `tests/permissions/test_no_bypass.py` (read it first — `:38-61`).

- [ ] **Step 1: Write the guard + its teeth test**

```python
# tests/scheduling/test_no_bypass.py  (model on tests/permissions/test_no_bypass.py)
# Scan app/ (skipping app/modules/scheduling/engine.py) for scheduling-decision shapes
# made outside the engine without a `# sched-exempt:` marker:
#   - request/appointment status comparisons:  r"\.status\s*(==|!=)\s*[\"']"
#   - capacity comparisons:                     r"(>=|>|<|<=)\s*capacity\(" and r"capacity\(\w+\)\s*(>=|>|<|<=)"
#   - the direct_booking workflow literal:      r"scheduling_workflow\s*==\s*[\"']direct_booking"
# A flagged line passes only if it (or the line above) contains "sched-exempt".
# Include test_guard_has_teeth: the patterns DO catch `req.status == "pending"` and
# `count >= capacity(s)`, and do NOT flag assignments / the engine's own TRANSITIONS keys.
```

(Implementer: copy the structure, regexes, comment-stripping, and `*_DIR in path.parents` skip from the permissions guard; adapt the patterns above; write a real `test_guard_has_teeth`.)

- [ ] **Step 2: Run — expect failures listing the remaining bare compares**

Run: `uv run pytest tests/scheduling/test_no_bypass.py -q`
Expected: FAIL, listing identity facts / state reads still bare (e.g. `req.doctor_id == viewer_doctor_id` is NOT a status compare so won't flag; a genuine remaining `req.status == "pending"` would). Add `# sched-exempt: <reason>` to each legitimate non-decision compare (status *reads* for display/filtering that are not gating a transition, e.g. `reads.py:80` status filter — mark it). If a flagged site is an actual decision, move it into the engine instead.

- [ ] **Step 3: Run until green**

Run: `uv run pytest tests/scheduling/ -q && uv run ruff check tests/scheduling/`
Expected: PASS — guard green with teeth; all decision logic is in the engine.

- [ ] **Step 4: Commit**

```bash
git add tests/scheduling/test_no_bypass.py app/modules/scheduling/ app/modules/clinics/service.py
git commit -m "test(scheduling): CI bypass-guard — no scheduling decision outside the engine"
```

---

### Task 8: The "Scheduling" temple tab

**Files:**
- Create: `app/modules/scheduling/dashboard.py`
- Modify: `scripts/temple/registry.py` (add to `ENGINES`)
- Test: covered by `tests/temple/test_no_drift.py` + `tests/temple/test_registry.py` (completeness) automatically.

**Interfaces:** Mirror `app/modules/permissions/dashboard.py` — `dashboard_data() -> dict` computed by RUNNING the engine.

- [ ] **Step 1: Write `dashboard_data()` for scheduling**

```python
# app/modules/scheduling/dashboard.py  (Sentinel header like the others)
# title "Scheduling"; build the matrix by RUNNING the engine:
#   - a state-machine view: for each (RequestStatus, RequestAction) run assert_actionable
#     (expired False/True) → cell {allowed, qualifier: "expired→blocked" where relevant}
#   - reverse_index: "Can this request be <action>'d?" → decided_at the file:line of
#     authorize_transition (derive via inspect, like permissions/_POLICY_LOC)
#   - settings_behavior: scheduling_workflow → [disposition], capacity settings → [occupancy]
# Return the same shape keys the generator expects: title, matrix{actions,roles/states,cells},
# reverse_index, settings_behavior. (Read permissions/dashboard.py:64-96 for the exact shape.)
```

(Implementer: follow `permissions/dashboard.py` exactly for the return shape; the "roles" axis becomes the `RequestAction` axis and the "actions" axis becomes `RequestStatus`, since this engine's matrix is status×action. Compute every cell by calling `assert_actionable`.)

- [ ] **Step 2: Register the engine**

In `scripts/temple/registry.py`, add `from app.modules.scheduling import dashboard as scheduling_dashboard` and `"scheduling": scheduling_dashboard.dashboard_data` to `ENGINES`.

- [ ] **Step 3: Regenerate + verify drift-guard + completeness**

Run: `make temple && uv run pytest tests/temple/ tests/scheduling/ -q && uv run ruff check app/modules/scheduling/dashboard.py scripts/temple/`
Expected: PASS — `discovered_engines() == set(ENGINES)` (completeness) and the committed HTML matches a fresh render (drift), now with a "Scheduling" tab.

- [ ] **Step 4: Commit**

```bash
git add app/modules/scheduling/dashboard.py scripts/temple/registry.py docs/architecture/temple-map.html
git commit -m "feat(temple): Scheduling engine lights up its generated dashboard tab"
```

---

## Self-Review

- **Spec coverage:** §2 playbook → Tasks 1 (net), 2–4 (consolidate), 5–6 (flip), 7 (guard). §4 families: Family 1 → Task 2 (`assert_actionable`/`TRANSITIONS`) + Task 5 flip; Family 2 → Task 3 (`initial_disposition`) + Task 5; Family 3 → Task 3 (`occupancy`) + Task 5 self-exclusion; Family 4 → Task 4 (`resolve_slots`) + Task 6 diary flip; Family 5 → Task 4 (slot-valid via resolver) + Task 3 (`authorize_booking`). §5 three gates → Task 3. §6 TRANSITIONS → Task 2. §8 characterization → Task 1. §9 guard → Task 7. §5 dashboard tab → Task 8. §10 FE wing → out of scope (separate spec, noted). §13 R3 no-migration → Global Constraints + Task 2 wire-compatible enum test.
- **Placeholder scan:** Tasks 4/7/8 contain "(implementer: …)" notes where the exact assertions/regex come from reading a named current file (`compute_slots`, the permissions guard, `permissions/dashboard.py`) — these are *characterization/mirror* tasks where the source-of-truth is existing code, not invented values; each names the precise file:line to copy from. All NEW engine logic (Tasks 2–3) is complete code, no placeholders.
- **Type consistency:** `Decision(allowed, reason, next_state)`, `RequestStatus`, `RequestAction`, `authorize_transition(*, status, action, role, settings, is_assigned, expired, other_consumers)`, `occupancy(other_consumers, settings)`, `may_decide(role, settings, *, is_assigned)`, `resolve_slots(windows, blocks, date_from, date_to, slot_minutes, capacity_n)` — names identical across Tasks 2–8. `other_consumers` (self-excluded count) is the consistent occupancy input everywhere.
- **One open contract to confirm at build time (Task 5 Step 2):** the exact error type/code the old guards raise — the implementer reads `_conflict()`/`ForbiddenError` and matches it so the wire response is unchanged; the characterization net is the proof.
