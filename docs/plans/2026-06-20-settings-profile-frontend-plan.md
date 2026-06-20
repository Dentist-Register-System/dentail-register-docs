# Settings & Profile — FRONTEND Slice Implementation Plan (#35)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the `/settings` screen (Profile + Clinic) matched to `Mockups/mockup_settings_profile.png`, on the backend shipped in the backend slice (`/me` name/joined_at, `PATCH /me/profile`, `Doctor.license_number`, `PATCH /clinics/{id}/doctors/me`).

**Architecture:** A `/settings` route (AuthGate → Shell → `AppShell`) hosting a two-pane settings layout: a secondary sub-nav (Profile · Clinic) + a content pane. Profile pane shows/edits the user's identity + own doctor profile; Clinic pane relocates the existing clinic-details edit. A new "Settings" destination is added to the app rail. Reuses existing primitives (`Card`, `Button`, chips, `useMe`, `useDoctor`, `EditClinicDetailsDialog`, the #61 success card, the doctor-profile wizard) — no new visual system (Rule 17.0).

**Tech Stack:** Next.js App Router (client components), TanStack Query, React Hook Form + Zod, react-i18next, Tailwind v4 semantic tokens.

## Global Constraints

- **Frontend-only.** No backend/migration (backend slice already merged). No new dependencies. No new design tokens (this slice does NOT change the palette — that's #65, handled separately).
- **Mockup fidelity:** match `Mockups/mockup_settings_profile.png` (read it). Sub-nav active state = soft `primary-container` pill (mirror the app rail). Two-pane on desktop; mobile = sub-nav list → detail with a back affordance.
- **Scope = Profile + Clinic ONLY.** No Security/Team/Services/Notifications/Integrations/Billing, no preferences/locale, no avatar upload (initials placeholder; real avatar #70), no email/phone change.
- **Profile editable fields:** Full Name (`PATCH /me/profile`), Specialization + License Number (`PATCH /clinics/{id}/doctors/me`). Read-only: Email, Phone, Role, Joined. No doctor profile (`me.doctor_id == null`) → hide doctor rows + show a "Create profile" CTA (reuse the full-screen `DoctorProfileWizard`).
- **Rule 17.0:** semantic tokens only (no raw colours), compose `components/ui/*` + layout components, no per-page CSS. **i18n-first:** every string via `t()` in BOTH `en.json` + `hi.json` (parity gated). Both themes; mobile-first; WCAG AA (focus the heading/pane on nav; labelled inputs; visible focus). Success card (#61) on saves.
- Commit trailer `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`. Feature branch → PR (never push `main`).

---

## File Structure
- Modify: `src/features/clinic/api.ts` (`Me` += name/joined_at; `updateSelfProfile`), `src/features/clinic/hooks.ts` (`useUpdateSelfProfile`).
- Modify: `src/features/doctors/api.ts` (`Doctor` += license_number; `updateSelfDoctor`), `src/features/doctors/hooks.ts` (`useUpdateSelfDoctor`).
- Modify: `src/components/shell/destinations.ts` (+ Settings destination).
- Create: `src/app/settings/page.tsx` (route).
- Create: `src/features/settings/settings-shell.tsx` (sub-nav + pane switch), `src/features/settings/profile-pane.tsx`, `src/features/settings/clinic-pane.tsx`.
- Modify: `src/app/page.tsx` (home clinic-card Edit → /settings) + `src/features/doctors/create-profile-banner.tsx` (CTA → /settings).
- Modify: `src/i18n/locales/en.json` + `hi.json` (`settings.*`, `nav.settings`).
- Docs (docs repo): design-system note.

---

## Task 1: API + hooks + types

**Files:** Modify `src/features/clinic/api.ts`, `src/features/clinic/hooks.ts`, `src/features/doctors/api.ts`, `src/features/doctors/hooks.ts`.

**Interfaces:**
- Produces: `Me.name`/`Me.joined_at`; `updateSelfProfile`/`useUpdateSelfProfile`; `Doctor.license_number`; `updateSelfDoctor`/`useUpdateSelfDoctor`.

- [ ] **Step 1: clinic api** — in `src/features/clinic/api.ts`, extend `Me` and add the endpoint:
```typescript
export type Me = {
  user_id: string | null;
  email: string | null;
  phone: string | null;
  doctor_id: string | null;
  needs_onboarding: boolean;
  memberships: Membership[];
  name: string | null;
  joined_at: string | null;
};

export const updateSelfProfile = (payload: { name?: string }) =>
  apiFetch<{ user_id: string; name: string | null; email: string | null; phone: string | null; joined_at: string }>(
    "/api/v1/me/profile",
    { method: "PATCH", body: JSON.stringify(payload) },
  );
```

- [ ] **Step 2: clinic hook** — in `src/features/clinic/hooks.ts`, add (mirror the existing hooks' query-invalidation style):
```typescript
export function useUpdateSelfProfile() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (payload: { name?: string }) => updateSelfProfile(payload),
    onSuccess: () => qc.invalidateQueries({ queryKey: ["me"] }),
  });
}
```
(Ensure `useMutation`/`useQueryClient` and `updateSelfProfile` are imported; the `me` query key matches `useMe`'s key — confirm and reuse the exact key string used by `useMe`.)

- [ ] **Step 3: doctors api** — in `src/features/doctors/api.ts`, add `license_number: string | null;` to the `Doctor` type and add:
```typescript
export const updateSelfDoctor = (
  clinicId: string,
  payload: { name?: string; phone?: string; specialty?: string; license_number?: string },
) => apiFetch<Doctor>(`/api/v1/clinics/${clinicId}/doctors/me`, {
  method: "PATCH",
  body: JSON.stringify(payload),
});
```

- [ ] **Step 4: doctors hook** — in `src/features/doctors/hooks.ts`, add (import `updateSelfDoctor`):
```typescript
export function useUpdateSelfDoctor(clinicId: string) {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (payload: { name?: string; phone?: string; specialty?: string; license_number?: string }) =>
      updateSelfDoctor(clinicId, payload),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ["doctors", clinicId] });
      qc.invalidateQueries({ queryKey: ["me"] });
    },
  });
}
```
(Match the existing `["doctor", clinicId, doctorId]`/`["doctors", clinicId]` key conventions used in this file; invalidate whatever `useDoctor` uses so the pane refetches.)

- [ ] **Step 5: Verify** — `npx tsc --noEmit && npm run build` clean.

- [ ] **Step 6: Commit**
```bash
git add src/features/clinic/api.ts src/features/clinic/hooks.ts src/features/doctors/api.ts src/features/doctors/hooks.ts
git commit -m "feat(settings): api + hooks for self profile + self doctor update; Me name/joined_at, Doctor license_number

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: Settings route + shell + sub-nav + Clinic pane + rail destination

**Files:** Create `src/app/settings/page.tsx`, `src/features/settings/settings-shell.tsx`, `src/features/settings/clinic-pane.tsx`; Modify `src/components/shell/destinations.ts`, `src/i18n/locales/en.json`+`hi.json`.

**Interfaces:** Consumes `useMe`, `AppShell`, `AuthGate`, `PageContainer`, `Card`/`CardHeader`/`CardTitle`/`CardContent`, `Button`, `Icon`, `EditClinicDetailsDialog`, `useClinic`. Produces `SettingsShell` rendering the sub-nav + the active pane; `ClinicPane`.

> **Read `Mockups/mockup_settings_profile.png` first** for the sub-nav + layout.

- [ ] **Step 1: Rail destination** — in `src/components/shell/destinations.ts`, append to the `destinations` array:
```typescript
  {
    key: "settings",
    labelKey: "nav.settings",
    icon: "settings",
    href: "/settings",
  },
```

- [ ] **Step 2: Clinic pane** — create `src/features/settings/clinic-pane.tsx`. Shows clinic details (from `useClinic`) read-only with the existing edit dialog for editors:
```tsx
"use client";

import { useTranslation } from "react-i18next";

import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { EditClinicDetailsDialog } from "@/features/clinic/edit-clinic-details-dialog";
import { useClinic } from "@/features/clinic/hooks";

export function ClinicPane({ clinicId, canManage }: { clinicId: string; canManage: boolean }) {
  const { t } = useTranslation();
  const clinic = useClinic(clinicId);
  const c = clinic.data;

  return (
    <Card data-testid="settings-clinic">
      <CardHeader className="flex flex-row items-start justify-between gap-3">
        <div>
          <CardTitle>{t("settings.clinic.title")}</CardTitle>
          <p className="text-sm text-muted-foreground">{t("settings.clinic.subtitle")}</p>
        </div>
        {canManage && <EditClinicDetailsDialog clinicId={clinicId} />}
      </CardHeader>
      <CardContent className="space-y-2">
        {clinic.isPending ? (
          <p className="text-sm text-muted-foreground">{t("common.loading")}</p>
        ) : (
          <dl className="divide-y divide-border">
            {[
              { k: t("settings.clinic.name"), v: c?.name },
              { k: t("settings.clinic.phone"), v: c?.phone },
              { k: t("settings.clinic.email"), v: c?.email },
            ].map((row) => (
              <div key={row.k} className="flex justify-between gap-4 py-2.5 text-sm">
                <dt className="text-muted-foreground">{row.k}</dt>
                <dd className="text-right font-medium text-foreground">{row.v || "—"}</dd>
              </div>
            ))}
          </dl>
        )}
      </CardContent>
    </Card>
  );
}
```
> Confirm `Clinic`/`useClinic` exposes `name`/`phone`/`email` (it does — `Clinic` type + contact fields); if a field name differs, use the actual one. Keep it minimal — the mockup's detail is on Profile, not Clinic.

- [ ] **Step 3: Settings shell** — create `src/features/settings/settings-shell.tsx`: a two-pane layout with a sub-nav (Profile · Clinic), default Profile, responsive (desktop side rail; mobile list→detail with back). Render `ProfilePane` (Task 3) and `ClinicPane`.
```tsx
"use client";

import { useState } from "react";
import { useTranslation } from "react-i18next";

import { Icon } from "@/components/ui/icon";
import { ProfilePane } from "@/features/settings/profile-pane";
import { ClinicPane } from "@/features/settings/clinic-pane";

type Section = "profile" | "clinic";

export function SettingsShell({ clinicId, canManageClinic }: { clinicId: string; canManageClinic: boolean }) {
  const { t } = useTranslation();
  const [section, setSection] = useState<Section>("profile");
  const items: { key: Section; labelKey: string; icon: string }[] = [
    { key: "profile", labelKey: "settings.nav.profile", icon: "person" },
    { key: "clinic", labelKey: "settings.nav.clinic", icon: "domain" },
  ];

  return (
    <div className="mx-auto w-full max-w-5xl px-4 py-6" data-testid="settings-page">
      <header className="mb-6">
        <h1 className="text-2xl font-semibold text-foreground">{t("settings.title")}</h1>
        <p className="text-sm text-muted-foreground">{t("settings.subtitle")}</p>
      </header>

      <div className="flex flex-col gap-6 md:flex-row">
        <nav className="md:w-52 md:shrink-0" aria-label={t("settings.title")}>
          <ul className="flex gap-2 overflow-x-auto md:flex-col md:overflow-visible">
            {items.map((it) => {
              const active = section === it.key;
              return (
                <li key={it.key}>
                  <button
                    type="button"
                    onClick={() => setSection(it.key)}
                    aria-current={active ? "page" : undefined}
                    data-testid={`settings-tab-${it.key}`}
                    className={`flex w-full items-center gap-2 rounded-full px-3 py-2 text-sm font-medium transition-colors md:rounded-lg ${
                      active
                        ? "bg-primary-container text-on-primary-container"
                        : "text-muted-foreground hover:bg-muted/50 hover:text-foreground"
                    }`}
                  >
                    <Icon name={it.icon} size={18} aria-hidden />
                    {t(it.labelKey)}
                  </button>
                </li>
              );
            })}
          </ul>
        </nav>

        <div className="min-w-0 flex-1">
          {section === "profile" ? (
            <ProfilePane clinicId={clinicId} />
          ) : (
            <ClinicPane clinicId={clinicId} canManage={canManageClinic} />
          )}
        </div>
      </div>
    </div>
  );
}
```

- [ ] **Step 4: Route** — create `src/app/settings/page.tsx` (mirror `patients/page.tsx`'s AuthGate→Shell→AppShell + me-loading/error/no-clinic pattern):
```tsx
"use client";

import { useTranslation } from "react-i18next";

import { AuthGate } from "@/components/auth-gate";
import { AppShell } from "@/components/shell/app-shell";
import { PageContainer } from "@/components/layout/page-container";
import { useMe } from "@/features/clinic/hooks";
import { SettingsShell } from "@/features/settings/settings-shell";

function SettingsRouteShell() {
  const { t } = useTranslation();
  const me = useMe();

  if (me.isPending) {
    return <PageContainer><p className="text-sm text-muted-foreground">{t("common.loading")}</p></PageContainer>;
  }
  if (me.isError) {
    return <PageContainer><p className="text-sm text-destructive" data-testid="me-error">{t("apiErrors.default")}</p></PageContainer>;
  }
  const membership = me.data?.memberships[0];
  const clinicId = membership?.clinic_id;
  if (!clinicId) {
    return <PageContainer><p className="text-sm text-muted-foreground" data-testid="no-clinic">{t("patients.noClinic")}</p></PageContainer>;
  }
  const role = membership?.role ?? "";
  const canManageClinic = role === "owner" || role === "practice_manager";

  return (
    <AppShell clinicName={membership?.clinic_name}>
      <SettingsShell clinicId={clinicId} canManageClinic={canManageClinic} />
    </AppShell>
  );
}

export default function SettingsPage() {
  return (
    <AuthGate>
      <SettingsRouteShell />
    </AuthGate>
  );
}
```

- [ ] **Step 5: i18n** — add to `en.json` (and mirror in `hi.json` with Hindi values):
```json
  "nav": { "settings": "Settings" },
  "settings": {
    "title": "Settings",
    "subtitle": "Manage your clinic and account",
    "nav": { "profile": "Profile", "clinic": "Clinic" },
    "clinic": { "title": "Clinic", "subtitle": "Your clinic's details", "name": "Clinic name", "phone": "Phone", "email": "Email" }
  }
```
(Merge `nav.settings` into the EXISTING `nav` block — do not duplicate the key. Profile-specific keys are added in Task 3.)

- [ ] **Step 6: Verify** — `npx tsc --noEmit && npm run build`; `npx playwright test tests/e2e/i18n.spec.ts` parity. (ProfilePane import will fail until Task 3 — implement Tasks 2 & 3 together if needed, or stub ProfilePane to a placeholder card that Task 3 replaces. If stubbing, the stub renders `<Card><CardContent>profile</CardContent></Card>` and is fully replaced in Task 3.)

- [ ] **Step 7: Commit**
```bash
git add src/app/settings/ src/features/settings/ src/components/shell/destinations.ts src/i18n/locales/
git commit -m "feat(settings): /settings route, sub-nav shell, clinic pane, rail destination

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: Profile pane (mockup centerpiece)

**Files:** Create `src/features/settings/profile-pane.tsx`; Modify `src/i18n/locales/en.json`+`hi.json`.

**Interfaces:** Consumes `useMe`, `useDoctor` (`@/features/doctors/hooks`), `useUpdateSelfProfile`, `useUpdateSelfDoctor`, `useSuccess` (`@/components/success/use-success`), `Card`/`CardHeader`/`CardTitle`/`CardContent`, `Button`, `Input`, `Icon`, `DoctorProfileWizard`. RHF + Zod.

> **Read `Mockups/mockup_settings_profile.png`** — match the header (avatar + name + role chip + specialization + email/phone) and the "Personal Information" card with Edit + label/value rows.

- [ ] **Step 1: Build the pane.** Create `src/features/settings/profile-pane.tsx`:
```tsx
"use client";

import { useState } from "react";
import { zodResolver } from "@hookform/resolvers/zod";
import { useForm } from "react-hook-form";
import { useTranslation } from "react-i18next";
import { z } from "zod";

import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { FormControl, FormField, FormItem, FormLabel, FormMessage, Form } from "@/components/ui/form";
import { Icon } from "@/components/ui/icon";
import { Input } from "@/components/ui/input";
import { useSuccess } from "@/components/success/use-success";
import { useMe, useUpdateSelfProfile } from "@/features/clinic/hooks";
import { useDoctor, useUpdateSelfDoctor } from "@/features/doctors/hooks";
import { DoctorProfileWizard } from "@/features/doctors/doctor-profile-wizard";

function initials(name: string | null | undefined): string {
  if (!name) return "?";
  return name.trim().split(/\s+/).slice(0, 2).map((p) => p[0]?.toUpperCase() ?? "").join("") || "?";
}

export function ProfilePane({ clinicId }: { clinicId: string }) {
  const { t } = useTranslation();
  const me = useMe();
  const doctorId = me.data?.doctor_id ?? null;
  const doctor = useDoctor(clinicId, doctorId ?? "");
  const success = useSuccess();
  const updateProfile = useUpdateSelfProfile();
  const updateDoctor = useUpdateSelfDoctor(clinicId);
  const [editing, setEditing] = useState(false);
  const [wizardOpen, setWizardOpen] = useState(false);

  const role = me.data?.memberships[0]?.role ?? "";
  const d = doctorId ? doctor.data : null;
  const fullName = me.data?.name ?? d?.name ?? "";

  const schema = z.object({
    name: z.string().min(1, t("validation.nameRequired")),
    specialty: z.string().optional(),
    license_number: z.string().optional(),
  });
  type Values = z.infer<typeof schema>;
  const form = useForm<Values>({
    resolver: zodResolver(schema),
    values: { name: fullName, specialty: d?.specialty ?? "", license_number: d?.license_number ?? "" },
  });

  async function onSave(values: Values) {
    await updateProfile.mutateAsync({ name: values.name });
    if (doctorId) {
      await updateDoctor.mutateAsync({
        specialty: values.specialty || undefined,
        license_number: values.license_number || undefined,
      });
    }
    setEditing(false);
    success({
      titleKey: "settings.profile.savedTitle",
      details: [{ labelKey: "settings.profile.name", value: values.name }],
    });
  }

  if (me.isPending) {
    return <Card><CardContent className="py-6"><p className="text-sm text-muted-foreground">{t("common.loading")}</p></CardContent></Card>;
  }

  const row = (label: string, value: string | null | undefined) => (
    <div className="flex justify-between gap-4 py-2.5 text-sm">
      <dt className="text-muted-foreground">{label}</dt>
      <dd className="text-right font-medium text-foreground">{value || "—"}</dd>
    </div>
  );

  return (
    <div className="space-y-5" data-testid="settings-profile">
      {/* Header */}
      <Card>
        <CardContent className="flex flex-col items-start gap-4 py-5 sm:flex-row sm:items-center">
          <div className="flex size-16 items-center justify-center rounded-full bg-primary-container text-xl font-semibold text-on-primary-container" aria-hidden>
            {initials(fullName)}
          </div>
          <div className="min-w-0">
            <div className="flex flex-wrap items-center gap-2">
              <h2 className="text-lg font-semibold text-foreground">{fullName || t("settings.profile.noName")}</h2>
              {role && <span className="rounded-full bg-primary-container px-2.5 py-0.5 text-xs font-medium capitalize text-on-primary-container">{t(`roles.${role}`, role)}</span>}
            </div>
            {d?.specialty && <p className="text-sm text-muted-foreground">{d.specialty}</p>}
            <p className="text-sm text-muted-foreground">{me.data?.email}</p>
            {me.data?.phone && <p className="text-sm text-muted-foreground">{me.data.phone}</p>}
          </div>
        </CardContent>
      </Card>

      {/* No doctor profile → CTA */}
      {!doctorId && (
        <Card>
          <CardContent className="flex flex-col items-start gap-3 py-5">
            <div className="flex items-center gap-2"><Icon name="stethoscope" size={20} className="text-primary" aria-hidden /><p className="text-sm font-medium text-foreground">{t("settings.profile.createDoctorPrompt")}</p></div>
            <Button size="sm" onClick={() => setWizardOpen(true)} data-testid="settings-create-profile">{t("settings.profile.createDoctorCta")}</Button>
          </CardContent>
        </Card>
      )}
      {wizardOpen && <DoctorProfileWizard clinicId={clinicId} onClose={() => setWizardOpen(false)} />}

      {/* Personal Information */}
      <Card>
        <CardHeader className="flex flex-row items-center justify-between gap-3">
          <CardTitle className="flex items-center gap-2"><Icon name="badge" size={18} aria-hidden />{t("settings.profile.personalInfo")}</CardTitle>
          {!editing && <Button size="sm" variant="outlined" onClick={() => { form.reset({ name: fullName, specialty: d?.specialty ?? "", license_number: d?.license_number ?? "" }); setEditing(true); }} data-testid="settings-edit-profile">{t("settings.profile.edit")}</Button>}
        </CardHeader>
        <CardContent>
          {editing ? (
            <Form {...form}>
              <form onSubmit={form.handleSubmit(onSave)} className="space-y-4" data-testid="settings-profile-form">
                <FormField control={form.control} name="name" render={({ field }) => (
                  <FormItem><FormLabel>{t("settings.profile.name")}</FormLabel><FormControl><Input data-testid="profile-fullname" {...field} /></FormControl><FormMessage /></FormItem>
                )} />
                {doctorId && (
                  <>
                    <FormField control={form.control} name="specialty" render={({ field }) => (
                      <FormItem><FormLabel>{t("settings.profile.specialization")}</FormLabel><FormControl><Input data-testid="profile-specialty" {...field} /></FormControl><FormMessage /></FormItem>
                    )} />
                    <FormField control={form.control} name="license_number" render={({ field }) => (
                      <FormItem><FormLabel>{t("settings.profile.license")}</FormLabel><FormControl><Input data-testid="profile-license" {...field} /></FormControl><FormMessage /></FormItem>
                    )} />
                  </>
                )}
                {(updateProfile.isError || updateDoctor.isError) && <p className="text-sm text-destructive">{t("apiErrors.default")}</p>}
                <div className="flex justify-end gap-2">
                  <Button type="button" variant="ghost" size="sm" onClick={() => setEditing(false)}>{t("common.cancel")}</Button>
                  <Button type="submit" size="sm" disabled={updateProfile.isPending || updateDoctor.isPending} data-testid="profile-save">{t("common.save")}</Button>
                </div>
              </form>
            </Form>
          ) : (
            <dl className="divide-y divide-border">
              {row(t("settings.profile.name"), fullName)}
              {row(t("settings.profile.email"), me.data?.email)}
              {row(t("settings.profile.phone"), me.data?.phone)}
              {doctorId && row(t("settings.profile.specialization"), d?.specialty)}
              {doctorId && row(t("settings.profile.license"), d?.license_number)}
              {row(t("settings.profile.role"), role ? t(`roles.${role}`, role) : "")}
              {row(t("settings.profile.joined"), me.data?.joined_at ? new Date(me.data.joined_at).toLocaleDateString() : "")}
            </dl>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
```
> Notes: `useDoctor(clinicId, "")` must be disabled when no id — the existing `useDoctor` hook should gate on a truthy id; if it does not, pass a guard so it doesn't fetch with an empty id (mirror how other hooks use `enabled`). `roles.*` i18n keys: reuse existing role labels if present, else the `t(\`roles.${role}\`, role)` fallback shows the raw role. `Form`/`FormLabel` are exported from `@/components/ui/form` (used in onboarding). `common.save` — add if missing.

- [ ] **Step 2: i18n** — add the `settings.profile` block + any missing `common.save`/`roles.*` to `en.json` and `hi.json` (parity):
```json
  "settings": {
    "profile": {
      "personalInfo": "Personal Information",
      "edit": "Edit",
      "name": "Full Name",
      "email": "Email",
      "phone": "Phone",
      "specialization": "Specialization",
      "license": "License Number",
      "role": "Role",
      "joined": "Joined Register",
      "noName": "Add your name",
      "savedTitle": "Profile updated",
      "createDoctorPrompt": "Are you a practicing doctor? Create your profile.",
      "createDoctorCta": "Create profile"
    }
  }
```
(Merge into the existing `settings` block from Task 2 — one `settings` object. Add `"common": { "save": "Save" }` if not present; mirror Hindi.)

- [ ] **Step 3: Verify** — `npx tsc --noEmit && npm run build` clean; i18n parity passes; manually confirm the route compiles. Replace any Task-2 ProfilePane stub.

- [ ] **Step 4: Commit**
```bash
git add src/features/settings/profile-pane.tsx src/i18n/locales/
git commit -m "feat(settings): profile pane — identity header + editable personal info (mockup-matched)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: Re-point home entries + docs

**Files:** Modify `src/app/page.tsx`, `src/features/doctors/create-profile-banner.tsx`; Docs repo design-system note.

- [ ] **Step 1: Home clinic-card Edit → Settings.** In `src/app/page.tsx`, where the clinic card renders `EditClinicDetailsDialog` (or an Edit affordance), replace it with a link/button navigating to `/settings` (Clinic). Use `next/link` `Link` styled as the existing button (e.g. `<Link href="/settings" className={buttonVariants({ variant: "outlined", size: "sm" })}>{t("clinic.edit")}</Link>`), or `useRouter().push("/settings")`. Keep the rest of the card unchanged. (If removing `EditClinicDetailsDialog` from home leaves an unused import, drop it.)

- [ ] **Step 2: Create-profile banner → Settings.** In `src/features/doctors/create-profile-banner.tsx`, change the CTA to navigate to `/settings` (Profile) instead of opening the wizard inline — e.g. the CTA becomes a `Link href="/settings"`. Keep the banner copy + dismiss. (The wizard is now reachable from the Profile pane's "Create profile" CTA.)

- [ ] **Step 3: Verify** — `npx tsc --noEmit && npm run build` clean; no unused imports.

- [ ] **Step 4: Commit**
```bash
git add src/app/page.tsx src/features/doctors/create-profile-banner.tsx
git commit -m "feat(settings): route home clinic-edit + create-profile entries into /settings

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

- [ ] **Step 5: Docs** — in `dentail-register-docs`: `git checkout main && git pull --ff-only && git checkout -b docs/settings-profile-frontend-35`; add a brief **Settings & Profile** note to `Design/02-design-system.md` (two-pane settings: sub-nav Profile/Clinic; Profile = identity header + editable Personal Information; reuses Card/chips/success card; references `Mockups/mockup_settings_profile.png` + spec #35); commit with trailer.

---

## Final Verification (before PRs)
- [ ] Frontend: `npx tsc --noEmit && npm run build` clean; `npx playwright test tests/e2e/i18n.spec.ts` pass.
- [ ] Manually: `/settings` shows Profile (header + editable Personal Info) + Clinic; Settings appears in the rail; home Edit + banner route into Settings.
- [ ] Frontend PR `Closes #35`; docs PR `Part of #35`.
- [ ] No backend/migration/dependency/token change. (Palette warmth = #65, separate.)

## Self-Review (against spec §4–§5)
- **/settings + sub-nav (Profile/Clinic only) + rail destination:** Tasks 1–2. ✅
- **Profile pane mockup-matched (header avatar/name/role chip/specialization/email/phone; Personal Information w/ Edit; editable Full Name/Specialization/License; read-only Email/Phone/Role/Joined; no-doctor CTA):** Task 3. ✅
- **Clinic pane relocates existing edit (owner/PM):** Task 2. ✅
- **Re-point home Edit + create-profile banner:** Task 4. ✅
- **Success card on save (#61); i18n en/hi; Rule 17.0; both themes:** Tasks 2–3. ✅
- **No avatar upload / preferences / Security / email-phone change / palette change:** honored (initials placeholder; #70/#65 separate). ✅
- **Placeholder scan:** code uses real hooks/components/endpoints from Task 1 + existing primitives; the two flagged confirmations (useMe query-key string; useDoctor `enabled` guard for empty id) are concrete verification steps against existing code, not TBDs. ✅
- **Type consistency:** `Me.name/joined_at`, `Doctor.license_number`, `updateSelfProfile`/`useUpdateSelfProfile`, `updateSelfDoctor`/`useUpdateSelfDoctor`, `SettingsShell`/`ProfilePane`/`ClinicPane` consistent across tasks. ✅
