# Patient Detail Redesign Implementation Plan (#80)

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development.

**Goal:** Tabbed two-column patient detail matching the approved render — a small backend per-patient appointments query + a frontend tabbed detail.

**Architecture:** Backend adds `GET /clinics/{id}/patients/{pid}/appointments` (no migration; `appointment_beta` already has `patient_id`). Frontend adds the hook + a pure upcoming/recent split + the tabbed detail (Overview/Appointments/Medical History/Notes — no Files; no new patient fields).

**Merge policy (IMPORTANT):** the **backend** PR may be squash-merged after review. The **frontend** PR must **NOT be auto-merged** — open it, then STOP and let the human test; merge only on their explicit say-so.

## Global Constraints
- No new patient fields (use existing). No Files tab. Match the render exactly (Settings/#65 language). Rule 17.0 (semantic tokens, compose `components/ui/*`, no per-page CSS). i18n en/hi parity. Both themes; mobile-first; WCAG AA. Backend `make test`; frontend `tsc --noEmit`+`build`+i18n.
- Backend: migrations controller-only (NONE expected here). Implementers validate via `make test`.
- Commit trailer `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`; SPECIFIC paths; don't touch `.env`/`.env.local`.

---

## Task 1: Backend — per-patient appointments query  (BACKEND branch → may auto-merge)

**Files (`dentist-registry-backend`):** Modify `app/modules/scheduling/schemas.py` (or patients), `app/modules/patients/router.py`, `app/modules/patients/service.py` (or scheduling service); Test `tests/patients/` or `tests/scheduling/`.

**Interfaces produced:** `GET /api/v1/clinics/{clinic_id}/patients/{patient_id}/appointments` → `list[PatientAppointmentRead]` ordered by `start_datetime` desc.

- [ ] **Step 1: Failing test** — add to `tests/scheduling/` (reuse fixtures that create a clinic + patient + an approved appointment, e.g. mirror `tests/scheduling/test_approval.py`):
```python
def test_patient_appointments_lists_for_patient(auth_client):
    # set up clinic + doctor(self) + availability + a patient + an appointment request approved,
    # then GET /clinics/{c}/patients/{p}/appointments returns 1 item with start_datetime + status.
    ...
def test_patient_appointments_empty(auth_client):
    # a patient with no appointments → []
def test_patient_appointments_unknown_patient_404(auth_client):
    # unknown/cross-clinic patient → 404
```
(Use the existing approval-flow helpers in `tests/scheduling/test_approval.py` to create an appointment; if simpler, insert an `Appointment` row via the service/session in the fixture.)

- [ ] **Step 2: Run → fail** (`make test`).

- [ ] **Step 3: Schema** — add `PatientAppointmentRead` (in `app/modules/scheduling/schemas.py`):
```python
class PatientAppointmentRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: uuid.UUID
    doctor_id: uuid.UUID
    start_datetime: datetime
    end_datetime: datetime
    status: str
    chief_complaint: str | None
```

- [ ] **Step 4: Service** — add `list_patient_appointments(db, *, clinic_id, patient_id)`: first `get_patient(db, clinic_id, patient_id)` (raises `NotFoundError` if not in clinic — reuse the patients service getter), then query `Appointment` where `patient_id == patient_id` ordered by `start_datetime` desc; return the list. Put it where the Appointment model is accessible (scheduling service), or in patients service importing the Appointment model.

- [ ] **Step 5: Router** — add to `app/modules/patients/router.py` (uses `CurrentMembership`):
```python
@router.get("/{clinic_id}/patients/{patient_id}/appointments", response_model=list[PatientAppointmentRead])
def patient_appointments(clinic_id: uuid.UUID, patient_id: uuid.UUID, db: DbSession, membership: CurrentMembership):
    return service.list_patient_appointments(db, clinic_id=clinic_id, patient_id=patient_id)
```
(Place before any catch-all; import `PatientAppointmentRead` + the service fn. If the query lives in scheduling service, import it there.)

- [ ] **Step 6: Run → pass** (`make test`). **Step 7: Commit** (specific paths) → `feat(patients): per-patient appointments query endpoint`.

> Backend PR: open + review + **may squash-merge** after the opus review. No migration.

---

## Task 2: Frontend — appointments api + hook + split logic (+ test)  (FRONTEND branch — hold)

**Files (`dentist-registry-frontend`):** Modify `src/features/patients/api.ts`, `src/features/patients/hooks.ts`; Create `src/features/patients/appointments-logic.ts`, `tests/e2e/patient-appointments-logic.spec.ts`.

- [ ] **Step 1: Failing test** — `tests/e2e/patient-appointments-logic.spec.ts`: `splitAppointments(items, now)` returns `{ upcoming, recent }` — upcoming = `start_datetime >= now` & status not "cancelled", sorted ascending; recent = the rest, sorted descending. Cover: a future + a past + a cancelled-future → cancelled not in upcoming; empty.
- [ ] **Step 2: fail.**
- [ ] **Step 3: Implement** `appointments-logic.ts`:
```typescript
export type PatientAppointment = { id: string; doctor_id: string; start_datetime: string; end_datetime: string; status: string; chief_complaint: string | null };
export function splitAppointments(items: PatientAppointment[], now: number) {
  const upcoming = items
    .filter((a) => a.status !== "cancelled" && Date.parse(a.start_datetime) >= now)
    .sort((a, b) => Date.parse(a.start_datetime) - Date.parse(b.start_datetime));
  const recent = items
    .filter((a) => !(a.status !== "cancelled" && Date.parse(a.start_datetime) >= now))
    .sort((a, b) => Date.parse(b.start_datetime) - Date.parse(a.start_datetime));
  return { upcoming, recent };
}
```
- [ ] **Step 4: api + hook** — `api.ts`: `listPatientAppointments(clinicId, patientId) => apiFetch<PatientAppointment[]>(\`/api/v1/clinics/${clinicId}/patients/${patientId}/appointments\`)`. `hooks.ts`: `usePatientAppointments(clinicId, patientId)` query (key `["patients", clinicId, "appointments", patientId]`, enabled when both set).
- [ ] **Step 5: pass; tsc+build clean. Step 6: Commit** (specific paths) → `feat(patients): patient-appointments api + hook + split logic`.

---

## Task 3: Frontend — tabbed patient detail (match render)  (FRONTEND branch — hold)

**Files:** Modify `src/features/patients/patient-detail.tsx`; i18n en+hi. (May extract `patient-detail-tabs.tsx` / small section components if the file grows large.)

> **Read the render** `.superpowers/brainstorm/*/content/patient-detail.html` AND `Mockups/each_patient_mockup.png` + `Mockups/within_patient_mockup.png`. Match exactly.

- [ ] **Step 1: Header** — back ("← All Patients", uses the `backLabel` prop) · large initials avatar (`avatarTint`/`initials` from patients-logic) · Name + age chip · phone (purple, `call` icon) · **Edit** (outlined purple + `edit`) + **Delete** (outlined + `delete`) top-right (reuse existing edit/delete dialogs).
- [ ] **Step 2: Tabs** — `Overview | Appointments | Medical History | Notes` (state-driven; active = purple underline; mobile = horizontal scroll). testids `patient-tab-{key}`.
- [ ] **Step 3: Overview tab** — 2-col (`grid lg:grid-cols-[1fr_380px]`, stacks on mobile):
  - Left: **Personal Information** `Card` (Phone, Age) · **Clinical Information** `Card` (Referral Source, Chief Complaint, Medical Conditions) · **Notes** `Card` (notes field; "No notes added yet." + Add/Edit Note → existing edit). Each = CardHeader(icon+title)+CardSeparator+content; label/value grid (`grid sm:grid-cols-2 gap-x-6 gap-y-4`).
  - Right: **Upcoming Appointments** `Card` — `usePatientAppointments`+`splitAppointments(_, Date.now())`; if `upcoming.length` → list, else soft empty-state ("No upcoming appointments…") ; **New Appointment** button → `Link href="/clinic-schedules"`. **Recent Appointments** `Card` — `recent` list (date·time via toLocaleString, type=`chief_complaint ?? t("...appointment")`, status badge) + **View all appointments →** (sets tab to "appointments").
- [ ] **Step 4: Appointments tab** — full list (upcoming then recent) with status badges; empty-state.
- [ ] **Step 5: Medical History tab** — Medical Conditions (field) + completed/past appointments as history; empty-states.
- [ ] **Step 6: Notes tab** — the notes field, view + edit.
- [ ] **Step 7: status badge helper** — map status→token classes (e.g. completed→`bg-success/15 text-success`, others→`bg-muted text-muted-foreground` / `bg-warning/15 text-warning`); semantic tokens only.
- [ ] **Step 8: i18n** — add `patients.tab.*`, `patients.upcomingAppts`, `patients.recentAppts`, `patients.noUpcoming*`, `patients.newAppointment`, `patients.viewAllAppts`, `patients.medicalHistory`, `patients.personalInfo`, `patients.clinicalInfo`, column/field labels, status labels — BOTH en+hi (parity).
- [ ] **Step 9: Verify** — `tsc --noEmit && npm run build` clean; i18n parity; `npx playwright test tests/e2e/patient-appointments-logic.spec.ts tests/e2e/i18n.spec.ts`. **Step 10: Commit** (specific paths).

> **After Task 3:** run the opus whole-branch review; fix Critical/Important; then **open the frontend PR and STOP — do NOT merge. Hand to the human to test; merge only when they say.**

## Self-Review (against spec)
- Backend per-patient appointments query + tests (no migration): Task 1. ✅
- Frontend api/hook/split + test: Task 2. ✅
- Tabbed detail header/tabs/Overview-2col/Appointments/Medical-History/Notes, no Files, no new fields, render-exact: Task 3. ✅
- New Appointment → /clinic-schedules; View all → Appointments tab: Task 3. ✅
- Merge policy: backend may merge; frontend held for human test. ✅
- Rule 17.0 + i18n + tests: throughout. ✅
- Placeholder scan: T1/T2 concrete code; T3 references the approved render + mockups for pixel composition (visual) with concrete grid/props/testids. ✅
