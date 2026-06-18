# Design System Foundation (Phase 0) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Stand up the design-system **foundation** in the web frontend — semantic design tokens (light + dark), `next-themes` light/dark/system switching with persistence, a theme toggle, and retrofit the existing Auth + Clinic Workspace UI onto tokens (no hardcoded colors) — **before any further screen/feature UI**.

**Architecture:** Tailwind CSS v4 with **CSS-variable semantic tokens** (`:root` light, `.dark` dark), `next-themes` (`attribute="class"`, `defaultTheme="system"`, no-flash, persisted), shadcn/ui aligned to the tokens. This is **Phase 0** of `Design/05-ui-implementation-roadmap.md`.

**Tech Stack:** Next 16 (App Router) + TypeScript, Tailwind v4, `next-themes` (MIT), shadcn/ui, react-i18next (already present), Playwright.

**Design source of truth:** `Design/01-design-philosophy.md`, `Design/02-design-system.md` (tokens + components + a11y), `Design/03-theme-system.md` (theme values + mechanics), `Design/04-cross-platform-guidelines.md`, `Design/05-ui-implementation-roadmap.md`.

## Global Constraints
- Frontend repo: `~/Documents/register_workspace/dentist-registry-frontend`; branch `design-system-foundation`; never push to main; PR via `gh-personal`.
- **No hardcoded colors anywhere** — every color via a semantic token (Design/02 §Color, Design/03 values). Same for radius/elevation/motion via tokens.
- **Both themes are first-class**: every touched component verified in light AND dark; **AA contrast** in both (Design/02 Part C). Dark expresses elevation via lighter surfaces.
- **Theme modes**: Light / Dark / **Follow System**; System is the default; explicit choice persists (localStorage via next-themes); no theme flash on load.
- Keep i18n intact (all copy via `t()`); keep B3 `data-testid`s; do not redesign flows — this is tokenization + theming, not new screens.
- Permissive-OSS only (`next-themes` MIT). No secrets. tsc + build + e2e must stay green.
- **Scope guard:** this plan is the foundation only. The component library (Phase 1) and app shell (Phase 2) are separate; **feature screens (SP2+) are deferred until Phases 0–1 are done.**

---

### Task D1: Semantic token layer (color/radius/elevation/motion, light + dark)

**Files:**
- Modify: `src/app/globals.css` (token definitions + Tailwind `@theme` mapping)
- Test: `tests/e2e/theme.spec.ts` (token-presence assertions)

**Interfaces:**
- Produces: the full semantic CSS-variable token set under `:root` (light) and `.dark` (dark), per `Design/03-theme-system.md`'s value table; Tailwind utilities resolve to these variables.

- [ ] **Step 1: Define semantic tokens for both themes**

In `src/app/globals.css`, replace the shadcn-default palette with the project's semantic tokens (use the exact values from `Design/03-theme-system.md`'s light/dark table): `--background`/`--foreground`, `--card`/`--card-foreground`, `--popover`/`--popover-foreground`, `--muted`/`--muted-foreground`, `--border`, `--input`, `--ring` (indigo), `--primary`/`--primary-foreground` (calm indigo — light indigo-600, dark indigo-500), `--secondary`/`--secondary-foreground`, `--accent`/`--accent-foreground` (neutral tint), `--destructive`/`--success`/`--warning`/`--info` (+ `-foreground`), `--overlay`. Define light under `:root`, dark under `.dark`. Add radius tokens (`--radius-sm/md/lg/xl`), elevation (`--shadow-1/2/3`), and motion (`--duration-fast/base/slow`, `--ease-standard`) per Design/02.

- [ ] **Step 2: Map tokens into Tailwind**

Ensure the Tailwind v4 `@theme inline` block exposes the tokens as utilities (`bg-background`, `text-foreground`, `bg-card`, `text-muted-foreground`, `border-border`, `bg-primary`, `text-primary-foreground`, `ring-ring`, `rounded-md`, etc.) reading the CSS variables — so components use semantic utilities, never raw colors.

- [ ] **Step 3: Token-presence test**

`tests/e2e/theme.spec.ts` — load `/`, assert key tokens resolve to non-empty values in both themes (read `getComputedStyle(document.documentElement).getPropertyValue('--background')` etc. under `:root` and after adding `.dark`). Assert `--primary` differs appropriately between themes.

- [ ] **Step 4: Verify + commit**

Run: `cp .env.local.example .env.local && npm run build && npx tsc --noEmit` (clean); `npm run test:e2e -- theme.spec.ts`.
```bash
git add -A && git commit -m "feat(design): add semantic design tokens (light + dark)"
```

---

### Task D2: Theme provider + toggle (light/dark/system, no-flash, persisted)

**Files:**
- Install: `next-themes`
- Create: `src/components/theme-provider.tsx`, `src/components/theme-toggle.tsx`
- Modify: `src/app/layout.tsx` (`suppressHydrationWarning` on `<html>`), `src/app/providers.tsx` (mount ThemeProvider outermost)

**Interfaces:**
- Produces: `<ThemeProvider>` (`attribute="class"`, `defaultTheme="system"`, `enableSystem`, persisted) wrapping the app; `<ThemeToggle/>` cycling Light/Dark/System with i18n labels.

- [ ] **Step 1: Install + provider**

```bash
npm install next-themes
```
`theme-provider.tsx` (`"use client"`): wrap `next-themes` `ThemeProvider` with `attribute="class"`, `defaultTheme="system"`, `enableSystem`, `disableTransitionOnChange`. Mount it as the OUTERMOST client provider in `providers.tsx` (around the i18n + query providers). Add `suppressHydrationWarning` to `<html>` in `layout.tsx` to prevent the theme-class hydration warning / flash.

- [ ] **Step 2: Theme toggle**

`theme-toggle.tsx` (`"use client"`): a small control toggling Light / Dark / System via `useTheme()`; labels from i18n (`t('theme.light')`/`t('theme.dark')`/`t('theme.system')` — add these keys to en.json + hi.json, keeping parity). Render it on the login page and the authed shell (alongside the existing locale switcher).

- [ ] **Step 3: Verify + commit**

Run: build + tsc clean. Manually confirm (or via e2e in D4) toggling adds/removes `.dark` and persists. 
```bash
git add -A && git commit -m "feat(design): theme provider + toggle (light/dark/system, persisted, no-flash)"
```

---

### Task D3: Retrofit existing UI to tokens (remove hardcoded colors)

**Files:**
- Modify: `src/components/ui/*` (shadcn primitives: button, card, input, label, form, tabs), `src/features/auth/*`, `src/app/page.tsx`, `src/app/login/page.tsx`, `src/components/locale-switcher.tsx`, and any component with literal colors.

**Interfaces:** none (visual/token refactor; behavior + testids unchanged).

- [ ] **Step 1: Replace hardcoded colors with semantic utilities**

Audit and convert every literal color / raw Tailwind color class (e.g. `text-red-500`, `bg-white`, `#...`, `text-gray-*`) in the touched components to semantic tokens (`text-destructive`, `bg-background`, `bg-card`, `text-muted-foreground`, `border-border`, `text-primary`, etc.) per Design/02. Error text → `text-destructive`. Surfaces → `bg-card`. Confirm with: `grep -rnE '#[0-9a-fA-F]{3,6}|\b(bg|text|border|ring)-(red|green|blue|gray|slate|zinc|neutral|white|black|amber|emerald|indigo)-?[0-9]*' src` returns nothing user-facing (allow tokens only).

- [ ] **Step 2: Verify both themes + a11y**

Build + tsc clean. Spot-check (or via D4 e2e) that auth + onboarding + shell render correctly in BOTH light and dark with AA contrast (focus rings visible, error text legible, surfaces distinct).

- [ ] **Step 3: Commit**

```bash
git add -A && git commit -m "refactor(design): tokenize auth + clinic workspace UI (no hardcoded colors)"
```

---

### Task D4: Tests + docs + PR

**Files:**
- Modify/extend: `tests/e2e/theme.spec.ts` (theme-switch + both-theme render), `CLAUDE.md` (design-system conventions)
- Create: a short design-system section in the frontend `CLAUDE.md`

- [ ] **Step 1: Theme e2e**

Extend `tests/e2e/theme.spec.ts`: toggle to Dark → assert `<html>` has `.dark` and a token (e.g. background) changed; reload → theme persisted (localStorage); toggle to System → follows the emulated OS scheme (`page.emulateMedia({ colorScheme: 'dark' })`). Keep it lightweight; reuse the mocked-session pattern from `auth.spec.ts` if a route behind AuthGate is needed (or test on `/login`).

- [ ] **Step 2: No-hardcoded-colors guard (optional, lightweight)**

Add a small test or document the grep from D3 Step 1 as the standing check.

- [ ] **Step 3: Frontend CLAUDE.md — design-system conventions**

Add a "Design system" section: semantic tokens only (no hardcoded colors/strings); both themes mandatory; `next-themes` light/dark/system; tokens defined in `globals.css`; components use semantic Tailwind utilities; a11y AA; mobile-first; point to the `dentail-register-docs/Design/` docs as source of truth.

- [ ] **Step 4: Verify + PR**

Run: `npx tsc --noEmit && npm run build && npm run test:e2e` — all green (theme + i18n + auth). 
```bash
git add -A && git commit -m "test(design): theme e2e + design-system CLAUDE.md"
git push -u origin design-system-foundation
gh-personal pr create --title "Design system foundation: tokens + theming" --body "Implements Phase 0 of Design/05-ui-implementation-roadmap.md ..."
```

---

## Acceptance (Phase 0)
1. Semantic tokens defined for light + dark (color/radius/elevation/motion); Tailwind utilities resolve to them.
2. `next-themes` light/dark/system, default System, persisted, no flash; theme toggle present (login + shell).
3. Existing auth/workspace UI fully tokenized — **no hardcoded colors**; renders correctly + AA in BOTH themes.
4. i18n intact; testids intact; behavior unchanged.
5. Theme e2e + existing suites green; tsc + build clean; CI green.
6. Frontend CLAUDE.md documents the design-system conventions.

**After Phase 0:** Phase 1 (component library) → Phase 2 (app shell) → then SP2 feature screens. Screen/feature UI remains deferred until Phases 0–1 land.
