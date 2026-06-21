# Move Clinic Details (Home → Settings → Clinic) Implementation Plan (#85)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Relocate all clinic details from Home into Settings → Clinic (redesigned to the approved render), and turn Home into a personalized welcome that keeps its operational widgets.

**Architecture:** Frontend-only composition in `dentist-registry-frontend`. (1) Make `EditClinicDetailsDialog` controllable so two triggers share one dialog. (2) Rebuild `ClinicPane` into a Clinic Information 2-col card + a Profile Completion card (CSS conic-gradient ring + bar + steps + Complete Profile + check rows), reusing `useClinic` / `computeClinicCompleteness` / `ClinicAddressPreview` patterns. (3) Strip the three clinic blocks from Home and add a personalized greeting. No backend, no migration, no new pure logic.

**Tech Stack:** Next.js (App Router, client components), react-i18next (en/hi), Tailwind v4 semantic tokens, Material Symbols, existing `components/ui/*` primitives.

## Global Constraints
- **Frontend-only.** No backend, no migration, no new npm deps. Reuse `useClinic`, `EditClinicDetailsDialog`, `computeClinicCompleteness`, and the `ClinicAddressPreview` boxed-preview pattern.
- **Rule 17.0:** semantic tokens only — no raw colour literals or Tailwind palette utilities (`bg-white`, `text-gray-*`); no per-page CSS files; no new design tokens. Inline CSS vars (`var(--primary)`, `var(--muted)`, `var(--card)`) are allowed (precedent: `auth-shell.tsx`).
- **i18n:** every new user-facing string is a `t()` key present in BOTH `src/i18n/locales/en.json` and `src/i18n/locales/hi.json` (the `tests/e2e/i18n.spec.ts` parity gate must pass).
- **Match the Settings → Profile pane** (`src/features/settings/profile-pane.tsx`): `Card` → `CardHeader`(`CardTitle` + `text-sm text-muted-foreground` subtitle) → `CardSeparator` → `CardContent`; Edit = `Button variant="outlined" size="sm"` + `Icon name="edit" size={16}` in `CardAction`; section titles `CardTitle` with `Icon size={18}`; labels `text-sm text-muted-foreground`, values `text-sm font-medium text-foreground`, `—` fallback; outer rhythm `space-y-5`.
- Both themes (light/dark); mobile-first (columns stack; ring/body stack). WCAG AA — the ring/bar are decorative; the steps line + check rows carry the accessible text.
- **CI = `npx tsc --noEmit` + `npm run build`** (the only two CI steps). Run `npx playwright test tests/e2e/i18n.spec.ts` locally for parity. Stale iCloud `" 2"` files break `tsc` — if `tsc` reports `.next/types/* 2.ts` or `* 2.tsx`, `find . -name "* 2.ts*" -not -path "./node_modules/*" -delete` and re-run.
- Commit trailer `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`; stage SPECIFIC paths (never `git add -A`; never stage `.superpowers/`); don't touch `.env.local`.
- **Merge policy:** frontend branch → open the PR and STOP; hand to the human to test; merge ONLY on their explicit say-so.

> **No new pure logic ⇒ no new unit test file.** The ring percent and "done/total" come from the already-tested `computeClinicCompleteness`; the greeting is a ternary on `me.data.name`. Per-task validation is `tsc --noEmit` + `npm run build` + i18n parity (and the existing `tests/e2e/clinic-completeness*.spec.ts`, if present, must still pass). This is deliberate, not an omission.

---

## Task 1: Make `EditClinicDetailsDialog` controllable

**Files:**
- Modify: `dentist-registry-frontend/src/features/clinic/edit-clinic-details-dialog.tsx`

**Interfaces:**
- Consumes: nothing new.
- Produces: `EditClinicDetailsDialog` now accepts optional `open?: boolean` and `onOpenChange?: (open: boolean) => void`. When BOTH are omitted it behaves exactly as today (renders its own outlined "Edit clinic details" `DialogTrigger`, internal state). When provided, it is controlled by the parent and renders NO default trigger (the parent supplies its own buttons).

**Context:** Today the dialog self-manages `useState` `open` and renders a `DialogTrigger`. The new Clinic pane needs TWO triggers (an Edit pill + a "Complete Profile" button) to open ONE dialog, so we lift open-state control to the parent. The dialog is currently used in exactly one place (`clinic-pane.tsx`, which Task 2 rewrites), so this refactor is safe.

- [ ] **Step 1: Add controlled props + open-state plumbing.**

Replace the props interface and the `const [open, setOpen] = useState(false);` line.

Change the interface (around line 55-57):
```tsx
interface EditClinicDetailsDialogProps {
  clinicId: string;
  open?: boolean;
  onOpenChange?: (open: boolean) => void;
}

export function EditClinicDetailsDialog({
  clinicId,
  open: controlledOpen,
  onOpenChange,
}: EditClinicDetailsDialogProps) {
```

Replace `const [open, setOpen] = useState(false);` (line ~64) with:
```tsx
  const [internalOpen, setInternalOpen] = useState(false);
  const isControlled = controlledOpen !== undefined;
  const open = isControlled ? controlledOpen : internalOpen;
  const setOpen = (next: boolean) => {
    if (!isControlled) setInternalOpen(next);
    onOpenChange?.(next);
  };
```
(Leave `handleOpenChange`, `onSubmit`'s `setOpen(false)`, and the `useEffect` on `[clinic.data, open]` unchanged — they now route through the wrapper `setOpen` / the derived `open`.)

- [ ] **Step 2: Render the default trigger only when uncontrolled.**

Wrap the existing `<DialogTrigger>…</DialogTrigger>` (lines ~177-183) so it renders only when the component is uncontrolled:
```tsx
      {!isControlled && (
        <DialogTrigger
          className={buttonVariants({ variant: "outlined", size: "default" })}
          data-testid="edit-clinic-details-button"
        >
          <Icon name="edit" size={18} aria-hidden />
          {t("clinic.editDetails")}
        </DialogTrigger>
      )}
```
Everything inside `<DialogPopup>` stays exactly the same.

- [ ] **Step 3: Verify.**

Run: `cd dentist-registry-frontend && npx tsc --noEmit && npm run build`
Expected: both succeed (no type errors; build completes). If `tsc` flags `* 2.ts*` files, delete them (see Global Constraints) and re-run.

- [ ] **Step 4: Commit.**
```bash
git add src/features/clinic/edit-clinic-details-dialog.tsx
git commit -m "refactor(clinic): make EditClinicDetailsDialog controllable (shared dialog)"
```

---

## Task 2: Rebuild Settings → Clinic pane (Clinic Information + Completion)

**Files:**
- Modify: `dentist-registry-frontend/src/features/settings/clinic-pane.tsx` (full rewrite)
- Modify: `dentist-registry-frontend/src/i18n/locales/en.json`
- Modify: `dentist-registry-frontend/src/i18n/locales/hi.json`

**Interfaces:**
- Consumes: `EditClinicDetailsDialog` controlled props from Task 1 (`open`, `onOpenChange`); `useClinic(clinicId)`; `computeClinicCompleteness(clinic)` → `{ items: {key, present}[], percent }`.
- Produces: the new `ClinicPane({ clinicId, canManage })` (same props as today).

- [ ] **Step 1: Add i18n keys (en).**

In `src/i18n/locales/en.json`:
- Update `settings.clinic` (currently `{ "title": "Clinic", "subtitle": "Your clinic's details", "name": "Clinic name", "phone": "Phone", "email": "Email" }`) to:
```json
"clinic": { "title": "Clinic Information", "subtitle": "Update your clinic details", "name": "Clinic Name", "phone": "Phone Number", "whatsapp": "WhatsApp Number", "email": "Email", "address": "Address", "addressPreview": "Address Preview" }
```
- Under `clinic.completeness` (currently has `title, percent, name, address, phone, whatsapp, email`) add:
```json
"subtitle": "Complete your clinic profile to build trust with your patients",
"steps": "{{done}} of {{total}} steps completed"
```
- Under `clinic` add a sibling key:
```json
"completeProfile": "Complete Profile"
```

- [ ] **Step 2: Add the SAME keys to hi.json (parity).**

In `src/i18n/locales/hi.json`, mirror every key added/changed in Step 1 with Hindi values:
```json
"settings"."clinic": { "title": "क्लिनिक जानकारी", "subtitle": "अपने क्लिनिक का विवरण अपडेट करें", "name": "क्लिनिक का नाम", "phone": "फ़ोन नंबर", "whatsapp": "व्हाट्सऐप नंबर", "email": "ईमेल", "address": "पता", "addressPreview": "पता पूर्वावलोकन" }
"clinic"."completeness"."subtitle": "अपने मरीज़ों का भरोसा बनाने के लिए अपनी क्लिनिक प्रोफ़ाइल पूरी करें"
"clinic"."completeness"."steps": "{{total}} में से {{done}} चरण पूर्ण"
"clinic"."completeProfile": "प्रोफ़ाइल पूरी करें"
```
(Place each under the matching existing object — do not create duplicate parent objects. Keep `{{done}}`/`{{total}}` placeholders intact.)

- [ ] **Step 3: Rewrite `clinic-pane.tsx`.**

Replace the entire file with:
```tsx
"use client";

import { useState } from "react";
import { useTranslation } from "react-i18next";

import { Button } from "@/components/ui/button";
import { Card, CardAction, CardContent, CardHeader, CardSeparator, CardTitle } from "@/components/ui/card";
import { Icon } from "@/components/ui/icon";
import { EditClinicDetailsDialog } from "@/features/clinic/edit-clinic-details-dialog";
import { useClinic } from "@/features/clinic/hooks";
import { computeClinicCompleteness } from "@/features/clinic/completeness";

export function ClinicPane({ clinicId, canManage }: { clinicId: string; canManage: boolean }) {
  const { t } = useTranslation();
  const clinic = useClinic(clinicId);
  const c = clinic.data;
  const [editOpen, setEditOpen] = useState(false);

  const { items, percent } = computeClinicCompleteness(c ?? {});
  const done = items.filter((i) => i.present).length;
  const total = items.length;

  const field = (label: string, value: string | null | undefined, opts?: { pre?: boolean }) => (
    <div className="mb-4 last:mb-0">
      <div className="mb-1 text-sm text-muted-foreground">{label}</div>
      <div className={`text-sm font-medium text-foreground${opts?.pre ? " whitespace-pre-line" : ""}`}>
        {value || "—"}
      </div>
    </div>
  );

  return (
    <div className="space-y-5" data-testid="settings-clinic">
      {/* Clinic Information */}
      <Card>
        <CardHeader>
          <CardTitle>{t("settings.clinic.title")}</CardTitle>
          <p className="text-sm text-muted-foreground">{t("settings.clinic.subtitle")}</p>
          {canManage && (
            <CardAction>
              <Button
                variant="outlined"
                size="sm"
                onClick={() => setEditOpen(true)}
                data-testid="settings-edit-clinic"
              >
                <Icon name="edit" size={16} aria-hidden />
                {t("clinic.editDetails")}
              </Button>
            </CardAction>
          )}
        </CardHeader>
        <CardSeparator />
        <CardContent>
          {clinic.isPending ? (
            <p className="text-sm text-muted-foreground">{t("common.loading")}</p>
          ) : (
            <div className="grid grid-cols-1 gap-x-10 gap-y-0 lg:grid-cols-2">
              <div>
                {field(t("settings.clinic.name"), c?.name)}
                {field(t("settings.clinic.phone"), c?.phone)}
                {field(t("settings.clinic.whatsapp"), c?.whatsapp_number)}
                {field(t("settings.clinic.email"), c?.email)}
              </div>
              <div>
                <div className="mb-4">
                  <div className="mb-1 text-sm text-muted-foreground">{t("settings.clinic.address")}</div>
                  <div className="whitespace-pre-line text-sm font-medium text-foreground">
                    {c?.formatted_address || "—"}
                  </div>
                  {c?.google_maps_url && (
                    <a
                      href={c.google_maps_url}
                      target="_blank"
                      rel="noopener noreferrer"
                      className="mt-1 inline-block text-sm font-medium text-primary underline-offset-4 hover:underline"
                      data-testid="clinic-directions-link"
                    >
                      {t("clinic.directions")}
                    </a>
                  )}
                </div>
                {c?.formatted_address && (
                  <div>
                    <div className="mb-1 text-sm text-muted-foreground">{t("settings.clinic.addressPreview")}</div>
                    <div className="rounded-lg bg-muted/50 px-4 py-3" data-testid="clinic-address-preview">
                      <p className="text-sm font-semibold text-foreground" data-testid="preview-clinic-name">
                        {c.name}
                      </p>
                      <div className="mt-1 whitespace-pre-line text-sm text-foreground" data-testid="preview-formatted-address">
                        {c.formatted_address}
                      </div>
                    </div>
                  </div>
                )}
              </div>
            </div>
          )}
        </CardContent>
      </Card>

      {/* Clinic Profile Completion */}
      <Card data-testid="clinic-completeness">
        <CardContent className="py-5">
          <div className="flex flex-col items-start gap-5 sm:flex-row sm:items-center">
            <div
              className="flex size-[78px] shrink-0 items-center justify-center rounded-full"
              style={{ background: `conic-gradient(var(--primary) ${percent}%, var(--muted) 0)` }}
              role="img"
              aria-label={t("clinic.completeness.steps", { done, total })}
              data-testid="clinic-completion-ring"
            >
              <div className="flex size-[60px] items-center justify-center rounded-full bg-card text-base font-bold text-foreground">
                <span data-testid="completeness-percent">{t("clinic.completeness.percent", { percent })}</span>
              </div>
            </div>
            <div className="min-w-0 flex-1">
              <p className="text-base font-semibold text-foreground">{t("clinic.completeness.title")}</p>
              <p className="mt-0.5 text-sm text-muted-foreground">{t("clinic.completeness.subtitle")}</p>
              <div className="mt-3 h-2 w-full overflow-hidden rounded-full bg-muted">
                <div className="h-full rounded-full bg-primary" style={{ width: `${percent}%` }} />
              </div>
              <p className="mt-2 text-xs text-muted-foreground">{t("clinic.completeness.steps", { done, total })}</p>
            </div>
            {canManage && (
              <Button
                size="sm"
                onClick={() => setEditOpen(true)}
                className="shrink-0"
                data-testid="clinic-complete-profile"
              >
                <Icon name="edit" size={16} aria-hidden />
                {t("clinic.completeProfile")}
              </Button>
            )}
          </div>
          <div className="mt-4 flex flex-wrap gap-x-6 gap-y-2">
            {items.map((item) => (
              <span
                key={item.key}
                className="flex items-center gap-2 text-sm text-foreground"
                data-testid={`completeness-item-${item.key}`}
              >
                <Icon
                  name={item.present ? "check_circle" : "radio_button_unchecked"}
                  size={18}
                  className={item.present ? "text-primary" : "text-muted-foreground"}
                  aria-hidden
                />
                {t(`clinic.completeness.${item.key}`)}
              </span>
            ))}
          </div>
        </CardContent>
      </Card>

      {/* Shared controlled edit dialog (opened by both Edit + Complete Profile) */}
      {canManage && (
        <EditClinicDetailsDialog clinicId={clinicId} open={editOpen} onOpenChange={setEditOpen} />
      )}
    </div>
  );
}
```

- [ ] **Step 4: Verify.**

Run: `cd dentist-registry-frontend && npx tsc --noEmit && npm run build && npx playwright test tests/e2e/i18n.spec.ts`
Expected: tsc clean, build completes, i18n parity test passes. (Delete `* 2.ts*` files first if tsc flags them.)

- [ ] **Step 5: Commit.**
```bash
git add src/features/settings/clinic-pane.tsx src/i18n/locales/en.json src/i18n/locales/hi.json
git commit -m "feat(settings): clinic information 2-col + profile completion card (#85)"
```

---

## Task 3: Strip clinic blocks from Home + personalized greeting

**Files:**
- Modify: `dentist-registry-frontend/src/app/page.tsx`
- Modify: `dentist-registry-frontend/src/i18n/locales/en.json`
- Modify: `dentist-registry-frontend/src/i18n/locales/hi.json`

**Interfaces:**
- Consumes: `useMe()` (`me.data.name: string | null`, `me.data.doctor_id`, `memberships[0].clinic_name`), `CreateProfileBanner`, `PendingRequestsCard`, `PageContainer`, `AppShell`.
- Produces: a leaner `HomeShell` (greeting + kept widgets).

- [ ] **Step 1: Add the greeting i18n key (en + hi).**

In `src/i18n/locales/en.json` under `home` add: `"welcomeName": "Welcome, {{name}}"`.
In `src/i18n/locales/hi.json` under `home` add: `"welcomeName": "नमस्ते, {{name}}"`.
(`home.welcomeBack` already exists in both — reuse it for the no-name fallback.)

- [ ] **Step 2: Replace the clinic shell render in `page.tsx`.**

In the `return (<AppShell …>` block of `HomeShell` (lines ~60-211), replace the entire `<section data-testid="clinic-shell" …>…</section>` body so it (a) keeps the `CreateProfileBanner` + `PendingRequestsCard`, (b) shows the greeting, and (c) drops the Clinic Summary card, `<ClinicAddressPreview>`, and `<ClinicCompleteness>`:
```tsx
        <section data-testid="clinic-shell" className="space-y-6">
          {clinicId && me.data && !me.data.doctor_id && <CreateProfileBanner />}
          <div>
            <h1 className="text-3xl font-bold tracking-tight text-foreground">
              {me.data?.name
                ? t("home.welcomeName", { name: me.data.name })
                : t("home.welcomeBack")}
            </h1>
            {membership?.clinic_name && (
              <p className="mt-1 text-sm text-muted-foreground">{membership.clinic_name}</p>
            )}
          </div>
          {clinicId && <PendingRequestsCard clinicId={clinicId} />}
        </section>
```

- [ ] **Step 3: Remove now-unused imports + the `useClinic` call.**

Delete the imports that are no longer referenced: `Card`, `CardAction`, `CardContent`, `CardDescription`, `CardHeader`, `CardSeparator`, `CardTitle` (the whole `@/components/ui/card` import), `Icon`, `buttonVariants`, `Link` (`next/link`), `PageHeader` (`@/components/layout/page-header`), `ClinicAddressPreview`, `ClinicCompleteness`. Keep `useMe`; remove `useClinic` from the `@/features/clinic/hooks` import. Delete the line `const clinic = useClinic(clinicId);`.
(After editing, confirm no remaining reference to any deleted symbol — `tsc` in Step 4 will catch a miss. `PageContainer`, `AppShell`, `AuthGate`, `Onboarding`, `CreateProfileBanner`, `PendingRequestsCard`, `useMe` stay.)

- [ ] **Step 4: Verify.**

Run: `cd dentist-registry-frontend && npx tsc --noEmit && npm run build && npx playwright test tests/e2e/i18n.spec.ts`
Expected: tsc clean (no "unused"/"undefined" symbol errors), build completes, i18n parity passes. (Delete `* 2.ts*` files first if flagged.)

- [ ] **Step 5: Commit.**
```bash
git add src/app/page.tsx src/i18n/locales/en.json src/i18n/locales/hi.json
git commit -m "feat(home): personalized welcome; move clinic details to Settings (#85)"
```

---

## Task 4: Clean up orphaned components (conditional)

**Files:**
- Possibly delete: `dentist-registry-frontend/src/features/clinic/clinic-address-preview.tsx`, `src/features/clinic/clinic-completeness.tsx`, and any of their `tests/e2e/*completeness*` / `*address-preview*` specs.

- [ ] **Step 1: Check for remaining references.**

Run: `cd dentist-registry-frontend && grep -rn "ClinicAddressPreview\|ClinicCompleteness" src tests`
- If the ONLY hits are the component definitions themselves (and their own test files), they are orphaned → proceed to Step 2.
- If anything else imports them, STOP and leave them in place (do not delete); report this and skip to Step 3.

- [ ] **Step 2: Delete the orphaned files (only if Step 1 showed they're unused).**

Delete the component file(s) and their dedicated test file(s) that are now orphaned. Do NOT delete `completeness.ts` (the pure `computeClinicCompleteness` — still used by Task 2) or its unit test.

- [ ] **Step 3: Verify.**

Run: `cd dentist-registry-frontend && npx tsc --noEmit && npm run build`
Expected: both succeed.

- [ ] **Step 4: Commit (only if files were deleted).**
```bash
git add -u src/features/clinic tests
git commit -m "chore(clinic): remove components orphaned by the Settings move (#85)"
```

---

## Self-Review (plan vs spec)
- **Spec §3 (Home greeting + keep widgets, drop 3 blocks):** Task 3. ✅
- **Spec §4a (Clinic Information 2-col + Edit):** Task 2 Step 3. ✅
- **Spec §4b (Completion ring/bar/steps + Complete Profile + check rows):** Task 2 Step 3. ✅
- **Spec §4c (both triggers open one dialog):** Task 1 (controllable) + Task 2 (shared controlled instance). ✅
- **Spec §5 (Profile pane conventions):** Global Constraints + Task 2 (CardSeparator, outlined sm Edit, label/value type scale, `space-y-5`). ✅
- **Spec §6 (i18n en/hi parity):** Task 2 Steps 1-2 + Task 3 Step 1. ✅
- **Spec §7 (files; orphan handling):** Tasks 2-4. ✅
- **Spec §9 (Rule 17.0, themes, CI, merge policy):** Global Constraints + per-task verify. ✅
- **Placeholder scan:** every code step has full code; no TBD/“similar to”. ✅
- **Type consistency:** `EditClinicDetailsDialog` props (`open`/`onOpenChange`) defined in Task 1 are exactly what Task 2 passes; `computeClinicCompleteness(c ?? {})` matches its `Partial<Clinic>` signature; `items`/`percent`/`present`/`key` names match `completeness.ts`. ✅
