# Multi-Slot Booking — Design Spec

**Date:** 2026-07-02
**Status:** **Approved** (2026-07-02) — all §2 decisions ruled by the user; ready for implementation (backend wing first).
**Doctrine:** `Rules/sentinel-rules.md` (Rules 1, 3, 5, 6, 9, 10, 11, 13) · `Rules/register-golden-rules.md` (2.4, 5, 6, 13, 16, 17–18, 19) · `Rules/frontend-handbook.md`. Builds on `docs/specs/2026-06-30-scheduling-engine-design.md`.
**Wings:** one design (this doc) → `docs/plans/2026-07-02-multi-slot-booking-backend-plan.md` (ships first) → `…-frontend-plan.md` (after BE, Golden Rule 19).
**Design mockup (approved):** interactive prototype off real tokens + the real `SlotChip`/`BookAppointmentFlow`, light + dark, signed off 2026-07-02. (The mockup showed an illustrative 4-slot ceiling; the ruling is **no cap**.)

---

## Implementation note (Golden Rule 2.4)

All §2 decisions are ruled — implementation may proceed. But the halt still stands for anything
**new**: if you hit a choice this spec does not cover while building, **STOP and ask the user** —
never default or infer. Dispatch every code-writing subagent with the ASSUMPTION-HALT directive
(`Rules/assumption-halt-directive.md`); they don't inherit it.

---

## 1. Goal

Let staff book **several contiguous slots as one longer appointment** — e.g. `10:00–10:30` + `10:30–11:00` + `11:00–11:30` becomes a single `10:00–11:30` appointment — from the booking wizard, in **both** booking workflows, without ever letting a covered slot be booked past its capacity, and without putting a single scheduling *decision* anywhere but the scheduling engine.

Real dental procedures run longer than one slot. Today staff can only book one slot and work around it. Multi-slot makes the true duration a first-class booking. **A proper FE + BE slice.**

---

## 2. Decision Ledger — all ✅ RULED (by the user, 2026-07-02)

- **Workflows:** both **direct-booking** and **doctor-approval** support multi-slot.
- **O1 — Capacity model:** *uniform capacity rule* — any booking (single or run) is allowed iff **every slot it covers still has room** (`occupancy < capacity(settings)`), occupancy counted by overlap. A run may share a slot that has room; it just can't push any covered slot past capacity. (Supersedes the earlier "capacity-1 only".)
- **O2 — Entry points:** multi-select lives in the wizard **Time step**, available from every door that opens `BookAppointmentFlow`; **edit-length** is reached from the **appointment's actions** (detail / diary row).
- **O3 — API shape:** submit `{ start_datetime, end_datetime }`; add a **nullable** `end_datetime` to `AppointmentRequest` (additive migration).
- **O4 — Single = run of length 1:** the existing path, unchanged.
- **O5 — Contiguity:** time-adjacency, same doctor; may cross an availability-window boundary; **cannot** cross a `full`/`blocked`/`past` slot (those break a run).
- **O6 — Cancel:** frees the entire span in one transaction (all-or-nothing); no partial run.
- **O7 — Diary:** a multi-slot appointment renders as **one** row spanning `start→end`.
- **Cap:** **none** — any number of contiguous slots-with-room may be joined. **Always on**; **no MVP scoping** (full feature).

---

## 3. The problem today (grounded in the code)

Occupancy is **derived, not stored**, and matched by **exact start-time**. `scheduling/service.py:336-367`:

```python
occ = counts.get(s["start_datetime"], 0)          # service.py:365 — keyed by exact start
s["status"] = "full" if occ >= s["capacity"] else "available"
```

A single appointment `10:00–11:30` increments only the `10:00` bucket, so `10:30`/`11:00` read `available` and can be booked past capacity. **This exact-match mismatch — not a data model — is the entire backend problem.** Counting by overlap fixes it and is behavior-preserving for every existing single-slot booking.

---

## 4. Architecture — one decision point, extended (not bypassed)

The scheduling engine (`scheduling/engine.py`) owns every scheduling decision behind three gates: `authorize_transition`, `authorize_booking`, `resolve_slots` (engine design §5). Multi-slot **extends them and adds nothing outside the engine**:

1. **`authorize_booking` becomes span-aware** — takes `(start, end)`, internally checks every covered slot for room + contiguity, returns **one** `Decision`. One call per caller (no caller composes two answers).
2. **`resolve_slots` / `occupancy` count by overlap** — switch the overlay from exact-start-match to `[start, end)`. A 1-slot booking overlaps exactly its own slot ⇒ behavior-preserving for single-slot (net-proven, Rule 11).
3. **`authorize_edit_span`** — editing a length is the same capacity+contiguity decision over the changed span (O2 reaches it from the appointment actions).
4. **`booking.py` (plumbing) locks the whole span** — `FOR UPDATE` over all covered slots (ordered), asks the engine once, writes/updates one row, or rolls back (all-or-nothing). Engine decides; repo locks + persists (Rule 13).

**Nothing new decides anywhere else.** FE, routers, hooks, reads stay messengers.

### New engine surface (one place each)
- `assert_span(slots, *, settings) → Decision` — pure; contiguity (O5) + each covered slot within capacity (O1). Composed inside the gates; never called directly.
- New stable reason `run_not_contiguous`; capacity denials reuse `slot_full` (with `details`). No cap reason, no capacity-1 reason.

---

## 5. Backend design

### 5.1 Data model (one additive migration — O3)
- `Appointment` — no change (`start_datetime`/`end_datetime` exist, `models.py:105-106`).
- `AppointmentRequest` — add **nullable** `end_datetime` (single-slot leaves it null). Additive, no backfill. **⚠️ Alembic — flag in the PR; parity-gated before deploy.**
- No new tables, no `group_id`.

### 5.2 Engine (`scheduling/engine.py`) — the only decider
- `assert_span`; `authorize_booking` span-aware; `authorize_edit_span`; `occupancy`/overlay by overlap. The occupancy change is surfaced through the characterization net and, if red beyond the intended run case, **brought to the user and ruled** (Golden 2.1).

### 5.3 Repository (`scheduling/booking.py`) — locks + persists, never decides
- `reserve_slot` locks all covered slots, asks the engine, writes one `Appointment` (direct) or one `AppointmentRequest` with `end_datetime` (approval), else rolls back.
- **Edit length:** lock old∪new span, ask `authorize_edit_span`, update `end_datetime`. **Cancel:** existing `authorize_transition` frees the whole span via overlap occupancy (O6) — prove with a test.
- Approve/reject/cancel/resend of a run route through the existing transition table (both workflows).

### 5.4 Enforcement
- **Extend the CI bypass-guard** to span/contiguity/overlap shapes; `# sched-exempt:` otherwise; `test_guard_has_teeth`.
- **Sentinel header** on every touched file. **Temple-map** "Scheduling" tab regenerated + drift-guarded.

---

## 6. Frontend design

### 6.1 Behavior — reads the engine, decides nothing
The wizard **Time step** (`book-appointment-flow.tsx :SlotStep`) gains multi-select — **pure UX over engine-provided slot facts**:
- Pick a start slot (violet); immediate time-adjacent slots **with room** become "Add next" (violet ring); non-adjacent/occupied dim.
- Extend into a contiguous range (**no cap**) → chips merge into one violet block; summary `09:00–10:30 · 90 min · 3 slots`; Review → Time updates live.
- On **Confirm**, submit `{ start_datetime, end_datetime }`; the **engine decides** and returns a `Decision`; the FE **renders `Decision.reason`**. **No `state==='available' && adjacent`, no capacity math, no length check in a component.**
- **Edit length** (O2): the same selector opens pre-loaded at the current span, from the appointment's actions.

### 6.2 Design system + 6.3 Enforcement
Real tokens, real `SlotChip`, centered `DialogPopup`, both themes AA, i18n `t()`. Only new visuals ("Add next", merged block) from existing tokens; no side-stripes/gradients. **Extend the FE sentinel guard** to fail CI on any client-side scheduling decision. Playwright e2e is the FE gate.

---

## 7. API contract
- **Create:** `POST …/appointment-requests { patient_id, start_datetime, end_datetime?, chief_complaint? }` — absent/one-slot `end_datetime` = today's behavior; a span = a run.
- **Edit length (O2):** `PATCH …/appointments/{id} { end_datetime }`.
- **Cancel (O6):** existing endpoint; frees the whole span.
- **Denials:** `run_not_contiguous`, `slot_full` (with `details`), `slot_not_available` via `{ error: { code, message, details } }` → `t("apiErrors.<code>")`.
- **Reads:** slot shape unchanged; occupancy reflects overlap.

---

## 8. Change-locality proof

| Future change | ONE place — BE | ONE place — FE |
|---|---|---|
| Add a run-length cap later | one constant + one clause in `assert_span` | reads the cap; no logic |
| Occupancy/conflict rule | the engine resolver overlay | none |
| Restrict runs to empty/capacity-1 (reverse O1) | `assert_span` capacity clause | none |
| New denial reason | one reason const | none — renders `reason` |
| How a run looks | none | the slot-grid component |

If a contiguity check, a capacity comparison, or a "run valid?" decision appears in two files, the build is broken — the CI guards (§5.4, §6.3) catch it.

---

## 9. Testing
- **Table tests (Rule 10):** `assert_span` over `(length, contiguity, per-slot occupancy vs capacity)`; the gates over `(workflow, span, occupancy)`; golden reasons.
- **Characterization net (Rule 11):** pin today's exact-match occupancy; prove overlap == exact for **every single-slot case** before flipping; any other divergence surfaced + ruled.
- **Concurrency (Golden 10.4):** overlapping runs → each covered slot respects capacity, all-or-nothing; `FOR UPDATE`-over-all-slots exercised; edit-extend race.
- **E2E (Playwright, isolated stack):** run → confirm → one appointment `start→end`; run across a block refused (`run_not_contiguous`); run into a full slot refused (`slot_full`); edit-extend/shrink; cancel-whole-run; single-slot unchanged; light/dark; inject-bug proof.

---

## 10. Risks & mitigations
- **R1 — Overlap changes a read.** Net proves single-slot identical first.
- **R2 — Concurrency on a shared/covered slot.** All covered slots locked `FOR UPDATE` in one tx; engine re-checks under lock; all-or-nothing.
- **R3 — Approval run held while pending.** Occupancy counts pending over the span; expiry frees it.
- **R4 — Migration.** Additive nullable, no backfill; flagged; parity-gated.
- **R5 — Unbounded run length.** Accepted per ruling; a cap is a one-place add later (§8).

---

## 11. Success criteria
- A contiguous run creates **one** appointment `start→end`; every covered slot honors capacity; no slot can be booked past capacity (proven under concurrency).
- Every multi-slot **decision** is in exactly one engine function; the extended bypass-guard is green and has teeth; no scheduling decision in the FE.
- Single-slot booking byte-for-byte unchanged (net green).
- Edit-length + cancel-whole-run work in both workflows.
- BE ships first, additive, deployable ahead of the FE wing.
