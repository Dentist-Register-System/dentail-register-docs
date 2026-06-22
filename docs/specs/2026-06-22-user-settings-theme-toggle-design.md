# User Settings + Compact Theme Toggle — Design Spec

**Status:** Approved (brainstorm 2026-06-22; mockup `Mockups/User_settings_mockup.png`). System-wide: **db + backend + frontend + docs**. Calm Soft-Purple; Settings/Profile-pane design language.
**Type:** Add a per-user **Settings → User Settings** pane (Appearance/theme + Language), persist those preferences **per account** (sync across devices), and replace the cluttered top-right controls with one compact light↔dark toggle.

## 1. Goal
Give each user a personal preferences home and a clean header. A non-tech-savvy doctor sets theme/language once and it follows their account on any device — no per-device resets, no confusing top-bar button cluster.

## 2. Scope decisions (locked in brainstorm)
- **Pane name:** "User Settings" (pairs with "Clinic Settings"; clearly "yours").
- **Ship now:** Appearance (theme) + Language, fully wired. **Defer:** Date & Time Format + Timezone (same table later; tied to #71). No dead controls shown.
- **Persistence = per-account (backend source of truth) + localStorage cache for instant, flash-free apply.** Theme/language sync across devices/logins; the local cache keeps load snappy and avoids a theme flash on repeat loads.
- **Instant apply, no Save button** for theme + language (you see the change live; persists in the background). Deviation from the mockup's "Save Changes" button — intentional, better UX. (A Save can return when Date/TZ ship, since those batch.)
- **Top-right header:** remove the old Light/Dark/System buttons AND the EN/हिं switcher. Add one compact theme toggle (sun↔moon). Language lives only in User Settings.
- Roles: any authenticated user manages their OWN preferences (not clinic-scoped, not role-gated).

## 3. Data model — migration `0016_user_preferences`
- New table `user_preferences_beta`, 1:1 with `app_user_beta`:
  - `id` UUID PK; `user_id` UUID FK → `app_user_beta.id`, **unique**.
  - `theme` VARCHAR(10) NOT NULL DEFAULT `'system'` + CHECK `theme IN ('light','dark','system')`.
  - `language` VARCHAR(10) NOT NULL DEFAULT `'en'` + CHECK `language IN ('en','hi')`.
  - `created_at`/`updated_at` (clock_timestamp, onupdate).
- No backfill: preferences are **lazily created** with defaults on first read/update (existing users → `system`/`en`, matching today's behavior = zero behavior change).

## 4. Backend
- **Model:** `UserPreferences` in a new `app/modules/preferences/` module (`models.py`, `schemas.py`, `service.py`, `router.py`). Keeps import direction clean (`core ← preferences`; the auth router composes it at the boundary, like it already composes clinics/doctors).
- **Service:** `get_or_create_preferences(db, user_id) -> UserPreferences` (returns existing or inserts a default row, committing). `update_preferences(db, user_id, data) -> UserPreferences` (get-or-create then apply `theme`/`language`, audit `user_preferences.updated`, commit).
- **Schemas:** `PreferencesRead { theme: str, language: str }`; `PreferencesUpdate { theme: str | None, language: str | None }` with validators (`theme ∈ {light,dark,system}`, `language ∈ {en,hi}`).
- **`GET /api/v1/me`:** add `preferences: PreferencesRead | None` to `MeRead`. Populate via `get_or_create_preferences` when `user` exists (null when `needs_onboarding`/no user). Composed at the auth router boundary (same pattern as the existing memberships/doctor composition; auth router may import `preferences.service`).
- **`PATCH /api/v1/me/preferences`** → `PreferencesRead`. Resolves the current user (404 if none), calls `update_preferences`, returns the row. Auth: any authenticated user, self only (keyed off `auth.sub` → user; no clinic/role check).
- **Tests (pytest):** default row lazily created (`system`/`en`); `/me` includes preferences; PATCH theme→dark persists + round-trips in `/me`; PATCH language→hi persists; invalid theme/language → 422; a second user's PATCH doesn't touch the first user's row; partial PATCH (only `theme`) leaves `language` unchanged.

## 5. Frontend
### 5a. Preferences sync layer
- Extend the `Me` type (`src/features/clinic/api.ts`) with `preferences: { theme: "light"|"dark"|"system"; language: "en"|"hi" } | null`.
- Add `updatePreferences(payload)` → `PATCH /api/v1/me/preferences`, and a `useUpdatePreferences()` mutation that, on success, updates the `["me"]` query cache and applies locally.
- **Hydration on login:** a small client effect (e.g. in the authed shell) reconciles backend prefs → local appliers once `me` loads: `setTheme(me.preferences.theme)` (next-themes) and `i18n.changeLanguage(me.preferences.language)` if they differ from the current local values. next-themes' localStorage cache still applies instantly on load (no flash on repeat loads); the reconcile only switches on a fresh device.
- **On change:** apply instantly (next-themes `setTheme` / `i18n.changeLanguage`, which already write their localStorage caches) AND fire `useUpdatePreferences` to persist to the account.

### 5b. User Settings pane (`src/features/settings/user-settings-pane.tsx`)
Built to `Mockups/User_settings_mockup.png` within the design system (compose `components/ui/*`, semantic tokens, both themes, mobile-first, WCAG AA).
- Header: "User Settings" / "Personalize your experience and manage your preferences."
- **Appearance** card: title "Appearance" + "Choose how Register looks." On the right, a **Light / Dark** control (reuse `SegmentedButton` with sun/moon icons). Below it (divider), a **"Use device setting"** row + description "Automatically match Register with your device theme." + a `Switch`.
  - `useDevice` = (theme === "system"). Toggling ON → `setTheme("system")`; toggling OFF → `setTheme(resolvedTheme)` (the current light/dark). When ON, the Light/Dark segmented is **disabled** (device decides).
  - Selecting Light/Dark sets theme explicitly (and implicitly turns Use-device off).
  - Every change persists via `useUpdatePreferences`.
- **Language** card: title "Language" + "Choose your preferred language." + a native styled `<select>` (English / हिंदी) → `i18n.changeLanguage` + persist.
- **No Save button.** Instant apply.
- Sub-nav: add `{ key: "user", labelKey: "settings.nav.user", icon: "manage_accounts" }` to `settings-shell.tsx` **after Profile**: Profile · User Settings · Clinic · Scheduling. Route the pane (no `canManage` gate — always the current user's own prefs).

### 5c. Compact header theme toggle (`src/components/theme-toggle.tsx` rewrite)
- Replace the 3-button group with one compact control: a small pill/segmented sun↔moon (≈ two icon segments, or an icon button that shows the resolved theme). Shows the resolved look; clicking flips to the opposite explicit theme (`setTheme(resolved === "dark" ? "light" : "dark")`), which also turns off "use device". Persists via `useUpdatePreferences`. `aria-label`, keyboard-operable, visible focus ring; hydration-guarded (mounted) like today.
- **Remove `<LocaleSwitcher />` from the header** (`app-shell.tsx`); delete `locale-switcher.tsx` (language now only in User Settings). The header right-side becomes just the compact theme toggle.

### 5d. i18n (en + hi parity)
- New: `settings.nav.user`, the User Settings pane copy (`settings.user.*` — title/subtitle, appearance.title/desc, appearance.light, appearance.dark, useDevice.row/desc, language.title/desc), and theme-toggle `aria-label`. Reuse existing `language.en`/`language.hi` for the select options.
- Remove now-unused `theme.system` / locale-switcher keys only if nothing else references them (verify first).

## 6. Quality
- Backend: `uv run ruff check .` clean; `make test` (incl. new preferences tests) green; migration 0016 via Supabase MCP (controller) — implementers validate on local PG :5433.
- Frontend: `tsc --noEmit` + `npm run build` + i18n en/hi parity (`tests/e2e/i18n.spec.ts`) green.
- Rule 17.0 (semantic tokens only, compose `components/ui/*`, no per-page CSS, no new tokens); both themes; mobile-first; WCAG AA. Faithful to the mockup (minus the deferred Date/TZ rows + the Save button).
- Never merge red (verify `gh-personal pr checks`). **Frontend PR held for user test;** backend merges after green review. Interactive HTML render of the pane + header toggle approved by the user BEFORE the frontend build.

## 7. Scope guards / deferred
- **Date & Time Format + Timezone** rows from the mockup — deferred (same `user_preferences_beta` table later; Timezone ties to #71).
- The mockup's **notification bell + "N" account/avatar menu** — out of scope (separate concern).
- The mockup's **Save Changes** button — omitted by design (instant apply).
- No clinic/role gating on preferences (always self).

## 8. Self-review (against the request)
- Settings → User Settings pane with app-wide UI settings (theme + language): §5b. ✅
- "User Settings" name (alt names considered): §2. ✅
- Top-right Light/Dark/System + EN/हिं removed; compact theme toggle that clearly shows light/dark added: §5c. ✅
- Language moved out of the header into User Settings: §5b/§5c. ✅
- Right-way persistence (per-account, syncs across devices) for ease-of-use: §2/§3/§4/§5a. ✅
- Faithful to mockup within the system (deferred Date/TZ + Save noted): §5b/§7. ✅
- Interactive render before build: §6. ✅
- Rule 17.0 + i18n + tests + merge policy: §6. Placeholder scan: concrete table/endpoints/fields/components; no TBD. ✅
