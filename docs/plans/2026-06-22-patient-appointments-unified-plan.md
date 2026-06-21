# Unified Patient Appointments Implementation Plan (#93)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show a patient's full scheduling history (confirmed appointments + pending/rejected/cancelled requests) on the patient-detail page, reusing the Requests rich rows + actions, with Overview overflow + a >1-pending warning.

**Architecture:** Backend rewrites `list_patient_appointments` into a unified enriched list (T1). Frontend extends `request-row` with `hidePatient` + makes the patient-appointments type `RequestListItem`-compatible + teaches the status helper "confirmed" (T2), then rewires patient-detail Overview cards (≤2 + View-all + >1-pending warning) and the Appointments tab to render the rich rows with actions (T3).

**Tech Stack:** FastAPI / SQLAlchemy / pytest; Next.js App Router / TanStack Query / react-i18next / Tailwind tokens.

## Global Constraints
- **Backend:** sync SQLAlchemy; uniform error envelope; cross-module reads via JOIN on the other modules' models (read-only — same pattern as #89); `uv run ruff check .` clean; `make test` on local PG :5433; **no migration**.
- **Enum/values:** request statuses `pending|approved|rejected|cancelled`; appointment status `confirmed`; unified item `kind ∈ ('request','appointment')`. Unified list = all confirmed appointments + requests with status in (`pending`,`rejected`,`cancelled`) — **exclude `approved` requests** (their confirmed appointment already represents them).
- **Action-id rule:** a `kind="request"` item's `id` = the **request id** (so Approve/Reject/Cancel hit the request action); `kind="appointment"` item's `id` = the appointment id (status `confirmed` ⇒ never actionable).
- **Frontend:** Rule 17.0 — semantic tokens only, compose `components/ui/*`, no per-page CSS, no new tokens. i18n en/hi parity (`tests/e2e/i18n.spec.ts`). Both themes; mobile-first; WCAG AA. **Reuse `request-row` (no duplication).** CI = `tsc --noEmit` + `npm run build`. Stale iCloud `* [0-9].ts*` files break tsc → delete + re-run.
- Commit trailer `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`; stage SPECIFIC paths; never `git add -A`; never stage `.superpowers/`.
- **Merge policy:** backend PR may squash-merge after green review; **frontend PR opens then STOPS** for the user's test. Never merge red.

---

## Task 1: Backend — unified `list_patient_appointments`

**Files:** Modify `app/modules/scheduling/service.py` (`list_patient_appointments`), `app/modules/scheduling/schemas.py` (`PatientAppointmentRead` → unified `PatientScheduleItem`), `app/modules/scheduling/booking.py` (reuse `is_expired`). Endpoint in `app/modules/patients/router.py` returns the new shape. Test `tests/scheduling/` (extend `test_patient_appointments.py`).

**Interfaces produced:** `GET /clinics/{id}/patients/{pid}/appointments` → `list[PatientScheduleItem]` with fields: `kind: str` ("request"|"appointment"), `id: uuid`, `doctor_id`, `doctor_name`, `patient_id`, `patient_name`, `patient_age: int|None`, `patient_gender: str|None`, `patient_phone: str|None`, `start_datetime`, `status`, `chief_complaint: str|None`, `created_at`, `updated_at`, `expires_at`, `expired: bool`, `requested_by_name: str|None`.

- [ ] **Step 1: Failing tests** in `tests/scheduling/test_patient_appointments.py` (reuse fixtures; set `scheduling_workflow="doctor_approval"` so pending requests exist):
```python
def test_patient_schedule_includes_pending_request_and_confirmed_appointment(...):
    # patient has a confirmed appointment (kind="appointment", status="confirmed")
    # AND a pending request (kind="request", status="pending", id == the request id)
    # both returned, enriched (doctor_name, patient_name, etc.)
def test_approved_request_not_duplicated(...):
    # approve a request -> only the confirmed appointment appears (no approved-request row)
def test_rejected_and_cancelled_requests_appear(...):
def test_unknown_patient_404(...):
```

- [ ] **Step 2: Run → fail.**

- [ ] **Step 3: Schema.** In `scheduling/schemas.py` replace `PatientAppointmentRead` with:
```python
class PatientScheduleItem(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    kind: str
    id: uuid.UUID
    doctor_id: uuid.UUID
    doctor_name: str
    patient_id: uuid.UUID
    patient_name: str
    patient_age: int | None
    patient_gender: str | None
    patient_phone: str | None
    start_datetime: dt.datetime
    status: str
    chief_complaint: str | None
    created_at: dt.datetime
    updated_at: dt.datetime
    expires_at: dt.datetime
    expired: bool = False
    requested_by_name: str | None
```

- [ ] **Step 4: Service.** Rewrite `list_patient_appointments` in `scheduling/service.py`:
```python
def list_patient_appointments(db, *, clinic_id, patient_id):
    from app.modules.patients import service as patients_service  # noqa: PLC0415
    from app.modules.doctors.models import Doctor  # noqa: PLC0415
    from app.modules.auth.models import AppUser  # noqa: PLC0415
    from app.modules.scheduling.models import Appointment, AppointmentRequest  # noqa: PLC0415
    from app.modules.scheduling.booking import is_expired  # noqa: PLC0415

    patient = patients_service.get_patient(db, clinic_id, patient_id)  # 404 if not in clinic
    pcommon = {
        "patient_id": patient.id, "patient_name": patient.name,
        "patient_age": patient.age, "patient_gender": patient.gender, "patient_phone": patient.phone,
    }
    items: list[dict] = []
    # Confirmed appointments
    for (a, d, u) in db.execute(
        select(Appointment, Doctor, AppUser)
        .join(Doctor, Doctor.id == Appointment.doctor_id)
        .outerjoin(AppUser, AppUser.id == Appointment.requested_by)
        .where(Appointment.patient_id == patient_id, Appointment.clinic_id == clinic_id)
    ).all():
        items.append({
            "kind": "appointment", "id": a.id, "doctor_id": a.doctor_id, "doctor_name": d.name,
            **pcommon, "start_datetime": a.start_datetime, "status": a.status,
            "chief_complaint": a.chief_complaint, "created_at": a.created_at, "updated_at": a.created_at,
            "expires_at": a.start_datetime, "expired": False,
            "requested_by_name": u.name if u is not None else None,
        })
    # Pending / rejected / cancelled requests (approved excluded — appointment represents them)
    for (r, d, u) in db.execute(
        select(AppointmentRequest, Doctor, AppUser)
        .join(Doctor, Doctor.id == AppointmentRequest.doctor_id)
        .outerjoin(AppUser, AppUser.id == AppointmentRequest.requested_by)
        .where(
            AppointmentRequest.patient_id == patient_id,
            AppointmentRequest.clinic_id == clinic_id,
            AppointmentRequest.status.in_(["pending", "rejected", "cancelled"]),
        )
    ).all():
        items.append({
            "kind": "request", "id": r.id, "doctor_id": r.doctor_id, "doctor_name": d.name,
            **pcommon, "start_datetime": r.start_datetime, "status": r.status,
            "chief_complaint": r.chief_complaint, "created_at": r.created_at, "updated_at": r.updated_at,
            "expires_at": r.expires_at, "expired": is_expired(r),
            "requested_by_name": u.name if u is not None else None,
        })
    items.sort(key=lambda x: x["start_datetime"], reverse=True)
    return items
```
(`Appointment` model has no `updated_at` → use `created_at` for both. Confirm `Appointment.created_at` + `requested_by` exist; they do.)

- [ ] **Step 5: Router.** In `app/modules/patients/router.py`, change the patient-appointments endpoint `response_model` from `list[PatientAppointmentRead]` to `list[PatientScheduleItem]` (update the import). The service returns dicts → FastAPI validates against the schema.

- [ ] **Step 6: Run → pass; ruff clean. Step 7: Commit** specific paths → `feat(scheduling): unified patient schedule (appointments + requests) (#93)`.

> Backend PR (T1): open + review + verify CI green → may squash-merge. No migration.

---

## Task 2: Frontend — `hidePatient` row + unified type + "confirmed" status

**Files:** Modify `src/features/scheduling/request-row.tsx` (hidePatient), `src/features/scheduling/request-status.ts` (confirmed), `src/features/patients/appointments-logic.ts` (`PatientAppointment` type → unified), `src/features/patients/api.ts` + `hooks.ts` (return type), `tests/e2e/request-status.spec.ts` (confirmed cases), i18n.

- [ ] **Step 1: Status helper handles "confirmed".** In `request-status.ts`: `statusToken` add `case "confirmed": return "success";`; `decisionLabelKey` add `case "confirmed": return "requests.confirmedOn";`. (Leave `isNew` as-is — only pending is "new".) Update `tests/e2e/request-status.spec.ts` to assert `statusToken("confirmed")==="success"` and `decisionLabelKey("confirmed")==="requests.confirmedOn"`.
- [ ] **Step 2: i18n (en+hi):** add `requests.status.confirmed` ("Confirmed"/Hindi) and `requests.confirmedOn` ("Confirmed on"/Hindi). Parity.
- [ ] **Step 3: `hidePatient` on the row.** In `request-row.tsx`, add `hidePatient?: boolean` to `RequestRowProps`. When true, do NOT render the patient-identity column (avatar + name + age/gender + phone); start the row with the Doctor column. The "New" badge (which sits on the patient name) — when `hidePatient`, render it next to the Doctor or omit it (omit is fine on the patient page). Everything else (status tint, chip, timestamp, expired flag, "Requested by" footer, Approve/Reject, ⋮, gating) unchanged. Requests page passes nothing (identity shows).
- [ ] **Step 4: Unified FE type.** In `appointments-logic.ts`, change `PatientAppointment` to the unified shape (superset matching the backend `PatientScheduleItem` AND the fields `request-row` reads — `RequestListItem`-compatible): add `kind`, `doctor_name`, `patient_name`, `patient_age`, `patient_gender`, `patient_phone`, `status`, `chief_complaint`, `created_at`, `updated_at`, `expires_at`, `expired`, `requested_by_name`. Keep `splitAppointments` working (it reads `status` + `start_datetime` — still fine; note `cancelled` goes to "recent"; `confirmed`/`pending` future → "upcoming"). `listPatientAppointments`/`usePatientAppointments` return the new type. (Ensure the FE type's fields are assignable to `request-row`'s `RequestListItem` prop — if the row prop type is `RequestListItem`, make `PatientAppointment` structurally compatible or have the row accept the shared fields.)
- [ ] **Step 5: Verify + commit.** `npx tsc --noEmit && npm run build && npx playwright test tests/e2e/request-status.spec.ts tests/e2e/i18n.spec.ts`. Commit specific paths → `feat(patients): hidePatient row + unified schedule type + confirmed status (#93)`.

---

## Task 3: Frontend — patient-detail Overview + Appointments tab (rich rows, actions, overflow, warning)

**Files:** Modify `src/features/patients/patient-detail.tsx`, i18n.

> Reads the unified `usePatientAppointments` list + `splitAppointments`. Renders `RequestRow` with `hidePatient` everywhere. Needs `canDecide`/`canCoordinate` + a way to switch tabs (Overview "View all" → Appointments tab).

- [ ] **Step 1: Permissions + tab switching.** In the patient-detail shell, compute `canDecide = me.data?.doctor_id != null` and `canCoordinate = role === "owner" || role === "practice_manager" || role === "assistant"` (via `useMe`; mirror `requests/page.tsx`). Lift/confirm the active-tab state so the Overview can switch to the `"appointments"` tab — pass a `goToAppointments: () => setTab("appointments")` callback into the Overview section.
- [ ] **Step 2: Overview Upcoming card.** Render up to **2** `upcoming` items as `<RequestRow hidePatient canDecide={canDecide} canCoordinate={canCoordinate} clinicId={clinicId} request={item} />`. If `upcoming.length > 2`, render a **"View all ({upcoming.length}) →"** button (`data-testid="upcoming-view-all"`) calling `goToAppointments`. Keep the card header + **New Appointment** button + the soft empty-state when `upcoming.length === 0`. **>1-pending warning:** compute `pendingCount = (data ?? []).filter(a => a.status === "pending").length`; when `pendingCount > 1`, render below the card a line: a `warning`-toned ⚠ `Icon` + `t("patients.multiplePending")` ("More than one pending appointments") styled `text-xs italic text-muted-foreground` (non-bold; tokens only). `data-testid="multiple-pending-warning"`.
- [ ] **Step 3: Overview Recent card.** Up to 2 `recent` items as `<RequestRow hidePatient .../>`; "View all ({recent.length}) →" (`data-testid="recent-view-all"`) when `recent.length > 2`; soft empty-state otherwise.
- [ ] **Step 4: Appointments tab.** Render ALL unified items (`[...upcoming, ...recent]`) as `<RequestRow hidePatient .../>` in the "All Appointments" card. Empty-state when none.
- [ ] **Step 5: Actions freshness.** Ensure the row's `useRequestAction` invalidations also refresh the patient list — confirm `useRequestAction.onSuccess` invalidates `["requests", clinicId]` + `["request-counts", clinicId]`; ADD an invalidation of the patient-appointments key (`["patients", clinicId, "appointments", patientId]`) so approving/cancelling here updates the patient view. (Either extend `useRequestAction` to also invalidate the patients-appointments queries broadly, e.g. `["patients", clinicId]`, or invalidate in the row's action callbacks. Pick the clean approach; document it.)
- [ ] **Step 6: i18n (en+hi):** add `patients.viewAllCount` ("View all ({{count}})"), `patients.multiplePending` ("More than one pending appointments"). Reuse existing `patients.upcomingAppts`/`recentAppts`/`allAppointments`/`newAppointment`/empty-state keys + the `requests.*` row keys. Parity.
- [ ] **Step 7: Verify + commit.** `npx tsc --noEmit && npm run build && npx playwright test tests/e2e/i18n.spec.ts`. Commit specific paths → `feat(patients): unified appointments in overview + tab with rich rows + actions (#93)`.

> After T3: opus whole-branch review → fix Critical/Important → **open the frontend PR and STOP for the user's test** (no auto-merge).

---

## Self-Review (plan vs spec)
- Pending requests visible on patient page (the gap): T1 + T3. ✅
- Unified list, dedup approved: T1. ✅
- Reuse `request-row` via `hidePatient` (no dup) + actions: T2/T3. ✅
- "confirmed" status renders correctly (green chip + "Confirmed on"): T2. ✅
- Overview cap 2 + "View all (N) →" to Appointments tab: T3. ✅
- ⚠ ">1 pending" italic warning under Upcoming (independent): T3. ✅
- Appointments tab = full rich rows: T3. ✅
- Actions reuse gating + invalidate patient view: T3. ✅
- Rule 17.0 + i18n parity + tests + merge policy: Global + per-task. ✅
- Type consistency: `PatientScheduleItem` (BE) fields == FE unified `PatientAppointment` == `request-row` reads; `kind`/`id`-rule consistent; `statusToken`/`decisionLabelKey` cover confirmed. ✅
- Placeholder scan: backend full code; FE references exact files/props/testids/keys + reuses the existing row. ✅
