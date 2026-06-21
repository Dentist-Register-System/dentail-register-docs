# Unified Patient Appointments — Design Spec (#93)

**Status:** Approved (brainstorm 2026-06-22). System-wide: **backend + frontend**. Builds on the Requests redesign (#89) — reuses its enriched row + action handlers.
**Type:** Make the patient-detail page show a patient's FULL scheduling history (confirmed appointments **and** requests), with the rich Requests-style rows, action support, and Overview→tab overflow.

## 1. Goal
Today the patient-detail appointments only show **confirmed appointments** (`appointment_beta`); **pending requests** are invisible there. Unify them so the patient page shows the complete picture (pending/confirmed/rejected/cancelled), in the same rich rows as the Requests page, and let doctors act on pending items right there.

## 2. Scope decisions (locked in brainstorm)
- **Unified list = confirmed appointments + requests that are `pending`/`rejected`/`cancelled`.** Skip `approved` requests — their created confirmed appointment already represents them (dedup; no doubles).
- **Reuse, don't duplicate:** extend the existing `request-row` with a `hidePatient` prop and reuse it on the patient page (`hidePatient=true`) — same rows, same Approve/Reject/Cancel handlers (`useRequestAction`), same permission gating. **Patient-scoped variant** drops the redundant patient-identity column (it's the patient's own page).
- **Actionable on the patient page too** (Approve/Reject/Cancel), reusing the row's existing action logic + gating (assigned-doctor / direct-mode behavior per #87/#89, incl. the "doctor can approve any pending regardless of mode" fix).
- **Overview cards:** up to **2** rich rows per card (Upcoming, Recent); **"View all (N) →"** button (→ Appointments tab) whenever a section has **>2** items.
- **>1 pending guard:** when the patient's **pending count > 1**, show a small **italic, non-bold** line with a ⚠ icon under the **Upcoming** card: *"More than one pending appointments."* (Independent of "View all".)
- **Appointments tab:** render **all** unified items as the rich rows.

## 3. Backend
- **`list_patient_appointments`** (`app/modules/scheduling/service.py`) → return a single **enriched, `RequestListItem`-compatible** list for the patient, combining:
  - all `Appointment` rows (status `confirmed`) for the patient, and
  - `AppointmentRequest` rows for the patient with status in (`pending`, `rejected`, `cancelled`).
  Join patient + doctor (+ requester) like the Requests list, so each item has: `id`, `doctor_id`, `doctor_name`, `patient_id`, `patient_name`/`age`/`gender`/`phone`, `start_datetime`, `status`, `chief_complaint`, `created_at`, `updated_at`, `expires_at`, `expired`, `requested_by_name`, and a discriminator (`kind: "request" | "appointment"`).
  - **Action-id rule:** for a `kind="request"` item, `id` = the **request id** (so the row's Approve/Reject/Cancel call the request action correctly). For `kind="appointment"`, `id` = the appointment id (these are `confirmed`, never `pending`, so the row shows no actions).
  - **Synthesize request-shaped fields for appointments:** confirmed appointments have no `expires_at`/`expired`/`requested_by_name` in the request sense — set `expired=false`, `expires_at` = the appointment time (or null-safe), `requested_by_name` from the appointment's `requested_by` if available else null.
  - Order by `start_datetime` desc (FE re-splits upcoming/recent). Authz unchanged (membership; `get_patient` 404 if not in clinic).
- **Schema:** introduce/extend the per-patient item schema (e.g. `PatientScheduleItem`) to the unified shape above; the endpoint `GET /clinics/{id}/patients/{pid}/appointments` returns `list[PatientScheduleItem]` (keep it a bare list — this is patient-scoped + bounded; no server pagination needed here).
- **Tests:** patient with a pending request + a confirmed appointment → both returned with correct `kind`/status/enrichment; approved request is NOT double-counted (only its appointment appears); rejected/cancelled requests appear; cross-clinic/unknown patient → 404; enrichment fields present.

## 4. Frontend
### 4a. Reuse the row
- Extend `src/features/scheduling/request-row.tsx` with `hidePatient?: boolean` — when true, omit the patient-identity column (avatar+name+age/gender+phone) and lead with Doctor / Chief Complaint / Date-Time / Status. Everything else (status tint, chip, timestamp, expired flag, "Requested by", Approve/Reject, ⋮ Cancel/Resend, gating) unchanged. The Requests page keeps `hidePatient` falsy (or omitted).
- The patient-appointments item type (FE) must be compatible with `RequestListItem` (same fields the row reads). Update `src/features/patients/api.ts` (`PatientAppointment` → the unified shape) + the hook.

### 4b. Patient detail (`src/features/patients/patient-detail.tsx`)
- Feed the unified list through `splitAppointments` (upcoming = future & not cancelled, asc; recent = rest, desc).
- **Overview → Upcoming card:** up to 2 upcoming rich rows (`hidePatient`); if `upcoming.length > 2`, a **"View all ({upcoming.length}) →"** button that switches the active tab to **Appointments**. Keep the card header + the **New Appointment** button + the soft empty-state when none. Below the card, when `pendingCount > 1`, the ⚠ italic non-bold warning line (`text-muted-foreground italic text-xs` + a `warning`-toned ⚠ icon; tokens only).
- **Overview → Recent card:** up to 2 recent rich rows; "View all (N) →" when `recent.length > 2`; soft empty-state otherwise.
- **Appointments tab:** all unified items as rich rows (upcoming then recent, or chronological) — full list.
- **Permissions:** compute `canDecide` (= `me.doctor_id != null`, per the #89 fix — assigned-doctor enforced by backend) + `canCoordinate` (owner/assistant; practice_manager removal is #91 — keep current role set until then) on the patient page and pass to the rows, so Approve/Reject/Cancel work here. Actions invalidate the patient-appointments query + requests/counts (so the row updates in place).
- i18n en/hi for: "View all ({{count}})", the ⚠ warning ("More than one pending appointments"), reuse existing requests/status keys.

## 5. Quality
- Backend: `uv run ruff check .` + `make test` (incl. new unified-query tests) green; no migration. Cross-module reads via join (like #89). 
- Frontend: `tsc --noEmit` + `npm run build` + i18n parity; pure-logic `splitAppointments` already tested — extend if pending-count logic added.
- Rule 17.0 (semantic tokens, compose `components/ui/*`, no per-page CSS); both themes; mobile-first; WCAG AA.
- Never merge red; **frontend PR held for user test**; backend may merge after green review.

## 6. Scope guards / deferred
- No new appointment-cancellation flow for *confirmed* appointments (only requests are actionable — confirmed rows are read-only here). Server pagination of patient history (bounded list is fine). The practice_manager removal + non-doctor-approval toggle remain #91.

## 7. Self-review (against the request)
- Pending requests now visible on the patient page (the reported gap): §3/§4. ✅
- Dedup approved-request↔appointment: §2/§3. ✅
- Reuse rich rows (no dup) via `hidePatient`: §2/§4a. ✅
- Overview cap 2 + "View all (N) →" to Appointments tab: §2/§4b. ✅
- ⚠ ">1 pending" italic warning under Upcoming, independent of View-all: §2/§4b. ✅
- Actionable on patient page (reused gating/handlers): §2/§4b. ✅
- Appointments tab = full rich rows: §2/§4b. ✅
- Rule 17.0 + i18n + tests + merge policy: §5. ✅
- Placeholder scan: concrete query/fields/props/components; no TBD. ✅
