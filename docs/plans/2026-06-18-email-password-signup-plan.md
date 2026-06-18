# Email/Password Sign-Up Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Add an email/password **sign-up** entry to `/login` so brand-new users can self-register, then land on the existing onboarding (create-clinic or join-invite). Confirm-email is ON, so show a "check your email" state on success.

**Architecture:** Frontend-only change to the existing Email tab in `login-form.tsx`: add a "Sign in / Create account" mode toggle; "Create account" calls `supabase.auth.signUp({ email, password, options:{ emailRedirectTo } })`. No backend change. The email confirmation link returns to Site URL (`http://localhost:3000`), where `supabase-js` establishes the session and the app proceeds to onboarding.

**Tech Stack:** Next.js App Router + TS, supabase-js, React Hook Form + Zod, react-i18next, shadcn, Playwright.

**Spec:** `docs/specs/2026-06-18-email-password-signup-design.md`.

## Global Constraints
- Repo: `~/Documents/register_workspace/dentist-registry-frontend`; branch `email-password-signup`; never push to main; PR via `gh-personal`.
- **i18n-first:** no hardcoded user-facing strings — all via `t()`; add every new key to BOTH `en.json` and `hi.json` (parity enforced by `tests/e2e/i18n.spec.ts`). Build Zod schemas inside the component with `t()`. Auth errors via a translated key, never the raw Supabase message.
- **Design system:** semantic tokens only; light/dark; mobile-first; AA.
- Backend unchanged. Permissive-OSS only; no secrets. CI runs `tsc --noEmit` + `npm run build` (must be clean); Playwright e2e is local.
- Read `AGENTS.md` (the Next.js docs note) and mirror existing patterns in `src/features/auth/login-form.tsx`.

---

### Task 1: Add email/password sign-up to the login Email tab

**Files:**
- Modify: `src/features/auth/login-form.tsx` (extend `EmailPasswordForm` with a Sign in / Create account mode + confirmation-pending state)
- Modify: `src/i18n/locales/en.json`, `src/i18n/locales/hi.json` (add `auth.signup.*` keys)
- Test: `tests/e2e/auth.spec.ts` (extend) or new `tests/e2e/signup.spec.ts`

**Interfaces:**
- Consumes: `supabase.auth.signUp`, `useTranslation`, RHF + Zod.
- Produces: a sign-up path that, on success with confirm-email ON, renders a confirmation-pending panel.

- [ ] **Step 1: i18n keys (both locales, keep parity)**

Add under `auth` in `en.json` (and Hindi equivalents in `hi.json`):
```json
"signup": {
  "modeSignIn": "Sign in",
  "modeCreate": "Create account",
  "create": "Create account",
  "checkEmailTitle": "Check your email",
  "checkEmailBody": "We sent a confirmation link to {{email}}. Click it to finish creating your account.",
  "failed": "Could not create your account. The email may already be registered.",
  "haveAccount": "Already have an account? Sign in",
  "noAccount": "New here? Create an account"
}
```
Hindi values: provide real translations (e.g. `"modeCreate": "खाता बनाएँ"`, `"checkEmailTitle": "अपना ईमेल देखें"`, etc.), same key structure.

- [ ] **Step 2: Extend `EmailPasswordForm` with a mode toggle + signUp**

In `src/features/auth/login-form.tsx`, change `EmailPasswordForm` to support two modes. Keep the existing sign-in behavior; add create-account. Sketch:
```tsx
function EmailPasswordForm() {
  const { t } = useTranslation();
  const router = useRouter();
  const [mode, setMode] = useState<"signin" | "signup">("signin");
  const [serverError, setServerError] = useState<string | null>(null);
  const [pendingEmail, setPendingEmail] = useState<string | null>(null);

  const emailSchema = z.object({
    email: z.string().email(t("validation.emailInvalid")),
    password: z.string().min(1, t("validation.passwordRequired")),
  });
  const form = useForm<EmailValues>({ resolver: zodResolver(emailSchema), defaultValues: { email: "", password: "" } });

  async function onSubmit(values: EmailValues) {
    setServerError(null);
    if (mode === "signin") {
      const { error } = await supabase.auth.signInWithPassword(values);
      if (error) { setServerError(t("auth.login.failed")); return; }
      router.replace("/");
      return;
    }
    // signup
    const { data, error } = await supabase.auth.signUp({
      email: values.email,
      password: values.password,
      options: { emailRedirectTo: `${window.location.origin}/` },
    });
    if (error) { setServerError(t("auth.signup.failed")); return; }
    // Confirm-email is ON → no session yet → show confirmation-pending panel.
    if (!data.session) { setPendingEmail(values.email); return; }
    router.replace("/");  // (defensive: if confirmation were off)
  }

  if (pendingEmail) {
    return (
      <div className="flex flex-col gap-3" data-testid="signup-pending">
        <h2 className="text-lg font-semibold">{t("auth.signup.checkEmailTitle")}</h2>
        <p className="text-sm text-muted-foreground">
          {t("auth.signup.checkEmailBody", { email: pendingEmail })}
        </p>
      </div>
    );
  }

  return (
    <Form {...form}>
      <form onSubmit={form.handleSubmit(onSubmit)} className="flex flex-col gap-4">
        {/* email + password fields: unchanged from current implementation */}
        {/* ...FormField email... ...FormField password... */}
        {serverError && <p className="text-sm text-destructive">{serverError}</p>}
        <Button type="submit" disabled={form.formState.isSubmitting} data-testid="email-submit">
          {mode === "signin" ? t("auth.login.signIn") : t("auth.signup.create")}
        </Button>
        <Button
          type="button"
          variant="ghost"
          data-testid="toggle-auth-mode"
          onClick={() => { setMode(mode === "signin" ? "signup" : "signin"); setServerError(null); }}
        >
          {mode === "signin" ? t("auth.signup.noAccount") : t("auth.signup.haveAccount")}
        </Button>
      </form>
    </Form>
  );
}
```
Keep the existing email/password `FormField`s exactly as they are now; only the submit handler, the mode toggle button, the submit label, and the pending panel are added.

- [ ] **Step 3: Verify**

Run: `cp .env.local.example .env.local && npx tsc --noEmit && npm run build` — clean.

- [ ] **Step 4: e2e (mocked Supabase)**

`tests/e2e/signup.spec.ts` — follow the Supabase-mock pattern already used in `tests/e2e/auth.spec.ts`. Mock `supabase.auth.signUp` to resolve `{ data: { user: { id: "..." }, session: null }, error: null }`. Assert:
- Toggling to "Create account" changes the submit button label.
- Submitting a valid email/password renders the confirmation-pending panel (`data-testid="signup-pending"`) containing the email.
- Toggling back to "Sign in" restores the sign-in button.
Also assert i18n parity still holds (the existing `i18n.spec.ts` covers the new keys).

Run: `npm run test:e2e -- signup.spec.ts i18n.spec.ts` → green.

- [ ] **Step 5: Commit + PR**
```bash
git add -A && git commit -m "feat(auth): email/password sign-up with confirm-email pending state; i18n"
git push -u origin email-password-signup
gh-personal pr create --title "Auth: email/password sign-up" --body "Implements docs/plans/2026-06-18-email-password-signup-plan.md. Closes Dentist-Register-System/dentail-register-docs#23."
```

## Acceptance
Matches spec §6: create-account mode on `/login`; confirmation-pending state on success (confirm-email ON); sign-in still works; new UI i18n'd (en+hi parity), semantic tokens, mobile-first/AA; no backend change; tsc/build clean; e2e green.
