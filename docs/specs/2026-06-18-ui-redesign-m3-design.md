# UI/UX Redesign — Material 3 Design System & Framework — Design Spec

> Status: Draft for review
> Date: 2026-06-18
> Author: Brainstormed via Claude Code (superpowers:brainstorming)
> Supersedes the **Linear × Stripe** design direction in `Design/01–05` and Golden Rules §17.

---

## 1. Context & Decision

The shipped UI (SP0/SP1 + SP2 doctor slice + email sign-up) is functional but visually bare. We are
**pivoting the product's design language to Material 3 (M3)** — clean, premium, pastel, elevated,
card-based — matched to the reference mockups in the UI brief. The goal is not just prettier auth
screens; it is a **reusable design framework** so every future screen inherits the look by composition
and nothing is built bespoke/ugly again.

**Recorded decision (supersedes prior docs):** The earlier **Linear × Stripe** philosophy
(neutral-forward canvas; *indigo reserved for action, never as fill*; no gradients; flat/hairline
elevation; Geist font; 8px radius) is **replaced by Material 3**. `Design/01–05` and Golden Rules §17
are rewritten to M3 as part of this work (this spec is the interim source of truth; see §8).

**Foundation decision:** We **re-skin the existing stack** (Next.js App Router + Tailwind v4 + shadcn/ui
primitives + `next-themes`) into an **M3 visual language** — we do **not** adopt a literal M3 component
library (MUI / Material Web). "Material 3" here is the visual target (tonal surfaces, soft elevation,
12–16px radius, Roboto, Material Symbols, the split-card/hero/nav-rail look), fully achievable by
re-theming tokens and restyling our components — without discarding the auth/doctors UI already built
or introducing a second styling system.

---

## 2. Scope

**In scope (this initiative, in build order — §8):**
1. **M3 design system** — new tokens (color/type/shape/elevation/motion), Roboto + Material Symbols.
2. **Reusable framework** — `<AppShell>` (nav-rail web / bottom-nav mobile + top app bar + centered
   content), layout primitives, and **page templates** (List / Detail / Form / Split-card auth).
3. **`/design-system` showcase** — every component in light + dark.
4. **Rebuild Login + Onboarding** (create clinic / join invite) to the reference look.
5. **Re-skin already-shipped screens** — email sign-up pending state, clinic shell (into AppShell),
   doctors page (into the List template) — so nothing looks half-old.
6. **Docs** — rewrite `Design/01–05` + Golden Rules §17 to M3.

**Out of scope / deferred:**
- **Google OAuth sign-in** (shown in the reference, confirmed filler) → backlog issue; a non-functional
  Google button is intentionally NOT added now.
- The **dashboard** in the mobile reference ("Dr. Alex", appointment counts) → aspirational; depends on
  scheduling data (later sub-project). We adopt its visual language but do not fake a dashboard.
- New feature screens (Assistant, Patient SP2 slices) remain paused until this foundation lands; they
  are then **built on the new framework**.
- **No business-logic changes** — this is presentation + framework only. APIs, auth, data flows unchanged.

---

## 3. Design Language — Material 3

Same plumbing as today (CSS custom properties → Tailwind v4 `@theme inline` → `next-themes`
light/dark/system). New values. Both themes are first-class.

### 3.1 Color — M3 tonal system (Calm Indigo)

We extend the existing semantic token set with **M3 container/surface roles**. Indigo may now be used
as a **fill, container, and soft gradient** (reversing the old reservation rule). Concrete values
(tunable during the design-system task; AA-verified in both themes):

| Role (token) | Light | Dark | Use |
|---|---|---|---|
| `--primary` / `--primary-foreground` | `#4F46E5` / `#FFFFFF` | `#C0C1FF` / `#26277A` | Primary actions, active state, FAB |
| `--primary-container` / `--on-primary-container` | `#E0E0FF` / `#1B1B5C` | `#3A3A8F` / `#E0E0FF` | Soft indigo fills, hero panel, selected tiles |
| `--secondary-container` / `--on-secondary-container` | `#E6E6F2` / `#1A1B2E` | `#44455A` / `#E2E1F3` | Secondary tonal fills, chips |
| `--tertiary-container` / `--on-tertiary-container` | `#FFD8E4` / `#31101D` | `#633B48` / `#FFD8E4` | Accent highlights (sparingly) |
| `--background` / `--foreground` | `#FCFCFF` / `#1B1B1F` | `#131318` / `#E5E1E9` | App canvas / primary text (cool-tinted neutral) |
| `--card` (surface-container) / `--card-foreground` | `#FFFFFF` / `#1B1B1F` | `#1E1E25` / `#E5E1E9` | Cards/tiles |
| `--surface-variant` / `--muted-foreground` | `#E4E2EC` / `#46464F` | `#2A2A33` / `#C7C5D0` | Subtle fills, secondary text |
| `--border` (outline-variant) | `#C7C5D0` | `#3A3A42` | Hairlines, text-field outlines |
| `--input` (outline) | `#767680` | `#8E8E99` | Form field border (M3 outlined) |
| `--ring` | `#4F46E5` | `#C0C1FF` | Focus ring |
| `--destructive`/`--success`/`--warning`/`--info` (+ `-foreground`) | M3 error/positive/caution/info roles | brightened for dark | Status only |
| `--hero-from` → `--hero-to` | `#E0E0FF` → `#EEF0FF` | `#2A2A6A` → `#1A1A40` | Auth hero gradient |

Existing token names (`--background`, `--card`, `--primary`, `--muted`, etc.) are **kept** so current
components keep working; new M3 roles (`--primary-container`, `--on-primary-container`,
`--surface-variant`, `--outline`, `--hero-*`) are **added**.

### 3.2 Typography — Roboto + M3 scale

Font: **Roboto Flex** (variable; fallback Roboto, then system). Loaded via `next/font`. M3 type roles
mapped onto our existing token names so components need minimal churn:

| Our token | M3 role | Size/Line (px) | Weight |
|---|---|---|---|
| `display` | Display Small | 36 / 44 | 400 |
| `h1` | Headline Small | 24 / 32 | 500 |
| `h2` | Title Large | 22 / 28 | 500 |
| `h3` / `title` | Title Medium | 16 / 24 | 500 |
| `body-large` | Body Large | 16 / 24 | 400 |
| `body` (default) | Body Medium | 14 / 20 | 400 |
| `label` | Label Large | 14 / 20 | 500 |
| `caption` | Label/Body Small | 12 / 16 | 400 |

Weights: 400 / 500 / 700. Numerals tabular where aligned (counts, times).

### 3.3 Shape, elevation, motion, icons
- **Radius:** `sm` 8 · `md` 12 (default) · `lg` 16 (cards/large surfaces) · `xl` 24 · `full` (pills/FAB).
- **Elevation 0–5** (soft, M3): e.g. `1: 0 1px 3px rgba(0,0,0,.08)` → `5: 0 12px 28px rgba(0,0,0,.16)`;
  dark mode leans on **tonal surface lift** (lighter `--card`) more than shadow. Levels: 0 flat,
  1 cards, 2 raised cards/menus, 3 dialogs, 4 nav, 5 FAB/temporary.
- **Motion:** M3 `standard` `cubic-bezier(.2,0,0,1)` and `emphasized` `cubic-bezier(.2,0,0,1)` with
  durations 120/200/300ms; respect `prefers-reduced-motion`. Calm — no bounce.
- **Icons:** **Material Symbols (Rounded)** via the variable icon font (or `@material-symbols` SVGs);
  filled/outlined per state. Replaces the current lucide usage incrementally.

---

## 4. The Reusable Framework (the core deliverable)

This is what makes future screens plug in seamlessly.

- **`<AppShell>`** (`src/components/shell/`): the chrome every authenticated screen renders inside —
  top **app bar** (brand/logo, page title slot, theme + locale switchers, profile menu), **navigation
  rail on web / bottom navigation on mobile** carrying the app's destinations, and a centered,
  max-width **content region**. A new screen drops into the shell and is instantly consistent.
- **Layout primitives** (`src/components/layout/`): `<PageContainer>` (max-width, responsive gutters,
  vertical rhythm), `<PageHeader>` (title + description + actions row), `<Section>`, `<CardGrid>`.
- **Page templates** (`src/components/templates/`) — coded skeletons + usage docs:
  - **ListPageTemplate** — header → search/filter → table (desktop) / card list (mobile) → empty state.
  - **DetailPageTemplate** — header → summary card → sections.
  - **FormPageTemplate** — header → card-wrapped form → sticky action row (mobile).
  - **AuthLayout** (`<AuthCard>`) — hero panel + form card (split on desktop, stacked on mobile).
- **Contract:** every future feature screen = `AppShell › <Template> › components`. Building
  Assistant/Patient becomes "fill a template," not "design from scratch."

---

## 5. Component Library + `/design-system` Showcase

Re-skin/extend shadcn primitives to M3 and document them in a live showcase route.

- **Components:** Button (filled / tonal / outlined / text + icon + FAB); Text Field (M3 filled &
  outlined, label/helper/error); Card & Tile; Chip (assist/filter/input); Badge; App Bar; Navigation
  Rail / Bottom Nav; Dialog; Bottom Sheet / Drawer; Snackbar (toast); Tabs (primary/secondary);
  List; Table; Segmented button; Loading (skeleton/spinner/progress); Empty & Error states.
- **`/design-system` route:** renders every component and every token (color/type/elevation/shape) in
  **light + dark**, with the theme + locale switchers. Serves as the visual contract and the dev
  reference future screens pull from. (Gated/dev-only or behind auth — decided at build time; it is a
  reference page, not a product feature.)

---

## 6. Auth + Onboarding Rebuild (reference look)

- **Login (`/login`):** split **AuthCard** — left **hero** (gradient `--hero-from→to`, app icon,
  "Welcome to Register System / The modern way to manage your clinic operations", trust bullets),
  right **form card** with Phone/Email **tabs** (segmented), M3 text fields, **filled** Continue,
  and the email **Create account / Sign in** toggle we already built. Mobile: stacked, centered,
  app icon on top, then card (matches the mobile reference).
- **Onboarding:** same card system — "Welcome! Set up your clinic" → **Create a new clinic** /
  **I have an invite** as M3 tiles/segmented; M3 fields; filled primary.
- **Re-skin shipped screens:** email-signup pending panel (M3 card), clinic shell (rendered inside
  `<AppShell>` — becomes the first "home" inside the new chrome), doctors page (into
  **ListPageTemplate** with M3 table/cards, the Add-doctor dialog as an M3 Dialog, invite token as a
  tonal card). The **share button** (#25) is *not* part of this work but its container is designed to
  accommodate it later.

---

## 7. Theming, i18n, Accessibility (unchanged commitments)
- Light / Dark / System via `next-themes` — both themes designed for every token/component.
- i18n-first: all strings via `t()`; new keys in `en.json` + `hi.json` with parity. No hardcoded copy.
- WCAG 2.1 AA contrast verified in both themes; focus rings always visible; 44px touch targets;
  Material Symbols icons paired with text/`aria-label`.
- Semantic tokens only — no raw colours in components (now an M3 token set).

---

## 8. Docs to Rewrite (recorded-decision follow-through)
As part of implementation: rewrite **`Design/01-design-philosophy`** (M3 principles), **`02-design-system`**
(M3 tokens/components), **`03-theme-system`** (M3 light/dark values), **`04-cross-platform`** (M3 nav
patterns), **`05-ui-implementation-roadmap`**; and **Golden Rules §17 (UI)** to M3. Until rewritten,
**this spec is the authoritative design-system reference.** Old docs get a banner pointing here.

---

## 9. Build Order (sequencing)
1. **Tokens + type + icons** — new globals.css token set, Roboto via `next/font`, Material Symbols;
   `tsc`/build green; theme switch still works.
2. **Framework + components + showcase** — AppShell, layout primitives, page templates, re-skinned
   components, `/design-system` route (light + dark).
3. **Auth + onboarding rebuild** — AuthCard/login/onboarding to the reference.
4. **Re-skin shipped screens** — email-signup, clinic shell → AppShell, doctors → ListPageTemplate.
5. **Docs rewrite** — Design/01–05 + Golden Rules §17 to M3.

Each step is independently shippable (PR) and keeps the app working.

---

## 10. Testing
- **Showcase/theme:** the `/design-system` route renders in light + dark; existing theme e2e
  (`tests/e2e/theme.spec.ts`) extended for the new token set; token presence assertions.
- **i18n:** parity test holds for all new keys.
- **Auth/onboarding e2e:** existing flows (login, signup pending, onboarding, doctors) updated for the
  new structure/testids and still pass (logic unchanged).
- **A11y:** AA contrast checked both themes; focus-visible on all controls; reduced-motion honored.
- CI = `tsc --noEmit` + `npm run build` clean; Playwright e2e local.

---

## 11. Acceptance Criteria
1. New M3 token set (color/type/shape/elevation) live for light + dark; Roboto + Material Symbols in use;
   no raw colours in components.
2. `<AppShell>` (nav-rail web / bottom-nav mobile + app bar + centered content) and the layout
   primitives + page templates exist and are documented; a new screen can be composed from them.
3. `/design-system` renders all components + tokens in both themes.
4. Login + onboarding match the reference (split card + hero on desktop, stacked on mobile); the
   shipped screens (email-signup, clinic shell, doctors) are re-skinned to the new system — nothing
   looks half-old.
5. Light/Dark/System all work; i18n parity holds; AA verified; existing flows still pass; CI green.
6. `Design/01–05` + Golden Rules §17 rewritten to Material 3; old Linear×Stripe direction recorded as
   superseded.
7. Google OAuth and the dashboard remain deferred (backlog); no fake/non-functional UI shipped for them.
