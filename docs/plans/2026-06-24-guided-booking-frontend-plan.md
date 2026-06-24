# Guided Appointment Booking — Frontend Plan (#59)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Replace the single booking dialog with one shared, guided `BookAppointmentFlow` sheet — reached from 3 doors, pre-filled by context, gated by a plain-language confirmation preview — plus inline quick-add and the patient-incomplete cues.

**Architecture:** A `BookAppointmentFlow` sheet over a small step state machine (Patient · Doctor · Slot · Reason · Review) with a checklist; pre-filled steps render ✓. Reuses the existing scheduling/patients data layer (`create_request`, patient search/create + duplicate-check, `useSlots`). A reusable `ConfirmationPreview` is the Review gate. A pure `isPatientComplete` helper powers a !-badge + banner. **No backend.**

**Tech Stack:** Next.js (App Router), React + TS, TanStack Query, react-i18next, Tailwind v4 semantic tokens, base-ui `sheet`/`Dialog`, Vitest + RTL, Playwright. Spec: `docs/specs/2026-06-24-guided-booking-design.md`. Mockups (directional) on #59.

## Global Constraints
- **Frontend-only — no backend / no migration.** Reuse `useCreateRequest` (`createRequest({patient_id,start_datetime,chief_complaint?,notes?})`), `usePatientSearch`, patient `create` + `duplicate-check`, `useSlots(clinicId,doctorId,from,to)`, the doctors list, `useClinic` (`scheduling_workflow`), `useSuccess`.
- **Plain language, never field codes**; **Reason optional** (never block on it); **Submit gated** until Patient + Doctor + Slot set.
- **Rule 17.0:** semantic tokens; compose `components/ui/*`; no per-page CSS/raw colours. Both themes; mobile-first (sheet full-screen on mobile); WCAG AA (badge/state by icon+text, ≥44px).
- **i18n-first:** all copy via `t()` under `booking.*` / `patient.incomplete.*`; add to BOTH `en.json`+`hi.json` (parity gated by `tests/e2e/i18n.spec.ts`); friendly date/time via `Intl`.
- `npx tsc --noEmit` + `npm run build` clean before each commit. Dev FE on 3000. **Render-on-:8753 sign-off before building UI. FE PR HELD for user QA.**

---

### Task 1: `isPatientComplete` helper (pure)

**Files:** Create `src/features/patients/patient-completeness.ts`; Test `src/features/patients/__tests__/patient-completeness.test.ts`.

**Interfaces:**
- Produces: `isPatientComplete(p): boolean` and `patientMissingFields(p): string[]`. **Complete = name + phone AND (age or date_of_birth) AND gender.**

- [ ] **Step 1: Write the failing test**

```ts
// src/features/patients/__tests__/patient-completeness.test.ts
import { describe, it, expect } from "vitest";
import { isPatientComplete, patientMissingFields } from "../patient-completeness";

const base = { id: "1", name: "Riya", phone: "+919800000000", age: 30, date_of_birth: null, gender: "female" };

describe("patient completeness", () => {
  it("complete when name+phone+age+gender present", () => {
    expect(isPatientComplete(base as never)).toBe(true);
    expect(patientMissingFields(base as never)).toEqual([]);
  });
  it("quick-add (name+phone only) is incomplete", () => {
    const p = { ...base, age: null, date_of_birth: null, gender: null };
    expect(isPatientComplete(p as never)).toBe(false);
    expect(patientMissingFields(p as never)).toEqual(["age", "gender"]);
  });
  it("date_of_birth satisfies the age requirement", () => {
    const p = { ...base, age: null, date_of_birth: "1990-01-01" };
    expect(isPatientComplete(p as never)).toBe(true);
  });
});
```

- [ ] **Step 2: Run → fail.** `npx vitest run src/features/patients/__tests__/patient-completeness.test.ts` → module not found.

- [ ] **Step 3: Implement**

```ts
// src/features/patients/patient-completeness.ts
export type PatientLike = {
  name?: string | null; phone?: string | null;
  age?: number | null; date_of_birth?: string | null; gender?: string | null;
};
export function patientMissingFields(p: PatientLike): string[] {
  const missing: string[] = [];
  if (!p.name) missing.push("name");
  if (!p.phone) missing.push("phone");
  if (p.age == null && !p.date_of_birth) missing.push("age");
  if (!p.gender) missing.push("gender");
  return missing;
}
export function isPatientComplete(p: PatientLike): boolean {
  return patientMissingFields(p).length === 0;
}
```

> NOTE: confirm `PatientRead` field names (`age` vs `date_of_birth`, `gender`) and align `PatientLike`. If only `date_of_birth` exists, drop `age`.

- [ ] **Step 4: Run → pass.** **Step 5: Commit** `feat(patients): patient-completeness helper (#59)`.

---

### Task 2: i18n keys (en + hi parity)

**Files:** Modify `src/i18n/locales/en.json` + `hi.json`.

- [ ] **Step 1: Add to en.json (then mirror in hi.json):**

```json
"booking": {
  "title": "Book appointment",
  "steps": { "patient": "Patient", "doctor": "Doctor", "slot": "Time", "reason": "Reason", "review": "Review" },
  "missing": { "patient": "Choose a patient", "slot": "Pick a time", "doctor": "Choose a doctor" },
  "patientSearch": "Search patients by name or phone",
  "newPatient": "New patient", "newPatientName": "Full name", "newPatientPhone": "Phone",
  "newPatientNote": "Please complete this patient's full details later in the Patients page.",
  "duplicateWarn": "A similar patient may already exist:",
  "reasonLabel": "Reason for visit (optional)", "notesLabel": "Notes (optional)",
  "next": "Next", "back": "Back", "edit": "Edit", "confirm": "Confirm",
  "review": { "patient": "Patient", "doctor": "Doctor", "when": "Date & time", "reason": "Reason", "none": "—" },
  "success": { "confirmed": "Appointment confirmed for {{patient}} with {{doctor}}, {{when}}.", "requested": "Request sent for approval." },
  "slotFull": "That time just filled up — please pick another."
},
"patient": { "incomplete": { "badge": "Details incomplete", "banner": "Please complete patient details." } }
```

- [ ] **Step 2:** Mirror in `hi.json`. **Step 3:** `npx playwright test tests/e2e/i18n.spec.ts` → PASS; commit `i18n(booking): guided booking + incomplete-patient strings en+hi (#59)`.

---

### Task 3: Patient-incomplete cues (!-badge + banner)

**Files:** Modify the Patients list row component (`src/features/patients/*` list/table) + `src/features/patients/patient-detail.tsx`; Test `src/features/patients/__tests__/incomplete-cues.test.tsx`.

**Interfaces:** Consumes `isPatientComplete` (Task 1).

- [ ] **Step 1: Write the failing test**

```tsx
// renders a "!" badge (testid patient-incomplete-badge) on a list row for an incomplete patient,
// and the yellow banner (testid patient-incomplete-banner) on patient-detail. Complete patient: neither.
```

- [ ] **Step 2–4:** In the Patients list row: when `!isPatientComplete(p)`, render a small inline **!** badge with `t("patient.incomplete.badge")` (icon + accessible text, semantic warning token, not colour-only), `data-testid="patient-incomplete-badge"`. In `patient-detail.tsx`: when incomplete, render a warning **banner** at top (`bg`/`text` warning tokens) `t("patient.incomplete.banner")` with a link/button to the edit form, `data-testid="patient-incomplete-banner"`. Build per spec §6.

- [ ] **Step 5: Commit** `feat(patients): incomplete-patient badge + banner (#59)`.

---

### Task 4: `ConfirmationPreview` component (reusable; booking instance)

**Files:** Create `src/components/confirmation-preview.tsx`; Test `src/components/__tests__/confirmation-preview.test.tsx`.

**Interfaces:**
- Produces: `ConfirmationPreview({ rows: { labelKey: string; value: string }[]; onBack: () => void; onConfirm: () => void; confirmLabelKey?: string; pending?: boolean })` — renders a readable summary card + Back/Edit + Confirm.

- [ ] **Step 1: Write the failing test**

```tsx
// renders each row label+value; Back calls onBack; Confirm calls onConfirm; disabled while pending.
```

- [ ] **Step 2–4:** Implement a design-system card listing `rows` (label via `t(labelKey)`, plain `value`), a secondary **Back** (`onBack`) and primary **Confirm** (`onConfirm`, disabled when `pending`). Generic so #60 can reuse it for cancel/reschedule/send. testids `confirmation-preview`, `confirm-back`, `confirm-submit`.

- [ ] **Step 5: Commit** `feat(ui): reusable ConfirmationPreview card (#59, #60)`.

---

### Task 5: `BookAppointmentFlow` sheet + steps + checklist

**Files:** Create `src/features/scheduling/book-appointment-flow.tsx` + step sections `booking-patient-step.tsx`, `booking-doctor-step.tsx`, `booking-slot-step.tsx`, `booking-reason-step.tsx`; Test `src/features/scheduling/__tests__/book-appointment-flow.test.tsx`.

**Interfaces:**
- Consumes: `usePatientSearch`, patient `create` + `duplicate-check`, doctors list (`useDoctors`), `useSlots`, `useCreateRequest`, `useClinic` (`scheduling_workflow`), `useSuccess`, `ConfirmationPreview` (Task 4), `isPatientComplete`.
- Produces: `BookAppointmentFlow({ clinicId; initial: { patientId?; patientName?; doctorId?; startDatetime?; label? }; open; onOpenChange })`.

- [ ] **Step 1: Write the failing test**

```tsx
// Pre-fill from a slot: render with initial={doctorId, startDatetime}; Doctor + Time show ✓; the
// active step is Patient. Submit is disabled until a patient is chosen. Choosing a patient enables
// the flow toward Review. (Mock the hooks.)
```

- [ ] **Step 2–4:** Implement:
  - **State:** `{ patientId, patientName, doctorId, startDatetime, label, reason, notes }` seeded from `initial`; a `step` cursor.
  - **Checklist** header: 5 items (`booking.steps.*`) each rendering ✓ (done/pre-filled), active, or pending; clicking a done step re-opens it.
  - **Patient step** (`booking-patient-step.tsx`): search (`usePatientSearch`) + a **"+ New patient"** → minimal add (name + phone) that first calls **duplicate-check** (show `booking.duplicateWarn` + the match to pick instead) then `create`; on select sets `patientId`/`patientName`. Carry the circled-i `booking.newPatientNote`.
  - **Doctor step** (`booking-doctor-step.tsx`): list clinic doctors; **auto-skip** (mark ✓) when exactly one doctor or `initial.doctorId` set.
  - **Slot step** (`booking-slot-step.tsx`): a date picker → `useSlots(clinicId, doctorId, date, date)` → choose a slot (sets `startDatetime`/`label`); pre-filled from `initial.startDatetime`.
  - **Reason step** (`booking-reason-step.tsx`): optional `reason` + `notes` inputs.
  - **Review:** render `ConfirmationPreview` with rows Patient/Doctor/Date-time/Reason (friendly `Intl` time; `booking.review.none` when blank); **Confirm** → `useCreateRequest(clinicId, doctorId).mutate({ patient_id, start_datetime, chief_complaint: reason || undefined, notes: notes || undefined })`. On success: `useSuccess` card — confirmed (`res.status==="approved" || res.created_appointment_id`) → `booking.success.confirmed`, else `booking.success.requested`; close. On `slot_full` → `booking.slotFull`, return to Slot step.
  - **Gating:** primary action disabled until `patientId && doctorId && startDatetime`; missing items surfaced via `booking.missing.*`.
  - Compose `Sheet` (full-screen mobile) + design-system components; testids `book-appointment-flow`, `booking-step-{patient,doctor,slot,reason,review}`, `booking-new-patient`, `booking-confirm`.

- [ ] **Step 5: Commit** `feat(scheduling): guided BookAppointmentFlow sheet + steps (#59)`.

---

### Task 6: Wire the 3 doors, retire `request-dialog`, e2e

**Files:** Modify the slot triggers (`src/features/scheduling/slots-preview-card.tsx` from #129 / `slot-viewer` legacy), `src/features/patients/patient-detail.tsx`, the Requests page header (`src/app/requests/page.tsx`); Remove `src/features/scheduling/request-dialog.tsx`; Test `tests/e2e/booking.spec.ts`.

- [ ] **Step 1:** Replace the slot chip's `RequestDialog` trigger with one that opens `BookAppointmentFlow` `initial={{ doctorId, startDatetime, label }}`. On `patient-detail`, add a primary **"Book appointment"** → `initial={{ patientId, patientName }}`. On the **Requests** page header, add a **"Book appointment"** button → `initial={{}}`. Delete `request-dialog.tsx` and its references.
- [ ] **Step 2:** e2e `tests/e2e/booking.spec.ts` (mock scheduling/patients/clinic): (a) book from a slot, Direct mode → "Appointment confirmed" success; (b) book standalone with **quick-add new patient** (incl. the duplicate-check path) → success, and the new patient then shows the **!** badge + the patient screen shows the yellow banner; (c) a Doctor-Approval clinic → "Request sent".
- [ ] **Step 3:** `npx tsc --noEmit && npm run build && npm run test:e2e -- booking`.
- [ ] **Step 4: Render on :8753 for sign-off** — the sheet from each door, quick-add, Review/confirm, both success states, the badge + banner (light/dark/mobile). **User sign-off before done.**
- [ ] **Step 5: Commit** `feat(scheduling): wire booking doors + retire request-dialog (#59)`.

---

## Self-Review (plan vs spec)
- One shared flow, 3 doors, pre-fill, sheet → Task 5 + Task 6. ✅
- Single guided screen + checklist; auto-skip doctor; reason optional; gated submit, plain-English missing → Task 5. ✅
- Inline quick-add (name+phone, dup-check, i-note) → Task 5 (patient step). ✅
- Incomplete-patient slice of #63 (deterministic helper + badge + banner) → Tasks 1, 3. ✅
- Review = reusable ConfirmationPreview; Direct/Approval outcome + success card → Tasks 4, 5. ✅
- Frontend-only; reuses existing endpoints → Global Constraints. ✅
- i18n/Rule 17.0/themes/a11y/render-before-build/FE-held → Global Constraints + Tasks 2, 6. ✅
- Placeholder scan: pure logic fully coded; UI tasks give contracts + key tests + cite spec; one verify-NOTE (patient field names). ✅
- Type consistency: `isPatientComplete`/`PatientLike`/`ConfirmationPreview` props/`BookAppointmentFlow` props consistent across tasks. ✅

## README
Update `dentist-registry-frontend/README.md` (the guided booking flow) within the FE PR.
