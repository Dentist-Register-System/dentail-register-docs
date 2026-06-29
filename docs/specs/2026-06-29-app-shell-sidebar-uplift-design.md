# App Shell & Nav — Sidebar Uplift (Design-System Uplift, Phase 1)

**Date:** 2026-06-29
**Status:** Approved (brainstormed)
**Scope:** Frontend-only, visual + structural re-skin of the app shell. **No nav-model
or behavior change.**
**Relates to:** `2026-06-24-app-shell-navigation-multiclinic-design.md` (nav behavior —
unchanged here), `2026-06-26-team-nav-consolidation-design.md` (current nav model),
`dentist-registry-frontend/docs/design-migration.md` (Phase 1), `DESIGN.md` §5
(navigation), Golden Rule §17.0 (the mockups are the approved benchmark), §18.6 (settings
under `/settings`).

## Problem

The live shell (`src/components/shell/app-shell.tsx`) is an **80px icon-stack rail** with
tiny stacked labels. `/impeccable audit` scored it **16/20** (technically clean — detector
0 tells), but `/impeccable critique` scored **27/40**, with the two weak heuristics being
**Consistency (2)** and **Aesthetic (2)**: it reads as a "functional internal tool," not the
premium labeled sidebar the approved mockup (`Mockups/home_final_mockup.png`) sets as the
benchmark. Specific gaps:

- Rail is a cramped 80px icon stack vs the mockup's **wide labeled left sidebar**.
- Clinic identity is exiled to the top bar; the mockup anchors it at the **sidebar top**.
- Active item uses `on-primary-container` (muted) instead of DESIGN.md's confident violet
  `text-primary` + lavender wash.
- Sign-out is a bare top-level nav item (fat-finger risk); the mockup uses an **account
  avatar menu**.
- Theme toggle is Light/Dark only (no **System**) and its targets are 30×34px (**< 44px**,
  fails WCAG 2.2 AA / Golden Rule §17.4).
- Pending requests show a bare color dot, not the **count** the mockup shows, and the count
  is not announced to screen readers.

## Goal

Replace the rail with the mockup's premium labeled sidebar and lift critique heuristics 4
& 8 from 2 → 4, while preserving everything already good (skip link, `aria-current`,
focus-visible rings, structural responsive, token-clean theming).

## Design

### 1. Desktop sidebar (headline)
- **Fixed, always-expanded ~220px labeled left sidebar.** Left-aligned **icon + text** rows
  replacing the 80px vertical stack. No collapse control (audience is non-technical clinic
  staff — "ease over power, earned familiarity").
- **Clinic identity block at the top** — monogram + clinic name, moved out of the top bar.
- **Active item:** lavender-wash pill (`bg-primary-container`) with **violet** icon + text
  (`text-primary`), per DESIGN.md §5. Replaces the off-spec `on-primary-container`.
- **Nav model unchanged** — Home · My Schedule · Clinic Schedules · Today · Requests · Team
  · Patients · Settings, role-filtered exactly as today (`destinations.ts` + the visibility
  logic in `app-shell.tsx` are untouched). Only the rendered *form* changes. The mockup's
  older "Doctors / Assistants" items remain folded into **Team** (per the team-nav
  consolidation).

### 2. Top app bar
- Clinic block leaves it (now in the sidebar).
- Right side gets an **account-avatar menu** (user monogram) owning: **Theme**
  (Light / Dark / **System** segmented — adds the missing System), **Language**, a
  **Settings** link, and **Sign out**. The full appearance/preference controls still live in
  the `/settings` pane (§18.6); the menu is a quick-access surface, not a second home for
  settings.

### 3. Folded-in audit/critique fixes
- **Requests:** render the pending **count** as a badge (mockup shows "3"), and expose it to
  assistive tech (e.g. visually-hidden "N pending requests"), not a color-only dot.
- **Theme controls → ≥44px** touch target.
- Preserve: skip link, `aria-label` on navs, `aria-current`, focus-visible rings, the
  structural rail→bottom-bar responsive switch, semantic tokens only (no hardcoded colors).

### 4. Mobile (minimal — full redesign deferred)
- Keep the existing bottom tab bar. Apply the new active-state tokens for consistency.
- **Remove Sign out from the bottom bar** (the account menu owns it now) — it currently
  crowds the bar as a 5th item.
- **No** hamburger / drawer / "More" overflow work. The full mobile-nav redesign is tracked
  separately (#56) and is explicitly out of scope here.

### Out of scope
Collapsible sidebar; full mobile-nav redesign (#56); per-screen content (Phase 3); core
primitives — button/input/badge/avatar (Phase 2); any backend or nav-behavior change.

## Components touched
- `src/components/shell/app-shell.tsx` — restructure (sidebar + top bar).
- New: account-avatar menu component (+ a shared theme/language quick-control if it cleanly
  factors out of the existing `theme-toggle.tsx`).
- `src/components/theme-toggle.tsx` — add **System**, bump targets to ≥44px (or supersede it
  inside the account menu).
- `destinations.ts` — **unchanged** (model is correct).

## Verification / success criteria
- `npx tsc --noEmit` clean; `npm run build` green (CI parity).
- WCAG 2.2 AA contrast **math-checked** in **both** themes (active violet on lavender wash,
  muted ink, account menu).
- All interactive targets ≥ 44px (theme controls included).
- Structural responsive verified: sidebar on `md+`, bottom bar below.
- Existing Playwright theme suite green; nav `data-testid`s preserved so E2E keeps passing.
- `prefers-reduced-motion` honored on any added transition.
- `/impeccable audit` + `critique` re-run after build; target critique ≥ 34/40 (Consistency
  & Aesthetic → 4), then `/impeccable polish`.
- Live-browser pass across themes/breakpoints when feasible (otherwise on beta during QA —
  the standing deferred item).

## Non-goals / risk notes
- Pure re-skin: no business logic, no API, no migration. Backend leads nothing here.
- Keep every `data-testid` (`nav-{key}`, `nav-mobile-{key}`, `signout-*`, `theme-*`) stable
  or update the E2E suite in lockstep — the QA/gatekeeper session owns that suite.
