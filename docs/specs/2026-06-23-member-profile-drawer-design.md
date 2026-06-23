# Member Profile Drawer + Expanded Fields — Design Spec

**Status:** Approved (brainstorm 2026-06-23; sub-issue #107 of #25; UI from the approved Assistants mockup's right-side drawer). System-wide: **backend + frontend + docs**. Register Design System, Rule 17.0, i18n-first.
**Type:** Add four member fields (DOB / gender / address / working hours) and a slide-in **profile drawer** (Overview tab live; Permissions/Activity tabs shown disabled) opened from the Team table — for both Doctors & Assistants. Profile editing is **self-service** (Settings → User Profile); the clinic **owner** keeps an admin ⋯ Edit for employment/basic fields.

## 1. Goal
Let anyone view a teammate's profile at a glance (slide-in drawer from the Team table) and let each person manage **their own** details in one place (Settings → User Profile). No one edits another person's *personal* info; the owner can still fix employment-record fields.

## 2. Scope decisions (locked in brainstorm)
- **New fields** on doctor & assistant: `date_of_birth` (date), `gender` (male/female/other), `address` (single free-text), `working_hours` (single free-text, e.g. "Mon–Sat, 10:00 AM – 06:00 PM"). All nullable.
- **Drawer = quick profile**; the existing `/doctors/[id]` page keeps the availability editor. The drawer (doctors) links out via "Manage availability".
- **Editing is self-service** via Settings → User Profile. The drawer's **Edit Profile** button appears **only on your own row** (`member.linked_user_id === me.user_id`) and routes to Settings → User Profile.
- **Owner admin override:** the Team-table ⋯ **Edit** (EditMemberDialog from #106) is **owner-only** and edits **employment/basic fields only** (name · role/specialty · phone · email). It does **not** touch the personal fields (DOB/gender/address/working-hours) — those are self-service only, even for the owner.
- **EditMemberDialog is kept** (owner uses it). The other ⋯ actions stay gated per #91 (see §5c).
- **Drawer tabs:** Overview (live) + **Permissions** & **Activity** rendered **disabled** ("coming soon") — built fully in #108/#109.
- New reusable **`sheet`** UI primitive (base-ui dialog anchored right), design-system styled.
- **No new tables**; gender reuses the patient enum pattern.

## 3. Data model — migration `0018_member_profile_fields`
Add to BOTH `doctor_beta` and `assistant_beta`:
- `date_of_birth` DATE NULL.
- `gender` VARCHAR(10) NULL + CHECK `gender IN ('male','female','other')` (mirrors `patient_beta.gender`, migration 0014).
- `address` VARCHAR(500) NULL.
- `working_hours` VARCHAR(200) NULL.
No backfill (all nullable). No new tables.

## 4. Backend
- **Reads:** `DoctorRead` + `AssistantRead` gain `date_of_birth: date | None`, `gender: str | None`, `address: str | None`, `working_hours: str | None`.
- **Self-update (doctor):** `DoctorSelfUpdate` gains the 4 fields (already has name/phone/specialty/license). `PATCH /clinics/{id}/doctors/me` already exists — extend it to persist them.
- **Self-update (assistant) — NEW:** assistants have NO self endpoint today. Add:
  - `AssistantSelfUpdate { name?, phone?, title?, date_of_birth?, gender?, address?, working_hours? }` (validators: gender ∈ enum).
  - `service.update_self_assistant(db, *, clinic_id, user_id, data)` — resolves the assistant row by `clinic_id` + `linked_user_id == user_id` (404 if none), applies `model_dump(exclude_unset=True)`, audit `assistant.self_updated`, commit.
  - `PATCH /clinics/{id}/assistants/me` → `AssistantRead`, `CurrentMembership` (self, keyed off membership.user_id).
- **Owner override (unchanged field set):** `DoctorUpdate`/`AssistantUpdate` keep their current fields (name/role/phone/email/status) — do NOT add the personal fields here. The ⋯ Edit endpoint gating stays #91 (owner/assistant for doctors PATCH; owner for assistants PATCH); the UI restricts the ⋯ Edit *item* to owner (§5c).
- **Validation:** gender invalid → 422 (validator on both Self-update + Read tolerant).
- **Tests (pytest):** doctor self-update persists the 4 fields + round-trips in read; assistant self-update persists + round-trips; assistant self-update 404 when the caller has no assistant row in the clinic; gender invalid → 422; owner DoctorUpdate/AssistantUpdate still works and does NOT accept the personal fields (they're simply absent from the schema); reads include the new fields (null by default).

## 5. Frontend
### 5a. `sheet` primitive
- `src/components/ui/sheet.tsx` — wraps `@base-ui/react/dialog` anchored to the right edge: backdrop + right-anchored panel, slide-in/out via `data-[starting-style]`/`data-[ending-style]` (translate-x), design-system tokens (`bg-card`, `border-border`, `shadow-elevation-4`, width ~`max-w-md`, full height, scrollable body). Exports `Sheet`, `SheetTrigger`, `SheetContent`, `SheetClose` mirroring the dialog wrapper conventions. Rule 17.0 — semantic tokens only.

### 5b. `<MemberProfileDrawer>`
- `src/features/team/member-profile-drawer.tsx` — `<MemberProfileDrawer kind member open onOpenChange me />`. Uses `<Sheet>`.
- Header: avatar initials, name, role chip (specialty/title), status badge, `X` close.
- **Tabs** (compose `components/ui/tabs`): Overview (active) · Permissions (disabled) · Activity (disabled). testids `drawer-tab-overview/permissions/activity`.
- **Overview**: a "Personal Information" card (Email · Phone · Date of birth · Gender · Address — each row icon + label + value, "—" when null) and an "Employment Information" card (Joined on=created_at · Role=specialty/title · Working hours). Format DOB via `Intl.DateTimeFormat`.
- **Edit Profile** button: rendered ONLY when `member.linked_user_id && member.linked_user_id === me.user_id` → routes to `/settings` and selects the **User Profile** pane (link/`router.push`). testid `drawer-edit-profile`.
- **Doctors only:** a "Manage availability" link → `/doctors/${member.id}`. testid `drawer-manage-availability`.
- testid `member-profile-drawer`.

### 5c. Team-table integration
- Clicking a Team-table row (name) **opens the drawer** for that member (both Doctors & Assistants) — replaces #106's name→`/doctors/[id]` navigation. The TeamTable gets the current user context (from `useMe`: `user_id` + membership `role`) to drive:
  - **⋯ Edit** item: shown only when `role === "owner"` (admin override → opens EditMemberDialog, employment/basic fields).
  - **⋯ Activate/Deactivate/Remove**: shown per #91 — owner always; assistant only on the **Doctors** table (assistant cannot manage assistants). (Backend already enforces; this aligns the UI so no action 403s.)
- The drawer is rendered once per TeamTable, opened with the clicked member.

### 5d. Settings → User Profile pane (role-aware self-edit)
- `src/features/settings/profile-pane.tsx` becomes role-aware: a **doctor** edits their doctor self (existing `useUpdateSelfDoctor` + the new fields); an **assistant** edits their assistant self (NEW `useUpdateSelfAssistant` → `PATCH /assistants/me`). Owner-who-is-a-doctor edits the doctor self; a pure-owner with no member record sees just the account name.
- Add the 4 fields to the form: DOB (date input), gender (select male/female/other), address (text), working hours (text), alongside the existing name/specialty(or title).
- Add `updateSelfAssistant` api + `useUpdateSelfAssistant` hook (mirror `updateSelfDoctor`), invalidating `["me"]`, `["assistants", clinicId]`, `["assistants-page", clinicId]`.

### 5e. Cross-cutting
- i18n en+hi parity for all new strings (`team.drawer.*`, field labels, `profile.*` additions, gender options, "coming soon"). Rule 17.0, both themes, mobile-first (the sheet goes full-width on mobile), WCAG AA.
- **Render on :8753** of the drawer (Overview, with/without Edit Profile) + the role-aware profile form — **user sign-off before building**.

## 6. Quality
- Backend: `uv run ruff check .` clean; `make test` green (self-update + read + 404 + 422 tests); migration `0018` via Supabase MCP (controller); implementers validate on local PG :5433.
- Frontend: `tsc --noEmit` + `npm run build` + i18n en/hi parity + e2e (drawer opens from row; Edit Profile only on own row; disabled tabs; owner-only ⋯ Edit; self-edit of new fields). FE PR **held for user QA**.
- Render-before-build sign-off; never merge red; `gh-personal`; **docs work in a git worktree** (a separate designer session shares the docs repo).

## 7. Scope guards / deferred
- **Permissions tab** content → #108 (own design; granular permissions). **Activity tab** content → #109 (audit read API). This slice only renders them disabled.
- No structured address / structured working-hours (free text by decision).
- Owner ⋯ Edit does NOT gain the personal fields (self-service only).
- Doctor availability stays on `/doctors/[id]` (not folded into the drawer).
- No assistant self-CREATE endpoint (assistants are created via invite; only self-UPDATE is added). If a self-create need surfaces, it's a separate item.

## 8. Self-review (against #107 + the mockup)
- New fields DOB/gender/address/working-hours on both members (migration, reads, self-update): §3/§4. ✅
- Slide-in drawer, Overview (Personal + Employment), Permissions/Activity disabled: §5a/§5b. ✅
- Opened from Team row, both entities: §5c. ✅
- Self-service edit (Settings → User Profile, role-aware) + assistant self endpoint (new): §4/§5d. ✅
- Edit Profile only on own row → Settings; owner-only ⋯ Edit (employment/basic only): §2/§5b/§5c. ✅
- New `sheet` primitive (design-system): §5a. ✅
- Drawer ↔ /doctors/[id] availability reconciled (link out): §2/§5b. ✅
- Render-before-build + Rule 17.0 + i18n + tests + docs-worktree: §5e/§6. ✅
- Placeholder scan: concrete fields/endpoints/components/migration number; no TBD. ✅
