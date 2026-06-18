# Email/Password Sign-Up — Design Spec

> Status: Draft for review
> Date: 2026-06-18
> Author: Brainstormed via Claude Code
> Scope: small auth enhancement (fills an SP1 gap); unblocks self-serve registration. Issue: dentail-register-docs#23.

---

## 1. Context & Purpose

SP1 shipped the login page with email/password **sign-in only** (`signInWithPassword`) and phone-OTP
(which auto-creates the account on first OTP). There is **no `signUp`**, so a brand-new user cannot
self-register by email. This blocks testing the product's two sign-up flows by email and is a real
product gap (email/password is a supported method per the SP1 auth spec).

This change adds an **email/password sign-up** entry to `/login`. It feeds the **existing** SP1
onboarding (no backend change): after authenticating, the user lands on the already-built onboarding,
which offers the two flows:
1. **Invite → join an existing clinic** (`POST /clinics/join`).
2. **No invite → self-onboard → create a new clinic** as owner (`POST /clinics`).

## 2. Scope Decisions

- **Frontend only.** Backend (`/me`, create-clinic, join) is auth-method-agnostic — unchanged.
- **Confirm email is ON** (Supabase). So `supabase.auth.signUp()` returns a user with **no session**
  until the email is confirmed. The UI must show a **"check your email"** state, not route to onboarding.
- **Confirmation round-trip:** the email link (sent via Resend) returns the user to **Site URL**
  (`http://localhost:3000`); `supabase-js` (`detectSessionInUrl`, default on) establishes the session;
  the app then proceeds to onboarding. We pass `emailRedirectTo: ${window.location.origin}/`.
- **UX:** within the existing **Email** tab, add a **Sign in / Create account** sub-toggle. Phone-OTP
  tab is unchanged (it remains the primary, and already supports new users).
- **i18n-first + design-system** as for all UI.

### Out of scope
Phone sign-up (already works), password reset (Supabase default flow), resend-confirmation button
(nice-to-have; can add later), social/SSO. No new backend endpoints.

## 3. Flow

```
/login → Email tab → "Create account" → email + password → supabase.auth.signUp({ email, password,
        options:{ emailRedirectTo: origin + "/" } })
   → (Confirm email ON) no session yet → UI shows "Check your email to confirm your address."
   → user opens email (Resend) → clicks confirm link → browser returns to http://localhost:3000/
   → supabase-js sets the session → AuthGate passes → GET /me → needs_onboarding=true
   → existing onboarding: Create clinic (owner)  OR  Join via invite token
```

## 4. UX & States (Email tab)

- **Mode toggle:** "Sign in" (default) | "Create account".
- **Sign in:** unchanged (`signInWithPassword`).
- **Create account:** email + password fields (password min length per Supabase policy, default ≥6);
  on submit → `signUp`. 
  - **Success (confirmation pending):** replace the form with a confirmation-pending panel:
    "Check your email — we sent a confirmation link to {email}. Click it to finish signing up."
  - **Error:** show `t('auth.signup.failed')` (e.g. user already registered) — do not leak raw text.
- All strings via `t()`; en + hi parity. Semantic tokens; mobile-first; AA.

## 5. Testing

- **Playwright e2e (mocked Supabase):** toggling to "Create account", submitting valid email/password
  calls `signUp` and renders the confirmation-pending panel; toggling back to "Sign in" still works;
  validation errors localize. Mock `supabase.auth.signUp` to resolve `{ data:{ user:{...}, session:null }, error:null }`.
- i18n parity test covers the new keys.

## 6. Acceptance Criteria

1. On `/login` → Email tab, a user can switch to **Create account**, enter email+password, and submit.
2. On success, the UI shows a **confirmation-pending** message (no premature redirect, since confirm-email is ON).
3. A real confirmation email is delivered (via the configured Resend SMTP); clicking the link returns
   to `http://localhost:3000/`, a session is established, and the user reaches **onboarding**.
4. From onboarding, the user can **create a clinic (owner)** or **join via invite** — both end-to-end.
5. Sign-in still works; all new UI is i18n'd (en+hi parity), uses semantic tokens, and is mobile-first/AA.
6. No backend changes; `tsc`/build clean; e2e green.
