# i18n Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Make the frontend i18n-ready (react-i18next, client-side) and move all existing Auth + Clinic Workspace strings into `en`/`hi` translation resources, with errors translated by code — before more UI is built.

**Architecture:** `react-i18next` + `i18next-browser-languagedetector`, client-side locale in localStorage, English default/fallback, Hindi added now. No route-prefix locale. Backend unchanged (already returns stable codes; that's the i18n contract).

**Tech Stack:** Next.js (App Router) + TypeScript, react-i18next, i18next, i18next-browser-languagedetector (all MIT), Playwright.

**Spec:** `docs/specs/2026-06-18-i18n-localization-design.md`.

## Global Constraints
- Frontend repo: `~/Documents/register_workspace/dentist-registry-frontend`; branch `i18n-foundation`; never push to main; PR via `gh-personal`.
- **No hardcoded user-facing strings** in touched components from now on — all via `t('key')`.
- English is default/fallback; `hi` mirrors `en`'s keys (real Hindi where feasible, en fallback for gaps).
- Errors/status shown via **codes** translated client-side, never the English backend `message`.
- Locale stored client-side (localStorage); low-effort EN/हिन्दी switcher. No route-prefix locale, no server metadata localization.
- Keep it lightweight; do not redesign the auth/workspace UI — only de-hardcode it. Remove the dead `ping` frontend feature. Permissive-OSS only; no secrets.
- Tests reuse Playwright (no new test framework).

---

### Task I1: i18n infrastructure + locale resources

**Files:**
- Install: `react-i18next`, `i18next`, `i18next-browser-languagedetector`
- Create: `src/i18n/config.ts`, `src/i18n/provider.tsx`, `src/i18n/locales/en.json`, `src/i18n/locales/hi.json`
- Modify: `src/app/layout.tsx` (wrap children in the i18n provider) or `src/app/providers.tsx`
- Test: `tests/e2e/i18n.spec.ts` (resource-parity test — pure logic, no browser)

**Interfaces:**
- Produces: an initialized i18next instance; `<I18nProvider>` mounted app-wide; `en.json`/`hi.json` with the full key set below; `useTranslation()` available in all client components.

- [ ] **Step 1: Install deps**

```bash
npm install react-i18next i18next i18next-browser-languagedetector
```

- [ ] **Step 2: i18n config**

`src/i18n/config.ts`:
```typescript
import i18n from "i18next";
import LanguageDetector from "i18next-browser-languagedetector";
import { initReactI18next } from "react-i18next";

import en from "@/i18n/locales/en.json";
import hi from "@/i18n/locales/hi.json";

if (!i18n.isInitialized) {
  i18n
    .use(LanguageDetector)
    .use(initReactI18next)
    .init({
      resources: { en: { translation: en }, hi: { translation: hi } },
      fallbackLng: "en",
      supportedLngs: ["en", "hi"],
      interpolation: { escapeValue: false },
      detection: {
        order: ["localStorage", "navigator"],
        lookupLocalStorage: "register.locale",
        caches: ["localStorage"],
      },
    });
}

export default i18n;
```

- [ ] **Step 3: Provider**

`src/i18n/provider.tsx`:
```tsx
"use client";

import { I18nextProvider } from "react-i18next";

import i18n from "@/i18n/config";

export function I18nProvider({ children }: { children: React.ReactNode }) {
  return <I18nextProvider i18n={i18n}>{children}</I18nextProvider>;
}
```
Wire it in `src/app/providers.tsx` (or `layout.tsx`) so it wraps the app **inside** the existing client providers (alongside the TanStack Query provider). Keep it a client boundary.

- [ ] **Step 4: `en.json` (source of truth — full key set)**

`src/i18n/locales/en.json`:
```json
{
  "app": { "name": "Register System" },
  "common": { "loading": "Loading…" },
  "language": { "en": "English", "hi": "हिन्दी", "label": "Language" },
  "auth": {
    "login": {
      "title": "Sign in",
      "tabs": { "phone": "Phone", "email": "Email" },
      "phoneLabel": "Phone number",
      "phonePlaceholder": "+1 555 000 0000",
      "sendCode": "Send code",
      "otpLabel": "One-time code",
      "otpPlaceholder": "123456",
      "verifyCode": "Verify code",
      "back": "Back",
      "emailLabel": "Email",
      "emailPlaceholder": "you@example.com",
      "passwordLabel": "Password",
      "passwordPlaceholder": "••••••••",
      "signIn": "Sign in",
      "failed": "Sign-in failed. Please try again."
    }
  },
  "onboarding": {
    "title": "Welcome! Set up your clinic",
    "tabs": { "create": "Create a new clinic", "join": "I have an invite" },
    "clinicNameLabel": "Clinic Name",
    "clinicNamePlaceholder": "Enter clinic name",
    "create": "Create",
    "inviteTokenLabel": "Invite Token",
    "inviteTokenPlaceholder": "Paste your invite token",
    "join": "Join"
  },
  "clinic": { "yourClinic": "Your Clinic", "clinicLabel": "Clinic", "roleLabel": "Role" },
  "validation": {
    "phoneRequired": "Phone number is required",
    "phoneInvalid": "Enter a valid phone number",
    "otpNumeric": "OTP must be numeric",
    "emailInvalid": "Enter a valid email",
    "passwordRequired": "Password is required",
    "clinicNameRequired": "Clinic name is required",
    "inviteTokenRequired": "Invite token is required"
  },
  "apiErrors": {
    "unauthorized": "Please sign in to continue.",
    "forbidden": "You don't have permission to do that.",
    "validation_error": "Please check the form and try again.",
    "conflict": "You are already a member of this clinic.",
    "not_found": "Not found.",
    "invalid_invite": "This invite is invalid, expired, or already used.",
    "default": "Something went wrong. Please try again."
  },
  "status": {
    "role": { "owner": "Owner", "practice_manager": "Practice Manager", "doctor": "Doctor", "assistant": "Assistant" },
    "memberStatus": { "active": "Active", "inactive": "Inactive" }
  }
}
```

- [ ] **Step 5: `hi.json` (mirror keys; real Hindi where feasible)**

`src/i18n/locales/hi.json` — same key structure as `en.json`. Provide Hindi for the common strings, e.g.:
```json
{
  "app": { "name": "Register System" },
  "common": { "loading": "लोड हो रहा है…" },
  "language": { "en": "English", "hi": "हिन्दी", "label": "भाषा" },
  "auth": {
    "login": {
      "title": "साइन इन करें",
      "tabs": { "phone": "फ़ोन", "email": "ईमेल" },
      "phoneLabel": "फ़ोन नंबर",
      "phonePlaceholder": "+91 98765 43210",
      "sendCode": "कोड भेजें",
      "otpLabel": "वन-टाइम कोड",
      "otpPlaceholder": "123456",
      "verifyCode": "कोड सत्यापित करें",
      "back": "वापस",
      "emailLabel": "ईमेल",
      "emailPlaceholder": "you@example.com",
      "passwordLabel": "पासवर्ड",
      "passwordPlaceholder": "••••••••",
      "signIn": "साइन इन करें",
      "failed": "साइन-इन विफल रहा। कृपया पुनः प्रयास करें।"
    }
  },
  "onboarding": {
    "title": "स्वागत है! अपना क्लिनिक सेट करें",
    "tabs": { "create": "नया क्लिनिक बनाएँ", "join": "मेरे पास निमंत्रण है" },
    "clinicNameLabel": "क्लिनिक का नाम",
    "clinicNamePlaceholder": "क्लिनिक का नाम दर्ज करें",
    "create": "बनाएँ",
    "inviteTokenLabel": "निमंत्रण टोकन",
    "inviteTokenPlaceholder": "अपना निमंत्रण टोकन पेस्ट करें",
    "join": "शामिल हों"
  },
  "clinic": { "yourClinic": "आपका क्लिनिक", "clinicLabel": "क्लिनिक", "roleLabel": "भूमिका" },
  "validation": {
    "phoneRequired": "फ़ोन नंबर आवश्यक है",
    "phoneInvalid": "मान्य फ़ोन नंबर दर्ज करें",
    "otpNumeric": "OTP केवल अंकों में होना चाहिए",
    "emailInvalid": "मान्य ईमेल दर्ज करें",
    "passwordRequired": "पासवर्ड आवश्यक है",
    "clinicNameRequired": "क्लिनिक का नाम आवश्यक है",
    "inviteTokenRequired": "निमंत्रण टोकन आवश्यक है"
  },
  "apiErrors": {
    "unauthorized": "जारी रखने के लिए कृपया साइन इन करें।",
    "forbidden": "आपके पास यह करने की अनुमति नहीं है।",
    "validation_error": "कृपया फ़ॉर्म जाँचें और पुनः प्रयास करें।",
    "conflict": "आप पहले से ही इस क्लिनिक के सदस्य हैं।",
    "not_found": "नहीं मिला।",
    "invalid_invite": "यह निमंत्रण अमान्य, समाप्त, या पहले से उपयोग किया जा चुका है।",
    "default": "कुछ गलत हुआ। कृपया पुनः प्रयास करें।"
  },
  "status": {
    "role": { "owner": "मालिक", "practice_manager": "प्रैक्टिस मैनेजर", "doctor": "डॉक्टर", "assistant": "सहायक" },
    "memberStatus": { "active": "सक्रिय", "inactive": "निष्क्रिय" }
  }
}
```

- [ ] **Step 6: Resource-parity test**

`tests/e2e/i18n.spec.ts` (a non-browser test — runs in the Playwright runner):
```typescript
import { test, expect } from "@playwright/test";

import en from "../../src/i18n/locales/en.json";
import hi from "../../src/i18n/locales/hi.json";

function keyPaths(obj: Record<string, unknown>, prefix = ""): string[] {
  return Object.entries(obj).flatMap(([k, v]) =>
    v && typeof v === "object"
      ? keyPaths(v as Record<string, unknown>, `${prefix}${k}.`)
      : [`${prefix}${k}`],
  );
}

test("hi locale has the same keys as en", () => {
  expect(new Set(keyPaths(hi))).toEqual(new Set(keyPaths(en)));
});

test("en values are all non-empty strings", () => {
  for (const path of keyPaths(en)) {
    const value = path.split(".").reduce<any>((o, k) => o[k], en);
    expect(typeof value === "string" && value.length > 0).toBe(true);
  }
});
```
(Ensure `tsconfig.json` allows JSON imports — `resolveJsonModule` is on by default in Next.js.)

- [ ] **Step 7: Build + commit**

Run: `cp .env.local.example .env.local && npm run build && npx tsc --noEmit` (clean). Run the parity test: `npm run test:e2e -- i18n.spec.ts` (2 passed).
```bash
git add -A
git commit -m "feat(i18n): add react-i18next infra + en/hi locale resources"
```

---

### Task I2: Move auth/workspace strings to translations + error-by-code + switcher; remove dead ping

**Files:**
- Modify: `src/features/auth/login-form.tsx`, `src/features/auth/onboarding.tsx`, `src/app/page.tsx`, `src/app/login/page.tsx`
- Modify: `src/lib/api-client.ts` (no behavior change — only ensure `ApiError.code` is available for translation; it already is)
- Create: `src/components/locale-switcher.tsx`
- Delete: `src/features/ping/` (dead code — not imported by any real component)
- Modify/extend: `tests/e2e/auth.spec.ts` (translated render + locale switch + translated validation)

**Interfaces:**
- Consumes: `useTranslation` from react-i18next; the `en`/`hi` keys from I1; `ApiError.code`.
- Produces: zero hardcoded user-facing strings in these components; a `<LocaleSwitcher/>`.

- [ ] **Step 1: Refactor each component to `t()` (string → key map)**

Replace every literal with `t('<key>')` per this mapping (from the current code):

`login-form.tsx`:
- validation: `"Phone number is required"`→`validation.phoneRequired`; `"Enter a valid phone number"`→`validation.phoneInvalid`; `"OTP must be numeric"`→`validation.otpNumeric`; `"Enter a valid email"`→`validation.emailInvalid`; `"Password is required"`→`validation.passwordRequired`. **Build the Zod schemas inside the component using `t()`** so messages localize.
- labels/placeholders/buttons: `Phone number`→`auth.login.phoneLabel`; `+1 555 000 0000`→`auth.login.phonePlaceholder`; `Send code`→`auth.login.sendCode`; `One-time code`→`auth.login.otpLabel`; `123456`→`auth.login.otpPlaceholder`; `Verify code`→`auth.login.verifyCode`; `Email`→`auth.login.emailLabel`; `you@example.com`→`auth.login.emailPlaceholder`; `Password`→`auth.login.passwordLabel`; `••••••••`→`auth.login.passwordPlaceholder`; `Sign in`→`auth.login.signIn`; tabs `Phone`/`Email`→`auth.login.tabs.phone`/`.email`; any "Back"→`auth.login.back`.
- Supabase auth errors: show `t('auth.login.failed')` as the user-facing message (keep the raw error only for console/debug, not as the display source).

`onboarding.tsx`:
- validation: `"Clinic name is required"`→`validation.clinicNameRequired`; `"Invite token is required"`→`validation.inviteTokenRequired` (schemas built with `t()`).
- `Welcome! Set up your clinic`→`onboarding.title`; tab labels→`onboarding.tabs.create`/`.join`; `Clinic Name`→`onboarding.clinicNameLabel`; `Enter clinic name`→`onboarding.clinicNamePlaceholder`; `Create`→`onboarding.create`; `Invite Token`→`onboarding.inviteTokenLabel`; `Paste your invite token`→`onboarding.inviteTokenPlaceholder`; `Join`→`onboarding.join`.
- **Error display by code**: replace the `"Failed to create clinic"` / `"Failed to join clinic"` fallbacks with a helper that, given the thrown error, renders `t('apiErrors.' + code, { defaultValue: t('apiErrors.default') })` when it's an `ApiError` (has `.code`), else `t('apiErrors.default')`.

`page.tsx`:
- `Loading…`→`common.loading`; `Your Clinic`→`clinic.yourClinic`; `Register System`→`app.name`; the role value → `t('status.role.' + role)`; label text "Clinic"/"Role" → `clinic.clinicLabel`/`clinic.roleLabel`.

`login/page.tsx`:
- `Sign in` heading → `auth.login.title`. (This page is currently a server component; convert the heading to a small client component or move the `<h1>` into `LoginForm`/a client wrapper so `t()` works. Keep `layout.tsx`'s `metadata.title` as the brand `"Register System"` — server metadata localization is out of scope.)

- [ ] **Step 2: Locale switcher**

`src/components/locale-switcher.tsx` (`"use client"`): a minimal control (two buttons or a select) calling `i18n.changeLanguage('en'|'hi')`; labels from `t('language.en')`/`t('language.hi')`. Render it on the login page and in the authed shell (`page.tsx`). Keep it tiny.

- [ ] **Step 3: Remove the dead ping feature**

```bash
git rm -r src/features/ping
```
Confirm nothing imports it: `grep -rn "features/ping" src` → no results. Build must still pass.

- [ ] **Step 4: Update the e2e**

Extend `tests/e2e/auth.spec.ts` (Supabase + backend still mocked):
- Assert the login or onboarding renders the English translated strings (e.g., `getByRole("button", { name: "Create" })` / `getByText("Welcome! Set up your clinic")`).
- Use the locale switcher to switch to Hindi and assert a Hindi string appears (e.g., the onboarding title `स्वागत है! अपना क्लिनिक सेट करें`).
- Trigger a validation error (submit empty clinic name) and assert the **translated** validation message renders (`Clinic name is required`, then in Hindi after switch if convenient).

- [ ] **Step 5: Verify + commit**

Run: `cp .env.local.example .env.local && npx tsc --noEmit && npm run build && npm run test:e2e` — all green; **grep for residual hardcoded user-facing strings** in the touched files (none should remain). 
```bash
git add -A
git commit -m "feat(i18n): localize auth + clinic workspace UI; error-by-code; locale switcher; remove dead ping"
```

- [ ] **Step 6: Open PR**

```bash
git push -u origin i18n-foundation
gh-personal pr create --title "i18n foundation: localize auth + clinic workspace" --body "Implements docs/plans/2026-06-18-i18n-foundation-plan.md ..."
```

---

## Backend
No code change. The backend already returns stable codes (`unauthorized`, `forbidden`, `validation_error`, `conflict`, `not_found`, `invalid_invite`) via the uniform error envelope, and stable enum values for roles/statuses — these are the i18n contract the frontend translates. Documented in the spec (§4), Golden Rule 16.2, and tech stack. Any future endpoint must keep returning stable codes; do not introduce English-only messages as a display source.

## Acceptance
Matches spec §7: i18n initialized (en default, hi present, key parity); all auth/workspace strings translated (none hardcoded); errors shown via translated codes; locale switcher persists; dead ping removed; parity + e2e (render, switch, validation) pass; CI green; backend unchanged.
