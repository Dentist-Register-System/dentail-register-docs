# Patient Detail Redesign — Design Spec (#80)

**Status:** Approved (brainstorm + visual companion + frontend-design 2026-06-21; render approved "exactly"). Refs `Mockups/each_patient_mockup.png` (desktop) + `Mockups/within_patient_mockup.png` (mobile).
**Type:** FULL build — a small **backend** slice (per-patient appointments query) + a **frontend** slice (tabbed detail). Settings/#65 language. Builds on the merged Patients redesign.

## 1. Goal
Replace the (already card-ified but plain) patient detail with the approved tabbed, two-column layout — making "click into a patient" as polished as the rest of the app.

## 2. Scope decisions (locked)
- **NO new patient fields** (use existing only: name, phone, age, referral_source, chief_complaint, medical_conditions, notes). The mockup's Date of Birth / Email / Gender / Blood Group / Allergies are **NOT added now** (later as needed).
- **Per-patient appointments = NEW backend query** (data exists in `appointment_beta` with `patient_id`; just no per-patient lookup). No migration.
- **Files tab dropped** for V1 (storage deferred; mockups saved for later).
- Match the approved render **exactly** (within the design system).

## 3. Backend slice (first)
- **Endpoint:** `GET /clinics/{clinic_id}/patients/{patient_id}/appointments` → list the patient's appointments, ordered by `start_datetime` desc. Response items: `{ id, start_datetime, status, chief_complaint, doctor_id }` (a `PatientAppointmentRead`-style schema; reuse `Appointment` fields). Authz: existing clinic membership (`CurrentMembership`); 404 if the patient isn't in the clinic.
- **Service:** query `appointment_beta` where `patient_id == patient_id` (and the patient belongs to `clinic_id`); order `start_datetime` desc. (No migration — appointments table exists.)
- **Tests (pytest):** returns the patient's appointments (ordered); empty list when none; cross-clinic/unknown patient → 404; only that patient's appointments returned.
- (Frontend splits upcoming = `start_datetime >= now` & not cancelled, recent = past, client-side.)

## 4. Frontend slice (after backend)
Match the render exactly:
- **Header:** "← All Patients" back (segment-aware label) · large initials avatar · **Name** + age chip · phone (purple, `call` icon) · **Edit** (outlined purple, pencil) + **Delete** (outlined) top-right. Reuse existing edit/delete dialogs.
- **Tabs:** Overview · Appointments · Medical History · Notes (NO Files). Active tab = purple underline. Mobile = horizontal scrollable tabs (icons + labels), content stacks.
- **Overview (2-col desktop, stacked mobile):**
  - **Left:** **Personal Information** card (Phone, Age) · **Clinical Information** card (Referral Source, Chief Complaint, Medical Conditions) · **Notes** card (current `notes` field; "No notes added yet." empty + **Add/Edit Note** → existing edit). Each card = `Card` + `CardHeader`(icon+title) + `CardSeparator` + content (label/value grid).
  - **Right:** **Upcoming Appointments** card — soft empty-state ("No upcoming appointments…") + **New Appointment** button; if upcoming exist, list them. **Recent Appointments** card — list (date·time, type=`chief_complaint` or "Appointment", status badge) + **View all appointments →** (switches to the Appointments tab).
- **Appointments tab:** full list of the patient's appointments (date/time, type, status badge), upcoming then past; empty-state when none.
- **Medical History tab:** Medical Conditions (the field) + the patient's **past/completed** appointments as history; empty-states.
- **Notes tab:** the `notes` field, view + edit (Add/Edit Note).
- **New Appointment** button → navigate to `/clinic-schedules` (booking entry) for V1 (deep pre-fill of the patient is a deferred enhancement).
- **Status badge** colours via semantic tokens (`success` for completed, `muted`/`warning` etc. by status). Appointment "type" = `chief_complaint` (no type field yet — deferred).
- Reuse `Card`/`CardHeader`/`CardSeparator`/`Table`?, `Button`(outlined), `Icon`, success cards, the existing patient edit/delete. New: a `usePatientAppointments(clinicId, patientId)` hook + the tabbed detail composition; a small pure helper to split upcoming/recent (unit-tested).

## 5. Scope guards / deferred (logged on #80)
New patient fields (DOB/Email/Gender/Blood Group/Allergies); Files tab (storage); appointment "type" field; multi-note Notes; "New Appointment" pre-filled-for-patient booking; per-patient appointment pagination. Mockups kept at `Mockups/each_patient_mockup.png` + `within_patient_mockup.png`.

## 6. Quality
Rule 17.0 (semantic tokens, compose `components/ui/*`, no per-page CSS); i18n en/hi parity; both themes; mobile-first (stacked + horizontal tabs); WCAG AA; backend `make test`; frontend `tsc --noEmit` + `npm run build` + i18n parity + a pure-logic unit test (upcoming/recent split). Migration via Supabase MCP only if any (none expected).
