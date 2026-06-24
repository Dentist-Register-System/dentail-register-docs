# Appointment Day-of Lifecycle — Frontend Plan (#139)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Let owner/assistant/doctor run the day from any appointment row — mark arrived / no-show / completed / cancel (+ undos) — gated by status + authz, with #60 preview → success card, and visible status badges.

**Architecture:** A pure `nextActions(status, viewer)` helper drives an `<AppointmentActions>` menu on appointment rows; meaningful actions route through the reusable `ConfirmationPreview` (#59/#60) then a success card; a `useAppointmentAction` hook calls the lifecycle endpoints and invalidates the right queries.

**Tech Stack:** Next.js App Router, React+TS, TanStack Query, react-i18next, Tailwind tokens, Vitest+RTL, Playwright. Spec: `docs/specs/2026-06-24-appointment-day-of-lifecycle-design.md`. Depends on backend #139 endpoints + the #59 `ConfirmationPreview` + `useSuccess`.

## Global Constraints
- **Rule 17.0** semantic tokens; compose `components/ui/*`; no per-page CSS. Both themes; mobile-first; WCAG AA (status by **icon+text**, not colour). i18n en+hi parity (gated). Plain language, never field codes.
- `npx tsc --noEmit` + `npm run build` clean per commit. **Render-on-:8753 sign-off before building. FE PR HELD for user QA.**

---

### Task 1: api + hook + `nextActions` helper

**Files:** Modify `src/features/scheduling/api.ts`, `hooks.ts`; Create `src/features/scheduling/appointment-actions.ts`; Test `__tests__/appointment-actions.test.ts`.

**Interfaces:**
- `appointmentAction(clinicId, apptId, action, body?)` → POST `/clinics/{c}/appointments/{a}/{action}`; `editCompletionNotes(clinicId, apptId, notes)` → PATCH.
- `useAppointmentAction(clinicId)` (mutation; invalidates `["appointments",...]`, `["slots",...]`, `["home-summary",...]`, `["patients",...]`).
- `nextActions(status, viewer: { role; isOwnAppt: boolean }): Action[]` where `Action ∈ "arrive"|"undo-arrival"|"no-show"|"undo-no-show"|"complete"|"cancel"|"edit-notes"`.

- [ ] **Step 1: Write the failing test**

```ts
import { nextActions } from "../appointment-actions";
it("confirmed → arrive/complete/no-show/cancel for owner", () => {
  expect(new Set(nextActions("confirmed", { role: "owner", isOwnAppt: false })))
    .toEqual(new Set(["arrive", "complete", "no-show", "cancel"]));
});
it("doctor on their own confirmed appt cannot cancel (→ #141)", () => {
  expect(nextActions("confirmed", { role: "doctor", isOwnAppt: true })).not.toContain("cancel");
});
it("doctor on another doctor's appt gets no actions", () => {
  expect(nextActions("confirmed", { role: "doctor", isOwnAppt: false })).toEqual([]);
});
it("arrived → complete/undo-arrival; completed → edit-notes; no_show → undo", () => {
  expect(new Set(nextActions("arrived", { role: "assistant", isOwnAppt: false }))).toEqual(new Set(["complete","undo-arrival"]));
  expect(nextActions("completed", { role: "assistant", isOwnAppt: false })).toEqual(["edit-notes"]);
  expect(nextActions("no_show", { role: "assistant", isOwnAppt: false })).toEqual(["undo-no-show"]);
});
```

- [ ] **Step 2–4:** Implement `nextActions` (status → base actions; filter by authz: owner/assistant→all run-day; doctor→only own, and **never cancel**; non-own doctor→none) + the api fns + hook.
- [ ] **Step 5: Commit** `feat(scheduling): appointment action api/hook + nextActions (#139)`.

---

### Task 2: i18n (en + hi)

- [ ] Add `appointment.lifecycle.*`: action labels (`arrive`/`undoArrival`/`noShow`/`undoNoShow`/`complete`/`cancel`/`editNotes`), prompts (`noShowReason`, `cancelReason`, `completionNotes` "optional", `notifyPatient`), status badges (`confirmed`/`arrived`/`completed`/`noShow`/`cancelled`), success copy. Mirror in hi.json; run i18n parity test. Commit `i18n(scheduling): appointment lifecycle strings en+hi (#139)`.

---

### Task 3: `<AppointmentStatusBadge>` + `<AppointmentActions>`

**Files:** Create `src/features/scheduling/appointment-status-badge.tsx`, `appointment-actions.tsx`; Test `__tests__/appointment-actions.test.tsx`.

**Interfaces:** `<AppointmentStatusBadge status />`; `<AppointmentActions appointment viewer onActioned />`.

- [ ] **Step 1:** Test: a confirmed appt for an owner renders an actions menu containing Arrived/Complete/No-show/Cancel; a completed appt shows the Completed badge + "Edit notes"; a non-own doctor sees no actions.
- [ ] **Step 2–4:** `AppointmentStatusBadge` — icon+text per status (semantic tokens; success/warning/destructive/muted), testid `appt-status-{status}`. `AppointmentActions` — render `nextActions(...)` as a menu/buttons (reuse the `dropdown-menu` primitive); **arrive / undo / undo-no-show** call the hook directly (one-tap) with a light success; **no-show / complete / cancel** open the flow in Task 4. testids `appt-action-{action}`.
- [ ] **Step 5: Commit** `feat(scheduling): appointment status badge + actions menu (#139)`.

---

### Task 4: Confirmation preview + success for no-show / complete / cancel

**Files:** Create `src/features/scheduling/appointment-action-dialog.tsx`; Test `__tests__/appointment-action-dialog.test.tsx`.

**Interfaces:** Consumes `ConfirmationPreview` (#59), `useAppointmentAction`, `useSuccess`.

- [ ] **Step 1:** Test: the **cancel** dialog requires a reason (submit disabled until entered), shows a **notify-patient** checkbox (default on) and a `ConfirmationPreview` (patient/doctor/time/reason); confirming calls the hook with `{reason, notify}` and shows a success card. No-show requires reason; complete allows empty notes.
- [ ] **Step 2–4:** Implement a single `<AppointmentActionDialog action appointment>`:
  - **no-show:** reason (required) + optional note → preview → confirm.
  - **complete:** optional notes (never blocks) → preview → confirm.
  - **cancel:** reason (required) + **notify-patient** checkbox (default on; copy notes send is not active yet) → preview → confirm.
  - Confirm → `useAppointmentAction.mutate`; on success `useSuccess` card (e.g. "Appointment cancelled", "Marked complete"); on `ConflictError` (stale) → a plain "this changed — refresh" message. testids `appt-dialog`, `appt-dialog-confirm`, `appt-notify`.
- [ ] **Step 5: Commit** `feat(scheduling): appointment no-show/complete/cancel dialogs + success (#139)`.

---

### Task 5: Wire into Today's Schedule / schedule / patient + e2e

**Files:** Modify `src/features/home/todays-schedule-card.tsx` (#62), the schedule appointment rows, `src/features/patients/patient-detail.tsx` appointments; Test `tests/e2e/appointment-lifecycle.spec.ts`.

- [ ] **Step 1:** Render `<AppointmentStatusBadge>` + `<AppointmentActions>` on appointment rows in all three surfaces, passing `viewer = { role: me.role, isOwnAppt: appt.doctor_id === me.doctor_id }`.
- [ ] **Step 2:** e2e (mock endpoints): owner marks a confirmed appt **Arrived → Complete** (badges update); owner **Cancels** with reason → success, and the freed slot becomes bookable again; **No-show** requires a reason; a **non-owner doctor** sees Arrive/Complete on their own appt but **no Cancel**; completion with empty notes succeeds.
- [ ] **Step 3:** `npx tsc --noEmit && npm run build && npm run test:e2e -- appointment-lifecycle`.
- [ ] **Step 4: Render on :8753 for sign-off** — the actions menu, each dialog, success cards, all status badges (light/dark/mobile). **User sign-off before done.**
- [ ] **Step 5: Commit** `feat(scheduling): wire appointment lifecycle into schedule/home/patient (#139)`.

---

## Self-Review (vs spec)
- Row actions gated by status + authz (doctor own, no cancel); arrival one-tap; no-show/complete/cancel via #60 preview + success; badges → Tasks 1,3,4,5. ✅
- Cancel notify-patient checkbox (send stubbed); reasons required; completion never blocks → Task 4. ✅
- Wired into Today's Schedule/#62 + schedule + patient → Task 5. ✅
- i18n/Rule 17.0/themes/a11y/render-before-build/FE-held → Global + Tasks 2,5. ✅
- Type consistency: `nextActions`/`Action`/`useAppointmentAction`/dialog props consistent across tasks. ✅

## README
Update `dentist-registry-frontend/README.md` (appointment lifecycle actions) in the FE PR.
