# Move Clinic Details: Home → Settings → Clinic — Design Spec (#85)

**Status:** Approved (brainstorm + frontend-design render 2026-06-21; render approved "just how I want them"). Refs the user's mockup (Settings → Clinic) + the approved render at `/tmp/clinic-settings-render/index.html`.
**Type:** **Frontend-only** composition move. All data + dialogs already exist — no backend, no migration. Part of the #80 design-language consistency effort. Calm Soft-Purple (#65) + the existing Settings/Profile layout language.

## 1. Goal
Relocate **all clinic details (view + edit)** off the Home dashboard into **Settings → Clinic**, redesigned to match the approved mockup. Home becomes a clean personalized welcome (keeping its operational widgets). Settings → Clinic becomes the single home for clinic info + profile completion.

## 2. Scope decisions (locked)
- **Frontend-only.** Reuse `useClinic`, `EditClinicDetailsDialog`, `ClinicAddressPreview`, `computeClinicCompleteness`. No new endpoints, no migration.
- **Home after the move:** personalized greeting **+ keep** the create-profile nudge (`CreateProfileBanner`) and the Pending Requests card (`PendingRequestsCard`). Remove the three clinic-detail blocks (Clinic Summary card, `ClinicAddressPreview`, `ClinicCompleteness`).
- **Settings sub-nav:** keep only the two built sections — **Profile** + **Clinic**. Omit the mockup's unbuilt rows (Scheduling/Notifications/Billing & Plan/Team/Integrations) until built (no dead links).
- **Completion card:** adopt the mockup's circular % ring + progress bar + "X of N steps completed" + **Complete Profile** button (opens the edit dialog), **and** keep the 5 per-item check rows below it.
- **Match the Settings → Profile pane conventions exactly** (see §5) so Clinic feels identical in weight/typography/spacing.

## 3. Home changes (`src/app/page.tsx` → `HomeShell`)
- **Greeting:** replace the `PageHeader` + Clinic Summary with a personalized welcome.
  - If `me.data.name` is set → title `t("home.welcomeName", { name })` = "Welcome, {name}" (name in `text-primary`).
  - Else → `t("home.welcomeBack")` = "Welcome back".
  - Subtitle = `membership.clinic_name` (`text-sm text-muted-foreground`), shown when present.
  - Use a real heading (`h1`, `text-3xl font-bold tracking-tight` — consistent with our page headings) inside `PageContainer`.
- **Remove from Home:** the Clinic Summary `Card` (lines ~72–199), `<ClinicAddressPreview>`, `<ClinicCompleteness>`, and the now-unused imports (`Card*`, `Icon`, `buttonVariants`, `Link`, `ClinicAddressPreview`, `ClinicCompleteness`, `useClinic` if no longer used).
- **Keep on Home:** `CreateProfileBanner` (when `me.data && !me.data.doctor_id`) and `PendingRequestsCard` (when `clinicId`). Onboarding / loading / error branches unchanged.
- `useClinic` is no longer needed on Home (clinic data now only used in Settings) — drop the call.

## 4. Settings → Clinic redesign (`src/features/settings/clinic-pane.tsx`)
Rebuild `ClinicPane` to compose two cards (wrapper `<div className="space-y-5" data-testid="settings-clinic">`), mirroring Profile's structure:

### 4a. Clinic Information card
- `Card` → `CardHeader` with `CardTitle` = `t("settings.clinic.title")` ("Clinic Information") + `<p className="text-sm text-muted-foreground">` = `t("settings.clinic.subtitle")` ("Update your clinic details"), and `CardAction` containing the edit trigger (`EditClinicDetailsDialog`, gated on `canManage`). → `CardSeparator` → `CardContent`.
- **Two-column content** (`grid grid-cols-1 lg:grid-cols-2 gap-x-10 gap-y-5`, stacks on mobile):
  - **Left column** — label/value pairs via the shared row pattern: Clinic Name (`c.name`), Phone Number (`c.phone`), WhatsApp Number (`c.whatsapp_number`), Email (`c.email`). Each: label `text-sm text-muted-foreground` above value `text-sm font-medium text-foreground`, `—` when empty.
  - **Right column** — **Address** (`c.formatted_address`, `whitespace-pre-line`; `—` when empty) + a **Google Maps** link (`c.google_maps_url`, `t("clinic.directions")`, `text-primary`) when present; then **Address Preview**: reuse the boxed preview look from `ClinicAddressPreview` (a `rounded-lg bg-muted/50 px-4 py-3` block with clinic name bold + `formatted_address`), shown only when `formatted_address` exists.
- Loading: `clinic.isPending` → `t("common.loading")` in `CardContent`.

> The label-on-top/value-below two-column layout (not Profile's single-column `row()` list) is intentional per the mockup; typography/weights/tokens still match Profile (`text-sm`, `text-muted-foreground` labels, `font-medium text-foreground` values).

### 4b. Clinic Profile Completion card
- `Card` → `CardContent` (no separate header needed; matches the mockup's single-block card). Drive everything from `computeClinicCompleteness(c)` → `{ items, percent }`.
- **Top row** (`flex items-center gap-5`, stacks on mobile):
  - **Ring** — circular progress using a conic-gradient ring (`bg-[conic-gradient(...)]` via an inline `--p` custom property = `percent`, ring colour `var(--primary)`, track `var(--muted)`), inner `bg-card` disc showing `{percent}%` (`text-base font-bold`). Pure CSS, token-only, no new deps. `data-testid="clinic-completion-ring"`.
  - **Body** (`flex-1`): title `t("clinic.completeness.title")` ("Clinic Profile Completion", `font-semibold`); subtitle `t("clinic.completeness.subtitle")` ("Complete your clinic profile to build trust with your patients", `text-sm text-muted-foreground`); a progress bar (`h-2 rounded-full bg-muted` track + `bg-primary` fill at `width:{percent}%`); steps line `t("clinic.completeness.steps", { done, total })` = "{done} of {total} steps completed" (`text-xs text-muted-foreground`), where `done = items.filter(i => i.present).length`, `total = items.length` (5).
  - **Complete Profile** button (`Button size="sm"`, filled) — opens the same edit-clinic dialog as the Edit pill. Gated on `canManage`. `data-testid="clinic-complete-profile"`.
- **Check rows** below (`flex flex-wrap gap-x-6 gap-y-2`): the existing per-item rows from `ClinicCompleteness` — `check_circle`/`radio_button_unchecked` icon (present → `text-primary`, absent → `text-muted-foreground`) + `t("clinic.completeness.{key}")`. `data-testid="completeness-item-{key}"` (preserve existing testids).

### 4c. Edit trigger wiring
- Both the **Edit** pill (CardAction) and **Complete Profile** button open `EditClinicDetailsDialog`. Inspect the dialog's current API (`src/features/clinic/edit-clinic-details-dialog.tsx`): if it self-manages its trigger/open state, render two instances or lift its open state so both triggers share one dialog. Implementer chooses the cleanest of: (a) controlled `open`/`onOpenChange` prop, or (b) two dialog instances. No behavior change to the dialog itself.

## 5. Match the Profile pane (cohesion contract)
Mirror `src/features/settings/profile-pane.tsx` exactly for shared elements:
- `Card` (default, no extra shadow class) → `CardHeader` (`CardTitle` + `text-sm text-muted-foreground` subtitle) → **`CardSeparator`** (inset divider) → `CardContent`.
- Edit affordance: `Button variant="outlined" size="sm"` + `Icon name="edit" size={16}` inside `CardAction`.
- Section/card titles use `CardTitle`; icons in titles are `size={18}`.
- Label/value typography: labels `text-sm text-muted-foreground`; values `text-sm font-medium text-foreground`; `—` fallback for empties.
- Outer vertical rhythm `space-y-5`.

## 6. i18n (en + hi parity — gated)
- **Add:** `home.welcomeName` ("Welcome, {{name}}" / Hindi), `clinic.completeness.subtitle`, `clinic.completeness.steps` ("{{done}} of {{total}} steps completed" / Hindi), `clinic.completeProfile` ("Complete Profile"), `settings.clinic.whatsapp`, `settings.clinic.address`, `settings.clinic.addressPreview` (+ Hindi for all).
- **Reuse existing:** `home.welcomeBack`, `clinic.editDetails`, `clinic.directions`, `clinic.completeness.title`, `clinic.completeness.{name,address,phone,whatsapp,email}`, `settings.clinic.title`, `settings.clinic.subtitle`, `settings.clinic.name/phone/email`, `common.loading`.
- All new keys in BOTH `en` and `hi` (the `tests/e2e/i18n.spec.ts` parity gate must pass).

## 7. Components / files touched
- **Modify:** `src/app/page.tsx` (Home strip + greeting), `src/features/settings/clinic-pane.tsx` (full rebuild), `src/features/clinic/edit-clinic-details-dialog.tsx` (only if needed to share open state), `src/i18n/locales/en.json` + `hi.json` (or wherever locale resources live).
- **Reuse (unchanged):** `useClinic`, `EditClinicDetailsDialog`, `computeClinicCompleteness`, `Card`/`CardHeader`/`CardTitle`/`CardAction`/`CardContent`/`CardSeparator`, `Button`, `Icon`, `PageContainer`.
- **No longer rendered (but keep the files; still used elsewhere or as references):** `ClinicAddressPreview` / `ClinicCompleteness` are no longer imported by Home. Note: their visual patterns are inlined into the new Clinic pane. If, after the move, neither is imported anywhere, the implementer may delete them and their tests — but only if truly unreferenced (grep first); otherwise leave them.

## 8. Scope guards / deferred (logged on #85)
- The other mockup sub-nav sections (Scheduling/Notifications/Billing/Team/Integrations) — built as their own features later.
- No new clinic fields. No avatar (that's #70). No backend changes.

## 9. Quality
- **Rule 17.0:** semantic tokens only (no raw colours / Tailwind palette utilities), compose `components/ui/*`, no per-page CSS, no new tokens.
- **i18n:** en/hi parity for all new keys (gated).
- Both themes (light/dark); mobile-first (2-col stacks; ring/body stack); WCAG AA (the ring/bar are decorative — the steps line + check rows carry the accessible text).
- **CI = `tsc --noEmit` + `npm run build`** clean (frontend CI runs these two only). Run `npx playwright test tests/e2e/i18n.spec.ts` locally for parity.
- **Merge policy:** this is a frontend branch → open the PR and **STOP**; hand to the user to test; merge only on their explicit say-so (per standing rule).

## 10. Self-review (against the request)
- Clinic details moved off Home into Settings → Clinic: §3 + §4. ✅
- Home = personalized "Welcome, {name}" / "Welcome back" + keeps both widgets: §3. ✅
- Clinic Information 2-col (name/phone/whatsapp/email + address + preview) with Edit: §4a. ✅
- Completion card (ring + bar + steps + Complete Profile) + check rows: §4b. ✅
- Sub-nav Profile + Clinic only: §2. ✅
- Matches Profile pane conventions (CardSeparator, type/weights): §5. ✅
- Frontend-only, no backend/migration: §2/§7. ✅
- Rule 17.0 + i18n parity + both themes + CI: §9. ✅
- Placeholder scan: concrete components/props/testids/keys throughout; no TBDs. ✅
