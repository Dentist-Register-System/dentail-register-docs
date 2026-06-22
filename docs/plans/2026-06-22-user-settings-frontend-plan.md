# User Settings — Frontend Implementation Plan (#101)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Add the Settings → User Settings pane (Appearance + Language, instant apply), persist preferences to the account via the merged backend, and replace the top-right control cluster with one compact light↔dark toggle.

**Architecture:** Frontend slice of the User Settings feature. Backend is merged: `GET /me` returns `preferences {theme,language}`; `PATCH /api/v1/me/preferences` updates them. next-themes (localStorage `theme`) + i18n (localStorage `register.locale`) remain the instant-apply layer; the backend is the cross-device source of truth, reconciled on login. Compose `components/ui/*`, semantic tokens only (Rule 17.0), both themes, mobile-first, WCAG AA.

**Tech Stack:** Next.js App Router (client components), TanStack Query, next-themes, react-i18next (en/hi parity gated), Tailwind v4 semantic tokens, Material Symbols. CI = `tsc --noEmit` + `npm run build`.

**Visual source of truth:** `/tmp/user-settings-render/index.html` (approved render — pane layout, the compact ☀/🌙 header toggle, Light/Dark segmented, Use-device switch disabling the segmented, Language select; light + dark).

## Global Constraints
- Preferences shape: `{ theme: "light"|"dark"|"system"; language: "en"|"hi" }`.
- Instant apply, NO Save button: theme via next-themes `setTheme`, language via `i18n.changeLanguage` — both fire immediately AND persist via `PATCH /me/preferences`.
- "Use device setting" = `theme === "system"`; ON → `setTheme("system")` + the Light/Dark segmented disables; OFF / picking Light or Dark → explicit theme.
- Header: ONE compact toggle (sun↔moon) reflecting the resolved theme; click flips to the opposite explicit theme (turning off system) + persists. Remove `<LocaleSwitcher/>` from the header; language lives only in User Settings.
- Nav order: Profile · **User Settings** · Clinic · Scheduling. No `canManage` gate (always the current user's own prefs).
- i18n: every new string in BOTH `en.json` + `hi.json` (parity gated by `tests/e2e/i18n.spec.ts`). Semantic tokens only; compose `components/ui/*`.
- Quality gate per task: `npx tsc --noEmit` clean + `npm run build`. Frontend PR held for user QA.

---

### Task 1: Preferences API types + hooks (update + hydration)

**Files:**
- Create: `src/features/preferences/api.ts`, `src/features/preferences/hooks.ts`
- Modify: `src/features/clinic/api.ts` (add `preferences` to `Me`)

**Interfaces:**
- Produces: `type UserPreferences = { theme: "light"|"dark"|"system"; language: "en"|"hi" }`; `updatePreferences(payload: Partial<UserPreferences>): Promise<UserPreferences>`; `useUpdatePreferences()` (mutation, merges result into the `["me"]` cache); `usePreferenceHydration()` (applies backend prefs → next-themes + i18n once on login).
- Consumes: `apiFetch` (`@/lib/api-client`), `useMe` (`@/features/clinic/hooks`), next-themes `useTheme`, `useTranslation`.

- [ ] **Step 1: Create the preferences API**

```typescript
// src/features/preferences/api.ts
import { apiFetch } from "@/lib/api-client";

export type UserPreferences = {
  theme: "light" | "dark" | "system";
  language: "en" | "hi";
};

export const updatePreferences = (payload: Partial<UserPreferences>) =>
  apiFetch<UserPreferences>("/api/v1/me/preferences", {
    method: "PATCH",
    body: JSON.stringify(payload),
  });
```
(Match the existing `apiFetch` usage in `src/features/clinic/api.ts` — same import + call shape as `updateClinicSettings`.)

- [ ] **Step 2: Add `preferences` to the `Me` type**

In `src/features/clinic/api.ts`, import the type and extend `Me`:
```typescript
import type { UserPreferences } from "@/features/preferences/api";
// ...
export type Me = {
  // ...existing fields...
  preferences: UserPreferences | null;
};
```

- [ ] **Step 3: Create the hooks**

```typescript
// src/features/preferences/hooks.ts
"use client";

import { useEffect, useRef } from "react";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { useTheme } from "next-themes";
import { useTranslation } from "react-i18next";

import type { Me } from "@/features/clinic/api";
import { useMe } from "@/features/clinic/hooks";
import { updatePreferences, type UserPreferences } from "@/features/preferences/api";

export function useUpdatePreferences() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (payload: Partial<UserPreferences>) => updatePreferences(payload),
    onSuccess: (prefs) => {
      qc.setQueryData<Me>(["me"], (prev) => (prev ? { ...prev, preferences: prefs } : prev));
    },
  });
}

/**
 * Apply the account's saved preferences to the local appliers (next-themes + i18n)
 * once, when /me first resolves. next-themes already applied the localStorage value
 * pre-paint; this only switches when the backend differs (e.g. a fresh device).
 */
export function usePreferenceHydration() {
  const me = useMe();
  const { setTheme } = useTheme();
  const { i18n } = useTranslation();
  const done = useRef(false);

  useEffect(() => {
    const prefs = me.data?.preferences;
    if (!prefs || done.current) return;
    done.current = true;
    if (prefs.theme !== localStorage.getItem("theme")) setTheme(prefs.theme);
    if (prefs.language !== i18n.language) void i18n.changeLanguage(prefs.language);
  }, [me.data?.preferences, setTheme, i18n]);
}
```

- [ ] **Step 4: Type-check + commit**

```bash
npx tsc --noEmit
git add src/features/preferences src/features/clinic/api.ts
git commit -m "feat(preferences): api + useUpdatePreferences + hydration hook; Me.preferences (#101)"
```

---

### Task 2: Compact header theme toggle + remove LocaleSwitcher + wire hydration

**Files:**
- Rewrite: `src/components/theme-toggle.tsx`
- Modify: `src/components/shell/app-shell.tsx` (drop `<LocaleSwitcher/>`; call `usePreferenceHydration()`)
- Delete: `src/components/locale-switcher.tsx`
- Modify: `src/i18n/locales/en.json` + `hi.json` (toggle aria-label key; remove now-dead keys if unreferenced)

**Interfaces:**
- Consumes: `useTheme` (next-themes), `useUpdatePreferences` (Task 1), `usePreferenceHydration` (Task 1), `Icon`.

- [ ] **Step 1: Rewrite the theme toggle (compact sun↔moon)**

Match the render's `.themeswitch` (two icon segments, active = resolved theme). Replace `src/components/theme-toggle.tsx` entirely:
```tsx
"use client";

import { useEffect, useState } from "react";
import { useTheme } from "next-themes";
import { useTranslation } from "react-i18next";

import { Icon } from "@/components/ui/icon";
import { useUpdatePreferences } from "@/features/preferences/hooks";

export function ThemeToggle() {
  const { t } = useTranslation();
  const { resolvedTheme, setTheme } = useTheme();
  const updatePrefs = useUpdatePreferences();
  const [mounted, setMounted] = useState(false);
  useEffect(() => setMounted(true), []);

  const isDark = mounted && resolvedTheme === "dark";

  function choose(next: "light" | "dark") {
    setTheme(next);
    updatePrefs.mutate({ theme: next });
  }

  return (
    <div
      className="inline-flex items-center overflow-hidden rounded-full border border-border bg-card"
      role="group"
      aria-label={t("settings.user.appearance.title")}
    >
      <button
        type="button"
        onClick={() => choose("light")}
        aria-label={t("settings.user.appearance.light")}
        aria-pressed={mounted ? !isDark : false}
        data-testid="theme-light"
        className={`flex h-[30px] w-[34px] items-center justify-center transition-colors ${!isDark ? "bg-primary text-primary-foreground" : "text-muted-foreground hover:text-foreground"}`}
      >
        <Icon name="light_mode" size={18} aria-hidden />
      </button>
      <button
        type="button"
        onClick={() => choose("dark")}
        aria-label={t("settings.user.appearance.dark")}
        aria-pressed={mounted ? isDark : false}
        data-testid="theme-dark"
        className={`flex h-[30px] w-[34px] items-center justify-center transition-colors ${isDark ? "bg-primary text-primary-foreground" : "text-muted-foreground hover:text-foreground"}`}
      >
        <Icon name="dark_mode" size={18} aria-hidden />
      </button>
    </div>
  );
}
```

- [ ] **Step 2: Update the app shell header + wire hydration**

In `src/components/shell/app-shell.tsx`:
- Remove the `LocaleSwitcher` import and its `<LocaleSwitcher />` usage (header right-side becomes just `<ThemeToggle />`).
- Call hydration once in the shell component body: add `import { usePreferenceHydration } from "@/features/preferences/hooks";` and call `usePreferenceHydration();` near the top of the `AppShell` function.

- [ ] **Step 3: Delete the locale switcher + clean i18n**

```bash
rm src/components/locale-switcher.tsx
```
Verify nothing else imports it: `grep -rn "locale-switcher\|LocaleSwitcher" src/` → no output (fix any stragglers). In `en.json`/`hi.json`, remove `language.label` and `theme.label`/`theme.system` ONLY if `grep -rn "theme.system\|theme.label\|language.label" src/` shows no remaining references (keep `language.en`/`language.hi` — the pane's select uses them). Keep en/hi parity for any removal.

- [ ] **Step 4: Type-check + build + parity + commit**

```bash
npx tsc --noEmit && npm run build && npx playwright test tests/e2e/i18n.spec.ts
git add src/components src/i18n/locales
git commit -m "feat(shell): compact light/dark header toggle; remove locale switcher; hydrate prefs (#101)"
```

---

### Task 3: User Settings pane + nav + i18n

**Files:**
- Create: `src/features/settings/user-settings-pane.tsx`
- Modify: `src/features/settings/settings-shell.tsx` (nav item + route)
- Modify: `src/i18n/locales/en.json` + `hi.json` (`settings.nav.user` + `settings.user.*`)

**Interfaces:**
- Consumes: `useTheme` (next-themes), `useTranslation`, `useUpdatePreferences` (Task 1), `SegmentedButton`, `Switch`, `Card`/`CardContent`, `Icon`.

- [ ] **Step 1: Create the pane**

Match the render's pane (Appearance card: Light/Dark segmented + divider + Use-device switch; Language card: select; no Save).
```tsx
// src/features/settings/user-settings-pane.tsx
"use client";

import { useEffect, useState } from "react";
import { useTheme } from "next-themes";
import { useTranslation } from "react-i18next";

import { Card, CardContent } from "@/components/ui/card";
import { Icon } from "@/components/ui/icon";
import { SegmentedButton } from "@/components/ui/segmented";
import { Switch } from "@/components/ui/switch";
import { useUpdatePreferences } from "@/features/preferences/hooks";

export function UserSettingsPane() {
  const { t } = useTranslation();
  const { theme, resolvedTheme, setTheme } = useTheme();
  const updatePrefs = useUpdatePreferences();
  const [mounted, setMounted] = useState(false);
  useEffect(() => setMounted(true), []);

  const useDevice = mounted && theme === "system";
  const activeMode = (mounted ? resolvedTheme : "light") === "dark" ? "dark" : "light";

  function setMode(next: string) {
    setTheme(next);
    updatePrefs.mutate({ theme: next as "light" | "dark" });
  }
  function toggleDevice(on: boolean) {
    const next = on ? "system" : (resolvedTheme === "dark" ? "dark" : "light");
    setTheme(next);
    updatePrefs.mutate({ theme: next as "light" | "dark" | "system" });
  }
  function setLanguage(lang: string) {
    void i18n.changeLanguage(lang);
    updatePrefs.mutate({ language: lang as "en" | "hi" });
  }
  const { i18n } = useTranslation();

  return (
    <div className="space-y-5" data-testid="settings-user">
      <div>
        <h2 className="text-2xl font-semibold text-foreground">{t("settings.user.title")}</h2>
        <p className="text-sm text-muted-foreground">{t("settings.user.subtitle")}</p>
      </div>

      {/* Appearance */}
      <Card>
        <CardContent className="py-5">
          <div className="flex items-center justify-between gap-4">
            <div>
              <p className="text-base font-semibold text-foreground">{t("settings.user.appearance.title")}</p>
              <p className="text-sm text-muted-foreground">{t("settings.user.appearance.desc")}</p>
            </div>
            <SegmentedButton
              ariaLabel={t("settings.user.appearance.title")}
              value={activeMode}
              onChange={setMode}
              disabled={useDevice}
              options={[
                { value: "light", label: t("settings.user.appearance.light"), icon: "light_mode" },
                { value: "dark", label: t("settings.user.appearance.dark"), icon: "dark_mode" },
              ]}
            />
          </div>
          <div className="my-[18px] h-px bg-border" />
          <div className="flex items-center justify-between gap-4">
            <div>
              <p className="text-base font-semibold text-foreground">{t("settings.user.useDevice.row")}</p>
              <p className="text-sm text-muted-foreground">{t("settings.user.useDevice.desc")}</p>
            </div>
            <Switch
              checked={useDevice}
              onCheckedChange={toggleDevice}
              data-testid="use-device-theme"
              aria-label={t("settings.user.useDevice.row")}
            />
          </div>
        </CardContent>
      </Card>

      {/* Language */}
      <Card>
        <CardContent className="py-5">
          <div className="flex items-center justify-between gap-4">
            <div>
              <p className="text-base font-semibold text-foreground">{t("settings.user.language.title")}</p>
              <p className="text-sm text-muted-foreground">{t("settings.user.language.desc")}</p>
            </div>
            <div className="flex items-center gap-2">
              <Icon name="language" size={20} className="text-muted-foreground" aria-hidden />
              <select
                data-testid="language-select"
                value={mounted ? i18n.language : "en"}
                onChange={(e) => setLanguage(e.target.value)}
                aria-label={t("settings.user.language.title")}
                className="h-11 w-64 rounded-xl border border-border bg-card px-3.5 text-sm text-foreground outline-none transition-colors focus-visible:border-ring focus-visible:ring-3 focus-visible:ring-ring/50"
              >
                <option value="en">{t("language.en")}</option>
                <option value="hi">{t("language.hi")}</option>
              </select>
            </div>
          </div>
        </CardContent>
      </Card>
    </div>
  );
}
```
(Note: move the `const { i18n } = useTranslation();` to the top with the other `useTranslation()` call — combine into `const { t, i18n } = useTranslation();` — the split above is illustrative; the implementer must declare hooks once at the top, not mid-body.)

- [ ] **Step 2: Add to the settings sub-nav (after Profile)**

In `src/features/settings/settings-shell.tsx`:
```typescript
import { UserSettingsPane } from "@/features/settings/user-settings-pane";
// ...
type Section = "profile" | "user" | "clinic" | "scheduling";
// items array — insert after profile:
  const items: { key: Section; labelKey: string; icon: string }[] = [
    { key: "profile", labelKey: "settings.nav.profile", icon: "person" },
    { key: "user", labelKey: "settings.nav.user", icon: "manage_accounts" },
    { key: "clinic", labelKey: "settings.nav.clinic", icon: "domain" },
    { key: "scheduling", labelKey: "settings.nav.scheduling", icon: "event_available" },
  ];
```
Route it in the pane switch (no `canManage` — own prefs):
```tsx
          {section === "profile" ? (
            <ProfilePane clinicId={clinicId} />
          ) : section === "user" ? (
            <UserSettingsPane />
          ) : section === "clinic" ? (
            <ClinicPane clinicId={clinicId} canManage={canManageClinic} />
          ) : (
            <SchedulingPane clinicId={clinicId} canManage={canManageClinic} />
          )}
```

- [ ] **Step 3: i18n (en + hi parity)**

Add `settings.nav.user` ("User Settings" / "उपयोगकर्ता सेटिंग्स") and the `settings.user` block (mirror in `hi.json`):
```json
"user": {
  "title": "User Settings",
  "subtitle": "Personalize your experience and manage your preferences.",
  "appearance": { "title": "Appearance", "desc": "Choose how Register looks.", "light": "Light", "dark": "Dark" },
  "useDevice": { "row": "Use device setting", "desc": "Automatically match Register with your device theme." },
  "language": { "title": "Language", "desc": "Choose your preferred language." }
}
```

- [ ] **Step 4: Type-check + build + parity + commit**

```bash
npx tsc --noEmit && npm run build && npx playwright test tests/e2e/i18n.spec.ts
git add src/features/settings src/i18n/locales
git commit -m "feat(settings): User Settings pane (appearance + language) + nav (#101)"
```

---

### Task 4: Final verification

**Files:** none.

- [ ] **Step 1: Full type-check + build + parity + theme e2e**

Run: `npx tsc --noEmit && npm run build && npx playwright test tests/e2e/i18n.spec.ts tests/e2e/theme.spec.ts`
Expected: PASS. If iCloud dup files break tsc, `find .next -name "* [0-9].*" -delete` and re-run. NOTE: `tests/e2e/theme.spec.ts` targets the OLD `data-testid="theme-light/dark/system"` on `/login`; the new toggle keeps `theme-light`/`theme-dark` but drops `theme-system` — if that suite references `theme-system`, update it to match the new 2-state toggle (do not delete coverage; adjust assertions).

- [ ] **Step 2: Manual self-check vs the render**

Confirm (dev server): compact header toggle flips light/dark; User Settings pane Appearance segmented + Use-device switch disabling the segmented; Language select switches live; both themes; no Save button; no LocaleSwitcher remnant in the header.

- [ ] **Step 3: Commit any fixups**

```bash
git add -A && git commit -m "test(settings): align theme e2e with compact toggle (#101)"
```

---

## Self-Review (plan vs spec)
- **Spec §5a sync layer (Me.preferences, updatePreferences, hydration, persist-on-change)** → Task 1 (+ used in T2/T3). ✅
- **Spec §5b User Settings pane (Appearance + Language, instant, no Save) + nav after Profile** → Task 3. ✅
- **Spec §5c compact header toggle + remove LocaleSwitcher** → Task 2. ✅
- **Spec §5d i18n en/hi** → Tasks 2/3 add to both; Task 4 parity gate. ✅
- **Type consistency:** `UserPreferences` defined Task 1 (api.ts), consumed in hooks/T2/T3; `useUpdatePreferences`/`usePreferenceHydration` defined T1, used T2/T3; `Section` union extended T3. ✅
- **Backend dependency:** `/me.preferences` + `PATCH /me/preferences` are merged (verified). ✅
- **Placeholder scan:** concrete components/keys/paths; the one illustrative note (declare `useTranslation` once) is explicitly called out for the implementer to apply. ✅
- **Rule 17.0:** semantic tokens only; composes `components/ui/*` (SegmentedButton, Switch, Card, Icon). ✅
