# Scheduling Workflow (Direct Booking vs Doctor Approval) — Design Spec (#87)

**Status:** Approved (brainstorm 2026-06-21; mockup for Settings → Scheduling provided). System-wide feature: **db + backend + frontend**.
**Type:** New clinic-level setting that governs whether appointments require doctor approval. Builds on SP3.2 (appointment requests + approval). Calm Soft-Purple (#65); Settings/Profile-pane language.

## 1. Goal
Let a clinic choose how appointments get confirmed:
- **Direct Booking** — appointments are immediately confirmed (no approval step). For solo practices / clinics where doctors manage their own schedules. Removes the self-approval "ritual" for an owner-doctor with no assistant.
- **Doctor Approval** — appointments require doctor approval before confirmation (today's flow). For clinics with assistants, multi-doctor clinics, visiting consultants.

## 2. Scope decisions (locked in brainstorm)
- **Setting location:** `ClinicSettings.scheduling_workflow` (1:1 with clinic). Enum `('direct_booking','doctor_approval')`, **default `direct_booking`**. (`GET`/`PATCH /clinics/{id}/settings` already exist, owner/PM-gated.)
- **Mechanic (Direct Booking):** booking stays one entry point (`create_request`); in direct mode it **auto-confirms inside the same transaction**, reusing the existing approval/capacity/locking logic (DRY via a shared `_materialize_appointment` helper). The request is created then immediately `approved`; the `Appointment` is `confirmed` with `source="direct_booking"`, `approved_by = the booker`. No separate code path / no orphan request artifact concerns.
- **Default chosen at clinic setup:** the create-clinic wizard asks for the workflow (Direct Booking pre-selected) with helper text "you can change this anytime in Settings → Scheduling". The DB default covers existing/pre-launch clinics.
- **Requests UI in Direct mode:** the Requests nav/page **stays visible**; the requests-queue **hides Approve/Reject** when the clinic is `direct_booking` (Cancel and other coordinator actions remain). (Direct mode produces no `pending` requests anyway; the rule is keyed on the setting so the approval affordance never appears.)
- **Notifications:** in-app behavior + copy only. Actual WhatsApp/calendar **sending stays stubbed** (hooks unchanged) — a separate future feature.
- **Reads for non-admins:** the settings endpoint is owner/PM-only, but the Requests queue (used by doctors/assistants) needs the mode — so expose `scheduling_workflow` **read-only on `GET /clinics/{id}`** (`ClinicRead`), available to any member.
- Owner/PM may edit; everyone else sees the Scheduling pane read-only.

## 3. Data model
- **Migration 0012** (after `0011_doctor_license`), applied via Supabase MCP `apply_migration`:
  - `ALTER TABLE clinic_settings ADD COLUMN scheduling_workflow VARCHAR(20) NOT NULL DEFAULT 'direct_booking'` + `CHECK (scheduling_workflow IN ('direct_booking','doctor_approval'))`.
- **Model:** `ClinicSettings.scheduling_workflow: Mapped[str]` (default `"direct_booking"`).
- **Appointment.source:** new allowed value `"direct_booking"` (existing default `"request_approval"`; no schema change — `source` is a free `String(20)`). Documents how a confirmed appointment was created.
- **Schemas:** add `scheduling_workflow` to `ClinicSettingsRead` + `ClinicSettingsUpdate`; add optional `scheduling_workflow` to `ClinicCreate` (default `direct_booking`); add read-only `scheduling_workflow` to `ClinicRead`.

## 4. Backend behavior
- **Refactor:** extract the appointment-creation block from `approve_request` into `_materialize_appointment(db, req, *, approved_by, source) -> Appointment` (capacity re-check, create `Appointment`, set `req.status="approved"` + `req.created_appointment_id`, audit `appointment.created`). `approve_request` calls it with `source="request_approval"`.
- **`create_request`:** after reserving the slot + creating the `pending` request, read `settings.scheduling_workflow` (already loaded for expiry). If `direct_booking`: call `_materialize_appointment(db, req, approved_by=actor_user_id, source="direct_booking")`, audit an extra `appointment_request.auto_approved`, and the returned request reflects `status="approved"` + `created_appointment_id`. If `doctor_approval`: unchanged (`pending`, doctor approves later).
- **Create clinic:** `create_clinic` service writes `scheduling_workflow` from the create payload onto the new `ClinicSettings` row (defaults to `direct_booking`).
- **Authz unchanged:** who can book (owner/PM/assistant — owner-doctor qualifies) and who can approve (linked doctor) are unchanged. Approve/reject endpoints still exist (used in doctor-approval mode).
- **Tests (pytest, extend `tests/scheduling/`):** direct mode → booking yields a `confirmed` Appointment immediately, request `approved`, `source="direct_booking"`, no `pending` left; doctor-approval mode → still `pending` then approve works (regression); capacity/race still enforced in direct mode; `ClinicCreate` with each workflow persists; settings PATCH toggles the mode. Add approve/reject coverage if the refactor touches it.

## 5. Frontend
### 5a. Clinic-setup wizard (`src/features/auth/onboarding.tsx`, `components/wizard`)
- Add a **Scheduling Workflow** step to the create-clinic `Wizard`: two selectable radio cards (Direct Booking pre-selected / Doctor Approval) with the §1 descriptions + "Recommended for" bullets, plus helper text *"Don't worry — you can change this anytime in Settings → Scheduling."* `createClinic` payload includes `scheduling_workflow`.

### 5b. Settings → Scheduling pane (matches the provided mockup)
- Add **Scheduling** as the 3rd sub-nav item in `settings-shell.tsx` (Profile · Clinic · Scheduling; icon `event_available`). Breadcrumb "Settings › Scheduling".
- New `scheduling-pane.tsx`: header "Scheduling" + "Manage how appointments are created and approved in your clinic." → a "Scheduling Workflow" card (icon + title + "Choose how appointments are confirmed in your clinic"): two radio cards (Direct Booking / Doctor Approval) each with description + "Recommended for" bullets; an info note *"You can change this setting at any time. It will apply to all future appointments."*; **Save Changes** button (enabled when changed) → `PATCH /clinics/{id}/settings`. Owner/PM editable; read-only (no Save, disabled radios) otherwise. Success card on save.
- New FE clinic-settings api (`getClinicSettings`, `updateClinicSettings`) + hooks (`useClinicSettings`, `useUpdateClinicSettings`, query key `["clinic-settings", clinicId]`).
- Compose `Card`/`CardHeader`/`CardSeparator`/`CardContent`/`Button`/`Icon`; match Profile/Clinic pane conventions; Rule 17.0; both themes.

### 5c. Requests queue + booking copy
- `requests-queue.tsx`: read the clinic's `scheduling_workflow` (via `useClinic`); when `direct_booking`, do not render the Approve/Reject (decide) buttons. Cancel (and resend) remain. Page header may note the mode (optional).
- Booking success copy (`request-dialog.tsx`): if the create response is auto-confirmed (`status === "approved"` / direct mode), show *"Appointment confirmed for {patient} with Dr {doctor} at {time}"*; else the existing "Request sent…" copy.

## 6. i18n (en + hi parity — gated)
New keys for: scheduling nav label, pane title/subtitle, "Scheduling Workflow", the two option titles + descriptions + "Recommended for" + each bullet, the "applies to future appointments" note, Save Changes, the wizard step copy + helper, the direct-booking confirmation message. All in both `en.json` + `hi.json`.

## 7. Quality
- **Backend:** `uv run ruff check .` clean; `make test` (incl. new tests) green; migration applied via Supabase MCP (controller-only) — implementers validate on local PG :5433, never alembic against Supabase.
- **Frontend:** `tsc --noEmit` + `npm run build` + i18n parity (`tests/e2e/i18n.spec.ts`) green; run relevant `tests/e2e/*.spec.ts` (e.g. auth onboarding) locally.
- **Rule 17.0** (semantic tokens, compose `components/ui/*`, no per-page CSS); both themes; mobile-first; WCAG AA. Match Profile/Clinic pane conventions.
- **CI gate:** never merge red — verify `gh-personal pr checks` green before merge. **Frontend PR held for user test;** backend may merge after green review.
- Docs updated alongside: PRD (new Scheduling Workflow section + annotations to §16/§17/§19) and the SP3.2 approval spec (note the auto-confirm path).

## 8. Scope guards / deferred
- WhatsApp/calendar/email **sending** (stubbed hooks) — future. The "Notifications" sub-nav and other mockup sub-nav sections (General/Location/Working Hours/Services/Templates/Billing) — not built here. No change to slot/capacity/expiry semantics. No per-doctor workflow override (clinic-level only).

## 9. Self-review (against the request)
- Direct Booking vs Doctor Approval clinic setting: §2/§3. ✅
- Direct mode auto-confirms (no approval ritual), reusing approval logic: §4. ✅
- Chosen at clinic setup wizard + "change later" helper: §2/§5a. ✅
- Settings → Scheduling pane per mockup, 3rd sub-nav: §5b. ✅
- Requests stays; Approve/Reject hidden in direct mode; Cancel kept: §2/§5c. ✅
- Notifications: in-app copy now, sending deferred: §2/§8. ✅
- Non-admin can read mode (ClinicRead): §2/§3. ✅
- PRD + entities/approval docs updated: §7 + companion PRD/SP3.2 edits. ✅
- Placeholder scan: concrete columns/endpoints/files/keys; no TBD. ✅
