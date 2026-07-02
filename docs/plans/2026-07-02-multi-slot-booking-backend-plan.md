# Multi-Slot Booking — Backend Plan

**Date:** 2026-07-02
**Design:** `docs/specs/2026-07-02-multi-slot-booking-design.md`
**Wing:** Backend — ships **first** (Golden Rule 19). Frontend plan follows.
**Doctrine:** Sentinel Rules 1/3/5/6/9/10/11/13 · Golden §5–6, §13, §19. Every PR: small, green, behavior-preserving; Sentinel header on every touched file; non-trivial logic leaves a runnable check.
**Model (ruled):** uniform capacity rule — any booking (single or run) allowed iff every covered slot stays within `capacity(settings)`, occupancy counted by overlap. No exclusivity, no length cap. Both workflows. Edit-length + cancel in scope.

## Guardrails (every PR)
- No scheduling **decision** leaves `scheduling/engine.py`. Callers make **one** engine call and read the `Decision`.
- The repo (`booking.py`) locks + persists; never decides (Rule 13).
- Characterization net green against **old** code before any resolver change (Rule 11).
- Alembic migration flagged prominently; parity-gated before deploy.

---

## PR 1 — Characterization net for occupancy (no production change)
- `tests/scheduling/characterization/test_occupancy_overlap.py`: pin **today's** exact-start-match occupancy over a grid of `(appointments/requests, slots, capacity)`, including cases that *will* change under overlap (recorded as the current answer).
- Assert the safety invariant: **for every single-slot booking, exact-match == overlap.**
- **Acceptance:** green against current `service.py:336-367`; no app code changed.

## PR 2 — Migration: `AppointmentRequest.end_datetime` (additive, nullable)
- Alembic revision adds `end_datetime timestamp NULL` to `appointment_request_beta`; update `models.py`. No backfill.
- **⚠️ MIGRATION — flag in PR body.** Additive/backward-compatible with the live single-slot FE.
- **Acceptance:** upgrade+downgrade clean on the isolated DB; existing tests green; no behavior change.

## PR 3 — Engine: span validation + overlap occupancy (logic only, table-tested)
- `engine.py`: `assert_span(slots, *, settings) → Decision` — contiguity (A4) + each covered slot within `capacity(settings)`. Reason `run_not_contiguous`; capacity denial reuses `slot_full` (with `details`).
- Change `occupancy`/resolver overlay to `[start, end)` overlap counting.
- Extend `authorize_booking` to accept the span and compose internally (permission unchanged) → one `Decision`.
- **Table tests (Rule 10):** `(length, contiguity, per-slot occupancy vs capacity, workflow)` grid; assert `allowed → reason is None`, `denied → reason ∈ REASONS`.
- **Acceptance:** engine tests green; PR 1 net re-run against the new overlay is **green for all single-slot cases**; any other divergence surfaced + ruled before merge. No call sites flipped yet.

## PR 4 — Repository: atomic span reserve + one spanning row
- `booking.py reserve_slot`: `SELECT … FOR UPDATE` over all covered slots (ordered by start); ask `authorize_booking` once; write **one** `Appointment` (direct) or **one** `AppointmentRequest` with `end_datetime` (approval); deny → roll back whole tx (all-or-nothing).
- Flip the create call site to the engine gate.
- **Concurrency tests (Golden 10.4):** two overlapping runs → each covered slot respects capacity, exactly one wins where capacity would be exceeded; run vs single overlap; approve-time re-check under lock.
- **Acceptance:** net green; concurrency tests green; single-slot path unchanged.

## PR 5 — Edit length + flip occupancy/lifecycle to the engine
- `authorize_edit_span` in the engine; `booking.py` locks old∪new span, updates `end_datetime` (extend needs room on the delta; shrink always allowed). Cancel already frees the whole span via the existing transition — add a test proving it.
- Route the slot-list/diary occupancy overlay + approve/reject/cancel/resend through the overlap-aware engine.
- This is the **behavior-change** PR (covered slots now count). Surface the characterization collision, get the ruling, ship labelled (Golden 2.1).
- **Acceptance:** edit-extend/shrink + cancel-whole-run green in both workflows; diary + booking share the one resolver.

## PR 6 — CI bypass-guard + API surface
- Extend `tests/scheduling/test_no_bypass.py` to span/contiguity/overlap shapes; `# sched-exempt:` markers on identity facts; `test_guard_has_teeth`.
- Router: accept `end_datetime` on create; add `PATCH …/appointments/{id}` for edit-length; uniform error envelope reasons.
- Temple-map "Scheduling" tab regenerated + drift-guarded.
- **Acceptance:** guard green with teeth; API contract (design §7) satisfied; temple drift test green; backend deployable ahead of FE.

---

## Deploy note
Backend-only, additive. Migration applied to beta (controller-only) **before** the BE deploy (parity gate). After merge: BE deploy → verify `/health` + a run booking + an edit-length via API against beta → only then the FE wing.
