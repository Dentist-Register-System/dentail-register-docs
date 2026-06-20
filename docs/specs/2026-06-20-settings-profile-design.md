# Settings & Profile — Design Spec (#35, first pass)

**Status:** Approved (brainstorm 2026-06-20; mockup `Mockups/mockup_settings_profile.png`).
**Decomposition:** **Slice 1 = backend (build FIRST)**, **Slice 2 = frontend UI** (matched to the mockup; consult the `frontend-design` skill with the mockup). One spec, one plan; backend tasks precede frontend tasks.

## 1. Problem & Goal
There is no Settings home and no per-user profile. Clinic editing lives on the home card; doctor-profile creation is a home banner; a user can't see/edit their own details in one place. **Goal:** a `/settings` screen hosting **Profile** (per-user identity + own doctor profile) and **Clinic** (relocated clinic-details editing), matched to the approved mockup. This is the #35 first pass; further sections (theme/language #31, Team, Services, Notifications, Integrations, Billing, Security) come later.

## 2. Scope (locked)

**In:** `/settings` route + sub-nav with exactly two sections — **Profile** and **Clinic**. Profile shows/edits the user's own details + their doctor profile. Clinic relocates the existing clinic-details edit.

**Profile fields:**
- **Editable:** Full Name (new `AppUser.full_name`); Specialization (existing `doctor.specialty`); License Number (new `doctor.license_number`).
- **Read-only / derived:** Email, Phone (from auth/`AppUser`); Role + Owner/role badge (from memberships); Joined Register (`AppUser.created_at`).
- Avatar shown as **initials placeholder** (real upload deferred → #70).
- If the user has **no doctor profile** (`doctor_id` null): hide the doctor-specific rows (Specialization, License Number) and show a **"Create your doctor profile"** CTA (reuses the existing full-screen doctor-profile wizard).

**Clinic section:** the existing clinic-details edit (currently `EditClinicDetailsDialog`), relocated into the Clinic pane; owner/practice_manager only (existing `PATCH /clinics/{id}` authz). Non-admins see read-only clinic details.

**Out / deferred (flagged):** real avatar upload (#70); phone change (Twilio OTP); email change + password change (the Security section — dropped this slice); all locale/preferences (Preferred Language, Time Zone, Date Format, Time Format — dropped); clinic timezone at setup (#71, separate); placeholder sub-nav sections (Team/Services/Notifications/Integrations/Billing — omitted entirely until built); theme/language toggle relocation (#31).

## 3. Slice 1 — Backend (build FIRST)

**Models (new columns, `_beta` tables unchanged otherwise):**
- `AppUser` (`app/modules/auth/models.py`): add `full_name: str | None` (nullable, `String(200)`).
- `Doctor` (`app/modules/doctors/models.py`, `doctor_beta`): add `license_number: str | None` (nullable, `String(100)`).

**Endpoints:**
- Extend **`GET /me`** (`MeRead`) with `full_name: str | None` and `joined_at` (= `AppUser.created_at`). (Email, phone, memberships/role, `doctor_id` already present.)
- New **`PATCH /me/profile`** → updates the caller's own `AppUser.full_name`. Body `{ full_name?: str }`. Returns the updated `MeRead`-shaped record (or the profile subset). Self-only (the authenticated user).
- Extend the existing doctor update **`PATCH /clinics/{clinic_id}/doctors/{doctor_id}`** schema (`DoctorUpdate`) with `license_number: str | None`. The doctor `name`, `specialty`, `phone` are already updatable; `license_number` joins them. Existing authz applies (owner/PM, or the linked user editing their own doctor — confirm self-edit is permitted; if the current authz blocks a plain doctor editing their own row, allow the linked user to PATCH their own doctor record).
- In-transaction audit via `record_audit` for the profile + doctor updates, consistent with existing mutations.

**Migration:** one Alembic revision (next after 0010, i.e. 0011) adding `app_user.full_name` + `doctor_beta.license_number`. Applied to Supabase via MCP `apply_migration` by the controller (implementers validate with `make test` only).

**Tests (pytest, local PG :5433):** `GET /me` includes full_name + joined_at; `PATCH /me/profile` updates own full_name (and cannot affect another user); doctor `PATCH` updates license_number; the linked user can edit their own doctor profile; uniform error envelope on validation.

## 4. Slice 2 — Frontend (after backend; `frontend-design`-guided, mockup-matched)

**Consult the `frontend-design` skill with `Mockups/mockup_settings_profile.png`** to maximize visual fidelity, while composing the Register Design System (Rule 17.0 — globals.css tokens + `components/ui/*` + AppShell; no per-page CSS).

- **`/settings` route + shell**: left sub-nav (desktop) / list-then-detail (mobile) with **Profile** + **Clinic** (default = Profile). Title "Settings", subtitle "Manage your clinic and account". Breadcrumb on the Profile page ("Settings › Profile") per mockup.
- **Settings (gear) destination** added to the app rail (`destinations.ts`), visible to all roles.
- **Profile pane** (mockup-matched): header (initials avatar w/ deferred-upload affordance hidden or disabled, name + role badge, specialization, email, phone). **Personal Information** card with an **Edit** action that toggles an edit form for the editable fields (Full Name, Specialization, License Number); Email/Phone/Role/Joined shown read-only. Uses `useUpdateSelfProfile` (PATCH /me/profile) for full_name and the existing doctor update hook for specialty/license. On success → the #61 **success card** ("Profile updated"). No-doctor-profile state → "Create your doctor profile" CTA (existing wizard).
- **Clinic pane**: render the existing clinic-details edit (reuse `EditClinicDetailsDialog`'s form/content) inside the pane; owner/PM editable, others read-only. Success → success card ("Clinic details saved", already wired).
- **Re-point entries**: the home clinic-card **Edit** → navigates to `/settings` (Clinic); the **create-profile banner** CTA → `/settings` (Profile). Keep the banner's dismiss behaviour.
- i18n en/hi for all new strings; both themes; WCAG AA (focus management on Edit toggle, labelled controls); mobile-first per the mockup's mobile frames.

## 5. Data flow & components (frontend)
- `src/features/profile/` (new): `api.ts` (`getMe` extended, `updateSelfProfile`), `hooks.ts` (`useUpdateSelfProfile`), `profile-pane.tsx` (view + edit), reuse `features/doctors` update hook for specialty/license.
- `src/app/settings/page.tsx` + a settings shell component (sub-nav + content switch). Keep panes as focused components (`profile-pane.tsx`, `clinic-pane.tsx`).
- Reuse: `/me` query (`features/clinic` `useMe`), doctor self hooks, `EditClinicDetailsDialog` form, the success-card hook (#61), the doctor-profile wizard (create CTA).

## 6. Testing & gates
- Backend: pytest as in §3.
- Frontend: i18n en/hi parity; any extracted pure logic unit-tested via the Playwright runner; `tsc --noEmit` + `npm run build` gates.

## 7. Out of scope / future (explicit)
Avatar upload (#70), clinic timezone (#71), phone change (Twilio), Security (password + email change), locale/preferences, theme/language relocation (#31), and the Team/Services/Notifications/Integrations/Billing sections (omitted until each is built).
