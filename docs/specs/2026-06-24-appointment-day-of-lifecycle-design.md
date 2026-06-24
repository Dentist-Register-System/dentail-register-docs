# Appointment Day-of Lifecycle — arrival · no-show · completion · cancel — Design Spec (#139)

**Status:** Approved in brainstorm (2026-06-24). Issue **#139** (Critical, pre-launch; Slice A of the appointment lifecycle, sub of epic #9). **Backend + frontend, with a migration.** Per `Workflows/18,19,20` + the direct-cancel path of `12`, and Golden Rules §5–§7. Register Design System, i18n-first.

**Type:** Add the day-of operational transitions on a **confirmed** appointment so a clinic can run a day: mark **arrived / no-show / completed**, undo arrival/no-show, and **directly cancel** (releasing capacity).

---

## 1. Goal
Booking puts a patient on the schedule; this lets the clinic *operate the day*. Today an appointment only reaches `confirmed` with no further transitions — a hard blocker for any real test.

## 2. Scope decisions (locked in brainstorm 2026-06-24)
- **Transitions:** `confirmed → arrived` (undo → confirmed); `confirmed/arrived → completed` (editable after, with audit); `confirmed → no_show` (undo → confirmed); `confirmed → cancelled` (releases capacity).
- **Completion = optional free-text notes** — `completed_by`/`completed_at` + nullable `completion_notes`; **never blocked** (Golden Rule 5.8); records editable later with audit.
- **No-show:** `no_show_reason` **required** (free-text V1; presets deferred), optional note; undoable.
- **Undo → `confirmed`** only in V1 (Golden Rule 5.9's "choose another target" deferred).
- **Direct cancel:** `cancel_reason` **required**, optional note; **notify-patient** checkbox (send **stubbed** — SP5 hooks); **releases slot capacity**.
- **Authz:** arrival/no-show/completion → **owner + assistant (any appointment); doctor (own)**. **Direct cancel → owner + assistant only** (a non-owner doctor's cancel is the **#141** two-step — deferred).
- **Every transition:** validates current state (§6.1), **first-committed-transition-wins** via row lock (§6.2), **idempotent** (§6.4), **audited** with actor+timestamp (§7), incl. undos.
- **Out of scope:** reschedule (#140), doctor-requested "Cancellation Requested" two-step (#141), WhatsApp/Calendar sends (SP5 stubbed), retroactive creation, treatment templates.

## 3. Data model — migration (new columns on `appointment_beta`; `status` stays free `String(20)`)
Add (all nullable): `arrived_at TIMESTAMP`, `no_show_reason TEXT`, `no_show_at TIMESTAMP`, `completed_by UUID`, `completed_at TIMESTAMP`, `completion_notes TEXT`, `cancel_reason TEXT`, `cancelled_at TIMESTAMP`, `cancelled_by UUID`. New `status` values used: `arrived`, `completed`, `no_show`, `cancelled` (no enum migration — status is a string). Migration applied to Supabase by the controller; implementers validate on local PG :5433.

## 4. Capacity correctness (MUST — prevents silent overbooking)
**`count_consumers` (booking.py:81) currently counts appointments with `status == "confirmed"` only.** Once `arrived`/`completed`/`no_show` exist, those would stop counting → the slot would appear free → **overbooking**. Fix: a slot is consumed by an appointment in **any non-releasing status**:
```python
Appointment.status.in_(("confirmed", "arrived", "completed", "no_show"))   # occupies the slot
```
Only **`cancelled`** (and later `rescheduled`, #140) **release** capacity. So: arrival/no-show/completion **do not** change capacity; **cancel does** (the appointment drops out of `count_consumers`, freeing the slot for rebooking). Add a regression test asserting that marking arrived/completed/no-show does **not** free capacity, and cancel **does**.

## 5. State machine + transition rules
- Allowed: `confirmed→arrived`, `arrived→confirmed` (undo), `confirmed→completed`, `arrived→completed`, `completed` edit-notes (stays completed), `confirmed→no_show`, `no_show→confirmed` (undo), `confirmed→cancelled`.
- Each transition: **lock the appointment row** (`SELECT … FOR UPDATE`, mirroring `_get_request_locked`), re-read status, **reject if not in an allowed source state** (`ConflictError` "no longer in a state that allows this action") → first-committed-transition-wins. **Idempotent**: re-issuing the same terminal transition that already holds is a no-op success (or 409 — pick 409 for cancel/complete to surface stale UI; arrival/no-show idempotent no-op). Record the relevant `appointment.{arrived,arrival_undone,no_show,no_show_undone,completed,completion_edited,cancelled}` **audit** event (actor, timestamp, reason/notes where applicable, old→new status).

## 6. Backend
- **Service** (`scheduling/booking.py` or a new `lifecycle.py` in the module): `mark_arrived`, `undo_arrival`, `mark_no_show(reason)`, `undo_no_show`, `complete(notes?)`, `edit_completion(notes)`, `cancel_appointment(reason, notify)`. Each: lock row → validate state → mutate + set the timestamp/actor/reason fields → audit → commit. `cancel_appointment` additionally frees capacity by virtue of §4 (status→cancelled; no manual slot bookkeeping needed since `count_consumers` excludes cancelled). `notify` is recorded but **not sent** (SP5 stub).
- **Authz** (`scheduling/router.py`): a `authorize_run_day(membership, appointment)` = owner/assistant any, doctor iff `appointment.doctor.linked_user_id == membership.user_id`; **cancel** uses `authorize_cancel` = owner/assistant only (non-owner doctor → 403 with a code pointing at #141 later).
- **Endpoints:** `POST /clinics/{id}/appointments/{appt_id}/{arrive|undo-arrival|no-show|undo-no-show|complete|cancel}` (+ `PATCH …/{appt_id}/completion-notes`). Bodies: no-show `{reason, note?}`, complete `{notes?}`, cancel `{reason, note?, notify?}`. Thin routers.
- **Tests:** each transition happy path + invalid-source rejection; undo paths; completion never blocked (empty notes ok); **§4 capacity regression** (arrived/completed/no-show keep capacity; cancel frees it, slot rebookable); **concurrency** (cancel-vs-complete, arrive-vs-cancel → first-wins); authz matrix (doctor own vs others; doctor cancel → 403); audit rows written for every transition.

## 7. Frontend
- **Actions on appointment rows** — Today's Schedule (#62 Home), the schedule views, and the patient's appointments. An appointment row exposes the **valid next actions** for its status (confirmed → Arrived / Complete / No-show / Cancel; arrived → Complete / Undo arrival; no_show → Undo; completed → Edit notes), gated by the viewer's authz.
- **#60 confirmation preview** for **no-show** (reason), **complete** (optional notes), **cancel** (reason + notify-patient checkbox) → **success card**. **Arrival** is one-tap (low-stakes, undoable) — a light success toast/card, no preview.
- **Status badges** always visible (Golden Rule 12.1): Confirmed / Arrived / Completed / No Show / Cancelled.
- New api + hooks (`useAppointmentAction(clinicId)`), invalidating appointments/slots/home-summary queries.

## 8. Cross-cutting
- **i18n** en+hi for all copy (`appointment.lifecycle.*`, action labels, reason prompts, status badges) — gated; plain language, never field codes.
- **Rule 17.0** (semantic tokens, compose `components/ui/*`, no per-page CSS); both themes; mobile-first; WCAG AA (status by icon+text). **Render-on-:8753 sign-off; FE held for QA; backend merges on green; migration controller-applied.**

## 9. Scope guards / deferred
- Reschedule → **#140**; doctor-requested cancellation two-step → **#141**; WhatsApp/Calendar sends (SP5 stubbed); retroactive creation; treatment templates; undo-to-chosen-target; no-show reason presets.

## 10. Self-review
- Arrival/no-show/completion/cancel transitions, undos, authz, audit, first-wins: §2/§5/§6. ✅
- Completion = optional free-text, never blocked; editable after: §2/§6. ✅
- **Capacity: cancel releases, others don't — `count_consumers` updated (overbooking guard)**: §4. ✅
- Direct cancel owner/assistant; non-owner-doctor → #141: §2/§6. ✅
- FE actions + #60 preview + success + badges: §7. ✅
- Migration (nullable cols, string status), no enum migration: §3. ✅
- Deferred items tracked (#140/#141): §9. ✅
- Placeholder scan: concrete fields/endpoints/capacity-fix/tests; verify-NOTEs implicit (match existing lock helper / model). ✅
