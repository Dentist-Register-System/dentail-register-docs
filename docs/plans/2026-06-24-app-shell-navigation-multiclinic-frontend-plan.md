# App-Shell & Navigation Pass — Frontend Plan (#56 + #143)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Add active-clinic switching (#143) + a curated mobile bottom-nav with "More" (#56) in one app-shell pass — without breaking the single-clinic experience.

**Architecture:** An `ActiveClinicProvider` becomes the single source of truth for `clinicId`/`role` (replacing `memberships[0]`); the shell renders an account/clinic menu (Change-clinic card + Sign out) and a role-curated mobile bar + "More" sheet. Switching the active clinic re-scopes the app via clinic-keyed query keys.

**Tech Stack:** Next.js App Router, React+TS, TanStack Query, react-i18next, Tailwind tokens, base-ui `dropdown-menu`/`sheet`, Vitest+RTL, Playwright. Spec: `docs/specs/2026-06-24-app-shell-navigation-multiclinic-design.md`.

## Global Constraints
- **Frontend-only; no backend.** `/me` already returns `memberships[]` with `clinic_id`, `clinic_name`, `role`.
- **Cross-cutting — build as ONE focused pass, AFTER #129/#59/#62/#139 land.** Do not parallelize; expect to touch `app-shell.tsx` + every `memberships[0]` consumer.
- **Rule 17.0** semantic tokens; compose `components/ui/*`; no per-page CSS. Both themes; mobile-first (≤5 bottom items, ≥44px); WCAG AA (keyboard-navigable menu; active by icon+text). i18n en+hi parity (gated).
- `npx tsc --noEmit` + `npm run build` clean per commit. **Render-on-:8753 sign-off before building. FE PR HELD for QA.**

---

### Task 1: Active-clinic context (provider + hook)

**Files:** Create `src/features/clinic/active-clinic.tsx`; Modify `src/app/providers.tsx`; Test `src/features/clinic/__tests__/active-clinic.test.tsx`.

**Interfaces:** `ActiveClinicProvider`, `useActiveClinic(): { clinicId, clinicName, role, memberships, setActiveClinic(id) }`. Seed = localStorage `register.activeClinic` if a valid active membership, else `memberships[0]`; persist on change.

- [ ] **Step 1:** Test: with two memberships, default active = first (or the persisted one if valid); `setActiveClinic` updates `clinicId`/`role`/`clinicName` and persists; a persisted-but-invalid id falls back to the first membership.
- [ ] **Step 2–4:** Implement the provider over `useMe().memberships` + localStorage; `useActiveClinic` reads it. Mount `ActiveClinicProvider` in `providers.tsx` (inside the auth boundary).
- [ ] **Step 5: Commit** `feat(clinic): active-clinic context provider (#143)`.

---

### Task 2: `primaryDestinations` curation helper

**Files:** Modify `src/components/shell/destinations.ts`; Test `__tests__/destinations.test.ts`.

**Interfaces:** `primaryDestinations(role, hasDoctorProfile): string[]` (≤4 keys); the rest are "secondary".

- [ ] **Step 1:** Test per spec §5: owner → `[home, my-schedule, requests, patients]` (my-schedule only if `hasDoctorProfile`, else `clinic-schedules`); assistant → `[home, clinic-schedules, requests, patients]`; doctor → `[home, my-schedule, patients]`.
- [ ] **Step 2–4:** Implement the role→primary mapping; `secondaryDestinations = visible − primary`.
- [ ] **Step 5: Commit** `feat(shell): role-aware primary destinations (#56)`.

---

### Task 3: Account menu + clinic-switcher card

**Files:** Create `src/components/shell/account-menu.tsx`, `clinic-switcher-card.tsx`; Test `__tests__/account-menu.test.tsx`.

**Interfaces:** `<AccountMenu />` (reads `useActiveClinic` + `useMe`); consumes `dropdown-menu`/`sheet`, `supabase.auth.signOut`.

- [ ] **Step 1:** Test: renders avatar+name+current-clinic; opening shows Current clinic (role badge), Change clinic, Sign out; **Change clinic** lists all memberships with role; selecting calls `setActiveClinic`; **switcher hidden when `memberships.length === 1`**; Sign out calls `signOut`.
- [ ] **Step 2–4:** Implement `<AccountMenu>` (button → menu) + `<ClinicSwitcherCard>` (list of `clinic-option-{id}` rows, active marked). i18n `account.*`/`clinic.switch*`; semantic tokens; keyboard-navigable.
- [ ] **Step 5: Commit** `feat(shell): account menu + clinic switcher card (#143)`.

---

### Task 4: Mobile "More" sheet + curated bottom nav

**Files:** Create `src/components/shell/more-sheet.tsx`; Modify `src/components/shell/app-shell.tsx`; Test `__tests__/app-shell-nav.test.tsx`.

- [ ] **Step 1:** Test: mobile bar renders the role's ≤4 primaries + a **More** tab; opening More shows secondary destinations + the account menu; desktop rail still shows all destinations; the requests pending-dot still appears.
- [ ] **Step 2–4:** In `app-shell.tsx`: swap `me.memberships[0]` → `useActiveClinic()`; **desktop rail** bottom = `<AccountMenu>` (replacing the bare sign-out, lines 145–170); **mobile bar** = `primaryDestinations(...)` mapped + a `nav-mobile-more` button → `<MoreSheet>` (secondary destinations + `<AccountMenu>`). App-bar clinic name reads `useActiveClinic().clinicName`.
- [ ] **Step 5: Commit** `feat(shell): curated mobile bottom-nav + More sheet (#56)`.

---

### Task 5: Switch behavior, `memberships[0]` sweep, i18n, e2e

**Files:** Modify all remaining `memberships[0]` consumers (`src/app/page.tsx`, any feature deriving `clinicId` from `/me`); `src/i18n/locales/en.json`+`hi.json`; Test `tests/e2e/clinic-switch.spec.ts`.

- [ ] **Step 1:** `grep -rn "memberships\[0\]" src/` → route each through `useActiveClinic()` (the mechanical sweep). Add i18n keys (`nav.more`, `account.*`, `clinic.switchTitle`, role badges) en+hi; run parity test.
- [ ] **Step 2:** Switch behavior: if a multi-step flow (booking / edit-availability) is open, confirm-discard before `setActiveClinic` (don't carry state across clinics); on switch, invalidate clinic-scoped caches if needed (query keys handle most).
- [ ] **Step 3:** e2e (mock `/me` with two memberships of different roles): switch clinic → app-bar name changes, data refetches, nav curation changes with the new role (e.g. owner→consultant); single-clinic `/me` → no switcher; mid-booking switch prompts discard.
- [ ] **Step 4:** `npx tsc --noEmit && npm run build && npm run test:e2e -- clinic-switch`. **Render on :8753 for sign-off** — account menu + switcher card + mobile More, for a two-clinic owner/consultant (light/dark/mobile). **User sign-off before done.**
- [ ] **Step 5: Commit** `feat(shell): clinic-switch behavior + memberships[0] sweep + i18n (#56, #143)`.

---

## Self-Review (vs spec)
- Active-clinic context replacing `memberships[0]` (+ sweep) → Tasks 1,5. ✅
- Account/clinic menu + Change-clinic card + Sign out; hidden for single-clinic → Task 3. ✅
- Role-curated mobile primaries + More sheet; desktop rail intact → Tasks 2,4. ✅
- Switch re-scopes (query keys) + mid-flow discard + invalid-active fallback → Tasks 1,5. ✅
- i18n/Rule 17.0/themes/a11y/render-before-build/FE-held → Global + Tasks 3,5. ✅
- Type consistency: `useActiveClinic` shape / `primaryDestinations` / `AccountMenu` consistent across tasks. ✅

## README
Update `dentist-registry-frontend/README.md` (active-clinic switching + mobile nav) in the FE PR.
