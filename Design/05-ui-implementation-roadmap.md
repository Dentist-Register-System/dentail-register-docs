# UI Implementation Roadmap

**Status:** Draft for review
**Date:** 2026-06-18
**Repo scope:** `dentist-registry-frontend` (web); native apps noted for continuity.
**Source of truth:** `design-master-brief.md` — all token names, values, and decisions referenced here derive from that document.

---

## Guiding Rule — Foundation Before Screens

> **The design-system foundation (Phases 0 and 1) must be fully in place before any further screen or feature UI is built.**

This is a hard sequencing constraint, not a preference. Sub-project 2 ("Core Entities" — clinics, patients, appointments, staff, and related CRUD screens) and every subsequent screen-level work item are **explicitly deferred** until Phase 0 and Phase 1 exit criteria are met. Building screens on top of an unfinished token layer produces technical debt that is expensive to retrofit: hardcoded colors, inconsistent theming, missed accessibility, and duplicated ad-hoc styling that resists future iteration.

From Phase 2 onward, every new UI surface consumes the token system and the component library. No ad-hoc hex values. No hardcoded strings. No one-off styling that sidesteps the semantic layer.

---

## Sequencing Summary

```
Design docs (now)
    └── Phase 0: Token & theme foundation  ← immediately next
            └── Phase 1: Core component library
                    └── Phase 2: App shell & navigation
                            └── Phase 3+: Feature screens (SP2 Core Entities, etc.)
                                    └── Native (later, separate workstream)
```

---

## Phase 0 — Token & Theme Foundation

**This is the immediately-next implementation task.**

### Goal

Replace the placeholder shadcn default palette currently in `globals.css` with the full semantic token layer defined in the design master brief. Wire `next-themes` for light/dark/system support with no flash. Retrofit the existing auth and clinic workspace components to consume only semantic tokens. At the end of this phase, the app looks correct and is fully accessible in both light and dark mode.

### What it delivers

**Token layer — color**
Define all semantic CSS variables for both `:root` (light) and `.dark` in `globals.css`, replacing the current neutral-only placeholders. Tokens to define: `--background`, `--foreground`, `--card`, `--card-foreground`, `--popover`, `--popover-foreground`, `--primary` (calm indigo — `oklch` equivalent of indigo-600 in light, indigo-500 in dark), `--primary-foreground`, `--secondary`, `--secondary-foreground`, `--muted`, `--muted-foreground`, `--accent`, `--accent-foreground`, `--border`, `--input`, `--ring` (indigo focus ring, visible in both themes), `--destructive`, `--destructive-foreground`, `--success`, `--success-foreground`, `--warning`, `--warning-foreground`, `--info`, `--info-foreground`, `--overlay`. The existing `@theme inline` block in Tailwind v4 format maps each variable to a utility class — extend it to cover the state colors and overlay.

**Token layer — typography, spacing, radius, elevation, motion**
Declare CSS custom properties (or Tailwind theme extensions in `globals.css`) for:
- The semantic type scale (`--text-display` through `--text-code`, with `font-size`, `line-height`, `font-weight`) — Geist Sans already installed, no font change required.
- The 4px-base spacing scale as Tailwind theme values where not already covered.
- Radius tokens: `--radius-sm` 6px, `--radius-md` 8px, `--radius-lg` 12px, `--radius-xl` 16px, `--radius-full` 9999px (the existing `--radius` variable becomes `--radius-md`).
- Elevation tokens: shadow values for `--shadow-1` (resting card), `--shadow-2` (popover/dropdown), `--shadow-3` (modal/sheet).
- Motion tokens: `--duration-fast` 120ms, `--duration-base` 200ms, `--duration-slow` 300ms; `--ease-standard` cubic-bezier(.2,0,0,1).

**`next-themes` wiring**
Add `next-themes` to the provider tree (`src/app/providers.tsx`). Configure: `attribute="class"`, `defaultTheme="system"`, `enableSystem`, `disableTransitionOnChange`. The `.dark` class on `<html>` drives the CSS variable flip already defined in `globals.css`. Persist selection to `localStorage`. No flash on load — `next-themes` injects a blocking script before hydration to apply the saved class.

**Theme toggle component**
A minimal `ThemeToggle` component (light / dark / system, icon-only or icon+label) that calls `useTheme()`. Wire it into the existing app shell header. This is the first "real" consumer of the token system and serves as a smoke test.

**Retrofit existing components**
The auth pages (`/login`, onboarding) and clinic workspace shell (`HomeShell`) currently use shadcn defaults — a neutral primary. Audit every color reference in `src/app/login/`, `src/features/auth/`, and `src/app/page.tsx`. Replace any hardcoded color utilities or inline styles with semantic token utilities (`bg-primary`, `text-muted-foreground`, `border-border`, etc.). The six existing shadcn primitives — `button.tsx`, `card.tsx`, `form.tsx`, `input.tsx`, `label.tsx`, `tabs.tsx` — receive the same treatment: confirm they read exclusively from CSS variables.

**Tailwind config alignment**
In `globals.css` (`@theme inline`), confirm all semantic tokens are mapped to Tailwind utility names. No utility in the codebase should reference a raw color (e.g., `text-indigo-600`); all color expression goes through semantic utilities.

### Exit criteria

- Both light and dark themes render correctly across all existing screens (login, OTP, onboarding, clinic shell). No incorrect colors in either theme.
- No hardcoded hex/rgb/oklch color values remain in component or page files — only CSS variable references.
- `--primary` resolves to indigo (not neutral) in both themes.
- Theme toggle persists selection across page reloads and cold starts.
- No flash of incorrect theme on load (hydration flash test).
- WCAG 2.1 AA contrast verified for both themes: body text 4.5:1 min; `--muted-foreground` passes AA; `--ring` is visible at 3:1 against its context in both themes.
- `prefers-reduced-motion` respected: motion tokens applied only as `transition-duration` via a motion-safe variant; no transforms/animations fire when reduced-motion is active.
- TypeScript builds clean; no regressions in the Playwright e2e suite.

### Tests

- Snapshot/visual regression: render the login and clinic-shell pages in light and dark and confirm token-correct appearance.
- Automated contrast check (e.g., via axe-core in Playwright) against both themes.
- Playwright: theme-toggle persists; no flash; both themes pass AA.

---

## Phase 1 — Core Component Library

### Goal

Build and document the full component set defined in the design master brief, on top of the Phase 0 token layer. Every component is token-correct, accessible, mobile-first, and renders correctly in both light and dark. Each component is the authoritative implementation — no parallel or one-off copies elsewhere in the codebase.

### What it delivers

**Component set** (each with purpose, anatomy, all variants and sizes, all states — default, hover, focus, active, disabled, loading, error — verified in both themes):

- **Actions:** Button (primary/secondary/ghost/destructive; sm/md/lg; loading state keeps width; full-width mobile variant).
- **Inputs and forms:** Input, Textarea, Select, Checkbox, Radio, Switch, DatePicker; always with Label, helper text, and error text (using `--destructive`); 44px minimum touch targets; all user-facing strings via `t()`.
- **Overlays:** Dialog (modal), Sheet (edge-anchored drawer), Drawer (full mobile sheet), Popover, Dropdown Menu, Tooltip.
- **Navigation:** see Phase 2 for the app shell; here build the primitive navigation components — NavItem, TabBar item, SideNavItem — without the shell layout wrapper.
- **Content surfaces:** Card (flat, resting elevation, interactive), Badge (neutral/success/warning/destructive/info), Tabs (horizontal; underline or pill variant), Table (desktop; collapses to card list on mobile), List (with/without icons, divider-optional).
- **Search:** SearchInput with clear, debounce-ready; empty and loading states inline.
- **Feedback:** Toast (transient, top or bottom position, auto-dismiss; success/warning/destructive/info variants); Notification item (persistent, for an in-app bell feed); Loading skeleton (preferred over spinner for content areas); Spinner (for button loading states only); Empty state (icon + title + body + primary action); Error state (clear i18n message + retry action).

**Component reference gallery**
A lightweight, non-production gallery route (or Storybook-equivalent) where every component variant can be viewed in isolation in both themes. This is the working contract between design and engineering — new contributors see exactly what exists before building.

**i18n alignment**
All user-facing strings in components (button labels, error messages, empty-state copy, toast messages) come from the `t()` translation function. No string literals in component markup.

**Elevation and motion in components**
Cards use `--shadow-1`; dropdowns and popovers use `--shadow-2`; dialogs and sheets use `--shadow-3` plus `--overlay` scrim. Transition durations use `--duration-fast`/`--duration-base`/`--duration-slow` with `--ease-standard`; all transitions are wrapped in a `motion-safe:` Tailwind variant.

### Exit criteria

- All components in the set above exist, are token-correct, and have documented usage.
- No hardcoded colors, no hardcoded strings in any component.
- Every interactive element has a visible focus ring (`--ring`) in both themes.
- All touch targets meet 44px minimum.
- Component gallery renders both themes and all states without errors.
- Axe-core runs clean on the gallery in both themes.
- TypeScript builds clean; Playwright e2e suite passes.

### Tests

- Unit/component tests (Vitest + React Testing Library) for state transitions (loading, error, disabled) and keyboard navigation on interactive components.
- Both-theme render tests for each component variant.
- Automated a11y (axe-core) run against the gallery in both themes.

---

## Phase 2 — App Shell & Navigation

### Goal

Implement the responsive, mobile-first app shell that frames every destination in the app. Navigation patterns differ by viewport but expose identical destinations and labels. Loading, empty, and error states are standardized at the shell level.

### What it delivers

**Mobile shell** (base breakpoint, up to `md` 768px):
- Bottom tab bar: fixed, 4–5 primary destinations, icon + label, active state uses `--primary` indigo; uses Phase 1 NavItem primitives.
- Drawer (full-height slide-in from left or bottom) for secondary navigation and settings — uses Phase 1 Sheet/Drawer component.
- Page-level header: app name / context + action icons (e.g., notification bell, profile); no persistent side chrome.

**Desktop shell** (`lg` 1024px+):
- Side navigation: fixed-width left rail; same destinations and labels as mobile bottom bar; expandable to show labels alongside icons; collapses to icon-only at narrower desktop widths.
- Content area: fluid right of the nav rail, with consistent page gutters (6–8 spacing tokens).
- Top header optional — only for page-level actions and breadcrumbs.

**Consistent across all destinations:**
- Transition between destinations uses `--duration-base` slide or fade; `motion-safe:` guard.
- Loading state: skeleton screens in the content area (not a full-page spinner).
- Empty state: the Phase 1 Empty state component with destination-appropriate copy (from i18n).
- Error state: Phase 1 Error state component with retry; never a raw error string.

**Responsive breakpoints:** mobile base → `sm` 640 → `md` 768 (still mobile shell) → `lg` 1024 (desktop shell begins) → `xl` 1280.

### Exit criteria

- Navigating between destinations works correctly on mobile (bottom tab + drawer) and desktop (side nav) with no layout shifts.
- Active destination is visually distinct in both themes, keyboard-navigable, and correctly announced to screen readers.
- Shell-level loading, empty, and error states display correctly in both themes.
- No layout or overflow issues between `320px` and `1440px` widths.
- TypeScript builds clean; Playwright e2e suite passes.

### Tests

- Responsive layout tests at representative widths (375px, 768px, 1024px, 1280px) in both themes.
- Keyboard navigation through destinations: Tab order, active-indicator, Enter/Space activation.
- Playwright: navigation routing, shell state transitions (loading → content, error → retry).

---

## Phase 3+ — Feature Screens

Phase 3 and beyond is where product feature screens are built. **These do not begin until Phase 0 and Phase 1 exit criteria are fully signed off.**

The first block is **SP2 — Core Entities UI**: clinics, patients, appointments, staff, and associated detail/edit/list screens. Every screen in this phase is an assembly of Phase 1 components, within the Phase 2 shell, reading from the Phase 0 token layer. No new styling primitives are introduced; if a pattern is missing, it is added to the component library first.

**Rules for Phase 3+ work:**
- All colors: semantic token utilities only.
- All copy: `t()` from i18n resources.
- All layout: spacing scale, not arbitrary pixel values.
- All interactive states: sourced from Phase 1 component props, not ad-hoc CSS.
- Tables fall back to card lists at mobile breakpoints, using Phase 1 Table/Card components.
- Forms use Phase 1 Form + Input + Label + error text pattern with React Hook Form + Zod (already the project convention).

---

## Native Apps — Token Continuity (Future Workstream)

Native iOS and Android are out of scope for the current build phase and are noted here for continuity only.

When native development begins, the same semantic token values defined in Phase 0 are mirrored to platform theming mechanisms:
- **iOS:** Swift UI color assets / semantic color sets referencing the same `oklch` values translated to `Color` resources; dynamic color for light/dark.
- **Android:** Material You color scheme seeded from the indigo primary; design tokens exported and consumed in theme XML or Compose MaterialTheme.

What must stay identical across platforms: all terminology and copy (same i18n codes), visual identity (same token values), navigation destinations and information architecture, component behavior, and accessibility commitments. What may vary by platform: navigation pattern (iOS tab bar + nav stack + swipe-back; Android bottom nav + top app bar + back button), native controls (pickers, date/time, keyboards), gesture vocabulary, density, haptics, and elevation expression (iOS uses materials and vibrancy; Android uses surface tones).

The Tailwind / CSS-variable layer is web-only; native apps read the same source-of-truth values via a shared token export (e.g., a JSON or Style Dictionary output from the design master brief values), not from the CSS file.

---

## Reference

All token names, values, typography scale, spacing scale, radius scale, elevation levels, and motion values referenced in this roadmap are defined authoritatively in `design-master-brief.md`. In case of any discrepancy between this roadmap and the master brief, the master brief governs.

Detailed implementation plans for each phase (file-by-file task breakdowns, PR sequencing, migration steps) are written separately in `docs/plans/` before implementation begins, per the spec-driven development workflow.
