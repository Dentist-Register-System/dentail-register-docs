# Member Profile Drawer (#107) — Frontend Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A slide-in member profile drawer (Overview live; Permissions/Activity disabled) opened from the Team table, the four new fields end-to-end, self-service editing via a role-aware Settings → User Profile pane, and owner-only ⋯ Edit.

**Architecture:** New `sheet` primitive (base-ui dialog, right-anchored) → `<MemberProfileDrawer>`. The Team table opens the drawer on row click and becomes user-aware (owner-only ⋯ Edit). Settings → Profile pane becomes role-aware (doctor OR assistant self-edit) and gains the four fields. Consumes the backend's new reads + `PATCH /assistants/me` + `me.assistant_id`.

**Tech Stack:** Next.js App Router, TanStack Query, react-hook-form + zod, Tailwind v4 semantic tokens, `@base-ui/react`, react-i18next.

## Global Constraints
- Spec: `docs/specs/2026-06-23-member-profile-drawer-design.md`. Frontend half of #107. Backend (merged) provides the 4 fields on `Doctor`/`Assistant` reads, `PATCH /clinics/{id}/assistants/me` (`AssistantRead`), and `me.assistant_id`.
- **Rule 17.0:** semantic tokens only, compose `components/ui/*`, no raw colors; the `sheet` primitive must match the design system (M3 surface/elevation, like `dropdown-menu`/`dialog`). Both themes.
- **Edit model:** profile editing is self-service (Settings → User Profile). The drawer's **Edit Profile** shows ONLY when `member.linked_user_id === me.user_id`. Owner-only ⋯ Edit (employment/basic fields) stays via EditMemberDialog. Personal fields are never edited via ⋯ Edit.
- i18n en/hi parity (gate `tests/e2e/i18n.spec.ts`). Render-before-build on :8753 (drawer + role-aware pane) before Task 3.
- CI = tsc + build; e2e local. FE PR held for user QA. `find .next -name "* [0-9].*" -delete` if iCloud dups break the build.

## File Structure
- Create: `src/components/ui/sheet.tsx`, `src/features/team/member-profile-drawer.tsx`.
- Modify: `src/features/doctors/api.ts`, `src/features/assistants/api.ts` + `hooks.ts` (types + assistant self + useAssistant), `src/features/clinic/api.ts` (Me type), `src/features/team/team-table.tsx`, `src/features/settings/profile-pane.tsx`, `src/i18n/locales/*`.
- Test: `tests/e2e/member-drawer.spec.ts`.

---

### Task 1: `sheet` primitive

**Files:** Create `src/components/ui/sheet.tsx`

**Interfaces:** `Sheet`, `SheetTrigger`, `SheetContent`, `SheetClose` wrapping `@base-ui/react/dialog` anchored right. Mirror `dialog.tsx`'s wrapper conventions exactly (read it first).

- [ ] **Step 1:** Read `src/components/ui/dialog.tsx`. Build `sheet.tsx` (`"use client"`): `Sheet`=Dialog.Root, `SheetTrigger`=Dialog.Trigger, `SheetClose`=Dialog.Close, `SheetContent`=Portal+Backdrop+Popup, the Popup anchored to the right edge, full height, `w-full sm:max-w-md`, slide-in via `data-[starting-style]:translate-x-full` / `data-[ending-style]:translate-x-full` + a backdrop fade. Tokens only: `bg-card text-card-foreground border-l border-border shadow-elevation-4`; backdrop `bg-overlay`. Include a scrollable body wrapper (`overflow-y-auto`).

```tsx
"use client";
import * as React from "react";
import { Dialog as DialogPrimitive } from "@base-ui/react/dialog";
import { cn } from "@/lib/utils";

function Sheet(props: DialogPrimitive.Root.Props) { return <DialogPrimitive.Root {...props} />; }
function SheetTrigger(props: DialogPrimitive.Trigger.Props) { return <DialogPrimitive.Trigger data-slot="sheet-trigger" {...props} />; }
function SheetClose(props: DialogPrimitive.Close.Props) { return <DialogPrimitive.Close data-slot="sheet-close" {...props} />; }
function SheetContent({ className, children, ...props }: DialogPrimitive.Popup.Props) {
  return (
    <DialogPrimitive.Portal>
      <DialogPrimitive.Backdrop className="fixed inset-0 z-40 bg-overlay transition-opacity data-[starting-style]:opacity-0 data-[ending-style]:opacity-0" />
      <DialogPrimitive.Popup
        data-slot="sheet-content"
        className={cn(
          "fixed inset-y-0 right-0 z-50 flex h-full w-full max-w-md flex-col",
          "border-l border-border bg-card text-card-foreground shadow-elevation-4 outline-none",
          "transition-transform duration-300 data-[starting-style]:translate-x-full data-[ending-style]:translate-x-full",
          className,
        )}
        {...props}
      >
        {children}
      </DialogPrimitive.Popup>
    </DialogPrimitive.Portal>
  );
}
export { Sheet, SheetTrigger, SheetClose, SheetContent };
```

> Verify base-ui Dialog part names + the `data-starting-style`/`data-ending-style` attrs against the installed version (same source dialog.tsx uses). Confirm `bg-overlay` token exists in globals.css; if not, use the same backdrop class dialog.tsx uses.

- [ ] **Step 2:** `tsc --noEmit` clean. Commit `feat(ui): sheet primitive (right-anchored, design-system)`.

---

### Task 2: Data layer — types + assistant self + useAssistant

**Files:** Modify `src/features/doctors/api.ts`, `src/features/assistants/api.ts` + `hooks.ts`, `src/features/clinic/api.ts`

**Interfaces:**
- `Doctor` + `Assistant` types gain `date_of_birth: string | null; gender: string | null; address: string | null; working_hours: string | null`.
- `Me` type (clinic/api.ts) gains `assistant_id: string | null`.
- `updateSelfAssistant(clinicId, payload)` → `PATCH /clinics/{id}/assistants/me`; `useUpdateSelfAssistant(clinicId)` (invalidates `["me"]`, `["assistants", clinicId]`, `["assistants-page", clinicId]`, `["assistant", clinicId]`).
- `fetchAssistant(clinicId, id)` + `useAssistant(clinicId, id)` (mirror `fetchDoctor`/`useDoctor`) so the profile pane can pre-fill an assistant's own record.
- Extend `DoctorSelfUpdate` payload type for `updateSelfDoctor` to include the 4 fields.

- [ ] **Step 1:** Add the 4 fields to `Doctor` (doctors/api.ts) and `Assistant` (assistants/api.ts) types. Add `assistant_id: string | null` to `Me` (clinic/api.ts).
- [ ] **Step 2:** assistants/api.ts: `fetchAssistant`, `updateSelfAssistant(clinicId, payload: {name?;phone?;title?;date_of_birth?;gender?;address?;working_hours?})`. assistants/hooks.ts: `useAssistant`, `useUpdateSelfAssistant` (invalidations above). doctors/api.ts: extend `updateSelfDoctor`'s payload type with the 4 fields.
- [ ] **Step 3:** `tsc --noEmit` clean. Commit `feat(team): member profile types + assistant self-update + useAssistant`.

---

### Task 3: `<MemberProfileDrawer>`  *(render-gated)*

> **Render gate:** controller serves the :8753 render and gets user sign-off before this task.

**Files:** Create `src/features/team/member-profile-drawer.tsx`

**Interfaces:** `<MemberProfileDrawer kind={"doctor"|"assistant"} member open onOpenChange me />` where `me` carries `user_id`. Uses `<Sheet>`.

- [ ] **Step 1:** Build it: `<Sheet open onOpenChange>` → `<SheetContent>`:
  - Header: avatar initials, name, role chip (specialty/title), status badge, `SheetClose` (X).
  - Tabs (`components/ui/tabs`): Overview (active) · Permissions (disabled) · Activity (disabled) — disabled via the tab's `disabled` prop + a "coming soon" affordance. testids `drawer-tab-overview/permissions/activity`.
  - Overview: "Personal Information" Card (Email · Phone · Date of birth[Intl format] · Gender[capitalized] · Address — each `—` when null) + "Employment Information" Card (Joined on=created_at · Role=specialty/title · Working hours).
  - **Edit Profile** button — ONLY when `member.linked_user_id && member.linked_user_id === me.user_id` → `router.push("/settings?pane=profile")` (deep-link to the User Profile pane; see Task 5 for the param). testid `drawer-edit-profile`.
  - Doctors only: **Manage availability** link → `/doctors/${member.id}`. testid `drawer-manage-availability`.
  - testid `member-profile-drawer`. Rule 17.0 tokens; strings via `t("team.drawer.*")` (add in Task 6).
- [ ] **Step 2:** `tsc --noEmit` clean. Commit `feat(team): member profile drawer (Overview)`.

---

### Task 4: Team-table opens drawer + owner-only ⋯ Edit

**Files:** Modify `src/features/team/team-table.tsx` (+ thin wrappers if they pass new props)

- [ ] **Step 1:** Pull current-user context via `useMe()` inside TeamTable: `meUserId = me.user_id`, `myRole = me.memberships[0].role`. Render one `<MemberProfileDrawer>` controlled by `openMember` state.
- [ ] **Step 2:** Row click (the name cell) opens the drawer for that member (set `openMember`), for BOTH doctors & assistants — replacing the doctor name→`/doctors/[id]` link from #106 (the "Manage availability" link inside the drawer now serves that).
- [ ] **Step 3:** ⋯ menu gating: show the **Edit** item only when `myRole === "owner"`; show **Activate/Deactivate/Remove** only when the current user may manage this entity per #91 (owner always; assistant only on the Doctors table — i.e. `config.kind === "doctor" && myRole === "assistant"`, plus owner). Pass `me`/role down via props or read `useMe` in the table.
- [ ] **Step 4:** `tsc --noEmit` + `npm run build` clean. Commit `feat(team): row opens profile drawer + owner-only edit`.

---

### Task 5: Role-aware Settings → User Profile pane + new fields

**Files:** Modify `src/features/settings/profile-pane.tsx` (+ settings-shell deep-link param if needed)

- [ ] **Step 1:** Make the pane role-aware. Today it uses `me.doctor_id` + `useDoctor`/`useUpdateSelfDoctor`. Add the assistant branch: when `me.assistant_id` is set, use `useAssistant(clinicId, me.assistant_id)` + `useUpdateSelfAssistant`. Compute `member = doctor ?? assistant`. Editing name still goes through `useUpdateSelfProfile`; the role/title + the 4 new fields go through the matching self-update hook.
- [ ] **Step 2:** Extend the form + read-view with the 4 fields: Date of birth (date input), Gender (select male/female/other), Address (text), Working hours (text). For a doctor keep specialty/license; for an assistant show title instead of specialty. Persist via the role's self-update hook.
- [ ] **Step 3:** Deep-link: ensure `/settings?pane=profile` selects the Profile pane (the drawer's Edit Profile links here). Read how `settings-shell.tsx` selects panes; if it's local state only, add support for an initial `?pane=` query param (via `useSearchParams`, Suspense-wrapped) defaulting to the existing default. testid on the pane already `settings-profile`.
- [ ] **Step 4:** `tsc --noEmit` + `npm run build` clean. Commit `feat(settings): role-aware profile pane + dob/gender/address/working-hours self-edit`.

---

### Task 6: i18n (en+hi) + e2e

**Files:** Modify `src/i18n/locales/en.json`, `hi.json`; Create `tests/e2e/member-drawer.spec.ts`

- [ ] **Step 1:** Add all new keys in BOTH locales in parity: `team.drawer.*` (personalInfo, employmentInfo, dateOfBirth, gender, address, workingHours, editProfile, manageAvailability, comingSoon, tabs.overview/permissions/activity), `settings.profile.*` additions (dateOfBirth, gender, address, workingHours, genderOptions), gender option labels. Run `npx playwright test tests/e2e/i18n.spec.ts` → green.
- [ ] **Step 2:** `tests/e2e/member-drawer.spec.ts` (mock backend per test-env.ts): row click opens `member-profile-drawer`; Overview shows the fields; Permissions/Activity tabs are disabled; **Edit Profile present only on the current user's own row** (mock `me.user_id` to match one member's `linked_user_id`, assert it's absent on others); owner-only ⋯ Edit (assert non-owner doesn't see `team-edit`). Also a settings test: an assistant self-edits a new field via the profile pane (mock `me.assistant_id` + `PATCH /assistants/me`). Run green.
- [ ] **Step 3:** `tsc --noEmit` + `npm run build` + the i18n gate clean. Commit `test(team): member drawer e2e + i18n en/hi parity`.

---

## Self-Review (against the spec)
- §5a sheet primitive (base-ui dialog, right-anchored, tokens): Task 1. ✅
- §5b drawer Overview (Personal+Employment), disabled Permissions/Activity, Edit Profile self-only→settings, doctor manage-availability: Task 3. ✅
- §5c row opens drawer (both), owner-only ⋯ Edit + #91 management gating: Task 4. ✅
- §5d role-aware profile pane + 4 fields + assistant self hooks + `?pane=profile` deep-link: Tasks 2/5. ✅
- §4 types + `me.assistant_id` consumed: Task 2. ✅
- §5e i18n en/hi + render-before-build + e2e: Task 6 + render gate. ✅
- Type consistency: field names match backend (`date_of_birth`/`gender`/`address`/`working_hours`); `useAssistant`/`useUpdateSelfAssistant` mirror doctor hooks; `me.assistant_id` used in Task 5. ✅
- Rule 17.0 emphasized (sheet + drawer tokens only). ✅
- Placeholder scan: concrete files/props/code/testids; the one "verify base-ui parts / ?pane support" notes are concrete verifications, not TBDs. ✅
