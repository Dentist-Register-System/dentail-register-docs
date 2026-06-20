# Owner-Doctor Self-Profile + Schedule Nav Split (Slice 1) — Design Spec

> Status: Draft for review · Date: 2026-06-20 · Requirement source: issue #49
> Scope: Slice 1 of the V1 role/scheduling fix. Make "owner is also a doctor" work via a **self-service doctor profile** (kept distinct from clinic data), fix the doctor authz, and split scheduling into **My Schedule** / **Clinic Schedules**. The guided one-question **wizard** UX is Slice 2 (#50), built immediately after; this slice uses a straightforward M3 form.

---

## 1. Context & Purpose
The app modeled clinic **owner** and **doctor** as mutually exclusive: creating a clinic makes you an `owner` member with **no `doctor_beta` row**, so you never appear in doctor lists, can't build a schedule, and can't be booked ("I'm the owner and there's nothing to schedule"). For V1 the clinic creator is almost always **also a doctor** (small Indian clinics), but a clinic's details are **not** a doctor's details (clinic reception phone ≠ doctor's personal phone). So the owner creates their **own doctor profile** as a separate, self-service step — not derived from clinic data, not a self-invite, not a provider abstraction.

**Core model decision:** *"Is this user a doctor?"* is answered by **a `doctor_beta` row linked to them (`linked_user_id`)**, independent of `clinic_member.role`. Roles (Owner / Doctor / Assistant) are **not mutually exclusive**. No role-set table, no provider/schedulable abstraction.

## 2. Scope Decisions (locked during brainstorming)
- **Clinic creation is unchanged** — no doctor data collected there, no auto-doctor.
- **Self doctor-profile** is an explicit, self-service action: creates a `doctor_beta` `linked_user_id = caller`, `status = active`, **no invite**. Distinct from the existing invite-based "Add doctor" (which creates an `invited` row + `clinic_invite` for someone else).
- **One self-profile per user** (per clinic) → 409 if it already exists.
- **Owner-doctor is the default happy path but not forced** — some owners are admin-only. Creation is prompted + skippable, available anytime.
- **Doctor-ness drives nav + authz**, not `clinic_member.role`.
- **Nav split**: My Schedule (own, no selector) vs Clinic Schedules (admin, M3 doctor picker). Replaces the SP3.1–3.2 single "Schedule" destination.
- **No traditional dropdowns** for non-trivial selection — prefer M3 searchable/bottom-sheet pickers (permanent design rule).
- Slice-1 doctor-profile + clinic-creation use a **straightforward M3 form**; the guided wizard is **Slice 2 (#50)**.
- **No SQL backfill** for the existing clinic — the existing owner creates their profile through the new banner/flow once shipped.
- Out of scope: the wizard UX (#50), doctor direct-booking (SP3.4), multi-role abstractions, mobile-nav overflow redesign.

## 3. Backend
### 3.1 Self doctor-profile
- **`POST /api/v1/clinics/{clinic_id}/doctors/me`** → `DoctorRead`. Creates a `doctor_beta` for the caller: `linked_user_id = current_user.id`, `status = active`, `clinic_id`, `name` (req), `phone` (req, personal), `specialty` (opt). No `clinic_invite`. Audit `doctor.created` (note: self/owner-doctor, no invite).
  - Auth: any **active clinic member** may create **their own** profile.
  - Idempotency: if the caller already has a `doctor_beta` in this clinic (`linked_user_id == caller`), return **409 `conflict`** (one self-profile).
  - Schema `DoctorSelfCreate` = `{ name (1..200), phone (1..32, permissive `^\+?[0-9\s\-().]+$`), specialty? }` (reuse the doctor phone-validation convention).
- The existing invite-based create (`POST …/doctors`) and `list_doctors` are unchanged; the new self row appears in `list_doctors` automatically.

### 3.2 `/me` exposes doctor identity
- `MeRead` gains **`doctor_id: uuid | null`** — the `doctor_beta` linked to the caller in their (first) clinic, else null. Drives nav (My Schedule) and opens it to that doctor.

### 3.3 Authz fix (the bug)
- `approve_request` / `reject_request` (scheduling `booking.authorize_decide`) currently require `membership.role == MemberRole.doctor`. **Change** to: allowed iff the caller is **linked to the request's doctor** (`get_doctor(clinic, request.doctor_id).linked_user_id == membership.user_id`), regardless of member role — so an owner-doctor approves their own requests. (Availability authz already allows owner/PM + doctor-self; create/cancel/resend already allow owner/PM/assistant — unchanged.)

## 4. Frontend (Rule 17.0, i18n en/hi, both themes, mobile-first, a11y)
### 4.1 Doctor-profile creation (M3 form — wizard in #50)
- An M3 dialog/form: `name` / personal `phone` / `specialty` → `POST …/doctors/me`. On success invalidate `["me"]` + doctor lists. 409 → "you already have a profile".
- **Entry points:** (a) **post-onboarding prompt** after clinic creation — *"Are you a doctor here? Set up your profile to start scheduling"* → form / Skip; (b) the **warning banner** (4.2); (c) a persistent CTA (e.g., My Schedule empty-state).

### 4.2 Dismissable warning banner
- An M3 **warning** banner shown to a member with **no `doctor_id`**: *"Are you a practicing doctor? Please create your profile."* with a "Set up profile" action + dismiss (session-scoped). Rendered on Home (and the schedule area). Dismissal is client-only; reappears next session until a profile exists.

### 4.3 Navigation split (`/me`-driven; replaces "Schedule")
- **My Schedule** (`/my-schedule`) — shown **iff `me.doctor_id`**. Opens directly to *that* doctor's availability editor + slot view; **no picker / no dropdown**.
- **Clinic Schedules** (`/clinic-schedules`) — shown to `owner` / `practice_manager` / `assistant`. An **M3 `DoctorPicker`** ("Viewing: Dr. X [Change]" → bottom sheet with search + list) selects a doctor → their slots (bookable via the SP3.2 request dialog) + availability (owner/PM editable). **Replaces the old `/schedule`** route.
- Visibility matrix: owner **with** profile → both; doctor-only → My Schedule; assistant / practice_manager / owner **without** profile → Clinic Schedules (+ banner for owners without a profile).
- Shared **`DoctorScheduleView(doctorId, canManage)`** component powers both (own id vs picked id). `/doctors/[id]` detail keeps its availability editor (same component) as an admin entry point.

### 4.4 M3 selection (no dropdowns)
- New reusable **`DoctorPicker`** (trigger + bottom-sheet/search list) replaces the native `<select>` used on the old Schedule screen.
- The availability editor's **day-of-week** `<select>` (7 options) → M3 **segmented**/chips (Mon–Sun).
- The SP3.2 patient picker is already a search list — unchanged.

## 5. Docs to update (this slice)
- **PRD** — clinic creation / roles / scheduling: owner-doctor default, self doctor-profile, My Schedule vs Clinic Schedules.
- **`Entities/01-clinic.md`** (clinic ≠ owner/doctor data), **`03-user.md`** (a user may link to a doctor profile; roles non-exclusive), **`04-doctor.md`** (self-created active profile without invite; doctor-ness = linked row).
- **Workflows** — scheduling + doctor lifecycle (self-profile path).
- **Golden Rules + design-system notes** — add the **permanent rules**: *"Owner-doctor is the default happy path,"* *"My Schedule and Clinic Schedules are separate navigable concepts,"* and *"Prefer M3 searchable/bottom-sheet/command selection over dropdowns (dropdowns only for 2–4 trivial options)."*

## 6. Testing
- **Backend:** self-profile creates an active linked `doctor_beta` (no invite); appears in `list_doctors`; second self-create → 409; `/me` returns `doctor_id` after creation (null before); an owner-doctor (member role `owner`, linked to the request's doctor) can **approve/reject** their own request (authz fix), and a non-linked member (incl. another doctor) gets 403; clinic creation still creates no doctor.
- **Frontend:** nav visibility per role/profile state (owner+profile → both; doctor-only → My Schedule; assistant/PM/owner-without-profile → Clinic Schedules); My Schedule opens with no picker; Clinic Schedules uses the M3 `DoctorPicker` (no native `<select>`); banner shows when `doctor_id` is null and is dismissable; profile form posts + refreshes `/me`; day-of-week segmented control; i18n en/hi parity; tsc + build.

## 7. Execution shape
One spec, one plan. Backend first (self-profile endpoint + `/me.doctor_id` + authz fix + tests), then frontend (profile form + banner + nav split + `DoctorScheduleView` + `DoctorPicker` + segmented day-of-week + i18n), then docs. No Supabase migration if no schema change is needed (the self-profile reuses `doctor_beta`); if any column is added it follows the offline-SQL → MCP `apply_migration` controller process. (Expected: **no new migration** — `doctor_beta` already has `linked_user_id`/`status`/`name`/`phone`/`specialty`.)
