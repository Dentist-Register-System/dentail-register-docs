# Material 3 UI Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Re-skin the frontend into a Material 3 visual language and stand up a reusable UI framework (AppShell + layout primitives + page templates + component library + `/design-system` showcase) so the auth/onboarding screens match the reference and all future screens plug in seamlessly.

**Architecture:** Keep the stack (Next.js App Router + Tailwind v4 + shadcn/ui primitives + `next-themes`); replace the *aesthetic* by swapping the token set to M3, adding Roboto + Material Symbols, restyling components, and adding a framework layer (`shell/`, `layout/`, `templates/`). No business-logic changes.

**Tech Stack:** Next.js (App Router) + TypeScript, Tailwind v4, shadcn/ui, next-themes, react-i18next, `next/font` (Roboto Flex), Material Symbols (Rounded), Playwright + Vitest.

**Spec:** `docs/specs/2026-06-18-ui-redesign-m3-design.md` (authoritative for token values, type scale, component list, reference look). The **reference mockups in the UI brief are the visual standard** — match them.

## Global Constraints
- Repo: `~/Documents/register_workspace/dentist-registry-frontend`; one feature branch per task-group; never push to main; PRs via `gh-personal`.
- **Semantic tokens only** — no raw colours / Tailwind palette utilities in components; use the M3 token utilities. Light/Dark/System all designed (`next-themes`).
- **i18n-first** — all strings via `t()`; new keys in BOTH `en.json` and `hi.json` (parity enforced by `tests/e2e/i18n.spec.ts`). No hardcoded copy.
- **a11y** — WCAG 2.1 AA contrast in both themes; focus-visible rings always; 44px touch targets; Material Symbols paired with text or `aria-label`; honor `prefers-reduced-motion`.
- **Mobile-first**; nav-rail (≥`md`) / bottom-nav (mobile). Match the reference for spacing, elevation, radius, pastel surfaces.
- No new heavy deps beyond `next/font` (built-in) + a Material Symbols icon source (permissive). No business-logic/API changes. CI = `tsc --noEmit` + `npm run build` (must stay green); Playwright e2e local. Read `AGENTS.md` (the Next.js docs note).
- **Token values, type scale, elevation, radii, and the M3 color table are in spec §3** — use those exact values.

---

### Task 1: M3 tokens + Roboto + Material Symbols (foundation)

**Files:**
- Modify: `src/app/globals.css` (replace token values with the M3 set; add container/surface/outline/hero roles; radii 12px default; elevation 0–5; motion)
- Modify: `src/app/layout.tsx` (load Roboto Flex via `next/font`; wire `--font-sans`)
- Modify: `package.json` (add `@fontsource-variable/...` not needed — use next/font; add Material Symbols source, e.g. `material-symbols` SVG package OR the icon font `<link>` — choose the SVG/icon approach in this task)
- Create: `src/components/ui/icon.tsx` (a thin `<Icon name=… />` wrapper over Material Symbols Rounded)
- Test: extend `tests/e2e/theme.spec.ts` (new tokens present in light + dark)

**Interfaces:**
- Produces: the full M3 token set as CSS vars + Tailwind utilities (`bg-primary-container`, `text-on-primary-container`, `bg-surface-variant`, `shadow-[var(--elevation-2)]`, `rounded-lg` = 16px, etc.); `<Icon name="add" />` component; Roboto applied app-wide.

- [ ] **Step 1: Load Roboto Flex** — in `layout.tsx`, `import { Roboto_Flex } from "next/font/google"`, instantiate with `variable: "--font-sans"`, weights/axes as needed, apply the variable class to `<html>`. Remove Geist.
- [ ] **Step 2: Material Symbols** — add a permissive Material Symbols source (Rounded). Recommended: the icon font via a self-hosted `@fontsource` or the `material-symbols` package; create `src/components/ui/icon.tsx` exposing `<Icon name="..." filled? size? />` that renders the symbol with `aria-hidden` (or `aria-label` when standalone). Verify license is OSS (Apache-2.0 — safe).
- [ ] **Step 3: Rewrite `globals.css` token values to M3** — using spec §3.1 (color table, both themes), §3.3 (radius `md`=12px default, `lg`=16px, `xl`=24px; elevation `--elevation-0..5`; motion easings). Keep existing token NAMES (`--background`, `--card`, `--primary`, `--muted`, `--border`, `--input`, `--ring`, state colors) and ADD the M3 roles (`--primary-container`/`--on-primary-container`, `--secondary-container`, `--tertiary-container`, `--surface-variant`, `--outline`, `--hero-from`/`--hero-to`). Map all new vars in the `@theme inline` block so Tailwind utilities exist. Set `--radius` to `0.75rem` (12px).
- [ ] **Step 4: Verify** — `cp .env.local.example .env.local && npx tsc --noEmit && npm run build` clean; run the app, toggle Light/Dark/System — tokens flip, no console errors. Existing screens will look transitional (that's fine; later tasks restyle them).
- [ ] **Step 5: Theme test + commit** — extend `tests/e2e/theme.spec.ts` to assert a couple of new M3 vars resolve in both themes (e.g. `--primary-container`, `--surface-variant`). Run `npm run test:e2e -- theme.spec.ts`. Commit: `feat(ui): M3 token set + Roboto Flex + Material Symbols foundation`.

> The exact globals.css is mechanical transcription of spec §3.1/§3.3 values into the existing file's structure (`:root`, `.dark`, `@theme inline`). Preserve the `@layer base` + reduced-motion block.

---

### Task 2: Core M3 components + `/design-system` showcase (start)

**Files:**
- Modify: `src/components/ui/{button,input,card,badge,tabs}.tsx`; Create: `src/components/ui/{text-field,chip,segmented.tsx}` as needed
- Create: `src/app/design-system/page.tsx` (showcase) + `src/features/design-system/` sections
- Test: `tests/e2e/design-system.spec.ts` (renders in light + dark)

**Interfaces:**
- Consumes: Task 1 tokens + `<Icon>`.
- Produces: M3-styled Button (`filled` default, `tonal`, `outlined`, `text`, `fab`; icon support), M3 TextField (filled + outlined, label/helper/error), Card/Tile, Chip, Badge, Tabs/Segmented — all token-only, both themes. `/design-system` route rendering them.

- [ ] **Step 1: Button** — restyle `button.tsx` to M3 variants: `filled` (bg-primary, on-primary, elevation-1, rounded-full or 12px), `tonal` (bg-secondary-container/on-secondary-container), `outlined` (border-outline), `text`, plus `fab` (circular, bg-primary-container, elevation-3) and optional leading `<Icon>`. 44px min height. Keep the existing `variant`/`size` API additive so current usages don't break (map old `default`→`filled`, `outline`→`outlined`, `ghost`→`text`, `destructive` retained).
- [ ] **Step 2: TextField** — M3 filled + outlined text field (floating or fixed label, helper/error text, leading/trailing icon). Provide as `text-field.tsx`; keep `input.tsx` working (wrap or restyle). Used by forms via RHF.
- [ ] **Step 3: Card/Tile, Chip, Badge, Tabs/Segmented** — M3 styling: cards `rounded-lg` (16px) + `--elevation-1`, surface-container bg; chips (assist/filter); badges (tonal container colors per status); tabs (primary underline + secondary), segmented button for the auth Phone/Email + onboarding Create/Join.
- [ ] **Step 4: `/design-system` showcase** — a route rendering each component with all variants/states, plus a **token panel** (color swatches, type scale, elevation samples, radii). Include the theme + locale switchers on the page. All labels via `t()` (add a `designSystem.*` key namespace to en/hi).
- [ ] **Step 5: Verify + commit** — `npx tsc --noEmit && npm run build` clean; `npm run test:e2e -- design-system.spec.ts i18n.spec.ts` (showcase renders light+dark; parity holds). Match the reference's button/field/card feel. Commit: `feat(ui): M3 core components + design-system showcase (controls)`.

---

### Task 3: Structural M3 components (nav, overlays, data) + extend showcase

**Files:**
- Create/Modify: `src/components/ui/{app-bar,nav-rail,bottom-nav,dialog,sheet,snackbar,list,table,skeleton,empty-state,error-state}.tsx`
- Modify: `src/app/design-system/page.tsx` (add these sections)
- Test: extend `tests/e2e/design-system.spec.ts`

**Interfaces:**
- Consumes: Task 1 tokens, Task 2 components, `<Icon>`.
- Produces: App bar, Navigation rail (web) + Bottom nav (mobile) bound to a destinations config, Dialog (M3), Bottom Sheet/Drawer, Snackbar/toast, List, Table, Skeleton, Empty + Error states — token-only, both themes, responsive.

- [ ] **Step 1: Nav** — `app-bar.tsx` (title slot + trailing actions), `nav-rail.tsx` (icon+label, active = primary-container pill indicator), `bottom-nav.tsx` (≤5 destinations, active tint). Driven by a `destinations` array (icon, labelKey, href). `aria-current` on active; arrow-key nav; 44px targets.
- [ ] **Step 2: Overlays** — restyle `dialog.tsx` (M3: surface-container, rounded-xl, elevation-3, action row), add `sheet.tsx` (bottom sheet, drag affordance, mobile-primary), `snackbar.tsx` (toast; success/info/error variants with left state color).
- [ ] **Step 3: Data + states** — restyle `table.tsx`/`list.tsx` (M3 rows, hover via surface-variant, selected via primary-container), `skeleton.tsx`, `empty-state.tsx` (icon + title + body + action), `error-state.tsx` (`role="alert"`). All copy via `t()`.
- [ ] **Step 4: Showcase + verify + commit** — add sections for all of the above to `/design-system` (light+dark). `npx tsc --noEmit && npm run build` clean; `npm run test:e2e -- design-system.spec.ts`. Commit: `feat(ui): M3 nav/overlay/data components + showcase`.

---

### Task 4: Framework — AppShell + layout primitives + page templates

**Files:**
- Create: `src/components/shell/app-shell.tsx`, `src/components/shell/destinations.ts`
- Create: `src/components/layout/{page-container,page-header,section,card-grid}.tsx`
- Create: `src/components/templates/{list-page-template,detail-page-template,form-page-template,auth-layout}.tsx`
- Test: `tests/e2e/app-shell.spec.ts`

**Interfaces:**
- Consumes: Task 2 + Task 3 components.
- Produces:
  - `<AppShell>{children}</AppShell>` — app bar + nav-rail(≥md)/bottom-nav(mobile) + centered max-width content; reads `destinations.ts`; shows theme/locale/profile in the app bar.
  - `<PageContainer>`, `<PageHeader title actions>`, `<Section>`, `<CardGrid>`.
  - `<ListPageTemplate header search children empty>`, `<DetailPageTemplate>`, `<FormPageTemplate>`, `<AuthLayout hero>{form}</AuthLayout>` (split desktop / stacked mobile).

- [ ] **Step 1: AppShell** — implement the responsive chrome (nav-rail on `md+`, bottom-nav on mobile, app bar with brand + theme/locale switchers + profile menu, centered content with max-width + gutters from spec). `destinations.ts` seeded with the real destinations that exist (Home, Doctors) — extensible. `<nav aria-label>`, skip-link.
- [ ] **Step 2: Layout primitives** — `PageContainer` (max-width, responsive padding, vertical rhythm), `PageHeader` (Title Large + optional description + actions row), `Section`, `CardGrid` (responsive columns).
- [ ] **Step 3: Templates** — compose primitives + components into the four templates. `AuthLayout` renders the hero (gradient `--hero-from→to`, app icon, headline/sub) + form card; split on `md+`, stacked + icon-on-top on mobile (match reference).
- [ ] **Step 4: Verify + commit** — render a throwaway page (or a showcase section) inside `AppShell` + each template to confirm composition; `npx tsc --noEmit && npm run build` clean; `tests/e2e/app-shell.spec.ts` asserts nav-rail on desktop viewport and bottom-nav on mobile viewport, active state, and that content is centered. Commit: `feat(ui): AppShell + layout primitives + page templates`.

---

### Task 5: Rebuild Login + Onboarding to the reference

**Files:**
- Modify: `src/features/auth/login-form.tsx`, `src/app/login/page.tsx`, `src/features/auth/onboarding.tsx`
- Modify: `src/i18n/locales/en.json`, `hi.json` (any new copy: hero headline/sub, trust bullets)
- Test: update `tests/e2e/auth.spec.ts`, `tests/e2e/signup.spec.ts`

**Interfaces:**
- Consumes: `AuthLayout`, M3 Button/TextField/Segmented/Tabs, `<Icon>`.

- [ ] **Step 1: Login** — wrap `/login` in `AuthLayout`: hero (left on desktop, top on mobile) + form card with Phone/Email **segmented tabs**, M3 text fields, **filled** Continue, and the existing email Create-account/Sign-in toggle + confirmation-pending panel (restyled as an M3 card). Preserve ALL existing behavior, testids, and Supabase calls — only the presentation changes. Add hero copy keys (`auth.hero.title`, `auth.hero.subtitle`, `auth.hero.bullets.*`) to en/hi.
- [ ] **Step 2: Onboarding** — render inside `AuthLayout` (or its own centered card): "Welcome! Set up your clinic" with **Create a new clinic** / **I have an invite** as a segmented control or two M3 tiles, M3 fields, filled primary. Preserve behavior + testids.
- [ ] **Step 3: Verify + commit** — `npx tsc --noEmit && npm run build` clean; update + run `tests/e2e/auth.spec.ts signup.spec.ts i18n.spec.ts` green (logic identical; selectors updated for new structure). Visually match the reference (split card + hero desktop; stacked mobile). Commit: `feat(ui): rebuild login + onboarding on M3 AuthLayout`.

---

### Task 6: Re-skin shipped screens (clinic shell + doctors) into the framework

**Files:**
- Modify: `src/app/page.tsx` (HomeShell → render inside `<AppShell>`)
- Modify: `src/features/doctors/{doctor-list,add-doctor-dialog}.tsx`, `src/app/doctors/page.tsx`
- Test: update `tests/e2e/doctors.spec.ts`

**Interfaces:**
- Consumes: `AppShell`, `ListPageTemplate`, M3 Table/List/Dialog/Card/Button/Badge.

- [ ] **Step 1: Home/clinic shell** — render the authenticated home (clinic name + role) inside `<AppShell>` as the first destination ("Home"); use M3 cards. This makes the shell the home base. Add a nav destination + link to **Doctors** (fixes the "type the URL" gap).
- [ ] **Step 2: Doctors** — render `/doctors` via `ListPageTemplate` (PageHeader "Doctors" + Add-doctor action → M3 Dialog; M3 table on desktop / card list on mobile; status `Badge`; empty state). Invite-token panel becomes a tonal card with the existing Copy (leave room for the future Share button #25 — do not implement it). Preserve behavior + testids.
- [ ] **Step 3: Verify + commit** — `npx tsc --noEmit && npm run build` clean; update + run `tests/e2e/doctors.spec.ts i18n.spec.ts` green. Confirm nothing looks half-old (all screens now on M3 + AppShell). Commit: `feat(ui): re-skin clinic shell + doctors into AppShell/templates`.

---

### Task 7: Rewrite Design docs + Golden Rules §17 to Material 3

**Files (docs repo `dentail-register-docs`):**
- Modify: `Design/01-design-philosophy.md`, `02-design-system.md`, `03-theme-system.md`, `04-cross-platform-guidelines.md`, `05-ui-implementation-roadmap.md`, `Rules/register-golden-rules.md` (§17)

- [ ] **Step 1: Rewrite docs** — replace the Linear×Stripe content with the **as-built M3** system: philosophy (premium, calm, pastel, elevated, card-based), tokens (the final values from `globals.css`), theme values (light/dark), cross-platform nav (rail/bottom-nav), and the framework (AppShell + templates) as the standard. Update Golden Rules §17 to reference M3 + the framework. Remove the "superseded" banners once content is M3. Keep the token-discipline / both-themes / mobile-first / a11y rules.
- [ ] **Step 2: Commit + PR** — docs PR via `gh-personal`; `git commit -m "docs: rewrite Design 01–05 + Golden Rules §17 to Material 3 (as built)"`.

---

## Self-Review
- **Spec coverage:** §3 tokens/type/shape/elevation → Task 1; §4 framework → Task 4; §5 components + showcase → Tasks 2–3; §6 auth rebuild + re-skin → Tasks 5–6; §8 docs → Task 7; §7 theming/i18n/a11y → Global Constraints + every task's verify. All covered.
- **Placeholder note:** UI components are specified by variant lists + token rules + reference-matching + showcase verification rather than full JSX (visual work is iterative and verified against the reference + `/design-system` in both themes); deterministic parts (tokens, fonts, shell/template structure, interfaces) are concrete. Token values live in spec §3 (single source) — not duplicated here to avoid drift.
- **Type/interface consistency:** component names (`AppShell`, `PageContainer`, `PageHeader`, `ListPageTemplate`, `AuthLayout`, `Icon`, `text-field`) are used consistently across Tasks 2–6; `destinations.ts` consumed by AppShell (Task 4) and extended in Task 6.
- **Behavior safety:** Tasks 5–6 explicitly preserve existing Supabase calls, data flows, and test IDs — presentation-only; e2e updated, not rewritten.
