# Theme & Palette Refresh Implementation Plan (#65)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** App-wide "Calm Soft-Purple" visual refresh — token values (globals.css) + shared Card spacing/divider + Settings layout polish — matching the approved mockup, with zero layout/type/name changes.

**Architecture:** Change values in `src/app/globals.css` (`:root` + `.dark`) → propagates everywhere (Rule 17.0: no component hardcodes colour). Bump `--card-spacing` + add a `CardSeparator` primitive in `src/components/ui/card.tsx`. Refine the Settings components. Frontend-only.

**Tech Stack:** Next.js App Router, Tailwind v4 semantic tokens, Material Symbols, react-i18next.

## Global Constraints
- **Values + spacing + divider + Settings polish ONLY.** Preserve token NAMES, layouts, navigation, typography, interaction patterns. No backend/migration/deps.
- WCAG AA both themes (white on `#6750A4` ≈ 4.9:1). Rule 17.0 (semantic tokens, compose `components/ui/*`, no per-page CSS). i18n en/hi parity for any new strings.
- Commit trailer `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`. Feature branch → PR. Do NOT touch `.env.local`. Commit SPECIFIC paths (never `git add -A`; never stage `.superpowers/`).
- Full spec: `docs/specs/2026-06-20-theme-refresh-design.md`.

---

## Task 1: Palette tokens (globals.css — app-wide)

**Files:** Modify `src/app/globals.css` (`:root` light block + `.dark` block).

- [ ] **Step 1: Light `:root` — change these token VALUES** (leave all others; do not rename):
```
--background:            #F4F4F6;
--muted:                 #ECEAF3;
--border:                #ECE9F3;
--input:                 #C4C1D1;
--ring:                  #6750A4;
--primary:               #6750A4;
--secondary:             #EADDFF;
--secondary-foreground:  #21005D;
--accent:                #EADDFF;
--accent-foreground:     #21005D;
--primary-container:     #EADDFF;
--on-primary-container:  #21005D;
--secondary-container:   #EADDFF;
--on-secondary-container:#21005D;
--surface-variant:       #EADDFF;
--outline:               #7965AF;
--hero-from:             #EADDFF;
--hero-to:               #F6F2FF;
--auth-panel-bg:         #6750A4;
--sidebar:               #EFEAF7;
--sidebar-primary:       #6750A4;
--sidebar-accent:        #EADDFF;
--sidebar-accent-foreground: #21005D;
--sidebar-border:        #ECE9F3;
--sidebar-ring:          #6750A4;
```
And replace the light elevations:
```
--elevation-1: 0 1px 2px rgba(35,30,55,.05);
--elevation-2: 0 2px 10px rgba(35,30,55,.05), 0 1px 3px rgba(35,30,55,.04);
--elevation-3: 0 6px 18px rgba(35,30,55,.08), 0 2px 6px rgba(35,30,55,.05);
--elevation-4: 0 10px 26px rgba(35,30,55,.10), 0 4px 10px rgba(35,30,55,.06);
--elevation-5: 0 16px 36px rgba(35,30,55,.12), 0 6px 14px rgba(35,30,55,.08);
```
(Keep `--background`/`--card` distinct: `--card` stays `#FFFFFF`. `--foreground`, `--muted-foreground` `#46464F`, state colours, radii unchanged.)

- [ ] **Step 2: Dark `.dark` — change these token VALUES:**
```
--background:            #17151E;
--card:                  #211F2A;
--popover:               #211F2A;
--muted:                 #28262F;
--border:                #322F3B;
--primary:               #CFBCFF;
--primary-foreground:    #381E72;
--ring:                  #CFBCFF;
--secondary:             #4A3F66;
--accent:                #4A3F66;
--primary-container:     #4A3F66;
--secondary-container:   #4A3F66;
--surface-variant:       #2A2735;
--sidebar:               #1E1B28;
--sidebar-primary:       #CFBCFF;
--sidebar-accent:        #4A3F66;
--sidebar-border:        #322F3B;
--sidebar-ring:          #CFBCFF;
```
(Dark `--on-primary-container`/`--on-secondary-container` stay `#EADDFF`; `--popover-foreground`, state colours, elevations, radii unchanged.)

- [ ] **Step 3: Verify** — `npx tsc --noEmit && npm run build` clean. Start the dev server and eyeball Home + Settings in light & dark (canvas neutral, rail lavender, cards lift, primary calmer). No build errors.

- [ ] **Step 4: Commit**
```bash
git add src/app/globals.css
git commit -m "feat(theme): Calm Soft-Purple palette — neutral canvas, soft borders/shadows, #6750A4 (#65)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: Card spacing + inset header divider (app-wide)

**Files:** Modify `src/components/ui/card.tsx`; apply `CardSeparator` to header+body cards.

- [ ] **Step 1: Airier spacing.** In `src/components/ui/card.tsx`, in the `Card` component className, change the spacing tokens: `[--card-spacing:--spacing(4)]` → `[--card-spacing:--spacing(5)]` and `data-[size=sm]:[--card-spacing:--spacing(3)]` → `data-[size=sm]:[--card-spacing:--spacing(4)]`. (20px default / 16px sm — airier, app-wide.)

- [ ] **Step 2: Add `CardSeparator`.** In the same file, add and export a subtle inset divider:
```tsx
function CardSeparator({ className, ...props }: React.ComponentProps<"div">) {
  return (
    <div
      data-slot="card-separator"
      role="separator"
      className={cn("mx-(--card-spacing) border-t border-border", className)}
      {...props}
    />
  )
}
```
Add `CardSeparator` to the `export { ... }` block. (Inset by `--card-spacing` → non-edge-to-edge; uses the now-light `--border` → "super subdued".)

- [ ] **Step 3: Apply across header+body cards.** Place `<CardSeparator />` between `CardHeader` and `CardContent` in cards that have a header followed by body content. Grep usages (`grep -rl "CardHeader" src`) and add it to each card with a meaningful header→body split (e.g. dashboard/home cards, patient detail, requests queue, schedule cards). Do NOT add to cards that are header-only or have no distinct body. This is the app-wide divider rollout.

- [ ] **Step 4: Verify** — `npx tsc --noEmit && npm run build` clean; eyeball a couple of cards (divider is subtle + inset; spacing airier).

- [ ] **Step 5: Commit**
```bash
git add src/components/ui/card.tsx <the card consumer files you touched>
git commit -m "feat(theme): airier card spacing + subtle inset CardSeparator, applied app-wide (#65)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: Settings layout polish (match mockup)

**Files:** Modify `src/features/settings/settings-shell.tsx`, `src/features/settings/profile-pane.tsx` (and `clinic-pane.tsx` if needed for the divider).

> **Read `Mockups/mockup_settings_profile.png`** for the target.

- [ ] **Step 1: Sub-nav as a bordered panel + softer active.** In `settings-shell.tsx`, wrap the sub-nav in a bordered `Card` panel (the existing `<nav>` becomes the content of a `<Card>` with a "SETTINGS" eyebrow above the items), always visible on desktop (`md:` column, as now). Change the active item style: keep the deeper app-rail Lilac for the MAIN rail (unchanged, in `app-shell.tsx`), but the **settings sub-nav active** uses a softer pale lavender — `bg-primary-container/55 text-on-primary-container` (instead of full `bg-primary-container`). Keep the real Material Symbol icons (person/Profile, domain or business/Clinic) and testids.

- [ ] **Step 2: Profile header — Edit pill, stacked header, no camera.** In `profile-pane.tsx`:
  - Move **Edit** into the Profile card header **top-right** as an outlined pill: `<Button variant="outlined" size="sm">` containing `<Icon name="edit" size={16} />` + `t("settings.profile.edit")`. (Use the existing edit toggle handler.) Remove the bottom/elsewhere Edit button.
  - **Header block:** initials avatar (NO camera badge — remove the camera affordance entirely), then to the right: **Name** (`text-lg font-semibold`) with the Owner/role chip inline, then **email** (`text-sm text-muted-foreground`), then **phone** (`text-sm text-muted-foreground`) — each stacked on its own line.
  - Add `<CardSeparator />` (from Task 2) under the card header (between the "Profile / Manage…" header and the body) per the mockup.
- [ ] **Step 3:** Ensure the Clinic pane (`clinic-pane.tsx`) header also uses the inset `CardSeparator` for consistency.

- [ ] **Step 4: Verify** — `npx tsc --noEmit && npm run build` clean; i18n parity holds (no new keys unless added → if so, mirror en/hi). Eyeball `/settings` in light + dark: 3-column, bordered sub-nav panel, softer active pill, top-right pencil Edit, stacked header, no camera, subtle divider.

- [ ] **Step 5: Commit**
```bash
git add src/features/settings/
git commit -m "feat(settings): bordered sub-nav panel, top-right Edit pill, stacked header, no camera, softer active (#65)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: Docs (design-system)

**Files (docs repo):** `Design/02-design-system.md`.

- [ ] **Step 1:** `git checkout main && git pull --ff-only && git checkout -b docs/theme-refresh-65`.
- [ ] **Step 2:** Update the palette section with the new "Calm Soft-Purple" values (light + dark), note the airier `--card-spacing` and the `CardSeparator` inset-divider pattern, and the Settings sub-nav/active treatment. Reference `docs/specs/2026-06-20-theme-refresh-design.md` (#65).
- [ ] **Step 3: Commit** with the trailer.

---

## Final Verification (before PRs)
- [ ] `npx tsc --noEmit && npm run build` clean; i18n parity.
- [ ] **Manual visual pass (both themes):** Home, Patients, Schedule (My + Clinic), Requests, Settings (Profile + Clinic), auth/onboarding — neutral canvas, lavender rail, calmer primary, soft borders/shadows, airier cards, subtle inset dividers; no contrast breakage, no hardcoded-colour islands, no layout breakage.
- [ ] Frontend PR `Closes #65`; docs PR `Part of #65`.

## Self-Review (against spec §2–§6)
- **§2 palette (light+dark exact values + softened elevations):** Task 1. ✅
- **§3 airier spacing (`--card-spacing`):** Task 2 Step 1. ✅
- **§4 inset header divider (`CardSeparator`, app-wide):** Task 2 Steps 2–3. ✅
- **§5 Settings polish (bordered sub-nav panel, softer active, top-right pencil Edit, stacked header, no camera, divider):** Task 3. ✅
- **§6 app-wide application + cross-screen verification (both themes):** Task 2 Step 3 + Final Verification. ✅
- **Preserve names/layout/type; no backend/deps:** honored throughout. ✅
- **Placeholder scan:** Task 2 Step 3 ("grep CardHeader usages, add divider to header+body cards") is a concrete rollout step, not a TBD; exact token values + component code are inline. ✅
- **Type consistency:** `CardSeparator` exported from card.tsx + consumed in Task 3; token names unchanged. ✅
