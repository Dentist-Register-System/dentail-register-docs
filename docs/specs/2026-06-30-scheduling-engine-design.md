# Scheduling Engine — Design Spec

**Date:** 2026-06-30
**Status:** Approved (brainstorm) → ready for implementation plan
**Doctrine:** `Rules/sentinel-rules.md` (Rules 3, 6, 9, 10, 11, 12, 14) · `Rules/register-golden-rules.md` (5, 6, 7, 10, 16.2, 19) · the Permissions engine is the proven template.

## 1. Goal

The internals that decide **scheduling** — whether a booking request can be approved/rejected/cancelled/resent, whether a new booking auto-confirms or waits, whether a slot is full, and what is bookable on a given day — are currently made by inline checks scattered across `booking.py`, `service.py`, `reads.py`, and `rules.py`. No state machine, no single owner.

Give Scheduling the **exact** treatment Permissions just received: **one engine, every decision in exactly one place, callers only ask.** The result is behavior-preserving (proven by a characterization net), and future lifecycle states (`cancelled`, `arrived`, `completed`, `no-show`, reschedule) become a **3–5 line edit to one transition table**, nowhere else.

This spec is the **backend wing**. The frontend wing (messenger-ification — the FE makes zero scheduling decisions) follows as a separate spec once the backend lands.

## 2. The playbook (same as Permissions, in order)

1. **Map** every place a scheduling decision is made. (§4 — done.)
2. **Characterization net** — pin the *current* behavior of every mapped site, so the engine can be proven byte-identical before any call site is flipped. (§8)
3. **Consolidate** — every mapped decision becomes **one function in `scheduling/engine.py`**. Nothing else decides. (§5–§6)
4. **Flip** all call sites to ask the engine; add a **CI bypass-guard** that keeps it that way. (§9)

**Binding rule (the user's):** *no more than one function call to decide.* A caller never composes two engine answers itself. If a decision needs state **and** capacity **and** permission, the engine composes them internally and returns **one** typed `Decision`.

## 3. The Permissions template we copy (contract)

- Typed `Decision` (`permissions/policy.py:41-57`): frozen dataclass, `allowed: bool` + `reason: str | None` (stable code when denied), and `__bool__` **raises** so a bare `if can(...)` can never silently allow. Shared `_ALLOW` singleton.
- One public gate: `permissions/__init__.py` exports only `Action, Decision, can`. Internals (`policy.py` reason constants, `dashboard.py`) are not re-exported.
- Table tests: `tests/permissions/test_decision.py` runs `itertools.product(ROLES, FLAGS, ACTIONS)` and asserts the `allowed → reason is None` / `denied → reason in REASONS` invariant over the full grid; `test_capability_matrix.py` pins golden snapshots.
- Anti-bypass guard: `tests/permissions/test_no_bypass.py` greps `app/` (skipping the engine dir) for role-decision shapes, with an `# authz-exempt:` marker escape and a `test_guard_has_teeth` proving the regex catches real shapes and ignores assignments/hints.
- Dashboard: `dashboard.py::dashboard_data()` computes its matrix by **running** the engine; registered in `scripts/temple/registry.py::ENGINES`; drift-guarded by `tests/temple/test_no_drift.py`.

## 4. The "before" map — every scheduling decision today

Verified against the code (not just the temple-map, which is stale where noted). Five decision families:

### Family 1 — "Is this request in a state that allows action X?" (the state machine)
- No `Enum` exists; `status` is bare strings. `AppointmentRequest.status` default `"pending"` (`models.py:81`); `Appointment.status` default `"confirmed"` (`models.py:107`), written `"confirmed"` only, only at `booking.py:157`. `source` ∈ {`request_approval`, `direct_booking`} (`models.py:108`).
- The guard `if req.status != "pending": raise _conflict()` is **re-typed in 4 functions**: approve `booking.py:299`, reject `booking.py:331`, cancel `booking.py:358`, resend `booking.py:381`.
- Expiry (`rules.py:17 is_expired`) is checked in **approve only** (`booking.py:293`), not the other three. **Correct as-is** (you may reject/cancel/resend an expired request; only *approving* a stale one is blocked) — the engine preserves this by parameterizing on action.
- Single-writer is intact: appointment `status` is written only from `booking.py`. `arrived`/`completed`/`no-show` do not exist yet (net-new, out of scope).

### Family 2 — "Does a new request auto-confirm or wait for approval?" (disposition)
- `booking.py:227`: `force_direct or settings.scheduling_workflow == "direct_booking"` → auto-materialize an appointment immediately vs leave `pending`.
- `clinics/service.py:162-163`: on admin switching the workflow to `direct_booking`, run `auto_approve_pending` (`booking.py:519`) over the backlog. Duplicate `"direct_booking"` string literal.

### Family 3 — "Is this slot full?" (occupancy / capacity)
- `count_consumers(db, slot_id)` (`booking.py:102-113`) = pending requests + confirmed appointments on a slot. The authoritative write-path count.
- `reserve_slot` (`booking.py:116-138`): `SELECT … FOR UPDATE` lock, then `count_consumers >= capacity(settings)` (`booking.py:136`) — capacity check at create.
- Approve-time second check (`booking.py:306`): `count_consumers - 1 >= capacity(settings)` — the `-1` is **self-exclusion** (the pending row being approved counts itself), meaningful, not a fudge.
- `capacity(settings)` (`rules.py:17-18`): `max_bookings_per_slot` if `allow_multiple_bookings_per_slot` else `1`. Single source for the *number*.
- Display re-count for the slot list badge (`service.py:380-406`): a **separate** two-SELECT count, `"full"` at `:406`. Same data, second implementation.

### Family 4 — "What's bookable on day X?" (availability resolution)
- `compute_slots(windows, blocks, …)` (`service.py:289-351`): the canonical resolver — chunks windows into slots (`_chunk` `:274`), applies blocks (full-day `:318`, interval `_overlaps` `:285/:321`), sets slot status. Called by `_validate_slot` (`booking.py:77-99`) and `list_slots`.
- The day-window predicate (`w.kind == "recurring" and day_of_week == dow` or `one_off and specific_date == day`) lives at `service.py:304-310`.
- **Divergence:** `reads.py:169-178 day_windows` re-implements that predicate **and ignores blocks** → a doctor with a full-day block still shows **available** in the diary. Also feeds working-window bounds (`reads.py:243`).

### Family 5 — "Is this start a legitimate slot?" (slot validation)
- `_validate_slot` (`booking.py:77-99`) re-runs `compute_slots` for the date and confirms the requested `start_datetime` is a real slot. Depends on Family 4.

### Adjacent (already correct, or out of scope)
- **Permission half** — already single-sourced in the **permission** engine. Scheduling calls `can(... DECIDE_BOOKING / CREATE_BOOKING / COORDINATE_BOOKING / MANAGE_AVAILABILITY / VIEW_CLINIC_SCHEDULE ...)` at `booking.py:68/283/349`, `service.py:47`, `doctors/router.py:40`, `members/deps.py:45`. **The temple-map's "Dog 1" claim that the approval rule is duplicated in `capabilities.py` is stale** — `capabilities.py:24` calls the permission engine. Scheduling will *delegate* to it (Rule 12), not re-own it.
- Per-row `can_decide` is computed inline, identically, in **two** projections (`booking.py:468-471`, `reads.py:100-103`); appointments hardcode `can_decide=False` (`reads.py:72`). These become emissions of the engine's one transition gate.
- `is_self` fact-gathering role compares (`booking.py:65/280`, `service.py:44`) are identity facts, not decisions — they stay, carrying `# sched-exempt:`/`# authz-exempt:` as today.
- **Window-authoring validation** (`end > start`, recurring/one-off invariants) is checked ×3 (`schemas.py:23-33`, `service.py:139-150`, `service.py:427-431`) — this belongs to the **Availability engine** queued next, **not** this one (§7).

## 5. The engine — home, files, public gate

Inside the existing `scheduling/` module (appointments *are* scheduling — keep the domain cohesive, least churn):

- **`scheduling/engine.py`** — the ONLY place a scheduling decision is made. Contains:
  - The status enums (`RequestStatus`, `AppointmentStatus`) — replacing bare strings, values identical to today's strings (wire-compatible).
  - The `TRANSITIONS` table (§6).
  - The typed `Decision` (copy the Permissions contract: frozen, `allowed`+`reason`, `__bool__` raises; the scheduling `Decision` also carries optional `next_state` for disposition — Rule 9 explicitly allows next-action metadata).
  - Stable `REASON_*` codes (e.g. `not_pending`, `request_expired`, `slot_full`, `slot_not_available`).
  - The pure decision functions (§ below).
- **`scheduling/__init__.py`** — the **one public gate**: exports only the engine surface (`Decision`, the enums, the public functions). `booking.py` / `service.py` / `reads.py` / `rules.py` are demoted to plumbing (DB access, locking, serialization) that *ask* the engine; they import from `scheduling.engine` only.
- **`scheduling/dashboard.py`** + add `"scheduling": scheduling_dashboard.dashboard_data` to `scripts/temple/registry.py::ENGINES` → the generated temple tab, named **"Scheduling"**.

### Public gate — one call to decide

The 5 families compose behind **three** entry points; every caller makes exactly one call and reads the `Decision`/result:

1. **`authorize_transition(request, action, *, role, settings, is_assigned) → Decision`**
   The single gate for approve / reject / cancel / resend. Internally composes: permission (delegates to the permission engine — `DECIDE_BOOKING` for approve/reject, `COORDINATE_BOOKING` for cancel/resend) + `assert_actionable` (the transition table + approve-only expiry) + capacity (approve only, self-excluded). Replaces the 4 scattered `status != "pending"` guards **and** is the one source for per-row `can_decide`.
2. **`authorize_booking(*, role, settings, is_own_doctor, slot) → Decision`**
   For new bookings: permission (`CREATE_BOOKING`) + slot-valid (Family 5→4) + capacity (Family 3). Carries the **disposition** (`next_state` = `pending` vs `confirmed`) from Family 2. Replaces the `workflow == "direct_booking"` branches.
3. **`resolve_slots(windows, blocks, range, settings) → [Slot]`**
   The **one** availability+occupancy resolver (promote `compute_slots`). Used by *both* booking-validation **and** the diary read path — killing the blocks-ignored divergence by construction. `_validate_slot`, `list_slots`, and `reads.py get_day_schedule` all route through it.

Internal pure helpers (not the gate, but the single home of each sub-decision): `assert_actionable(status, action) → Decision`, `occupancy(consumers, settings) → Decision`, `initial_disposition(settings, *, force_direct) → RequestStatus`, plus the resolver internals (`_chunk`, `_overlaps`, the window-for-day predicate). No caller calls these directly — they reach them only through the three gates.

## 6. The transition table (why "future = 3–5 lines")

`TRANSITIONS` is literal data: `{(RequestStatus, Action): TransitionRule}` where a rule names the resulting state and which guards apply (permission action, whether expiry blocks it, whether capacity is checked). Today's rows:

| from | action | → to | guards |
|---|---|---|---|
| `pending` | approve | `approved` (+ appointment `confirmed`) | DECIDE_BOOKING · expiry-blocks · capacity (self-excl) |
| `pending` | reject | `rejected` | DECIDE_BOOKING |
| `pending` | cancel | `cancelled` | COORDINATE_BOOKING |
| `pending` | resend | `pending` (no state change) | COORDINATE_BOOKING |

Adding `cancelled`/`arrived`/`completed`/`no-show` later = new enum values + new rows here. One file, one place — exactly the property the whole exercise buys.

## 7. The Appointments / Availability seam

This engine owns the day **resolver** (Family 4) because occupancy and slot-validation depend on it, and because the live blocks-bug lives there. It does **not** own window-**authoring** validation (the `end > start` / kind-invariant checks ×3) — that is the **Availability engine**, queued next. Clean cut: *Scheduling decides what's bookable and what can happen to a booking; Availability will decide whether a window definition is valid.* The temple-map's separate "Appointments" + "Availability" sections fold under the generated **"Scheduling"** tab as each engine lands.

## 8. Characterization net (prove-then-wire — Rule 11)

Before touching a production file, write a net that pins **current** behavior of every mapped site, computed from the **old** code:
- **State machine:** for each `(status, action)` pair, record the old guard's outcome (allowed / which error) — including the approve-only expiry asymmetry.
- **Occupancy:** for representative `(consumers, capacity-settings)` grids, record `count_consumers`/`reserve_slot`/approve-check verdicts **and** the display badge — capturing whether the two counts already agree (they should; the net proves it).
- **Resolver:** for representative `(windows, blocks, date)` inputs, record `compute_slots` output **and** `reads.py day_windows` output — this is where the **divergence is made explicit**: the two produce different answers for a blocked day. The net documents both; consolidation forces one. **When that collision turns a characterization assertion red, I bring the exact case to the user and they rule** (no silent change). Expected ruling (per brainstorm): the diary adopts the block-applying resolver.
- **Disposition:** for `workflow ∈ {direct_booking, doctor_approval}` × `force_direct`, record pending-vs-confirmed.

The net lives at `tests/scheduling/characterization/` and must be **green against today's code** before the engine exists. After the engine is wired, the same behavioral assertions run against the new path; differences are either proven-identical or surfaced-and-ruled.

## 9. Flip + CI bypass-guard

After the engine is proven, flip every call site to the single engine call, then add **`tests/scheduling/test_no_bypass.py`** (sibling of the permissions guard): grep `app/` (skipping `scheduling/engine.py`) for scheduling-decision shapes — bare `\.status\s*(==|!=)\s*["']` request/appointment status comparisons, capacity comparisons against `capacity(`/`max_bookings`, and the window-kind predicate — failing CI unless marked `# sched-exempt: <reason>`. Include a `test_guard_has_teeth`. Identity-fact role compares keep their existing exempt markers.

## 10. Both wings, in order

- **Wing 1 — backend (this spec):** map → net → engine → flip → guard → dashboard tab.
- **Wing 2 — frontend (separate spec, after BE ships):** audit the FE for any scheduling *decision* (status comparisons, capacity/occupancy math, availability computed client-side); replace with engine-emitted flags/data (the diary renders what `resolve_slots` decided; row actions read the engine's `can_decide`/actionability); extend the FE sentinel guard to scheduling shapes. PDP/PEP: the FE asks, never decides.

## 11. PR sequence (small, green, behavior-preserving)

1. **Characterization net** — pin current behavior against the old code (no production change). Proves the baseline.
2. **`scheduling/engine.py`** — enums + `Decision` + `TRANSITIONS` + `assert_actionable` + `occupancy` + `initial_disposition`, with table tests. No call sites flipped yet.
3. **`resolve_slots`** — promote `compute_slots` into the engine as the one resolver; table-test it; route `_validate_slot` + `list_slots` through it (still no behavior change — those already used `compute_slots`).
4. **Flip the state-machine + disposition call sites** (`booking.py` approve/reject/cancel/resend/create + `clinics/service.py` backfill) to `authorize_transition`/`authorize_booking`; net stays green; per-row `can_decide` now sourced from the gate.
5. **Flip the diary** (`reads.py get_day_schedule`) to `resolve_slots` — the blocks-divergence collision; surface + rule; fix the diary.
6. **CI bypass-guard** + `# sched-exempt` markers on the identity facts.
7. **Dashboard tab** — `scheduling/dashboard.py` + registry; temple tab "Scheduling"; refresh temple-map (correct the stale Dog-1 claim).

Each PR flags any Alembic migration prominently (none expected — this is logic-only; the enums are wire-compatible with existing string values, no column change). Backend-only; ships ahead of any FE wing per Golden Rule 19.

## 12. Testing

- **Table tests** (Rule 10): every `(status, action)` and representative `(consumers, capacity)` / `(windows, blocks, date)` combination asserted explicitly, golden-snapshot style.
- **Characterization** (Rule 11): old-vs-new equivalence over the same grids.
- **Concurrency** (Golden Rule 10.4): the existing `reserve_slot` `FOR UPDATE` + capacity behavior must be preserved — keep/extend simultaneous-booking and approve/cancel-race tests; the engine decides, the repo still holds the lock and the transaction (Rule 13).
- **Drift** — the new dashboard tab is covered by `tests/temple/test_no_drift.py` automatically once registered.

## 13. Risks & mitigations

- **R1 — Hidden behavior in the "agreeing" duplicates.** Mitigation: the characterization net runs against old code first; any non-obvious difference shows as a red baseline before the engine exists.
- **R2 — The blocks-divergence is a real behavior change.** Mitigation: surfaced explicitly at the collision (PR 5), ruled by the user, shipped as a labelled fix — never silent (Golden Rule 2.1).
- **R3 — Enum migration.** Mitigation: enum *values* equal today's strings; the DB columns stay string; no Alembic change. If a future PR wants a DB-level enum/index, it's flagged separately.
- **R4 — Transaction boundaries.** Mitigation: the engine returns decisions; it does not open transactions or acquire locks. `booking.py` keeps `reserve_slot`'s `FOR UPDATE` + the atomic approve-and-create (Golden Rule 13.3) — decision and persistence stay separated, as in Permissions.
- **R5 — Scope creep into net-new states.** Mitigation: `cancelled`/`arrived`/`completed`/`no-show` are explicitly out; the table just makes them cheap later.

## 14. Success criteria

- Every Family-1…5 decision is made in exactly one function in `scheduling/engine.py`; the bypass-guard is green and has teeth.
- The characterization net proves behavior-preserving (save the one ruled blocks-fix).
- A caller makes **one** engine call per decision; no caller composes engine answers.
- The "Scheduling" temple tab is generated + drift-guarded.
- Backend tests green; backend-only, additive, deployable ahead of the FE wing.
