# Design System Specification

**Status:** Draft for review
**Date:** 2026-06-20 (palette updated — theme refresh #65)
**Scope:** Product-agnostic, reusable SaaS design system — web + iOS + Android.

---

## Overview

This specification defines the design tokens, component standards, and accessibility requirements for a modern SaaS design system. The aesthetic target is Linear × Stripe: clean, fast, calm, professional, premium. Color communicates state and action — never decoration. Whitespace and typography establish hierarchy; visual chrome is minimal.

**Non-negotiables:**
- Semantic tokens only — no hardcoded values or colors anywhere in components.
- Dark mode is a primary target, not an afterthought. Every token and component is specified for both light and dark themes.
- WCAG 2.1 AA accessibility is built in from the start, not retrofitted.
- All user-facing copy comes from i18n resources (`t()`) — the design system never hardcodes strings.

---

# Part A — Design Tokens

## A.1 Architecture: Two-Layer Token Model

Tokens are organized in two layers:

| Layer | Purpose | Used by |
|---|---|---|
| **Primitive scale** | Raw values (color ramps, numeric scales). Never referenced directly in components. | Semantic layer only |
| **Semantic tokens** | Role-based names that map primitives to intent. Flip between light and dark themes. | All components, Tailwind utilities |

Implemented as CSS custom properties (`--token-name`). Tailwind utilities read the variables. Native apps (iOS, Android) mirror the same semantic values via their platform theming system.

**The rule:** components and styles always reference semantic tokens. Primitive values (raw hex, raw numbers) appear only in the token definition layer.

---

## A.2 Color Tokens

### Soft-Purple reservation rule

Soft-Purple (`--primary`) is reserved exclusively for: primary actions, active/selected state, focus rings, and links. It must never appear as a background fill or decorative element. The canvas stays neutral (off-white in light, deep charcoal-lavender in dark).

### Palette: "Calm Soft-Purple" (updated in theme refresh #65)

The palette was refreshed in #65 to replace the previous electric-violet primary and harsh canvas with calmer, warmer values — closer to Linear/Notion/Apple. Direction: calm, premium, all-day clinical use. Token **names** are unchanged; only **values** changed. See `docs/specs/2026-06-20-theme-refresh-design.md` for rationale and the full before/after table.

**Light theme (`:root`) headline values:**

| Token | Value | Note |
|---|---|---|
| `--background` | `#F4F4F6` | Neutral calm canvas — not lavender; purple lives in the rail/chrome |
| `--card` | `#FFFFFF` | White — now visibly lifts off the dimmer canvas |
| `--primary` | `#6750A4` | M3 Soft Purple — calm/premium, not electric |
| `--primary-container` / `--secondary` / `--accent` / `--sidebar-accent` | `#EADDFF` | Warm Lilac container (chips, app-rail active pill) |
| `--on-primary-container` / `--secondary-foreground` / `--accent-foreground` | `#21005D` | Dark purple on Lilac |
| `--border` | `#ECE9F3` | Light hairline — cards read as shadow-elevated, not boxed |
| `--sidebar` | `#EFEAF7` | Lavender rail (kept/loved) |
| `--ring` / `--sidebar-primary` / `--sidebar-ring` | `#6750A4` | Match primary |
| `--muted` | `#ECEAF3` | Softer fills |
| `--input` | `#C4C1D1` | Softer input outline |
| `--outline` | `#7965AF` | Calmer outline |
| `--hero-from` / `--hero-to` | `#EADDFF` / `#F6F2FF` | Soft hero gradient |

**Dark theme (`.dark`) headline values:**

| Token | Value | Note |
|---|---|---|
| `--background` | `#17151E` | Deep charcoal-lavender, off near-black (less harsh) |
| `--card` / `--popover` | `#211F2A` | Lifted for surface separation |
| `--primary` / `--ring` / `--sidebar-primary` / `--sidebar-ring` | `#CFBCFF` | Soft lilac primary |
| `--primary-container` / `--secondary` / `--accent` / `--sidebar-accent` | `#4A3F66` | Calmer (less saturated) container |
| `--border` / `--sidebar-border` | `#322F3B` | Subtler hairline |
| `--sidebar` | `#1E1B28` | Rail |
| `--muted` | `#28262F` | — |
| `--surface-variant` | `#2A2735` | — |

**Accessibility:** WCAG AA preserved in both themes (white on `#6750A4` ≈ 4.9:1; text on Lilac high-contrast). State colors (`--destructive`, `--success`, `--warning`, `--info`) are unchanged.

### Semantic color tokens

Each token listed below has a paired `-foreground` token for text/icon drawn on that surface. Light/dark values are defined above and in `docs/specs/2026-06-20-theme-refresh-design.md` (#65); per-theme CSS lives in `src/app/globals.css`.

| Token | Foreground pair | Role |
|---|---|---|
| `--background` | `--foreground` | App canvas background / primary text. Light: `#F4F4F6` / ink. Dark: `#17151E` / near-white. |
| `--card` | `--card-foreground` | Card and panel surfaces. Light: `#FFFFFF` on dimmer `#F4F4F6` canvas. Dark: `#211F2A` on `#17151E`. |
| `--popover` | `--popover-foreground` | Popover/dropdown surfaces. Shares card values by default; overridable. |
| `--muted` | `--muted-foreground` | Subtle fills and secondary text. `--muted-foreground` must still pass AA contrast against `--muted`. |
| `--border` | — | Hairline separators. Light: `#ECE9F3` (soft). Dark: `#322F3B` (subtle). Used sparingly — prefer whitespace to establish grouping. |
| `--input` | — | Form field border. Slightly more prominent than `--border`. |
| `--ring` | — | Focus ring. Soft-Purple (`#6750A4` light / `#CFBCFF` dark); always visible. |
| `--primary` | `--primary-foreground` | **Calm Soft-Purple** — primary actions. Light `#6750A4` (M3 Purple). Dark `#CFBCFF` (soft lilac). Foreground = white / dark-purple respectively. |
| `--secondary` | `--secondary-foreground` | Neutral secondary buttons and fills. Shares Lilac container value (`#EADDFF` light / `#4A3F66` dark). |
| `--accent` | `--accent-foreground` | Subtle hover/selected background tint. Uses Lilac container — not a decorative fill. |
| `--destructive` | `--destructive-foreground` | Red. Destructive actions, error states, deletion. |
| `--success` | `--success-foreground` | Green. Positive confirmations, completed states. |
| `--warning` | `--warning-foreground` | Amber. Caution, degraded states, non-blocking issues. |
| `--info` | `--info-foreground` | Blue. Informational messages, neutral notifications. |
| `--overlay` | — | Modal/sheet scrim. Black at ~50% opacity (light) / ~60% opacity (dark). |

State colors (`--destructive`, `--success`, `--warning`, `--info`) are for status and feedback only — never for branding or decoration.

---

## A.3 Typography

### Font family

| Role | Family |
|---|---|
| UI text | `Geist Sans`, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif |
| Code / numeric | `Geist Mono`, ui-monospace, "SF Mono", Consolas, monospace |

Weights in use: 400 (regular), 500 (medium), 600 (semibold). Do not introduce additional weights.

### Semantic type scale

All sizes in px (rem at 16px base). Default UI text is `body` (14px) — matching the Linear/Stripe density baseline.

| Token | Size (px) | Line-height (px) | Weight | Notes |
|---|---|---|---|---|
| `display` | 30 | 36 | 600 | Hero headings, marketing moments |
| `h1` | 24 | 32 | 600 | Page titles |
| `h2` | 20 | 28 | 600 | Section headings |
| `h3` | 18 | 26 | 600 | Sub-section headings |
| `title` | 16 | 24 | 600 | Card titles, dialog headers |
| `body` | 14 | 22 | 400 | **Default UI text** |
| `body-strong` | 14 | 22 | 500 | Emphasized body, inline labels |
| `body-sm` | 13 | 20 | 400 | Dense lists, secondary content |
| `label` | 13 | 16 | 500 | Form labels, table column headers |
| `caption` | 12 | 16 | 400 | Help text, timestamps, metadata |
| `code` | 13 | 20 | 400 | Code blocks, monospaced values (Geist Mono) |

**Readability rule:** maximum body line length ~70ch. Never render meaningful text below 12px (`caption` is the floor).

---

## A.4 Spacing

**Base unit:** 4px.

| Token | px | Semantic use |
|---|---|---|
| `0` | 0 | — |
| `1` | 4 | Icon gaps, micro-padding |
| `2` | 8 | Control inline padding (tight) |
| `3` | 12 | Control padding (default) |
| `4` | 16 | Card padding (sm breakpoint / compact), stack gap (default) |
| `5` | 20 | **Card padding default** (`--card-spacing`, updated in theme refresh #65) |
| `6` | 24 | Section-level padding |
| `8` | 32 | Section gap (tight) |
| `10` | 40 | — |
| `12` | 48 | Section gap (default) |
| `16` | 64 | Large section gap |
| `20` | 80 | — |
| `24` | 96 | Page-level vertical rhythm |

**Semantic guidance:**

| Context | Tokens |
|---|---|
| Control padding (inputs, buttons) | `2`–`3` |
| Stack / list gap | `2`–`4` |
| Card padding | `5` (default, 20px via `--card-spacing`) · `4` (sm breakpoint) |
| Section gap | `8`–`12` |
| Page gutters | `4` (mobile) → `6`–`8` (desktop) |

Use generous whitespace to establish grouping. Add separators (`--border`) only when whitespace alone cannot create the needed visual break.

---

## A.5 Border Radius

| Token | px | Default use |
|---|---|---|
| `sm` | 6 | Tags, chips, small badges |
| `md` | 8 | Inputs, buttons, cards **(default)** |
| `lg` | 12 | Sheets, large cards, drawers |
| `xl` | 16 | Large panels, featured surfaces |
| `full` | 9999 | Pills, avatars, toggle tracks |

Style is moderate and soft — not sharp-cornered enterprise, not pill-everything. `md` (8px) is the default for interactive controls and content cards.

---

## A.6 Elevation

Prefer subtle elevation. The system uses hairline borders and soft, faint-purple-tinted shadows rather than heavy neutral shadows. In dark mode, lighter surfaces (via `--card`, `--popover`) carry elevation more than shadows do.

**Softened elevations (updated in theme refresh #65):** shadows now use a faint purple tint (`rgba(35,30,55,…)`) and reduced opacity so cards feel lifted rather than heavy.

| Level | Token | Context | Shadow |
|---|---|---|---|
| `0` | `--elevation-0` | Flat, default | None — use background color and spacing |
| `1` | `--elevation-1` | Resting cards | `--border` hairline + `0 1px 2px rgba(35,30,55,.05)` |
| `2` | `--elevation-2` | Popovers, dropdowns, menus | `0 2px 10px rgba(35,30,55,.05), 0 1px 3px rgba(35,30,55,.04)` |
| `3` | `--elevation-3` | Drawers, raised panels | `0 6px 18px rgba(35,30,55,.08), 0 2px 6px rgba(35,30,55,.05)` |
| `4` | `--elevation-4` | Modals, sheets | `0 10px 26px rgba(35,30,55,.10), 0 4px 10px rgba(35,30,55,.06)` |
| `5` | `--elevation-5` | Full-screen overlays | `0 16px 36px rgba(35,30,55,.12), 0 6px 14px rgba(35,30,55,.08)` |

Dark theme: rely on lighter surface tokens (`--card` at `#211F2A`) rather than increasing shadow opacity. Shadows remain intentionally faint in dark mode.

---

## A.7 Motion

Calm and fast. No bounce, spring, or decorative spin animations.

| Token | Duration | Use |
|---|---|---|
| `fast` | 120ms | Hover state changes, press feedback |
| `base` | 200ms | Enter/leave transitions, tab switches |
| `slow` | 300ms | Sheet/dialog open-close, page transitions |

**Easing:** `standard` = `cubic-bezier(.2, 0, 0, 1)` (ease-out character) for most transitions. `emphasized` for large surface entries (sheets, modals).

**Reduced-motion:** always respect `prefers-reduced-motion: reduce`. Disable non-essential transforms (translate, scale). Opacity transitions may remain as they don't induce vestibular discomfort.

---

# Part B — Component Standards

Each component entry covers: purpose, key anatomy, variants, sizes, states, both-theme behavior, accessibility, and mobile vs. desktop.

**Shared rules across all components:**
- All interactive states use semantic tokens — no hardcoded colors.
- All copy via `t()` — no hardcoded strings.
- Focus ring: `--ring` (Soft-Purple — `#6750A4` light / `#CFBCFF` dark), 2px solid, 2px offset, visible in both themes.
- Touch targets: minimum 44×44px on mobile.
- Loading states prefer skeletons over spinners where content shape is known.

---

## B.1 Buttons

**Purpose:** trigger an action.

**Anatomy:** container + label (+ optional leading/trailing icon) + optional spinner.

**Variants:**

| Variant | Fill | Use |
|---|---|---|
| `primary` | `--primary` solid, white text | The single primary action per context |
| `secondary` | `--secondary` neutral fill | Alternative/secondary actions |
| `outline` | `--border` border, transparent fill | Tertiary actions |
| `ghost` | Transparent, hover tints via `--accent` | Low-emphasis in-context actions |
| `destructive` | `--destructive` solid | Irreversible or dangerous actions |
| `link` | Underline, `--primary` color | Navigation or inline actions |

**Sizes:**

| Size | Height | Padding | Font |
|---|---|---|---|
| `sm` | 32px | `px-3 py-1.5` | `body-sm` |
| `md` | 36px | `px-4 py-2` | `body` |
| `lg` | 44px | `px-5 py-2.5` | `body-strong` |

**States:** default → hover (lightened/tinted fill) → focus (`--ring`) → active (darkened fill) → disabled (reduced opacity, no pointer events) → loading (spinner replaces label, width preserved).

**Both themes:** `--primary` is `#6750A4` (M3 Soft Purple) in light and `#CFBCFF` (soft lilac) in dark to maintain contrast. All other variants adjust via their semantic tokens.

**Accessibility:** `aria-disabled` for disabled state; `aria-busy` + accessible label during loading. Minimum 44px height on mobile (`lg` size or CSS min-height override).

**Mobile vs. desktop:** full-width on mobile forms (within form containers). Fixed-width on desktop. Icon-only buttons always include `aria-label`.

---

## B.2 Inputs

**Purpose:** single-line text entry.

**Anatomy:** label (always present, above) + input field + optional leading icon/prefix + optional trailing icon/clear button + helper text or error text (below).

**Variants:** default, with-icon, with-prefix, with-suffix, search (see Search component).

**Sizes:** default height 40px (meets 44px touch target with label included in tap region on mobile). Dense: 36px desktop-only.

**States:**

| State | Visual |
|---|---|
| Default | `--input` border, `--background` fill |
| Hover | Slightly elevated `--input` border |
| Focus | `--ring` focus ring, `--input` border |
| Filled | Same as default |
| Disabled | `--muted` fill, reduced opacity |
| Error | `--destructive` border + error text in `--destructive` below field |
| Loading | Disabled appearance + spinner in trailing position |

**Both themes:** `--input` and `--background` invert cleanly. Error color (`--destructive`) is verified for contrast in both.

**Accessibility:** `<label>` always explicitly associated with `<input>` via `for`/`id`. Helper text and error text linked via `aria-describedby`. Error announced via `aria-invalid="true"` + live region. Never rely on placeholder as a label substitute.

**Mobile vs. desktop:** same component; system keyboard adapts to `inputmode` and `type` attributes. Autocomplete attributes set appropriately (`autocomplete`, `autocorrect`, `autocapitalize`).

---

## B.3 Forms

**Purpose:** structured data collection via a set of inputs.

**Anatomy:** form container + field groups (label + input + helper/error) + optional section headings + action row (primary + secondary buttons).

**Layout:** single-column on mobile. Optional two-column grid on desktop for related fields (e.g., first name / last name). Never more than two columns.

**Validation:** real-time validation on blur; summary error if server returns errors. Error messages sourced from i18n codes (`t('validation.required')` etc.) — never hardcoded.

**States:** each field independently carries its own state. Form-level disabled (e.g., during submission): all fields + buttons disabled, submit shows loading state.

**Both themes:** form backgrounds use `--background` or `--card` depending on context (inline vs. dialog).

**Accessibility:** form landmark (`<form>`). `fieldset`/`legend` for grouped fields (e.g., address). Error summary at top of form linked to individual fields. Tab order follows visual reading order.

**Mobile vs. desktop:** stacked single-column on mobile. Action row is sticky at viewport bottom on mobile for long forms. Full-width buttons on mobile form action row.

---

## B.4 Navigation

**Purpose:** move between top-level destinations and key sub-sections.

**Anatomy:**
- Mobile: bottom tab bar (up to 5 destinations) or hamburger drawer for overflow.
- Desktop: collapsible side navigation (icon + label, grouped sections) or top navigation bar.
- Both: same destination labels and IA — only the pattern adapts.

**Variants:** bottom tab bar (mobile), side nav (desktop), top nav bar (desktop alternative for simpler apps).

**States:** default, hover (`--accent` tint), active/selected (`--primary` indicator + label, icon tinted `--primary`), disabled.

**Both themes:** active indicator uses `--primary`; nav background uses `--card` or a dedicated nav surface token.

**Accessibility:** `<nav>` landmark with `aria-label`. Active item marked `aria-current="page"`. Keyboard: arrow keys move between items; Enter activates. Skip-navigation link provided.

**Mobile vs. desktop:** bottom tab bar on mobile — thumb-reachable, max 5 items, icon + short label. Desktop side nav — full labels, nested sections, collapsible to icon-only. Same destinations, different chrome. Never design desktop-only destinations.

---

## B.5 Cards

**Purpose:** group related content or actions into a visually bounded unit.

**Anatomy:** card container + optional header (title + subtitle + actions) + optional `CardSeparator` + content area + optional footer (actions or metadata).

**Variants:** default (elevation 1), flat (elevation 0, use border), interactive/clickable (hover lifts to elevation 2), featured (larger padding, optional accent top border).

**States:** default → hover (interactive variant: shadow lifts, subtle bg shift via `--accent`) → active (pressed scale on mobile) → selected (`--primary` left border or ring).

**Both themes:** `--card` surface is `#FFFFFF` in light, `#211F2A` in dark. Shadow uses softened purple-tinted elevations (see A.6); rely on surface color for depth in dark mode.

**Spacing — `--card-spacing` (updated in theme refresh #65):** the shared card spacing token is **20px** (`--spacing(5)`), bumped from 16px for airier breathing room matching the approved mockup. This widens padding and internal gaps on every card app-wide via the `Card` primitive.

**CardSeparator — inset header divider (added in theme refresh #65):** a subtle, non-edge-to-edge horizontal rule between `CardHeader` and `CardContent` on cards that have both a header and a body. Implementation: `mx-(--card-spacing) border-t border-border` — inset by the card padding so it reads as a structural element, not a full bleed line. Applied to Settings panes, profile, dashboard, and list cards with a visible header. Very subtle by design: uses the now-lighter `--border` token.

**Accessibility:** if the whole card is clickable, use a single `<a>` or `<button>` wrapping the content with a descriptive `aria-label`. Avoid nested interactive elements inside a clickable card unless carefully structured.

**Mobile vs. desktop:** full-width on mobile (no columns). 2–3 column grid on desktop. Padding uses `--card-spacing` (20px) uniformly; `sm` breakpoint uses 16px.

---

## B.6 Drawers

**Purpose:** persistent side panel for contextual content (e.g., filters, detail view) without leaving the current context.

**Anatomy:** overlay scrim (`--overlay`) + drawer panel + header (title + close button) + scrollable content area + optional footer (actions).

**Variants:** left (navigation), right (detail/filters), full-screen (mobile fallback for complex content).

**Sizes:** 320px (sm), 480px (md), 640px (lg) on desktop. Full-width on mobile.

**States:** closed (off-screen), entering (`slow` 300ms ease-out from edge), open, leaving (reverse).

**Both themes:** panel uses `--card` surface; scrim uses `--overlay`.

**Accessibility:** traps focus inside when open. ESC closes. `role="dialog"` + `aria-modal="true"` + `aria-labelledby`. Returns focus to trigger on close.

**Mobile vs. desktop:** slides from bottom on mobile (sheet pattern — see B.7). Slides from left/right on desktop. Scrim always present.

---

## B.7 Sheets

**Purpose:** bottom sheet (mobile-primary) for contextual actions or detail without full navigation.

**Anatomy:** scrim + sheet panel (with drag handle on mobile) + header + content + optional action row.

**Variants:** half-height (peek), full-height, snap-points (mobile).

**States:** closed → entering (slides up, `slow` 300ms) → open → leaving (slides down).

**Both themes:** `--card` surface, `--overlay` scrim.

**Accessibility:** same as Drawer — focus trap, ESC, `role="dialog"`, `aria-modal`, focus return. Drag handle has `aria-label` for screen readers.

**Mobile vs. desktop:** sheet is the primary pattern on mobile. On desktop, the same content may instead render as a Drawer or Dialog depending on complexity. Never use a bottom sheet layout on desktop.

---

## B.8 Dialogs

**Purpose:** interrupt the user to confirm an action, display critical information, or collect focused input.

**Anatomy:** `--overlay` scrim + dialog panel + header (title + optional close icon) + content + footer (action row: primary + cancel).

**Variants:** confirmation (small, destructive primary button for dangerous actions), informational (no destructive button), form dialog (input collection).

**Sizes:** sm 400px, md 560px, lg 720px max-width. Full-width with margin on mobile.

**States:** closed → entering (fade-in + subtle scale-up, `base` 200ms) → open → leaving (reverse).

**Both themes:** `--card` panel, `--overlay` scrim, `--foreground` text.

**Accessibility:** focus trap. ESC closes (except for critical, non-dismissible dialogs). `role="dialog"`, `aria-modal="true"`, `aria-labelledby` pointing to dialog title. First focusable element receives focus on open (or the dialog itself if content is purely informational).

**Mobile vs. desktop:** full-width with 16px margin on mobile. Centered fixed-width on desktop. Action buttons stack vertically on mobile, inline on desktop.

---

## B.9 Badges

**Purpose:** short, non-interactive status label or count indicator.

**Anatomy:** container + text (1–2 words max) or number.

**Variants:**

| Variant | Fill | Use |
|---|---|---|
| `default` | `--secondary` | Neutral label |
| `primary` | `--primary` tint | Active, selected, highlighted |
| `destructive` | `--destructive` tint | Error, critical, overdue |
| `success` | `--success` tint | Complete, healthy, paid |
| `warning` | `--warning` tint | Caution, pending, at-risk |
| `info` | `--info` tint | Informational |
| `outline` | Border only | Low-emphasis label |

**Sizes:** default (`label` 13px, height 22px), sm (`caption` 12px, height 18px).

**Both themes:** tint fills lighten in dark mode. Always verify foreground contrast against tinted background.

**Accessibility:** status badges include `role="status"` if updated dynamically. Color alone never conveys meaning — pair with text (e.g., "Overdue", not just a red badge). No interactive affordance on badge itself.

**Mobile vs. desktop:** same. Ensure badge text doesn't truncate at small widths — constrain badge content, not badge width.

---

## B.10 Tabs

**Purpose:** switch between views within the same context/page.

**Anatomy:** tab list (horizontal, scrollable on mobile if overflow) + tab panels.

**Variants:** line (underline indicator — default), pill (filled background on active tab), vertical (sidebar tabs on desktop).

**States:** default → hover (`--accent` tint) → active/selected (`--primary` underline or fill) → focus (`--ring`) → disabled (reduced opacity, `aria-disabled`).

**Both themes:** active indicator uses `--primary`; tab list background transparent or `--muted`.

**Accessibility:** `role="tablist"`, `role="tab"`, `role="tabpanel"`. Arrow keys navigate between tabs; Tab/Shift-Tab moves to panel content. `aria-selected` on active tab. `aria-controls` links tab to panel.

**Mobile vs. desktop:** horizontal scrolling tab bar on mobile (no wrapping). Max 5–6 tabs before considering a different navigation pattern. On desktop, may switch to vertical tabs for complex views.

---

## B.11 Tables

**Purpose:** display structured, comparable data in rows and columns.

**Anatomy:** table container (with horizontal scroll wrapper) + thead (column headers with optional sort) + tbody (data rows) + optional tfoot (totals/summary) + optional pagination or load-more.

**Variants:** default, striped (alternate row `--muted` tint), bordered, compact (reduced row height).

**States:** row hover (`--accent` tint), row selected (`--primary` tint + checkbox), column sort (chevron icon, `aria-sort`), loading (skeleton rows), empty (see Empty States, B.16).

**Both themes:** header background uses `--muted`; row hover uses `--accent`; selected row uses `--primary` tint.

**Accessibility:** `<table>`, `<thead>`, `<th scope="col">`, `<td>`. Sortable headers are `<button>` or `aria-sort`. Caption or `aria-label` describes the table. Row checkboxes have `aria-label` referencing the row.

**Mobile vs. desktop:** tables collapse to card-per-row layout on mobile (base and `sm` breakpoints). Each "card" shows key fields; secondary fields are hidden or in an expand. Never force horizontal scroll on mobile for primary data. Horizontal scroll acceptable on `md`+ for dense data tables.

---

## B.12 Lists

**Purpose:** display a collection of items that don't require column-aligned comparison.

**Anatomy:** list container + list item (icon or avatar + primary text + secondary text + optional trailing action or metadata).

**Variants:** simple (text only), with-icon, with-avatar, with-trailing-action, grouped (sectioned with sticky headers).

**States:** item hover (`--accent` tint) → active/selected (`--primary` tint, left border indicator) → focus → disabled.

**Both themes:** hover and selected states use semantic accent/primary tints.

**Accessibility:** `<ul>`/`<li>` for display lists. If items are interactive links, use `<a>`. If selectable, use `role="listbox"` + `role="option"` with `aria-selected`. Keyboard: arrow keys navigate items, Enter activates, Space toggles selection.

**Mobile vs. desktop:** same structure. Item height: minimum 44px (mobile), 40px (desktop). Trailing actions may collapse to an overflow menu on narrow viewports.

---

## B.13 Search

**Purpose:** filter or locate content within a dataset or globally.

**Anatomy:** search input (with leading search icon, optional clear button) + results dropdown (popover, elevation 2) or inline results panel.

**Variants:** inline (filters a visible list), global (command palette / full-screen on mobile), scoped (within a card or section).

**States:** default → focused (ring, results panel opens if applicable) → typing (real-time results) → loading (spinner in trailing position) → results (list of matches) → empty (no-results message with suggestion) → error (error message + retry).

**Both themes:** input uses `--input`/`--background`; results panel uses `--popover`/`--popover-foreground`.

**Accessibility:** `role="combobox"` on input, `aria-expanded`, `aria-controls` pointing to results list. Results list: `role="listbox"`, each result `role="option"`. Arrow keys navigate results; Enter selects; ESC clears/closes. Debounce queries to avoid excessive network calls.

**Mobile vs. desktop:** expands to full-screen search overlay on mobile (tap the search input). Inline dropdown on desktop.

---

## B.14 Loading States

**Purpose:** communicate that content or an action is in progress.

**Variants:**

| Variant | When to use |
|---|---|
| **Skeleton** | Page/section initial load when content shape is known. Preferred. |
| **Spinner** | Indeterminate async action within a component (button loading, inline action). |
| **Progress bar** | Determinate upload, multi-step process with known progress. |

**Skeleton:** gray animated pulse fills (`--muted` background) in the shape of the content to appear. No text in skeletons — just shape. Match dimensions of real content as closely as possible.

**Spinner:** 20px (inline/button), 32px (card/section), 48px (full-page). Uses `--muted-foreground` color on neutral surfaces, white inside `--primary` buttons.

**Both themes:** `--muted` skeleton fills adapt per theme. Spinner color uses semantic tokens.

**Accessibility:** `aria-busy="true"` on the loading container. Screen-reader-only text (`.sr-only`) announces "Loading…" on entry. Remove `aria-busy` when done.

**Mobile vs. desktop:** same. Skeleton column count matches the loaded layout to avoid layout shift.

---

## B.15 Empty States

**Purpose:** communicate that a list, view, or dataset has no items — and guide the user to resolve it.

**Anatomy:** icon (illustrative, not interactive) + title (h3, `t('empty.title')`) + optional description (body, `t('empty.description')`) + primary action button.

**Variants:** no-data (first use, no items created yet), no-results (search/filter returned nothing), no-access (user lacks permission).

**States:** single static state — no hover/interactive on the empty state container itself.

**Both themes:** icon uses `--muted-foreground`; text uses `--foreground` and `--muted-foreground`; button follows Button component tokens.

**Accessibility:** region `aria-label="No items"` or equivalent `t()` key. Action button fully keyboard accessible.

**Mobile vs. desktop:** centered vertically in the available space on both. Icon smaller on mobile (48px vs 64px).

---

## B.16 Error States

**Purpose:** communicate that something went wrong and provide a recovery path.

**Anatomy:** icon (alert/error, `--destructive`) + error title (`t('error.title')`) + human-readable message (`t('error.message_code')`) + retry button (or other recovery action).

**Variants:** inline (within a card or section), full-page (catastrophic failure), field-level (see Inputs).

**Copy rule:** error messages come from i18n codes. The design system never hardcodes error strings.

**Both themes:** `--destructive` token is verified for contrast in both themes.

**Accessibility:** `role="alert"` or `aria-live="assertive"` for dynamically injected error states so they are announced immediately by screen readers.

**Mobile vs. desktop:** same structure. Retry button is full-width on mobile.

---

## B.17 Toasts

**Purpose:** transient, non-disruptive feedback about a completed action or brief status.

**Anatomy:** toast container (top-center or bottom-center, outside main content flow) + optional icon + message + optional action link + auto-dismiss timer.

**Variants:** `default`, `success`, `warning`, `destructive`, `info`. Paired with corresponding state color token.

**Behavior:**
- Auto-dismiss after 4–5 seconds (configurable).
- Pause timer on hover.
- Stack vertically if multiple appear; oldest dismissed first.
- Transient — not logged or persisted. For persistent messaging use Notifications (B.18).

**Both themes:** toast surface uses `--card`/`--card-foreground` with a left border in the variant's state color.

**Accessibility:** `role="status"` (informational) or `role="alert"` (destructive). `aria-live="polite"` for most; `aria-live="assertive"` for destructive only. Action within toast is keyboard accessible before dismiss.

**Mobile vs. desktop:** full-width with horizontal margin on mobile (bottom of viewport). Fixed-width (360px) anchored top-right or bottom-right on desktop.

---

## B.18 Notifications

**Purpose:** persistent, in-app messages that require or deserve user acknowledgment; accessible from the notification bell/inbox.

**Anatomy:** notification bell icon (with unread badge count) + notification panel/drawer + notification item (icon + title + description + timestamp + read/unread state + optional action).

**Variants:** informational, success, warning, destructive — each using the corresponding state color for the leading icon.

**Behavior:**
- Persistent — survive page navigation until read or dismissed.
- Unread count badge on the bell icon.
- Mark-as-read on open or explicit action.
- Distinct from Toasts: Toasts are ephemeral feedback; Notifications are a persistent inbox.

**States:** unread (bold title, `--primary` or accent left indicator), read (muted), hover (`--accent` tint), focus, selected.

**Both themes:** notification panel uses `--popover`/`--card` surface. Unread indicator uses `--primary`.

**Accessibility:** bell button has `aria-label={t('notifications.label')}` + `aria-haspopup`. Unread count in badge uses `aria-label={t('notifications.unread_count', { count })}`. Notification panel is a `role="dialog"` or `role="region"` with live region for new arrivals.

**Mobile vs. desktop:** notification panel slides in as a sheet on mobile (see B.7). Popover or drawer panel on desktop.

---

# Part C — Accessibility Standards

## C.1 Color Contrast

All text and meaningful UI elements must meet WCAG 2.1 AA minimums. Verified in both light and dark themes.

| Element type | Minimum ratio |
|---|---|
| Normal text (below 18px / 14px bold) | 4.5:1 |
| Large text (18px+ / 14px+ bold) | 3:1 |
| UI components, icons, borders against background | 3:1 |
| `--muted-foreground` against `--muted` | 4.5:1 |
| Focus ring (`--ring`) against adjacent background | 3:1 |

**Rule:** no color-only meaning. Every status, state, or category communicated by color must also be communicated by an icon, text label, pattern, or other non-color cue.

---

## C.2 Keyboard Navigation

- Every interactive element (buttons, inputs, links, tabs, menu items, checkboxes, radio buttons, selects, toggles, sortable headers) is reachable and operable via keyboard alone.
- Tab order follows the visual reading order (left-to-right, top-to-bottom).
- No keyboard traps — Tab always moves focus forward, Shift+Tab backward, ESC closes overlays and returns focus to the trigger.
- Focus ring: `--ring` (Soft-Purple — `#6750A4` light / `#CFBCFF` dark), 2px solid, 2px offset. Visible in both light and dark themes. Never suppressed globally (`:focus-visible` is acceptable; `:focus { outline: none }` without replacement is not).
- Arrow key navigation within compound widgets: tab bars, listboxes, menus, radio groups, sliders.

---

## C.3 Touch Targets

- Minimum touch target size: **44×44px** on all mobile interactive elements.
- If a visual element is smaller (e.g., a 16px icon button), extend the tap area using padding or `min-height`/`min-width` in CSS without changing visual size.
- Adequate spacing between adjacent targets to prevent mis-taps: minimum 8px gap.

---

## C.4 Responsive Breakpoints

Mobile-first: design for the smallest viewport first. Desktop layout is derived from — not the baseline for — the mobile layout.

| Breakpoint | Prefix | Min-width | Typical use |
|---|---|---|---|
| base | (none) | 0px | Mobile, single column |
| `sm` | `sm:` | 640px | Large phone / small tablet |
| `md` | `md:` | 768px | Tablet portrait |
| `lg` | `lg:` | 1024px | Tablet landscape / laptop |
| `xl` | `xl:` | 1280px | Desktop |

Design decisions (navigation pattern, card columns, table vs. card layout, button width, sheet vs. dialog) are made at each breakpoint explicitly. Desktop never introduces new workflows not accessible on mobile — it adds density, columns, and persistent navigation chrome.

---

## C.5 Readability

- Body text minimum: 14px (`body` token) for meaningful UI text. Absolute floor: 12px (`caption` token) for metadata only.
- Sufficient line-height: all tokens include comfortable line-height (see type scale in A.3).
- Constrained line length: maximum ~70ch for body text blocks to maintain readability.
- Font smoothing: `-webkit-font-smoothing: antialiased` on macOS/iOS; `auto` elsewhere. Never `crisp-edges`.
- Text does not lose meaning when user zooms to 200% (no fixed-height text containers that clip).

---

## C.6 System Preferences

| Preference | Behavior |
|---|---|
| `prefers-color-scheme` | Honored when user selects "Follow System" theme. Light and Dark are also explicit user choices stored in persistence (next-themes). |
| `prefers-reduced-motion` | Non-essential transforms (translate, scale, rotate) are disabled. Opacity and color transitions may remain. Duration effectively 0 for animations that convey no meaning on their own. |
| `prefers-contrast: more` | Increase border visibility, bump `--muted-foreground` contrast where possible. (Stretch goal; AA baseline always met.) |

---

## C.7 Semantic HTML and ARIA

- Use the correct HTML element before reaching for ARIA (`<button>` not `<div role="button">`; `<a>` for navigation; `<table>` for tabular data).
- ARIA landmarks: `<header>`, `<nav aria-label="...">`, `<main>`, `<aside>`, `<footer>`. One `<main>` per page.
- Live regions (`aria-live`) scoped to the element that changes — not the document body.
- Images: `alt` text on all `<img>`. Decorative images `alt=""`. SVG icons `aria-hidden="true"` when accompanied by visible text; `aria-label` when icon-only.
- Form controls always have a visible label (not just a placeholder).

---

---

## B.19 Guided One-Question Wizard

**Purpose:** replace dense multi-field creation forms with a calm, premium onboarding experience — one focused question at a time. Used for multi-field creation flows (clinic creation, doctor-profile creation). See `docs/specs/2026-06-20-guided-wizard-design.md` (#50) and [[Golden Rules §18]].

**Anatomy:**
- **Top progress bar** — linear fill from 0 → 100 % as the user advances.
- **One-question card** — a single centered card per step. Each card contains: a step heading, the field(s) for that step, and a per-card reassurance line (circled-i icon + italic muted text below the field(s), above the buttons).
- **Desktop left step-rail** — vertical stepper: completed steps show a checkmark, the current step is highlighted, upcoming steps are numbered. Hidden below `md` breakpoint.
- **Mobile dot row** — horizontal dots: completed = filled, current = elongated, upcoming = muted. Hidden at `md`+. Both rail and dots derive from the same step model.
- **Control row** — Back (hidden on step 1) · Skip (optional steps only) · Next (required steps, disabled until the step is valid) · Submit on the last step ("Create clinic" / "Create profile" — no separate review screen).

**Grouping rule:** group naturally cohesive fields into a single step — do **not** fragment them into one card per field. Example: the full structured postal address (address\_line\_1, area, city, state, pin\_code, and optional address\_line\_2 / landmark / google\_maps\_url) is **one "Address" card**, not five separate cards.

**Validation:** per-step only — trigger only the current step's fields before advancing (RHF `trigger(stepFields)`). Required steps gate Next until valid; optional steps show Skip. Back always preserves entered values.

**Reassurance line:** every card shows a circled-i + italic muted text. Per-flow copy is i18n-keyed; never hardcoded.

**Architecture:** config-driven `Wizard` component — each step is `{ key, labelKey, optional, fields[], content }`. Shared React Hook Form instance holds all values across steps. The wizard owns progress, rail/dots, controls, and final submit. Consumers pass `onComplete(values)` and a `reassuranceKey`.

**Both themes:** uses `--card`, `--muted-foreground`, `--primary` (progress + rail active), `--border` (rail connector) — no hardcoded colors.

**Accessibility:** focus moves to the step heading on advance; rail/dots carry appropriate ARIA roles and labels; Back/Next/Skip keyboard-navigable; Enter submits the active step.

**Mobile vs. desktop:** mobile — dot row + full-width card + stacked buttons. Desktop — left step-rail (hidden on mobile) + centered card + inline control row.

---

## B.20 Success Card

**Purpose:** must-acknowledge confirmation shown after important create/save/decide actions (request sent, approved, declined, schedule saved, profile created, etc.). Replaces silent dialog-close feedback — the app has no toasts for significant outcomes. See `docs/specs/2026-06-20-success-cards-design.md` (#61).

**Anatomy:** `--overlay` scrim + card panel + **✓ badge** (`bg-success/10` fill · `text-success` icon/ring — reuses the existing `--success` token, no new token) + **title** (`DialogTitle`, semibold, `title` scale) + **detail rows** (plain-language label + value pairs; rows with empty values are omitted) + **Dismiss button** (primary, full-width on mobile / fixed-width on desktop) + optional **deep-link action** (secondary, shown only when a target route exists for the created/updated entity).

**Interaction:**
- Must-acknowledge — does not auto-dismiss. User must tap/click Dismiss (or the deep-link action) to proceed.
- If a new success is triggered while one is already visible, the new card replaces the old one.
- No stacking, no queue; only one card is ever shown at a time.

**Variants:** Dismiss-only (default, V1) · with deep-link action (when a target route exists).

**Both themes:** panel uses `--card` / `--card-foreground`; scrim uses `--overlay`; badge uses `--success` / `--success-foreground` tint; no hardcoded colors.

**Accessibility:** `role="dialog"`, `aria-modal="true"`, `aria-labelledby` pointing to the `DialogTitle`. Focus is trapped inside; Dismiss receives focus on open. ESC is not a dismiss shortcut (must-acknowledge). Returns focus to trigger element on close.

**Mobile vs. desktop:** bottom-sheet layout on mobile (slides up, rounded top corners, `--overlay` scrim). Centered fixed-width dialog (max-width `sm`, 400px) on desktop. Detail rows and action buttons stack vertically on mobile; on desktop the optional deep-link action sits beside Dismiss in the footer row.

---

## B.21 Settings & Profile Page

**Purpose:** a single `/settings` destination where users view and edit their own identity (Profile pane) and clinic details (Clinic pane). Replaces the scattered entry points previously found on the home card (clinic edit) and home banner (create-profile CTA). See `Mockups/mockup_settings_profile.png` and `docs/specs/2026-06-20-settings-profile-design.md` (#35).

**Route & shell:** `/settings` — a three-column layout on desktop: app rail → **Settings sub-nav as its own bordered `Card` panel** (SETTINGS eyebrow + icon rows for Profile and Clinic) → active content. The sub-nav is always visible on desktop; on mobile it becomes a top list followed by the section content. Page title is "Settings", subtitle "Manage your clinic and account". A breadcrumb ("Settings › Profile" / "Settings › Clinic") appears above the active pane content on both breakpoints.

**Sub-nav active treatment (updated in theme refresh #65):** the active Settings sub-nav pill uses a **paler** lavender (`bg-primary-container/55` over the card, dark-purple label/icon) — intentionally softer than the app rail's deeper Lilac (`#EADDFF`) active pill, so the two levels of navigation are visually differentiated. Real Material Symbol icons: `person` for Profile, `business` for Clinic.

**Profile pane:**
- **Identity header** — initials avatar (real upload deferred → #70), display name, role chip, specialization, email, phone.
- **Personal Information card** — an Edit action toggles an inline edit form in place (no dialog/drawer). Editable fields: Full Name, Specialization, License Number. Read-only rows: Email, Phone, Role, Joined date. On save → **Success Card** (B.20) "Profile updated".
- **No-doctor-profile state** — when the user has no linked doctor record (`doctor_id` null), doctor-specific rows (Specialization, License Number) are hidden and a **"Create your doctor profile"** CTA is shown; this reuses the full-screen guided wizard (B.19).

**Clinic pane:** hosts the existing clinic-details edit form (relocated from `EditClinicDetailsDialog`). Editable by owner/practice\_manager only; all other roles see read-only clinic details. On save → Success Card "Clinic details saved".

**Navigation wiring:** the app rail gains a **Settings (gear)** destination visible to all roles. The home clinic-card **Edit** button and the create-profile banner CTA both now navigate into `/settings` (Clinic and Profile panes respectively); banner dismiss behaviour is preserved.

**Both themes:** uses `--primary-container` (active sub-nav pill, paled to `/55` opacity in Settings sub-nav per theme refresh #65), `--card`, `--muted-foreground`, `--border` — no hardcoded colors.

**Accessibility:** Edit toggle moves focus to the first editable field; form controls are labelled; breadcrumb uses `aria-label="breadcrumb"`; sub-nav items carry `aria-current="page"` for the active section; both themes WCAG AA.

**Mobile vs. desktop:** mobile — sub-nav list at top of page, content below; stacked edit-form buttons. Desktop — left sub-nav rail + right content area with the active-pill indicator.

---

*End of Design System Specification — 02-design-system.md*
