# 03 — Theme System

**Status:** Draft for review
**Date:** 2026-06-18
**Depends on:** `02-color-tokens.md` (token names and primitive scale)

---

## 1. Purpose

This document defines how theming works: the architecture, the switching strategy, the per-theme token values, and the authoring rules every contributor must follow. Doc 02 defines the token names; this doc defines how those same tokens take different values in light and dark contexts and how the system moves between them.

---

## 2. Theme Architecture — Two-Layer Token Model

The design system uses a strict two-layer model:

```
Primitive scale  →  Semantic tokens  →  Component styles
(raw values)        (CSS variables)     (Tailwind utilities)
```

### Layer 1 — Primitives

Raw, unnamed values: the neutral ramp, the indigo ramp, and functional hues (red, green, amber, blue). Primitives are defined once and never referenced directly in components or in Tailwind class names. They exist only as the source material that semantic tokens draw from.

### Layer 2 — Semantic tokens

Semantic tokens are named by **role**, not by value: `--primary`, `--background`, `--destructive`. They are implemented as CSS custom properties. Light and dark are not separate token sets — they are two value assignments for the exact same token names.

```
Same token name:   --primary
Light value:       #4F46E5   (indigo-600)
Dark value:        #6366F1   (indigo-500)
```

Components reference only semantic tokens via Tailwind CSS variable utilities (`bg-[--background]`, `text-[--foreground]`, `border-[--border]`, etc.). Because components never touch a primitive, switching themes requires no component changes — the CSS variable values flip and every surface updates automatically.

---

## 3. CSS Variable Scoping Strategy

Semantic tokens are declared as CSS custom properties. Light-theme values live on `:root`; dark-theme values live on `.dark` (or equivalently `[data-theme="dark"]` on `<html>`). Tailwind v4's `@theme` block maps each variable to a Tailwind design token so utility classes resolve at runtime.

```css
/* Light theme — :root (default) */
:root {
  --background: #FFFFFF;
  --foreground: #0B0B0F;
  --card:        #FFFFFF;
  --card-foreground: #0B0B0F;
  --muted:       #F4F5F7;
  --muted-foreground: #6B7280;
  --border:      #E5E7EB;
  --input:       #E5E7EB;
  --ring:        #4F46E5;
  --primary:     #4F46E5;
  --primary-foreground: #FFFFFF;
  --secondary:   #F3F4F6;
  --secondary-foreground: #111827;
  --accent:      #F3F4F6;
  --accent-foreground: #111827;
  --destructive: #DC2626;
  --destructive-foreground: #FFFFFF;
  --success:     #16A34A;
  --success-foreground: #FFFFFF;
  --warning:     #D97706;
  --warning-foreground: #111827;
  --info:        #2563EB;
  --info-foreground: #FFFFFF;
  --overlay:     rgba(0, 0, 0, 0.50);
}

/* Dark theme */
.dark {
  --background: #0B0C0E;
  --foreground: #F4F5F7;
  --card:        #141517;
  --card-foreground: #F4F5F7;
  --muted:       #1C1D21;
  --muted-foreground: #9CA3AF;
  --border:      #27282D;
  --input:       #27282D;
  --ring:        #6366F1;
  --primary:     #6366F1;
  --primary-foreground: #FFFFFF;
  --secondary:   #1F2028;
  --secondary-foreground: #E5E7EB;
  --accent:      #1F2028;
  --accent-foreground: #E5E7EB;
  --destructive: #EF4444;
  --destructive-foreground: #FFFFFF;
  --success:     #22C55E;
  --success-foreground: #FFFFFF;
  --warning:     #F59E0B;
  --warning-foreground: #111827;
  --info:        #3B82F6;
  --info-foreground: #FFFFFF;
  --overlay:     rgba(0, 0, 0, 0.60);
}
```

**No hardcoded color values appear anywhere outside this block.**

---

## 4. Light vs Dark Value Table

Representative hex/oklch values — tune at implementation time. All pairs must pass WCAG 2.1 AA (4.5:1 for body text; 3:1 for large text and UI elements).

| Semantic token | Light value | Dark value | Notes |
|---|---|---|---|
| `--background` | `#FFFFFF` | `#0B0C0E` | App canvas |
| `--foreground` | `#0B0B0F` | `#F4F5F7` | Primary text on canvas |
| `--card` / `--popover` | `#FFFFFF` | `#141517` | Surface; slightly lifted in dark |
| `--card-foreground` | `#0B0B0F` | `#F4F5F7` | Text on card surfaces |
| `--muted` | `#F4F5F7` | `#1C1D21` | Subtle fills, tag backgrounds |
| `--muted-foreground` | `#6B7280` | `#9CA3AF` | Secondary text; must still pass AA |
| `--border` | `#E5E7EB` | `#27282D` | Hairline separators; use sparingly |
| `--input` | `#E5E7EB` | `#27282D` | Field borders |
| `--ring` | `#4F46E5` | `#6366F1` | Focus ring; visible against both canvases |
| `--primary` | `#4F46E5` (indigo-600) | `#6366F1` (indigo-500) | Calm indigo; actions, links, active state |
| `--primary-foreground` | `#FFFFFF` | `#FFFFFF` | Label on primary fills |
| `--secondary` | `#F3F4F6` | `#1F2028` | Neutral secondary buttons/fills |
| `--secondary-foreground` | `#111827` | `#E5E7EB` | Label on secondary fills |
| `--accent` | `#F3F4F6` | `#1F2028` | Hover/selected bg tint; neutral, NOT indigo |
| `--accent-foreground` | `#111827` | `#E5E7EB` | Text on accent fills |
| `--destructive` | `#DC2626` | `#EF4444` | Errors, delete actions |
| `--destructive-foreground` | `#FFFFFF` | `#FFFFFF` | Label on destructive fills |
| `--success` | `#16A34A` | `#22C55E` | Confirmations, done states |
| `--success-foreground` | `#FFFFFF` | `#FFFFFF` | Label on success fills |
| `--warning` | `#D97706` | `#F59E0B` | Cautionary states |
| `--warning-foreground` | `#111827` | `#111827` | Label on warning fills (dark text on amber — AA) |
| `--info` | `#2563EB` | `#3B82F6` | Informational states |
| `--info-foreground` | `#FFFFFF` | `#FFFFFF` | Label on info fills |
| `--overlay` | `rgba(0,0,0,0.50)` | `rgba(0,0,0,0.60)` | Modal/sheet scrim |

**Indigo rule:** `--primary` and `--ring` are the only surfaces that use indigo. Indigo must not appear as a background, decoration, or hover tint. The canvas stays neutral.

**Dark elevation note:** in dark mode, elevation is expressed by lighter surface values, not by heavier shadows. `--card` (`#141517`) sits visibly above `--background` (`#0B0C0E`). Keep shadows subtle; avoid heavy shadow values in dark.

---

## 5. Theme Switching Strategy

### 5.1 Three modes

| Mode | Behaviour |
|---|---|
| **Light** | User has explicitly chosen light. `.dark` class absent from `<html>`. |
| **Dark** | User has explicitly chosen dark. `.dark` class present on `<html>`. |
| **Follow System** | Default until the user picks. Reads `prefers-color-scheme` and applies the matching class. Updates automatically when the OS setting changes. |

Dark mode is a primary design target, not a derived afterthought. Every component is designed in dark first alongside light — not adapted after the fact.

### 5.2 Web implementation — next-themes

```tsx
// app/layout.tsx (or equivalent root layout)
import { ThemeProvider } from 'next-themes'

export default function RootLayout({ children }) {
  return (
    <html lang="en" suppressHydrationWarning>
      <body>
        <ThemeProvider
          attribute="class"          // adds/removes .dark on <html>
          defaultTheme="system"      // Follow System until user picks
          enableSystem               // react to prefers-color-scheme
          disableTransitionOnChange  // prevent flash during SSR hydration
        >
          {children}
        </ThemeProvider>
      </body>
    </html>
  )
}
```

Key points:
- `attribute="class"` — Tailwind's `dark:` variant and `.dark { }` CSS blocks both read the class.
- `defaultTheme="system"` — no explicit user choice defaults to Follow System.
- `enableSystem` — next-themes subscribes to the `prefers-color-scheme` media query; when the OS switches, the class updates without a page reload.
- `suppressHydrationWarning` on `<html>` — prevents React's hydration warning caused by the server not knowing the client's OS preference. This is the standard pattern; it does not suppress meaningful errors.

### 5.3 Theme toggle component

The toggle must cycle through Light / Dark / System (or offer all three explicitly). It reads the current `resolvedTheme` from `useTheme()` to display the correct icon and label. Example shape:

```tsx
import { useTheme } from 'next-themes'

function ThemeToggle() {
  const { theme, setTheme, resolvedTheme } = useTheme()
  // render a button or segmented control; aria-label reflects current state
  // options: setTheme('light') | setTheme('dark') | setTheme('system')
}
```

The toggle must be keyboard-accessible (focusable, `Enter`/`Space` activates), must carry an `aria-label` describing the current state ("Switch to dark mode"), and must display the focus ring (`--ring`) visibly in both themes.

### 5.4 Reacting to OS changes in System mode

When `theme === 'system'`, `resolvedTheme` reflects the current OS preference and updates in real time via the `prefers-color-scheme` media query listener managed by next-themes. Components should read `resolvedTheme` (not `theme`) when they need to know the active visual mode — for example, to choose between a light and dark logo variant.

### 5.5 Native iOS and Android

Native apps mirror the same semantic token values via their respective platform theming systems:
- **iOS:** `UIColor` dynamic colors / SwiftUI `Color` with light and dark variants matching the token table above. The app follows `UIUserInterfaceStyle` (system default; user can override in app settings).
- **Android:** Material You `colorScheme` or manual `Light/DarkTheme` resources carrying the same values. Follows `UiModeManager` / `AppCompatDelegate`.

Both platforms follow the OS appearance by default. User overrides (when exposed in the app) write to a persisted preference (see Section 6).

---

## 6. Persistence

| Scope | Mechanism | Default |
|---|---|---|
| Web (session and across sessions) | `localStorage` via next-themes key `theme` | `"system"` |
| Native iOS | `UserDefaults` key `app.theme` | `"system"` |
| Native Android | `SharedPreferences` key `app_theme` | `"system"` |
| Signed-in users (future) | User preference record synced server-side | `"system"` |

Until explicit user-preference syncing is implemented, the web localStorage value is the source of truth for web and native apps store their own preference locally. When the signed-in preference feature ships, the explicit choice stored locally is uploaded on next sign-in and applied across all devices; the local value acts as a cache.

System is always the default: a user who has never touched the theme control gets whatever their OS is set to.

---

## 7. Per-Component Requirements

Every component in the design system must satisfy all of the following:

### Both themes, by design

No component is considered complete unless it has been designed and reviewed in both light and dark. Designs handed to implementation must include both states. Dark is not a "dark:override pass" done at the end — it is part of the initial design.

### Contrast (WCAG 2.1 AA)

- Body text and interactive labels: 4.5:1 against their background in both themes.
- Large text (≥ 18px regular or ≥ 14px bold): 3:1 in both themes.
- UI elements (icons, input borders against their surface): 3:1 in both themes.
- `--muted-foreground` must pass AA — it is a common failure point; verify explicitly.
- State colors (`--destructive`, `--success`, `--warning`, `--info`) must pass AA in both themes when used as text or icon fills against `--background` and `--card`.

### Elevation in dark

In dark mode, elevation is communicated primarily through surface lightness, not shadow weight. The stepped surface values (`--background` → `--card` → popovers) provide the visual lift. Shadows remain soft:

| Level | Shadow |
|---|---|
| 0 — flat | none |
| 1 — resting card | `0 1px 2px rgba(0,0,0,0.06)` |
| 2 — popover/dropdown | `0 4px 12px rgba(0,0,0,0.10)` |
| 3 — modal/sheet | `0 12px 32px rgba(0,0,0,0.18)` + `--overlay` scrim |

Avoid increasing shadow opacity in dark mode beyond the values above.

### Focus ring

Every interactive element (button, input, link, toggle, select, tab) must render the focus ring (`outline` or `box-shadow` using `--ring`) when it receives keyboard focus. The ring must be visually distinct in both themes. Test with Tab key in a browser — if you cannot see where focus is, the component is not complete.

---

## 8. Authoring Rules

### 8.1 Never hardcode a color

All color references in component code, Tailwind class names, and CSS must resolve to a CSS variable. There are no exceptions.

**Bad:**
```tsx
// Hardcoded hex — breaks in dark mode, breaks if the token value changes
<div className="bg-[#4F46E5] text-white">
```

**Bad:**
```css
/* Hardcoded Tailwind palette color — same problem */
.my-component { background-color: theme('colors.indigo.600'); }
```

**Good:**
```tsx
// Semantic token via CSS variable — flips automatically per theme
<div className="bg-[--primary] text-[--primary-foreground]">
```

**Good:**
```css
.my-component { background-color: var(--primary); color: var(--primary-foreground); }
```

### 8.2 Adding a new token

Follow this checklist for every new semantic token:

1. **Name it by role**, not by value. `--surface-raised` not `--gray-100`.
2. **Define it in both themes.** Add the light value to `:root` and the dark value to `.dark` in the global CSS file. Never add a token to only one theme.
3. **Document it in doc 02** (the color token reference) with its purpose, light value, dark value, and a note on which components use it.
4. **Verify contrast in both themes** before the PR is opened. Use a contrast checker against the surface it appears on.
5. **Do not add tokens for one-off use.** If a value is needed by a single component in a non-standard way, question whether a token is the right abstraction or whether the component should use an existing token differently.

### 8.3 Verifying a component

Before marking any component as ready for implementation:

- [ ] Designed in light — screenshot or frame reviewed.
- [ ] Designed in dark — screenshot or frame reviewed.
- [ ] All text contrast checked: body 4.5:1, large text 3:1, in both themes.
- [ ] UI element contrast checked: icons, borders 3:1, in both themes.
- [ ] Focus ring visible with keyboard navigation in both themes.
- [ ] No hardcoded color values in the component's code or Tailwind classes.
- [ ] Elevation expressed correctly for the component's level (surface color in dark; appropriate shadow in light).

### 8.4 Indigo reservation

Indigo (`--primary`, `--ring`) is reserved for:
- Primary action buttons (solid fill)
- Links and inline actions
- Active/selected state indicators
- Focus rings

Indigo must not appear as:
- A background or decorative fill
- A hover tint (use `--accent` for hover backgrounds)
- Any surface that is not a primary action or active indicator

If a design calls for an indigo surface that is not a primary action or active state, it is a token misuse — revise the design.

---

## 9. Quick Reference — How Themes Interlock

```
OS preference (prefers-color-scheme)
        │
        ▼  (when theme = "system")
next-themes resolves → adds/removes .dark on <html>
        │
        ▼
CSS: .dark { --background: #0B0C0E; --primary: #6366F1; ... }
        │
        ▼
Tailwind utility: bg-[--background]  →  resolves to dark value
        │
        ▼
Component renders correctly in dark — zero code changes needed
```

The same flow applies when the user explicitly picks Light or Dark — next-themes writes to localStorage and sets the class; the CSS cascade does the rest.
