# Role Cleanup + Appointment Settings — Design Spec (#91)

**Status:** Approved (brainstorm 2026-06-22; mockup `Mockups/Appointment_settings_mockup.png`). System-wide: **db + backend + frontend + docs**. Calm Soft-Purple; Settings/Profile-pane design language.
**Type:** Remove the `practice_manager` role (→ Owner, Doctor, Assistant), and add a new **Settings → Appointment Settings** pane with (a) an "Allow other staff to approve appointments" toggle and (b) a configurable request-expiry duration (default 120 min, or "Never"). Builds on #87 (scheduling workflow) and #89 (requests redesign).

## 1. Goal
- Collapse the role set to **Owner, Doctor, Assistant**. `practice_manager` is dead weight in India — the Assistant role already covers reception + practice-management duties.
- Give clinics owner-controlled appointment policy: let assistants approve/reject on doctors' behalf (off by default), and let owners pick how long requests stay pending before expiring (including "Never").
- Keep Direct Booking (solo) vs Doctor Approval (multi) coherent: expiry only matters where approval exists.

## 2. Scope decisions (locked in brainstorm)

### 2a. Role removal
- New role set: `owner`, `doctor`, `assistant`. `practice_manager` removed from `MemberRole`, all routers/services, all frontend role checks, and en/hi locale role labels.
- **No data migration, no enum recreation.** The Postgres `member_role` ENUM physically retains the unused `'practice_manager'` value (verified 0 rows in `clinic_member_beta` and `clinic_invite_beta` on 2026-06-22). Leaving the value is harmless; recreating a PG enum is risky and unnecessary. Documented as known residue, cleanable later.
- **Doctor-ness** remains "has a linked `doctor_beta` profile" (`doctor_id`/`linked_user_id`), independent of membership role. An owner-doctor has role `owner` + a linked doctor profile.

### 2b. Permission model (final)

| Action | Owner | Assigned Doctor | Other Doctor | Assistant |
|---|:--:|:--:|:--:|:--:|
| Approve / Reject a request | ✅ always | ✅ (own only) | ❌ | ✅ **only if `allow_staff_approval`** |
| Create / Cancel / Resend request | ✅ | ❌ | ❌ | ✅ |
| Manage doctors (profiles + availability) | ✅ | own availability | — | ✅ |
| Send / revoke invites | ✅ | ❌ | ❌ | ❌ |
| Manage assistants | ✅ | ❌ | ❌ | ❌ |
| Edit clinic settings (profile, scheduling, appointment) | ✅ | ❌ | ❌ | ❌ |

- **Owner = superuser**: always allowed, every action, regardless of toggle.
- The toggle exclusively empowers the **Assistant** role to approve/reject. It never lets Doctor A act on Doctor B's request — among doctors, only the assigned doctor decides.
- "Allow other staff to approve appointments" is friendlier copy than naming the Assistant role; behaviorally it gates the Assistant.

### 2c. Appointment Settings
- **Toggle** `allow_staff_approval` (default **OFF** for new and existing clinics). Behaviorally relevant only in Doctor Approval mode (Direct Booking has no pending requests). Authz check is toggle-based only (not mode-gated) to avoid stranding requests.
- **Request expiry duration** stored in the existing `appointment_request_expiry_minutes`, made nullable: an integer (minutes) or **NULL = Never**. Default 120.
- **"Never"** → request `expires_at` is NULL → never expires → stays pending until manually approved/rejected/cancelled.
- **Direct Booking gray-out**: when `scheduling_workflow == 'direct_booking'`, the expiry-duration control is **disabled** with a locked note (matches the mockup 🔒 card). The toggle stays enabled with an info note that it applies only to multi-booking.

### 2d. Auto-approve on switch to Direct Booking (corner case)
- When clinic settings change `scheduling_workflow` → `direct_booking` and pending requests exist, all pending requests are **auto-approved** (materialized into confirmed appointments) in the same transaction, preserving Direct Booking's "no pending state" invariant.
- The frontend shows a **count-aware confirm** before the switch ("N pending request(s) will be auto-approved.").

## 3. Data model — migration `0015_appointment_settings` (via Supabase MCP; implementers validate on local PG :5433)
- `clinic_settings_beta`: **ADD** `allow_staff_approval BOOLEAN NOT NULL DEFAULT false`.
- `clinic_settings_beta`: **ALTER** `appointment_request_expiry_minutes` → **DROP NOT NULL** (nullable; NULL = Never). Keep existing default 120 for non-null inserts.
- `appointment_request_beta`: **ALTER** `expires_at` → **DROP NOT NULL** (nullable; NULL = never expires).
- **No role/enum migration.**

## 4. Backend

### 4a. Role removal (mechanical)
- `app/modules/members/models.py`: remove `practice_manager` from `MemberRole`.
- `require_role(...)` updates:
  - `app/modules/doctors/router.py`: `(owner, practice_manager)` → `(owner, assistant)`.
  - `app/modules/scheduling/service.py` `authorize_manage_availability`: `(owner, practice_manager)` → `(owner, assistant)` (doctor-own branch unchanged).
  - `app/modules/scheduling/booking.py` `_COORDINATORS`: `(owner, practice_manager, assistant)` → `(owner, assistant)`.
  - `app/modules/assistants/router.py`: `(owner, practice_manager)` → `(owner)`.
  - `app/modules/invites/router.py`: `(owner, practice_manager)` → `(owner)`.
  - `app/modules/clinics/router.py` `_settings_admin` + `_clinic_admin`: `(owner, practice_manager)` → `(owner)` for **PATCH/admin**; see 4d for GET relax.
- `tests/clinics/test_address.py:186`: change the `"practice_manager"` invite payload to a valid role (`"assistant"`).

### 4b. Approve/Reject authz
`app/modules/scheduling/booking.py` `authorize_decide` becomes settings-aware:
```python
def authorize_decide(db, *, clinic_id, request, membership, settings) -> None:
    if membership.role == MemberRole.owner:
        return
    doctor = get_doctor(db, clinic_id, request.doctor_id)
    if doctor.linked_user_id == membership.user_id:
        return
    if membership.role == MemberRole.assistant and settings.allow_staff_approval:
        return
    raise ForbiddenError("Your role is not permitted to approve or reject this request.")
```
- Router (`scheduling/router.py`) approve + reject load `settings = get_settings(db, clinic_id)` and pass to `authorize_decide`.

### 4c. Expiry "Never"
- `create_request` / `resend_request`: `expires_at = None if settings.appointment_request_expiry_minutes is None else now() + timedelta(minutes=...)`.
- `is_expired`: `req.status == "pending" and req.expires_at is not None and dt.datetime.now() > req.expires_at`.
- `AppointmentRequest.expires_at`: `Mapped[datetime | None]` (nullable).
- `list_requests` / reads: `expired` stays a derived bool via `is_expired`; NULL `expires_at` → `expired=False`, and the row's `expires_at` may be null (FE must handle).

### 4d. Settings read/write split + schema
- **GET `/clinics/{clinic_id}/settings`** → relax to any active clinic member (read-only). **PATCH stays owner-only** (`require_role(owner)`).
- `ClinicSettings.allow_staff_approval: Mapped[bool]` (default False); `appointment_request_expiry_minutes: Mapped[int | None]`.
- `ClinicSettingsRead`: add `allow_staff_approval: bool`; `appointment_request_expiry_minutes: int | None`.
- `ClinicSettingsUpdate`: add `allow_staff_approval: bool | None`; `appointment_request_expiry_minutes: int | None` (validate ≥1 when not None).

### 4e. Auto-approve on switch (`update_settings` service)
- Detect transition: incoming `scheduling_workflow == 'direct_booking'` AND current (pre-update) `!= 'direct_booking'`.
- Within the same transaction, for every `pending` request in the clinic: materialize a confirmed appointment (reuse `_materialize_appointment`, source `"direct_booking"`, `actor_user_id` = the updating owner), set request `approved` + `created_appointment_id`, record audit `appointment_request.auto_approved`.
- Apply the rest of the settings update normally. Capacity already reserved at request creation; re-check defensively per request and skip-with-audit if a slot is somehow full (should not happen).

### 4f. Tests (pytest; `uv run ruff check .` + `make test` green)
- Authz matrix for approve & reject: owner (always) / assigned doctor (always) / other doctor (403) / assistant with toggle ON (allowed) and OFF (403).
- Manage-doctors now allowed for assistant; invites/assistants/clinic-settings PATCH forbidden for assistant; GET settings allowed for a non-owner member.
- Expiry: `expiry_minutes=None` → request created with `expires_at=None`; never reported `expired`; approve not blocked. Numeric expiry still expires and blocks approve.
- Auto-approve-on-switch: switching to direct_booking with N pending → N confirmed appointments created, requests `approved`; switching with 0 pending → no-op; switching away from direct_booking → no auto-approval.
- Role removal: no remaining `practice_manager` reference; invite with removed role rejected by schema/validation.

## 5. Frontend

### 5a. Role removal (mechanical)
Remove `practice_manager` from: `src/app/settings/page.tsx`, `src/app/requests/page.tsx`, `src/app/clinic-schedules/page.tsx`, `src/app/doctors/[id]/page.tsx`, `src/components/shell/app-shell.tsx`, `src/features/patients/patient-detail.tsx`, and the `roles`/`status.role` blocks in `src/i18n/locales/en.json` + `hi.json`. Update each role predicate to the new model (e.g. `canManage`/`canCoordinate` drop the PM clause; manage-doctors/clinic-schedules use `owner || assistant`; settings/invites use `owner`).

### 5b. Appointment Settings pane (new) — `src/features/settings/appointment-settings-pane.tsx`
Built to `Mockups/Appointment_settings_mockup.png` within the design system (compose `components/ui/*`, semantic tokens, both themes, mobile-first). Owner-only pane.
- **Header:** "Appointment Settings" + "Configure appointment approval preferences and request expiry settings."
- **Staff Approval card:** title "Staff Approval" + subtitle; row "Allow other staff to approve appointments" + description + a toggle (`Switch`) bound to `allow_staff_approval`; an info callout: "This applies only to multi-booking workflow (clinics with assistants or multiple staff). In Direct Booking (solo clinic), appointments are automatically approved." Toggle stays enabled in both modes.
- **Request Expiry card:** title "Request Expiry" + subtitle; row "Request expiry duration" + description + a `Select` (30 / 60 / 120 (Default) / 240 / 480 minutes / Never) bound to `appointment_request_expiry_minutes` (Never = null). Info callout: "If set to Never, requests will not expire and will remain pending until manually approved or rejected." **When `scheduling_workflow === 'direct_booking'`**: the Select is **disabled**, and a bordered locked note card shows ("Note for Direct Booking (Solo Clinic): When Direct Booking workflow is selected, appointment requests are automatically approved and this setting is disabled.") with a 🔒 (lock) icon.
- **Bottom save bar:** info "These settings apply to all future appointment requests. Existing requests will follow the previous configuration." + "Save Changes" button → PATCH `{allow_staff_approval, appointment_request_expiry_minutes}`; success card on save.
- Sub-nav: add `{ key: "appointment", labelKey: "settings.nav.appointment", icon: "event_available" }` (use a distinct icon from Scheduling, e.g. `event_note`) to `settings-shell.tsx` after Scheduling. Route the pane; gate to owner.

### 5c. Per-row decide gating — `src/features/scheduling/request-row.tsx` + callers
- Replace the coarse `canDecide: boolean` with `role: string`, `myDoctorId: string | null`, `allowStaffApproval: boolean` props.
- Per-row: `canDecideRow = role === "owner" || (myDoctorId != null && myDoctorId === r.doctor_id) || (role === "assistant" && allowStaffApproval)`; `showApproveReject = canDecideRow && r.status === "pending" && !r.expired`.
- Update callers: `src/app/requests/page.tsx` and `src/features/patients/patient-detail.tsx` pass `role`, `me.doctor_id`, and `allowStaffApproval` (read from `useClinicSettings(clinicId)`, now member-readable). `useRequests`/list components thread the new props through.
- Handle nullable `r.expires_at` (Never) in any row copy that referenced the expiry timestamp.

### 5d. Auto-approve confirm — `src/features/settings/scheduling-pane.tsx`
- On Save when the new choice is `direct_booking` and the previous saved value was not, read pending count (`useRequestCounts(clinicId).data.pending`); if `> 0`, open a confirm dialog ("N pending request(s) will be auto-approved.") before the PATCH. On confirm → PATCH `{scheduling_workflow:'direct_booking'}`; on success invalidate `requests`, `request-counts`, and patient/appointments queries. If 0 pending, save directly.

### 5e. API + types
- `src/features/clinic/api.ts` `ClinicSettings`: add `allow_staff_approval: boolean`; change `appointment_request_expiry_minutes: number | null`. (`useClinicSettings`/`useUpdateClinicSettings` unchanged in shape.)

### 5f. i18n
en/hi parity for all new copy: `settings.nav.appointment`, the Appointment Settings pane (`settings.appointment.*` — title/subtitle, staffApproval.title/desc/row/info, requestExpiry.title/desc/row/info/never/directNote, save bar), expiry option labels, and the auto-approve confirm dialog copy. Gated by `tests/e2e/i18n.spec.ts`.

## 6. Docs updates (this spec phase)
- **PRD** (`PRD/PRD_v3_1_Founder_Edition.md`): §6 remove the Practice Manager user section + scrub "practice-manager" mentions in §6.1/§6.2/§11 (→ owner/assistant per the split); §17 make expiry configurable (default 120, or Never) instead of fixed 120; add a short §15.2/§19 note on the Staff Approval toggle (owner-set; lets assistants approve/reject; owner always can; assigned doctor always can; never cross-doctor).
- **Entities**: `Entities/02-clinic-settings.md` add `Allow staff approval` + note expiry may be "Never" (nullable); `Entities/09-appointment-request.md` note `expires_at` may be null (never expires).
- **Workflows**: `Workflows/09-appointment-request.md` (expiry now configurable incl. Never) + `Workflows/10-appointment-approval.md` (who may approve/reject under the toggle).
- A roles note: roles are `owner, doctor, assistant`; `practice_manager` retired.

## 7. Sub-issues under #91
- **#91a — Backend**: migration 0015, role removal + authz model (incl. settings-aware approve/reject), expiry-Never, auto-approve-on-switch, GET-settings relax, tests.
- **#91b — Frontend**: role removal, Appointment Settings pane, per-row decide gating, auto-approve confirm, API/types, i18n.

## 8. Quality
- Backend: `uv run ruff check .` clean; `make test` (incl. new tests) green; migration via Supabase MCP, validated on local PG :5433.
- Frontend: `tsc --noEmit` + `npm run build` + i18n parity green; pure-logic unit test for the decide-gating helper.
- Rule 17.0 (semantic tokens only, compose `components/ui/*`, no per-page CSS, no new tokens); both themes; mobile-first; WCAG AA. Faithful to the mockup.
- Never merge red (verify `gh-personal pr checks`). **Frontend PR held for user test;** backend may merge after green review.

## 9. Scope guards / deferred
- Only "Appointment Settings" is added to the settings nav — NOT the mockup's aspirational User Settings / Notifications / Team / Integrations / Billing items.
- The existing Scheduling pane (Direct Booking vs Doctor Approval radio, #87) stays as a separate sibling pane.
- No Postgres enum recreation; `'practice_manager'` value remains physically in the type (0 rows).
- Notifications remain in-app/stubbed (unchanged from #87).

## 10. Self-review (against the request)
- Roles → Owner/Doctor/Assistant; PM removed everywhere: §2a/§4a/§5a. ✅
- Owner = superuser; toggle empowers Assistant only; never cross-doctor: §2b/§4b/§5c. ✅
- Appointment Settings pane to the mockup (Staff Approval + Request Expiry, gray-out + lock note): §5b. ✅
- Toggle default OFF; expiry default 120 + Never (nullable): §2c/§3/§4c. ✅
- Direct Booking grays out expiry; toggle stays enabled: §2c/§5b. ✅
- Auto-approve-on-switch with count-aware confirm: §2d/§4e/§5d. ✅
- Admin-power split (assistant: manage doctors; owner-only: invites/assistants/settings): §2b/§4a. ✅
- Settings GET readable by members for UI gating; PATCH owner-only: §4d. ✅
- Sub-issues under #91; docs updated: §6/§7. ✅
- Rule 17.0 + i18n + tests + merge policy: §8. Placeholder scan: concrete fields/endpoints/components, no TBD. ✅
