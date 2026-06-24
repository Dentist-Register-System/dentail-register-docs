# Guided Appointment Booking — Design Spec (#59)

**Status:** Approved in brainstorm (2026-06-24). Issue **#59** (Critical, pre-launch). Builds on SP3.2 booking + **#87** (Direct vs Approval) + **#50** guided pattern. **Frontend-only — no backend.** Delivers the booking instance of **#60** (ConfirmationPreview) and the patient slice of **#63** (incomplete detection). Register Design System (Rule 17.0), i18n-first. Directional mockups to follow (dev fine-tunes at render-on-:8753 sign-off).

**Type:** Replace the single dense booking dialog with **one shared, guided booking flow** — a checklist that's fast for repeat use, pre-fills by entry point, and gates submission behind a plain-language confirmation preview.

---

## 1. Goal

*"Reception or an owner-doctor books an appointment in seconds, from wherever they are, never misses a required step, and always sees a plain 'is this right?' before it's committed."* Booking is a high-frequency action, so guided must not mean slow.

Today's `request-dialog.tsx` is a single slot-first dialog (search patient → complaint/notes → submit) — the "giant form" this replaces. The backend already does the right thing (`create_request` auto-confirms in Direct mode per #87); this is a **frontend UX restructure**.

## 2. Scope decisions (locked in brainstorm 2026-06-24)

1. **One shared `BookAppointmentFlow` component** (a **sheet** — full-screen on mobile, side/centered on desktop; stays in context). Opened from **3 doors**, each **pre-filling** what it knows:
   - **Slot** (My Schedule / Clinic Schedules) → Doctor + Date/time pre-filled.
   - **Patient** (patient detail screen) → Patient pre-filled.
   - **Primary "Book appointment"** button (Requests page header) → nothing pre-filled.
   - *(Home / global door deferred — fast-follow.)*
2. **Single guided screen with a checklist** (Patient · Doctor · Slot · Reason · Review). Each step is **✓ done/pre-filled (collapsed, still editable)** or the **active** step. The user only touches what's missing. **Not** a page-per-step wizard (booking is repeated daily).
3. **Adaptive by pre-fill** — pre-filled steps render ✓; this is *one* component, not multiple layouts. **Doctor step auto-skips** when the clinic has a single doctor or it's pre-filled.
4. **Reason optional** (Golden Rule 5.8 — never block on it); its step is still shown.
5. **Submit gated by the Review step.** Missing required items (patient, slot) are surfaced in **plain English**, never field codes. Cannot submit silently incomplete.
6. **Inline quick-add patient** (name + phone, with duplicate-check) inside the Patient step, carrying a circled-**i** reassurance line; no leaving the flow.
7. **Patient-incomplete slice of #63** (deterministic; FE-derived; see §6).
8. **Review = the reusable `ConfirmationPreview` (#60 booking instance)**; outcome follows #87.
9. **No backend.** Reuses `create_request`, patient search/create + duplicate-check, `compute_slots`, clinic `scheduling_workflow`.
10. **Deferred/coordinated:** #134 (doctor self-booking) separate but accommodated; #60 stays open for cancel/reschedule/send; #63 keeps aggregation + appointment-level missing-info.

## 3. The guided flow

A `BookAppointmentFlow` sheet driven by a small state machine over the steps. Header: "Book appointment" + a **checklist/progress** (5 items with ✓/active/pending). Each step is a section that expands when active and collapses to a one-line ✓ summary when done.

| Step | Required | Content | Pre-fillable from |
|---|---|---|---|
| **Patient** | ✅ | search existing + **"+ New patient"** quick-add (§5) | Patient door |
| **Doctor** | ✅ (auto) | pick clinic doctor; **auto-skipped** if 1 doctor or pre-filled | Slot door |
| **Slot** | ✅ | pick date → available slots (`compute_slots` via `useSlots`); shows capacity state | Slot door (date/time) |
| **Reason** | optional | chief complaint (+ optional notes) | — |
| **Review** | ✅ gate | the `ConfirmationPreview` (§7) → Confirm | — |

- **Gating:** the primary action is disabled until Patient + Doctor + Slot are set; the checklist shows what's pending in plain English ("Choose a patient", "Pick a time"). Tapping a ✓ step re-opens it for edit.
- **Cancel/close** discards the in-progress booking (nothing persisted until Confirm).

## 4. Entry points (doors)

All three render `<BookAppointmentFlow initial={...} />` with pre-filled context; one component, one behaviour.
- **Slot** — the slot chips on My Schedule / Clinic Schedules become a "book this slot" trigger → `initial = { doctorId, startDatetime }` (Doctor + Slot ✓; opens on Patient). *(Replaces the current `request-dialog` trigger.)*
- **Patient detail** — a primary **"Book appointment"** action on `patient-detail` → `initial = { patientId }` (Patient ✓; opens on Doctor/Slot).
- **Primary button** — a **"Book appointment"** button in the **Requests** page header → `initial = {}` (full flow).

## 5. Patient step + inline quick-add

- **Search** existing patients (`usePatientSearch`); pick one → ✓.
- **"+ New patient"** → a minimal inline add: **Name + Phone** only. On entry, run the existing **duplicate-check** (`POST …/patients/duplicate-check`) and, if a similar patient exists, show a **"possible duplicate"** prompt offering the match before creating. On create (`POST …/patients`), select the new patient and continue.
- **Circled-i reassurance line:** *"Please complete this patient's full details later in the Patients page."* (i18n-keyed).

## 6. Incomplete-patient detection (the #63 patient-slice)

- **Deterministic rule (FE-derived from existing patient fields, no backend):** a patient is **complete** when it has **name + phone AND (age or date_of_birth) + gender**; otherwise **incomplete**. *(Confirm the exact patient field names — `age`/`date_of_birth`, `gender` — against `PatientRead` when implementing.)* A quick-add patient (name + phone only) is therefore incomplete until completed.
- **Cues:**
  - A small **!** badge on the **Patients list** row for any incomplete patient (icon + text/tooltip, not colour-only).
  - A yellow **"Please complete patient details"** banner atop that patient's **detail screen** (`patient-detail`), linking to the edit form.
- A tiny shared helper `isPatientComplete(patient): boolean` / `patientMissingFields(patient): string[]` powers both cues. **#63** aggregates this clinic-wide (count/list on Home/#62) — out of scope here.

## 7. Review → confirm (the #60 ConfirmationPreview booking instance)

- Build a reusable **`ConfirmationPreview`** card (parameterized per action; this issue wires the **booking** instance). Booking preview shows, in **plain language**: **Patient** (name) · **Doctor** ("Dr. Sayali") · **Date/time** ("Tue 4:30 PM") · **Reason** (or "—"). *(WhatsApp message preview is added when notification templates land — SP5/SP6; show structured details until then.)*
- **Back/Edit** affordance (return to any step) + an explicit **Confirm** button (the deliberate second step).
- **Outcome (per #87):** submit calls `createRequest({ patient_id, start_datetime, chief_complaint, notes })`.
  - **Direct Booking** (response `status==="approved"` / `created_appointment_id`) → **success card** *"Appointment confirmed for {patient} with {doctor}, {time}."*
  - **Doctor Approval** → **success card** *"Request sent for approval."*
  - **Slot full** (`slot_full`) → plain-English inline error, stay on the Slot step.

## 8. Frontend components
- `src/features/scheduling/book-appointment-flow.tsx` — the sheet + step state machine + checklist + gating; props `{ clinicId; initial: { patientId?; doctorId?; startDatetime? }; open; onOpenChange }`.
- Step sections: `booking-patient-step.tsx` (search + quick-add), `booking-doctor-step.tsx` (auto-skip logic), `booking-slot-step.tsx` (date + `useSlots`), `booking-reason-step.tsx`.
- `src/components/confirmation-preview.tsx` — reusable `ConfirmationPreview` (booking instance consumed here).
- `src/features/patients/patient-completeness.ts` — `isPatientComplete` / `patientMissingFields`; consumed by the Patients list badge + `patient-detail` banner.
- Wire the 3 doors (§4); **retire** `request-dialog.tsx` (superseded). Reuse `sheet`, `Card`, `Button`, `Input`, the `useSuccess` success card, `usePatientSearch`, `useCreateRequest`, `useSlots`, the doctors list/picker, and `useClinic` (for `scheduling_workflow`).

## 9. Data & backend
**No backend changes.** Reuses: `POST …/appointment-requests` (`create_request`; auto-confirms in Direct mode), `GET …/patients` (search) + `POST …/patients` + `POST …/patients/duplicate-check`, `GET …/slots`, doctors list, `GET /clinics/{id}` (`scheduling_workflow`). Patient completeness is computed client-side from existing `PatientRead` fields.

## 10. Cross-cutting
- **i18n** en+hi parity for all new copy (`booking.*`, `patient.incomplete.*`) — gated by `tests/e2e/i18n.spec.ts`; plain-language strings; friendly date/time via `Intl`.
- **Rule 17.0** (semantic tokens, compose `components/ui/*`, no per-page CSS); both themes; **mobile-first** (sheet full-screen on mobile); WCAG AA (badge/status by icon+text, ≥44px, focus, contrast).
- **Render-on-:8753 + user sign-off before building** (the sheet from each door, the quick-add, the Review/confirm, both success states, the !-badge + banner). **FE PR held for user QA.**

## 11. Tests
- **Unit:** `isPatientComplete` (name+phone+age/DOB+gender → complete; any missing → incomplete; quick-add patient → incomplete). Step-gating logic (submit disabled until patient+doctor+slot).
- **Component (RTL):** pre-fill from each door (slot → Doctor/Slot ✓ and opens on Patient; patient → Patient ✓); doctor step auto-skips with one doctor; quick-add creates + selects a patient; Review shows plain-language summary; Confirm disabled until complete.
- **e2e (Playwright, mocked):** book from a slot end-to-end (Direct mode → "confirmed" success); book standalone with quick-add new patient (duplicate-check path); Doctor-Approval mode → "request sent"; the new patient shows the **!** badge + the patient screen shows the yellow banner.

## 12. Scope guards / deferred
- **No backend.** No new endpoints/migration.
- **#134** doctor self-booking — separate/deferred; flow accommodates it (a future "book for self" door sets `doctor_id = self`).
- **#60** — the reusable `ConfirmationPreview` is built here (booking); extending it to cancel/reschedule/send stays #60.
- **#63** — clinic-wide aggregation of incomplete patients + appointment-level missing-info stays #63; #59 ships only the per-patient detection + cues.
- **Home/global booking door** — fast-follow.

## 13. Self-review (against the request + brainstorm)
- One shared flow, 3 doors, pre-fill, sheet, fast/guided: §2/§3/§4. ✅
- Adaptive single-screen + checklist; auto-skip doctor; reason optional; gated submit, plain-English missing: §3. ✅
- Inline quick-add (name+phone, dup-check, i-note): §5. ✅
- Incomplete-patient slice of #63 (deterministic; ! badge + yellow banner; FE-derived): §6. ✅
- Review = #60 ConfirmationPreview; Direct vs Approval outcome + success card: §7. ✅
- Frontend-only; reuses existing endpoints: §8/§9. ✅
- i18n/Rule 17.0/themes/a11y/render-before-build/FE-held: §10. ✅
- Cluster: #134 deferred, #60 build-here, #63 aggregation noted: §2/§12. ✅
- Placeholder scan: concrete components/endpoints/rules; the one verify-NOTE (patient field names) flagged, not a TBD. ✅
