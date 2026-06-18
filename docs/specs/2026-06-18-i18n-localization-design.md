# Internationalization / Localization (i18n) — Design Spec

> Status: Draft for review
> Date: 2026-06-18
> Author: Brainstormed via Claude Code
> Scope: Cross-cutting foundation (applies to all frontend slices from now on)

---

## 1. Context & Purpose

The Register System is India-first; multi-language support is a **core product requirement**,
not a later enhancement. This spec makes the app **i18n-ready before more UI is built**, so
Hindi/Marathi/etc. can be added by adding translations — never by refactoring code. It is a
focused correction layered onto the just-merged Auth + Clinic Workspace (SP1) UI; it does **not**
redesign anything.

See PRD §39 and Golden Rules §16 for the product-level decisions this implements.

## 2. Locked Decisions

- **i18n-ready from the start.** English is the **default/fallback** locale.
- **Hindi** is the first additional language; **Marathi** planned next (Pune/Maharashtra market).
- **Nothing user-facing is hardcoded**: UI text, page/section titles, nav labels, form
  labels/placeholders, buttons, validation messages, status labels, empty/loading states,
  notification copy, and WhatsApp/communication templates all come from translation resources.
- **Frontend owns user-facing translation.** The backend returns **stable machine-readable
  codes** for errors/statuses; the frontend maps codes → localized messages. English backend
  messages are never the display source.
- **Clinical / entered data is not translated** in V1 (patient names, doctor/treatment notes,
  complaints are stored and shown as entered).
- **Language preference** is supported conceptually at clinic and user level. V1 stores locale
  **client-side** (localStorage); a persisted preference can follow without refactoring.
- **Templates** are localization-ready (per-locale variants, English fallback).

## 3. Approach (frontend)

**Library: `react-i18next` + `i18next-browser-languagedetector`** (MIT). Rationale: industry
standard, simple, **client-side**, no route-prefix locale — matching "store locale client-side,
don't over-engineer route handling." The app is client-component-heavy (everything behind
`AuthGate`; forms are client components), so client-side i18n covers all user-facing strings.
(`next-intl`'s route/middleware model was considered and rejected as heavier than needed for V1.)

### Structure
```
src/i18n/
  config.ts        # i18next init: resources, fallbackLng 'en', supportedLngs ['en','hi'],
                   # localStorage detection ('register.locale'), interpolation
  provider.tsx     # 'use client' <I18nProvider> wrapping the app (added in root layout)
  locales/
    en.json        # full key set (source of truth)
    hi.json        # Hindi; real translations where feasible, en fallback for gaps
```
Single namespace, nested keys: `app`, `common`, `nav`, `auth`, `onboarding`, `clinic`,
`validation`, `apiErrors`, `status`.

### Patterns
- Components use `const { t } = useTranslation()` and render `t('key')`. **No literal
  user-facing strings** in components from here on.
- **Zod validation messages** are produced via `t()` — schemas are built inside components (or a
  factory that takes `t`) so messages reflect the active locale.
- **API/auth errors → translated by code**: the `api-client`'s `ApiError` carries `code`
  (`unauthorized`, `forbidden`, `validation_error`, `conflict`, `not_found`, `invalid_invite`).
  The UI renders `t('apiErrors.<code>', t('apiErrors.default'))` — never the English `message`.
  Supabase auth (third-party) errors map common cases where a stable code/status is available,
  else a generic localized message.
- **Status/role labels** (`owner`, `doctor`, `active`, …) render via `t('status.*')`, not the
  raw enum value.
- **Locale switcher**: a small EN / हिन्दी control (login + authed shell). Low-effort;
  `i18n.changeLanguage(...)` persists to localStorage via the detector.

### Hydration note
i18n initializes synchronously with bundled resources, fallback `en`. A non-`en` stored locale
may cause a brief first-paint in English on the login page before the client applies the stored
locale; acceptable for V1 (most UI renders after the `AuthGate` loading state). Not worth
route-based SSR locale now.

## 4. Backend (i18n-friendly, no localization build)

No behavior change. The backend already returns stable codes via the uniform error envelope
(`{ "error": { "code", "message", "details" } }`) and stable enum values for statuses/roles.
This spec **documents that the codes/enums are the i18n contract** — the frontend translates
them; the English `message` is for logs/devs only. Any new endpoints must keep returning stable
codes.

## 5. Out of Scope (V1)
- Backend message localization / `Accept-Language` negotiation.
- Persisted user/clinic locale in the database (conceptually supported; client-side for now).
- Route-prefixed locales (`/hi/...`), server-rendered translated metadata.
- Auto-translation of any clinical/entered content.
- Full WhatsApp/notification template localization implementation (only the *readiness*
  decision is captured; built when integrations/templates land in SP5/SP6).
- Marathi translations (structure supports adding the locale later).

## 6. Testing
- **Resource parity** test: `hi.json` key set matches `en.json`; `en` values non-empty.
- **e2e** (Playwright): auth/onboarding render translated strings; the locale switcher changes a
  visible string to Hindi; a validation error renders the translated message.
- **No-hardcoded-strings** discipline enforced by review on all newly touched auth/workspace UI.

## 7. Acceptance Criteria
1. `react-i18next` initialized; `en` default with a complete key set; `hi` present (≥ the same
   keys, real Hindi where feasible).
2. All Auth + Clinic Workspace user-facing strings (login, onboarding, shell, validation, error
   displays, status/role labels, empty/loading) come from translations — none hardcoded.
3. API/auth errors are shown via translated **codes**, not English backend messages.
4. A low-effort locale switcher toggles EN ↔ हिन्दी and persists in localStorage.
5. The dead frontend `ping` feature is removed.
6. Resource-parity + e2e (translated render, locale switch, translated validation) pass; CI green.
7. Backend unchanged behaviorally; the stable-code contract is documented.
