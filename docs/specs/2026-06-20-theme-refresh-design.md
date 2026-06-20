# Theme & Palette Refresh — Design Spec (#65)

**Status:** Approved (brainstorm + visual-companion iteration 2026-06-20; frontend-design lens applied; ref `Mockups/mockup_settings_profile.png`).
**Type:** App-wide **visual refresh** — token values + shared-component spacing/divider + Settings layout polish. **NOT a redesign.** Preserve layouts, navigation, component hierarchy, typography, interaction patterns, and **semantic token NAMES** (values change only). Frontend-only; no backend/migration; no new dependencies.

## 1. Goal
Make the UI feel calm, warm, and premium for all-day clinical use — fixing the "industrial" feel (too-bright canvas, flat white-on-white cards, hard borders, electric primary). Direction = Linear/Notion/Apple calm, matched to the approved mockup. Applies across the **entire frontend** (propagates via `globals.css` tokens + the shared `Card` primitive; Rule 17.0 means no component hardcodes colour).

## 2. Palette — "Calm Soft-Purple" (exact token values)

Replace the values in `src/app/globals.css`. **Only values listed change; every other token stays.** Token names unchanged.

### Light (`:root`)
| Token | Current | New | Why |
|---|---|---|---|
| `--background` | `#FCFCFF` | **`#F4F4F6`** | neutral calm canvas (NOT lavender — purple lives in the rail/chrome, not the backdrop) |
| `--card` | `#FFFFFF` | `#FFFFFF` | keep — now lifts off the dimmer canvas |
| `--muted` | `#E4E2EC` | **`#ECEAF3`** | softer fills |
| `--border` | `#C7C5D0` | **`#ECE9F3`** | light hairline — cards read as shadow-elevated, not boxed |
| `--input` | `#767680` | **`#C4C1D1`** | softer input outline |
| `--ring` | `#7C3AED` | **`#6750A4`** | match primary |
| `--primary` | `#7C3AED` | **`#6750A4`** | M3 Soft Purple — calm/premium, not electric |
| `--secondary`,`--accent`,`--primary-container`,`--secondary-container`,`--surface-variant`,`--sidebar-accent` | `#EDE9FE` | **`#EADDFF`** | warm Lilac container (chips, app-rail active pill) |
| `--secondary-foreground`,`--accent-foreground`,`--on-primary-container`,`--on-secondary-container` | (various) | **`#21005D`** | dark-purple on Lilac |
| `--outline` | `#8B5CF6` | **`#7965AF`** | calmer outline |
| `--ring`,`--auth-panel-bg`,`--sidebar-primary`,`--sidebar-ring` | `#7C3AED` | **`#6750A4`** | match primary |
| `--sidebar` | `#EDE9FE` | **`#EFEAF7`** | the lavender rail hue (kept/loved) |
| `--sidebar-border` | `#C7C5D0` | **`#ECE9F3`** | soft |
| `--hero-from`/`--hero-to` | lavender | `#EADDFF` / `#F6F2FF` | soft hero |
| **elevations** | (see below) | **softened, faint-purple-tinted** | gentler lift |

Softened light elevations:
```
--elevation-1: 0 1px 2px rgba(35,30,55,.05);
--elevation-2: 0 2px 10px rgba(35,30,55,.05), 0 1px 3px rgba(35,30,55,.04);
--elevation-3: 0 6px 18px rgba(35,30,55,.08), 0 2px 6px rgba(35,30,55,.05);
--elevation-4: 0 10px 26px rgba(35,30,55,.10), 0 4px 10px rgba(35,30,55,.06);
--elevation-5: 0 16px 36px rgba(35,30,55,.12), 0 6px 14px rgba(35,30,55,.08);
```

### Dark (`.dark`)
| Token | Current | New | Why |
|---|---|---|---|
| `--background` | `#131318` | **`#17151E`** | deep charcoal-lavender, off near-black (less harsh) |
| `--card`,`--popover` | `#1E1E25` | **`#211F2A`** | lifted for separation |
| `--muted` | `#2A2A33` | **`#28262F`** | — |
| `--border`,`--sidebar-border` | `#3A3A42` | **`#322F3B`** | subtler |
| `--primary`,`--ring`,`--sidebar-primary`,`--sidebar-ring` | `#C4B5FD` | **`#CFBCFF`** | soft lilac primary |
| `--primary-foreground` | `#2E1065` | **`#381E72`** | — |
| `--primary-container`,`--secondary`,`--accent`,`--secondary-container`,`--sidebar-accent` | `#4C1D95`/`#3B2A6A` | **`#4A3F66`** | calmer (less saturated) container |
| `--sidebar` | `#1E1530` | **`#1E1B28`** | rail |
| `--surface-variant` | `#2A1F40` | **`#2A2735`** | — |

**Accessibility:** WCAG AA preserved both themes (white on `#6750A4` ≈ 4.9:1; text on Lilac high-contrast; verify any borderline pair). State colours (destructive/success/warning/info) unchanged.

## 3. Spacing — airier rhythm (app-wide)
Bump the shared card spacing for breathing room matching the mockup: in `src/components/ui/card.tsx`, change `--card-spacing` from `--spacing(4)` (16px) to **`--spacing(5)` (20px)** (and `sm` from `--spacing(3)`→`--spacing(4)`). This widens padding + internal gaps on **every** card app-wide.

## 4. Subtle inset header divider (app-wide)
A **light, non-edge-to-edge** rule separating a card's header from its body (per the mockup). Implementation (resolved in plan): a `CardSeparator` element — `mx-(--card-spacing) border-t border-border` — placed between `CardHeader` and `CardContent`, so it's inset by the card padding and uses the (now light) `--border`. Applied to header+body cards across the app (Settings panes, profile, dashboard cards, list cards with a header). Very subtle by design.

## 5. Settings layout polish (refine the shipped #35 Settings UI to match the mockup)
- **Three-column, sub-nav always visible on desktop:** app rail → **Settings sub-nav as its own bordered `Card` panel** (SETTINGS eyebrow + icon rows) → active content. On mobile, the sub-nav stays a horizontal/list selector (current responsive behaviour).
- **Sub-nav active pill softer than the app rail:** app-rail active keeps the deeper Lilac (`primary-container` `#EADDFF`); the **settings sub-nav active** uses a **paler** lavender (`bg-primary-container/55` over the card) with dark-purple label/icon. Real Material Symbol icons (person/Profile, business/Clinic).
- **Edit = top-right outlined pill** with the real `edit` (pencil) icon, purple outline+text, in the Profile card header (replaces the bottom filled button).
- **Profile header hierarchy:** avatar (initials, **no camera badge** — avatar upload is #70) + **Name** (bold) with Owner chip, then **email**, then **phone** stacked beneath.
- Inset header divider (§4) under the "Profile / Manage…" header.

## 6. Scope & application
- **App-wide:** the palette (tokens), spacing (`--card-spacing`), softer border/shadows, and the header divider apply everywhere automatically via `globals.css` + the `Card` primitive (+ adding `CardSeparator` to header+body cards). The Settings polish (§5) is Settings-specific.
- **Verify across screens:** after applying, sanity-check Home, Patients, Schedule (My/Clinic), Requests, Settings, and the auth/onboarding screens in **both themes** — no broken contrast, no hardcoded-colour islands surfacing, no layout breakage.
- **Out of scope:** no layout/navigation/typography/interaction changes beyond §3–§5; no token renames; no new features; next-themes already in use (no architecture change). Avatar upload (#70) and clinic timezone (#71) remain separate.

## 7. Testing
- `tsc --noEmit` + `npm run build` clean; i18n en/hi parity (no new strings expected beyond the Settings polish, if any).
- Manual visual pass across the screens in §6, both themes (the real verification for a palette change).
- Update `Design/02-design-system.md` palette + Card sections after merge.
