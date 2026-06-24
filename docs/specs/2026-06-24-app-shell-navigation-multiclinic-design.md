# App-Shell & Navigation Pass — Mobile Bottom-Nav + Multi-Clinic Switcher — Design Spec (#56 + #143)

**Status:** Approved in brainstorm (2026-06-24). Delivers **#56** (mobile bottom-nav curation) **and #143** (active-clinic / workspace switcher) as **one coherent app-shell pass** — both touch `src/components/shell/app-shell.tsx`, so build the shell **once**. **Frontend-only; backend ≈ ready** (already `clinic_id`-scoped; `/me` returns `memberships[]` with `clinic_name` + `role`). Register Design System, i18n-first. **Cross-cutting — not parallelizable; BUILD after the core-loop FE redesigns (#129/#59/#62/#139) land**, onto a stable shell.

**Type:** Restructure the app shell so (a) a multi-clinic user can switch the **active clinic** and the whole app re-scopes, and (b) the mobile bottom nav is a curated set of primary destinations + a "More" overflow.

---

## 1. Goal
- **#143:** a user who belongs to multiple clinics (owns one, consults at another) can **switch the active clinic**; the app then shows that clinic's data + the user's role *there*. This is **active-clinic (workspace) switching on the existing multi-tenancy** — not new multi-tenancy.
- **#56:** the mobile bottom nav currently crams **all 8 destinations + sign-out** into the bar (`app-shell.tsx:182–258`). Curate to ~4 role-appropriate primaries + a **"More"** overflow.

## 2. Scope decisions (locked in brainstorm 2026-06-24)
- **Active-clinic context** replaces the `memberships[0]` assumption (`app-shell.tsx:31,35` and everywhere a `clinicId`/`role` is derived).
- **Account/clinic menu** (bottom-left desktop / inside "More" on mobile): current clinic + **Change clinic** (clinics card) + **Sign out**.
- **Mobile bottom nav** = ~4 **role-curated** primaries + **"More"** sheet (secondary destinations + account/clinic menu). Sign-out moves out of the cramped bar into the account menu.
- **Switch behavior:** re-scope all clinic-keyed queries; **reset in-progress flows**; update the app-bar clinic name. **Single-clinic user → no switcher.**
- **Backend ≈ none.** *(Optional, deferred: persist "last active clinic" server-side — localStorage suffices for V1.)*
- **Build sequencing:** one focused shell pass, **after** #129/#59/#62/#139; cross-cutting, not parallelizable.

## 3. Active-clinic context (#143)
- `src/features/clinic/active-clinic.tsx` — `ActiveClinicProvider` + `useActiveClinic()` returning `{ clinicId, clinicName, role, memberships, setActiveClinic(clinicId) }`.
- **Seed:** from `useMe().memberships`; initial active = `localStorage["register.activeClinic"]` **if it's still a valid active membership**, else the first membership. Persist on change.
- **Mount** the provider high (e.g. in `providers.tsx` or the authed shell) so every screen reads the same active clinic.
- **Replace** every ad-hoc `me.memberships[0]?.clinic_id` / `role` derivation (starting with `app-shell.tsx:31,35`, `src/app/page.tsx`, and any feature that computes `clinicId` from `/me`) with `useActiveClinic()`. *(Audit the FE for `memberships[0]` — that's the mechanical sweep.)*
- Because all TanStack Query keys are `["…", clinicId]`, changing `clinicId` **auto-refetches** the new clinic's data.

## 4. Account / clinic menu (#143)
- `src/components/shell/account-menu.tsx` — an **account button** (avatar initials + the user's name + current clinic name + chevron) opening a menu (reuse `dropdown-menu` / `sheet`):
  - **Current clinic** — name + the user's **role badge** for it.
  - **Change clinic** → a **clinics card/sheet** listing **all** `memberships` (clinic name + the user's role there); the active one marked; selecting one calls `setActiveClinic` and closes. Hidden when `memberships.length === 1`.
  - **Sign out** (moves here from the bare rail/bar buttons).
- **Desktop:** replaces the bottom-of-rail sign-out (`app-shell.tsx:145–170`). **Mobile:** rendered inside the "More" sheet (§5).
- testids: `account-menu`, `change-clinic`, `clinic-option-{clinicId}`, `signout`.

## 5. Mobile bottom-nav curation + "More" (#56)
- A role-aware `primaryDestinations(role, hasDoctorProfile)` returns ≤4 keys; the rest go to "More".

| Role | Primary (bottom bar, + More) | "More" sheet |
|---|---|---|
| **Owner** (incl. owner-doctor) | Home · My Schedule\* · Requests · Patients | Clinic Schedules, Doctors, Assistants, Settings, **account/clinic** |
| **Assistant** | Home · Clinic Schedules · Requests · Patients | Doctors, Assistants, Settings, **account/clinic** |
| **Doctor** (non-owner) | Home · My Schedule · Patients | Settings, **account/clinic** |

\*My Schedule shown only with a linked doctor profile (existing rule); if absent, fill the slot with Clinic Schedules. My Schedule ≠ Clinic Schedules stay distinct (Rule 18.2).
- The 5th bottom-nav slot is **"More"** (icon `more_horiz`) → opens a **sheet** listing the secondary destinations (same row style) **followed by the account/clinic menu** (§4) incl. Sign out.
- The **desktop rail keeps all destinations** (vertical room); only mobile curates. The `requests` pending-dot stays.
- testids: `nav-mobile-more`, `more-sheet`, `more-dest-{key}`.

## 6. Switch behavior + edge cases
- On `setActiveClinic`: persist; if a multi-step flow is open (booking, edit-availability), **confirm/discard** before switching (don't carry state across clinics); after switch, the app-bar clinic name + nav curation + role-scoped screens (#62/#108) all update from the new role — for free.
- **Active clinic invalid** (user removed/deactivated there) → fall back to the first valid membership + a toast.
- **Onboarding / no-clinic** users: provider yields no active clinic → existing onboarding path unaffected.

## 7. Frontend files
- New: `src/features/clinic/active-clinic.tsx` (provider/hook), `src/components/shell/account-menu.tsx`, `src/components/shell/more-sheet.tsx`, `src/components/shell/clinic-switcher-card.tsx`.
- Modify: `src/components/shell/app-shell.tsx` (consume `useActiveClinic`; rail bottom = account-menu; mobile bar = curated primaries + More), `src/app/providers.tsx` (mount provider), `src/app/page.tsx` + any `memberships[0]` consumers.
- Add `primaryDestinations()` to `src/components/shell/destinations.ts`.

## 8. Cross-cutting
- **i18n** en+hi (`nav.more`, `account.*`, `clinic.switch*`, role badges) — gated; no hardcoded strings.
- **Rule 17.0** (semantic tokens, compose `components/ui/*`, no per-page CSS); both themes; **mobile-first** (≤5 bottom items, ≥44px); WCAG AA (active state by icon+text; menu keyboard-navigable). **Render-on-:8753 sign-off; FE held for QA.**

## 9. Tests
- **Unit:** `primaryDestinations(role,…)` returns the right ≤4 per role; active-clinic seed/persist/validate (invalid → fallback).
- **Component:** account menu renders clinics with roles, hides switcher for single-clinic, `setActiveClinic` updates context; More sheet lists secondary destinations + account.
- **e2e:** a two-clinic user switches clinic → the app re-scopes (clinic name + data + role-appropriate nav change, e.g. owner→consultant loses Settings/Team primaries); mobile shows 4 primaries + More; single-clinic user sees no switcher; switching mid-booking prompts discard.

## 10. Scope guards / deferred
- **No new multi-tenancy** (already exists); **no backend** (optional server-side last-clinic deferred). Build **after** the core-loop FE redesigns. Multi-clinic *data merging* (cross-clinic views) explicitly **out** — one active clinic at a time.

## 11. Self-review
- Active-clinic context replacing `memberships[0]`; switch re-scopes via query keys: §3/§6. ✅
- Account/clinic menu (desktop bottom-left + mobile More) with Change-clinic card + Sign out: §4. ✅
- Mobile curation ≤4 role-aware + More (Rule 18.2 preserved): §5. ✅
- Single-clinic → no switcher; invalid-active fallback; mid-flow discard: §6. ✅
- Backend ≈ none; delivers BOTH #56 + #143; build-after-FE, not parallelizable: §2/§8. ✅
- i18n/Rule 17.0/themes/a11y/render-before-build/FE-held: §8. ✅
- Placeholder scan: concrete files/hooks/curation table/tests; the `memberships[0]` audit is the one mechanical sweep, called out. ✅
