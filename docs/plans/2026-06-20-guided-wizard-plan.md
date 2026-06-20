# Guided One-Question Wizard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a reusable M3 guided wizard (one question per card, top progress, desktop left step-rail / mobile dots, Skip/Next, per-card reassurance) and migrate clinic creation + doctor-profile creation onto it.

**Architecture:** A config-driven `Wizard` component (RHF-backed shared form; renders progress + desktop rail + mobile dots + the current step's content + a per-flow reassurance line + Back/Next/Skip; validates the current step's fields before advancing; submits on the last step). A pure `step-logic.ts` holds the testable navigation math. Two consumers pass step configs: clinic creation (onboarding, 5 steps) and doctor-profile creation (full-screen overlay replacing the #49 dialog, 3 steps).

**Tech Stack:** Next.js App Router (client components), React Hook Form + Zod, react-i18next, Tailwind v4 semantic tokens, Playwright (pure-logic + i18n; tsc + build are the CI gates). **Frontend-only — no backend/API/schema/migration.**

**Spec:** `docs/specs/2026-06-20-guided-wizard-design.md` (issue #50).

## Global Constraints

- **No backend/migration.** Reuses existing endpoints via existing hooks: `useCreateClinic()` (`POST /clinics`) and `useCreateSelfDoctor(clinicId)` (`POST …/doctors/me`). Do not touch any backend repo.
- **Locked design:** one question per card; **the clinic postal address is ONE card** (not per-field); top **progress bar**; **desktop left step-rail** (done ✓ / current / upcoming) hidden below `md`; **mobile horizontal dots** (`md:hidden`, current elongated); **Back** (not on step 1), **Next** (required steps, disabled until the step is complete), **Skip** (optional steps); **last step submits** ("Create clinic" / "Create profile") — no separate review step; **reassurance line on every card** = a circled-i (M3 `info` icon) + italic muted text, below the field(s), above the buttons, per-flow copy (clinic → "…Your clinic → Edit clinic details"; doctor → "…in My Profile").
- **Validation per step:** advancing a required step runs RHF `trigger(stepFields)` and only proceeds if valid; reuse the existing Zod rules (phone `^\+?[0-9\s\-().]+$`, PIN `^[1-9][0-9]{5}$`, email, required fields). Back preserves entered values.
- **Frontend Rule 17.0:** semantic tokens only (no raw colours / `bg-white` / `text-gray-*`), compose `components/ui/*`, no per-page CSS, both themes, mobile-first, WCAG AA (focus the step heading on advance; rail/dots have roles/labels). **i18n-first:** every user-facing string via `t()`, in BOTH `en.json` + `hi.json` (parity enforced by `tests/e2e/i18n.spec.ts`).
- **Next.js caveat (`AGENTS.md`):** breaking changes; client components; consult `node_modules/next/dist/docs/` if surprised. Permissive-OSS only; **no new dependencies** (RHF, i18next, the UI primitives all exist).
- Frontend repo `dentist-registry-frontend`; docs `dentail-register-docs`. Commit trailer `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`. Feature branch → PR (never push `main`).

---

## File Structure
- Create: `src/components/wizard/step-logic.ts` — pure navigation math (testable).
- Create: `src/components/wizard/wizard.tsx` — the reusable `Wizard` component.
- Create: `tests/e2e/wizard-logic.spec.ts` — pure-logic unit test.
- Modify: `src/features/auth/onboarding.tsx` — `CreateClinicForm` → wizard steps (5 steps; address one card).
- Create: `src/features/doctors/doctor-profile-wizard.tsx` — full-screen doctor-profile wizard.
- Modify: `src/features/doctors/create-profile-banner.tsx` — open the full-screen wizard (replace the dialog).
- Delete: `src/features/doctors/doctor-profile-dialog.tsx`.
- Modify: `src/i18n/locales/en.json` + `hi.json` — wizard control + per-flow copy keys.
- Modify (docs repo): a design-system / Golden Rules note.

---

## Task 1: Reusable `Wizard` + pure step-logic + unit test + i18n

**Files:** Create `src/components/wizard/step-logic.ts`, `src/components/wizard/wizard.tsx`, `tests/e2e/wizard-logic.spec.ts`; Modify `src/i18n/locales/en.json` + `hi.json`.

**Interfaces:**
- Produces: `stepStatuses(count, current): ("done"|"current"|"upcoming")[]`, `wizardProgressPercent(count, current): number`, `isLastStep(count, current): boolean`; `WizardStep` type; `Wizard` component.

- [ ] **Step 1: Write the failing unit test**

Create `tests/e2e/wizard-logic.spec.ts`:
```typescript
import { test, expect } from "@playwright/test";

import { isLastStep, stepStatuses, wizardProgressPercent } from "../../src/components/wizard/step-logic";

test("step statuses mark done / current / upcoming", () => {
  expect(stepStatuses(5, 2)).toEqual(["done", "done", "current", "upcoming", "upcoming"]);
});

test("progress percent reflects current step (1-based)", () => {
  expect(wizardProgressPercent(5, 0)).toBe(20);
  expect(wizardProgressPercent(5, 4)).toBe(100);
  expect(wizardProgressPercent(3, 1)).toBe(67);
});

test("isLastStep detects the final step", () => {
  expect(isLastStep(5, 4)).toBe(true);
  expect(isLastStep(5, 3)).toBe(false);
});
```

- [ ] **Step 2: Run → fail** (`cd dentist-registry-frontend && npx playwright test tests/e2e/wizard-logic.spec.ts`).

- [ ] **Step 3: Implement the pure logic** — create `src/components/wizard/step-logic.ts`:
```typescript
export type StepStatus = "done" | "current" | "upcoming";

export function stepStatuses(count: number, current: number): StepStatus[] {
  return Array.from({ length: count }, (_, i) =>
    i < current ? "done" : i === current ? "current" : "upcoming",
  );
}

export function wizardProgressPercent(count: number, current: number): number {
  if (count <= 0) return 0;
  return Math.round(((current + 1) / count) * 100);
}

export function isLastStep(count: number, current: number): boolean {
  return current === count - 1;
}
```

- [ ] **Step 4: Run → pass.**

- [ ] **Step 5: Build the `Wizard` component** — create `src/components/wizard/wizard.tsx`:
```tsx
"use client";

import type { ReactNode } from "react";
import { useState } from "react";
import type { FieldValues, Path, UseFormReturn } from "react-hook-form";
import { useTranslation } from "react-i18next";

import { Button } from "@/components/ui/button";
import { Form } from "@/components/ui/form";
import { Icon } from "@/components/ui/icon";
import { isLastStep, stepStatuses, wizardProgressPercent } from "@/components/wizard/step-logic";

export interface WizardStep<T extends FieldValues> {
  key: string;
  labelKey: string;          // short rail/dot label
  questionKey: string;       // big card heading
  fields: Path<T>[];         // RHF fields validated before Next
  optional?: boolean;        // shows Skip
  isComplete?: (values: T) => boolean; // gates Next for required steps
  content: ReactNode;        // the field UI (rendered inside the shared <Form>)
}

interface WizardProps<T extends FieldValues> {
  form: UseFormReturn<T>;
  steps: WizardStep<T>[];
  reassuranceKey: string;
  submitLabelKey: string;
  onComplete: (values: T) => void;
  isSubmitting?: boolean;
  errorSlot?: ReactNode;
}

export function Wizard<T extends FieldValues>({
  form, steps, reassuranceKey, submitLabelKey, onComplete, isSubmitting, errorSlot,
}: WizardProps<T>) {
  const { t } = useTranslation();
  const [i, setI] = useState(0);
  const step = steps[i];
  const statuses = stepStatuses(steps.length, i);
  const last = isLastStep(steps.length, i);
  const values = form.watch();
  const canAdvance = step.isComplete ? step.isComplete(values) : true;

  async function next() {
    if (last) {
      await form.handleSubmit(onComplete)();
      return;
    }
    const ok = await form.trigger(step.fields);
    if (ok) setI((n) => n + 1);
  }

  return (
    <Form {...form}>
      <div className="flex flex-col" data-testid="wizard">
        {/* progress bar */}
        <div className="h-1 w-full overflow-hidden rounded-full bg-muted" aria-hidden>
          <div className="h-full rounded-full bg-primary transition-all" style={{ width: `${wizardProgressPercent(steps.length, i)}%` }} />
        </div>

        {/* mobile dots */}
        <div className="mt-3 flex justify-center gap-1.5 md:hidden" role="tablist" aria-label={t("wizard.steps")}>
          {statuses.map((s, idx) => (
            <span
              key={steps[idx].key}
              className={
                s === "current" ? "h-1.5 w-5 rounded-full bg-primary"
                : s === "done" ? "h-1.5 w-1.5 rounded-full bg-primary"
                : "h-1.5 w-1.5 rounded-full bg-muted"
              }
              aria-current={s === "current" ? "step" : undefined}
            />
          ))}
        </div>

        <div className="mt-4 flex gap-6">
          {/* desktop rail */}
          <nav className="hidden w-44 shrink-0 flex-col gap-3 md:flex" aria-label={t("wizard.steps")}>
            {steps.map((st, idx) => {
              const s = statuses[idx];
              return (
                <div key={st.key} className={`flex items-center gap-2 text-sm ${s === "current" ? "font-semibold text-foreground" : s === "done" ? "text-foreground/80" : "text-muted-foreground"}`} aria-current={s === "current" ? "step" : undefined}>
                  <span className={`flex size-5 items-center justify-center rounded-full text-[11px] ${s === "done" ? "bg-primary text-primary-foreground" : s === "current" ? "border border-primary text-primary" : "border border-border text-muted-foreground"}`}>
                    {s === "done" ? <Icon name="check" size={13} aria-hidden /> : idx + 1}
                  </span>
                  {t(st.labelKey)}
                </div>
              );
            })}
          </nav>

          {/* stage */}
          <div className="flex-1">
            <p className="text-xs uppercase tracking-wide text-muted-foreground">
              {t("wizard.stepOf", { current: i + 1, total: steps.length })}
            </p>
            <h2 className="mt-1 mb-5 text-xl font-semibold text-foreground" tabIndex={-1} data-testid="wizard-question">
              {t(step.questionKey)}
            </h2>

            <div data-testid={`wizard-step-${step.key}`}>{step.content}</div>

            {/* reassurance */}
            <p className="mt-5 flex items-center gap-2 border-t border-dashed border-border pt-3 text-xs italic text-muted-foreground" data-testid="wizard-reassurance">
              <Icon name="info" size={16} className="text-primary not-italic" aria-hidden />
              {t(reassuranceKey)}
            </p>

            {errorSlot}

            <div className="mt-4 flex items-center gap-2">
              {i > 0 && (
                <Button type="button" variant="ghost" size="sm" onClick={() => setI((n) => n - 1)} data-testid="wizard-back">
                  {t("wizard.back")}
                </Button>
              )}
              <span className="ml-auto flex gap-2">
                {step.optional && !last && (
                  <Button type="button" variant="outlined" size="sm" onClick={() => setI((n) => n + 1)} data-testid="wizard-skip">
                    {t("wizard.skip")}
                  </Button>
                )}
                <Button type="button" onClick={next} disabled={(!last && !canAdvance) || (last && isSubmitting)} data-testid="wizard-next">
                  {last ? t(submitLabelKey) : t("wizard.next")}
                </Button>
              </span>
            </div>
          </div>
        </div>
      </div>
    </Form>
  );
}
```
> Notes: `Icon name="check"`/`"info"` are Material Symbols already used in the app. The `Wizard` wraps everything in `<Form {...form}>` so each step's `content` can use `FormField`. Next is `type="button"` (navigation-controlled); the final step calls `form.handleSubmit(onComplete)`.

- [ ] **Step 6: Add i18n keys (en)** — `src/i18n/locales/en.json`. Add a `wizard` block + per-flow blocks:
```json
  "wizard": {
    "next": "Next",
    "back": "Back",
    "skip": "Skip",
    "steps": "Steps",
    "stepOf": "Step {{current}} of {{total}}"
  },
  "clinicWizard": {
    "reassurance": "Don't worry — you can change any of these later under Your clinic → Edit clinic details.",
    "submit": "Create clinic",
    "steps": { "name": "Clinic name", "phone": "Phone", "whatsapp": "WhatsApp", "email": "Email", "address": "Address" },
    "q": {
      "name": "What's your clinic called?",
      "phone": "What's the clinic's phone number?",
      "whatsapp": "A WhatsApp number? (optional)",
      "email": "A clinic email? (optional)",
      "address": "Where is the clinic located?"
    }
  },
  "doctorWizard": {
    "reassurance": "You can change any of these later in My Profile.",
    "submit": "Create profile",
    "title": "Set up your doctor profile",
    "steps": { "name": "Your name", "phone": "Your phone", "specialty": "Specialty" },
    "q": {
      "name": "What's your name, doctor?",
      "phone": "What's your phone number?",
      "specialty": "What's your specialty? (optional)"
    }
  },
```

- [ ] **Step 7: Add i18n keys (hi)** — mirror in `hi.json` with Hindi values:
```json
  "wizard": { "next": "आगे", "back": "पीछे", "skip": "छोड़ें", "steps": "चरण", "stepOf": "चरण {{current}} / {{total}}" },
  "clinicWizard": {
    "reassurance": "चिंता न करें — आप इन्हें बाद में आपका क्लिनिक → क्लिनिक विवरण संपादित करें के अंतर्गत बदल सकते हैं।",
    "submit": "क्लिनिक बनाएँ",
    "steps": { "name": "क्लिनिक का नाम", "phone": "फ़ोन", "whatsapp": "व्हाट्सऐप", "email": "ईमेल", "address": "पता" },
    "q": { "name": "आपके क्लिनिक का नाम क्या है?", "phone": "क्लिनिक का फ़ोन नंबर क्या है?", "whatsapp": "व्हाट्सऐप नंबर? (वैकल्पिक)", "email": "क्लिनिक ईमेल? (वैकल्पिक)", "address": "क्लिनिक कहाँ स्थित है?" }
  },
  "doctorWizard": {
    "reassurance": "आप इन्हें बाद में My Profile में बदल सकते हैं।",
    "submit": "प्रोफ़ाइल बनाएँ",
    "title": "अपनी डॉक्टर प्रोफ़ाइल सेट करें",
    "steps": { "name": "आपका नाम", "phone": "आपका फ़ोन", "specialty": "विशेषज्ञता" },
    "q": { "name": "डॉक्टर, आपका नाम क्या है?", "phone": "आपका फ़ोन नंबर क्या है?", "specialty": "आपकी विशेषज्ञता क्या है? (वैकल्पिक)" }
  },
```

- [ ] **Step 8: Verify** — `npx playwright test tests/e2e/wizard-logic.spec.ts tests/e2e/i18n.spec.ts` (or node parity for i18n) + `npx tsc --noEmit && npm run build`. All pass.

- [ ] **Step 9: Commit**
```bash
git add src/components/wizard/ tests/e2e/wizard-logic.spec.ts src/i18n/locales/
git commit -m "feat(wizard): reusable guided wizard component + step logic + i18n

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: Migrate clinic creation onto the wizard

**Files:** Modify `src/features/auth/onboarding.tsx`.

**Interfaces:** Consumes `Wizard`/`WizardStep` (Task 1), `useCreateClinic`, the existing `createSchema`/`CreateValues`, `FormField`/`FormItem`/`FormControl`/`FormLabel`/`FormMessage`, `Input`, `common.optional`.

- [ ] **Step 1: Rebuild `CreateClinicForm` as a wizard.** Keep the existing `createSchema` (Zod) and `useForm` defaults. Replace the long single `<form>` with a `Wizard` driven by 5 steps. The error slot shows the API error (as today). Reference implementation:
```tsx
import { Wizard, type WizardStep } from "@/components/wizard/wizard";
// ... inside CreateClinicForm, keep createSchema + form (useForm) as-is ...

  const steps: WizardStep<CreateValues>[] = [
    {
      key: "name", labelKey: "clinicWizard.steps.name", questionKey: "clinicWizard.q.name",
      fields: ["name"], isComplete: (v) => !!v.name?.trim(),
      content: (
        <FormField control={form.control} name="name" render={({ field }) => (
          <FormItem><FormControl><Input placeholder={t("onboarding.clinicNamePlaceholder")} data-testid="clinic-name-input" {...field} /></FormControl><FormMessage /></FormItem>
        )} />
      ),
    },
    {
      key: "phone", labelKey: "clinicWizard.steps.phone", questionKey: "clinicWizard.q.phone",
      fields: ["phone"], isComplete: (v) => !!v.phone?.trim(),
      content: (
        <FormField control={form.control} name="phone" render={({ field }) => (
          <FormItem><FormControl><Input placeholder={t("clinic.phonePlaceholder")} data-testid="clinic-phone" {...field} /></FormControl><FormMessage /></FormItem>
        )} />
      ),
    },
    {
      key: "whatsapp", labelKey: "clinicWizard.steps.whatsapp", questionKey: "clinicWizard.q.whatsapp",
      fields: ["whatsapp_number"], optional: true,
      content: (
        <FormField control={form.control} name="whatsapp_number" render={({ field }) => (
          <FormItem><FormControl><Input placeholder={t("clinic.whatsappPlaceholder")} data-testid="clinic-whatsapp" {...field} /></FormControl><FormMessage /></FormItem>
        )} />
      ),
    },
    {
      key: "email", labelKey: "clinicWizard.steps.email", questionKey: "clinicWizard.q.email",
      fields: ["email"], optional: true,
      content: (
        <FormField control={form.control} name="email" render={({ field }) => (
          <FormItem><FormControl><Input placeholder={t("clinic.emailPlaceholder")} data-testid="clinic-email" {...field} /></FormControl><FormMessage /></FormItem>
        )} />
      ),
    },
    {
      key: "address", labelKey: "clinicWizard.steps.address", questionKey: "clinicWizard.q.address",
      fields: ["address_line_1", "area", "city", "state", "pin_code"],
      isComplete: (v) => !!(v.address_line_1?.trim() && v.area?.trim() && v.city?.trim() && v.state?.trim() && v.pin_code?.trim()),
      content: (
        <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
          <FormField control={form.control} name="address_line_1" render={({ field }) => (
            <FormItem className="sm:col-span-2"><FormLabel>{t("onboarding.addressLine1Label")}</FormLabel><FormControl><Input data-testid="clinic-address-line1" {...field} /></FormControl><FormMessage /></FormItem>
          )} />
          <FormField control={form.control} name="address_line_2" render={({ field }) => (
            <FormItem className="sm:col-span-2"><FormLabel>{t("onboarding.addressLine2Label")} <span className="text-xs text-muted-foreground">({t("common.optional")})</span></FormLabel><FormControl><Input data-testid="clinic-address-line2" {...field} /></FormControl><FormMessage /></FormItem>
          )} />
          <FormField control={form.control} name="landmark" render={({ field }) => (
            <FormItem className="sm:col-span-2"><FormLabel>{t("onboarding.landmarkLabel")} <span className="text-xs text-muted-foreground">({t("common.optional")})</span></FormLabel><FormControl><Input data-testid="clinic-landmark" {...field} /></FormControl><FormMessage /></FormItem>
          )} />
          <FormField control={form.control} name="area" render={({ field }) => (
            <FormItem><FormLabel>{t("onboarding.areaLabel")}</FormLabel><FormControl><Input data-testid="clinic-area" {...field} /></FormControl><FormMessage /></FormItem>
          )} />
          <FormField control={form.control} name="city" render={({ field }) => (
            <FormItem><FormLabel>{t("onboarding.cityLabel")}</FormLabel><FormControl><Input data-testid="clinic-city" {...field} /></FormControl><FormMessage /></FormItem>
          )} />
          <FormField control={form.control} name="state" render={({ field }) => (
            <FormItem><FormLabel>{t("onboarding.stateLabel")}</FormLabel><FormControl><Input data-testid="clinic-state" {...field} /></FormControl><FormMessage /></FormItem>
          )} />
          <FormField control={form.control} name="pin_code" render={({ field }) => (
            <FormItem><FormLabel>{t("onboarding.pinCodeLabel")}</FormLabel><FormControl><Input data-testid="clinic-pin" {...field} /></FormControl><FormMessage /></FormItem>
          )} />
          <FormField control={form.control} name="google_maps_url" render={({ field }) => (
            <FormItem className="sm:col-span-2"><FormLabel>{t("onboarding.mapsUrlLabel")} <span className="text-xs text-muted-foreground">({t("common.optional")})</span></FormLabel><FormControl><Input data-testid="clinic-maps-url" {...field} /></FormControl><FormMessage /></FormItem>
          )} />
        </div>
      ),
    },
  ];

  const errorSlot = createClinic.isError ? (
    <p className="mt-3 text-sm text-destructive" data-testid="create-clinic-error">
      {(() => { const code = getApiErrorCode(createClinic.error); return code ? t(`apiErrors.${code}`, t("apiErrors.default")) : t("apiErrors.default"); })()}
    </p>
  ) : null;

  return (
    <Wizard form={form} steps={steps} reassuranceKey="clinicWizard.reassurance"
      submitLabelKey="clinicWizard.submit" onComplete={onSubmit}
      isSubmitting={createClinic.isPending} errorSlot={errorSlot} />
  );
```
Keep the existing `onSubmit(values)` payload builder unchanged. Remove the old long `<form>` JSX. The `getApiErrorCode` helper already exists in the file.

- [ ] **Step 2: Onboarding layout width.** The create-clinic wizard needs more width than the narrow auth card. In `OnboardingCard`, when `mode === "create"`, render the `CreateClinicForm` (wizard) in a wider container (e.g., drop the inner `Card` padding constraints for the create path, or render the wizard full-width within the onboarding column). Keep the Create/Join tab toggle and the Join form unchanged. Inspect `OnboardingCard`/`AuthShell` and give the wizard adequate width on desktop (the rail + stage need ~640px); the Join path stays the compact form.
> If `AuthShell`'s split layout is too narrow for the rail on desktop, it is acceptable for the create path to render the wizard in a wider centered container below the headline rather than the narrow right card. Match the existing premium look; do not introduce per-page CSS — use layout utilities/tokens.

- [ ] **Step 3: Verify** — `npx tsc --noEmit && npm run build`; manually confirm the create flow compiles. (i18n parity already covered in Task 1.)

- [ ] **Step 4: Commit**
```bash
git add src/features/auth/onboarding.tsx
git commit -m "feat(onboarding): clinic creation as guided wizard (5 steps, address one card)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: Migrate doctor-profile creation onto the wizard (full-screen)

**Files:** Create `src/features/doctors/doctor-profile-wizard.tsx`; Modify `src/features/doctors/create-profile-banner.tsx`; Delete `src/features/doctors/doctor-profile-dialog.tsx`.

**Interfaces:** Consumes `Wizard`/`WizardStep`, `useCreateSelfDoctor`, RHF + Zod, `ApiError`.

- [ ] **Step 1: Build the full-screen doctor-profile wizard** — create `src/features/doctors/doctor-profile-wizard.tsx`:
```tsx
"use client";

import { zodResolver } from "@hookform/resolvers/zod";
import { useForm } from "react-hook-form";
import { useTranslation } from "react-i18next";
import { z } from "zod";

import { Button } from "@/components/ui/button";
import { FormControl, FormField, FormItem, FormMessage } from "@/components/ui/form";
import { Icon } from "@/components/ui/icon";
import { Input } from "@/components/ui/input";
import { Wizard, type WizardStep } from "@/components/wizard/wizard";
import { ApiError } from "@/lib/api-client";
import { useCreateSelfDoctor } from "@/features/doctors/hooks";

const _schemaStatic = z.object({ name: z.string().min(1), phone: z.string().min(1), specialty: z.string().optional() });
type ProfileValues = z.infer<typeof _schemaStatic>;

export function DoctorProfileWizard({ clinicId, onClose }: { clinicId: string; onClose: () => void }) {
  const { t } = useTranslation();
  const create = useCreateSelfDoctor(clinicId);

  const schema = z.object({
    name: z.string().min(1, t("validation.clinicNameRequired")),
    phone: z.string().min(1, t("validation.phoneRequired")).regex(/^\+?[0-9\s\-().]+$/, t("validation.phoneInvalid")),
    specialty: z.string().optional(),
  });
  const form = useForm<ProfileValues>({ resolver: zodResolver(schema), defaultValues: { name: "", phone: "", specialty: "" } });

  function onComplete(values: ProfileValues) {
    create.mutate(
      { name: values.name, phone: values.phone, specialty: values.specialty || undefined },
      { onSuccess: onClose },
    );
  }

  const steps: WizardStep<ProfileValues>[] = [
    { key: "name", labelKey: "doctorWizard.steps.name", questionKey: "doctorWizard.q.name", fields: ["name"], isComplete: (v) => !!v.name?.trim(),
      content: <FormField control={form.control} name="name" render={({ field }) => (<FormItem><FormControl><Input placeholder={t("doctorProfile.namePlaceholder")} data-testid="profile-name" {...field} /></FormControl><FormMessage /></FormItem>)} /> },
    { key: "phone", labelKey: "doctorWizard.steps.phone", questionKey: "doctorWizard.q.phone", fields: ["phone"], isComplete: (v) => !!v.phone?.trim(),
      content: <FormField control={form.control} name="phone" render={({ field }) => (<FormItem><FormControl><Input placeholder={t("clinic.phonePlaceholder")} data-testid="profile-phone" {...field} /></FormControl><FormMessage /></FormItem>)} /> },
    { key: "specialty", labelKey: "doctorWizard.steps.specialty", questionKey: "doctorWizard.q.specialty", fields: ["specialty"], optional: true,
      content: <FormField control={form.control} name="specialty" render={({ field }) => (<FormItem><FormControl><Input data-testid="profile-specialty" {...field} /></FormControl><FormMessage /></FormItem>)} /> },
  ];

  const exists = create.error instanceof ApiError && create.error.code === "conflict";
  const errorSlot = create.isError ? (
    <p className="mt-3 text-sm text-destructive" data-testid={exists ? "profile-exists" : "profile-error"}>
      {exists ? t("doctorProfile.exists") : t("apiErrors.default")}
    </p>
  ) : null;

  return (
    <div className="fixed inset-0 z-50 overflow-auto bg-background" role="dialog" aria-modal="true" data-testid="doctor-profile-wizard">
      <div className="mx-auto w-full max-w-3xl px-4 py-8">
        <div className="mb-6 flex items-center justify-between">
          <h1 className="text-lg font-semibold text-foreground">{t("doctorWizard.title")}</h1>
          <button onClick={onClose} className="text-muted-foreground hover:text-foreground" aria-label={t("common.cancel")} data-testid="close-profile-wizard">
            <Icon name="close" size={20} />
          </button>
        </div>
        <Wizard form={form} steps={steps} reassuranceKey="doctorWizard.reassurance" submitLabelKey="doctorWizard.submit" onComplete={onComplete} isSubmitting={create.isPending} errorSlot={errorSlot} />
      </div>
    </div>
  );
}
```

- [ ] **Step 2: Banner opens the full-screen wizard** — rewrite `src/features/doctors/create-profile-banner.tsx` to toggle the wizard instead of embedding the dialog:
```tsx
"use client";

import { useState } from "react";
import { useTranslation } from "react-i18next";

import { Button } from "@/components/ui/button";
import { Icon } from "@/components/ui/icon";
import { DoctorProfileWizard } from "@/features/doctors/doctor-profile-wizard";

export function CreateProfileBanner({ clinicId }: { clinicId: string }) {
  const { t } = useTranslation();
  const [dismissed, setDismissed] = useState(false);
  const [open, setOpen] = useState(false);
  if (dismissed) return null;

  return (
    <>
      <div className="flex items-start justify-between gap-3 rounded-lg border border-warning bg-warning/10 px-4 py-3" data-testid="create-profile-banner" role="status">
        <div className="flex items-start gap-2">
          <Icon name="info" size={20} className="text-warning" aria-hidden />
          <div>
            <p className="text-sm font-medium text-foreground">{t("doctorProfile.bannerQuestion")}</p>
            <p className="text-sm text-muted-foreground">{t("doctorProfile.bannerBody")}</p>
            <div className="mt-2">
              <Button size="sm" onClick={() => setOpen(true)} data-testid="open-doctor-profile">{t("doctorProfile.bannerCta")}</Button>
            </div>
          </div>
        </div>
        <button onClick={() => setDismissed(true)} className="text-muted-foreground hover:text-foreground" aria-label={t("doctorProfile.dismiss")} data-testid="dismiss-banner">
          <Icon name="close" size={18} />
        </button>
      </div>
      {open && <DoctorProfileWizard clinicId={clinicId} onClose={() => setOpen(false)} />}
    </>
  );
}
```

- [ ] **Step 3: Delete the old dialog** — `git rm src/features/doctors/doctor-profile-dialog.tsx`. Grep for any other importer of `DoctorProfileDialog` and repoint/remove (the banner was the only consumer; confirm).

- [ ] **Step 4: Verify** — `npx tsc --noEmit && npm run build` clean; no references to the deleted dialog.

- [ ] **Step 5: Commit**
```bash
git add src/features/doctors/doctor-profile-wizard.tsx src/features/doctors/create-profile-banner.tsx src/features/doctors/doctor-profile-dialog.tsx
git commit -m "feat(doctors): doctor-profile creation as full-screen guided wizard (replaces dialog)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: Docs — design-system note (docs repo)

**Files (in `dentail-register-docs`):** the design-system notes + Golden Rules.

- [ ] **Step 1:** `git checkout main && git pull --ff-only && git checkout -b docs/guided-wizard-50`.
- [ ] **Step 2:** Add a short **guided-wizard pattern** note to the design-system docs (where the M3 components/patterns are described): one question per card; top progress; desktop left step-rail / mobile dots; Skip on optional, Next on required, last-step submit; per-card reassurance line; group cohesive units (full address) into one step. Reference `docs/specs/2026-06-20-guided-wizard-design.md` (#50) and [[Golden Rules §18]].
- [ ] **Step 3:** In `Rules/register-golden-rules.md`, add a brief rule under §18: multi-field creation flows (clinic, doctor profile) use the guided one-question wizard; group naturally-related fields into a single step (don't fragment, e.g. the postal address is one card).
- [ ] **Step 4: Commit** (docs repo) with the trailer.

---

## Final Verification (before PRs)
- [ ] Frontend: `npx tsc --noEmit && npm run build` clean; `npx playwright test tests/e2e/wizard-logic.spec.ts tests/e2e/i18n.spec.ts` (or node parity for i18n) → pass.
- [ ] Frontend PR `Closes #50`; docs PR `Part of #50`. Board #50 → In Review → Completed.
- [ ] No backend/migration/Supabase change.

## Self-Review (against the spec)
- **§2 layout (progress, desktop rail, mobile dots, Back/Next/Skip, last-step submit, reassurance circled-i + italic per-flow):** Task 1 `Wizard`. ✅
- **§2 one-question-per-card; address = one card:** Task 2 (address step groups all address fields). ✅
- **§2 per-step validation (trigger on step fields; Next gated; Skip on optional; Back preserves values):** Task 1 (`next()` uses `form.trigger(step.fields)`, `isComplete` gates Next, `optional` → Skip; RHF retains values across steps). ✅
- **§3 flows (clinic 5 steps → POST /clinics; doctor 3 steps → POST …/doctors/me):** Tasks 2, 3. ✅
- **§4 reusable config-driven Wizard; RHF shared form; responsive rail/dots; doctor dialog → full-screen:** Tasks 1, 3. ✅
- **§6 testing (pure-logic unit test; i18n parity; tsc/build):** Task 1 + final verification. ✅
- **§7 docs:** Task 4. ✅
- **Placeholder scan:** "inspect OnboardingCard/AuthShell width" (Task 2 Step 2) is a real layout integration step with a concrete fallback, not a placeholder; "grep for other DoctorProfileDialog importers" is a verification step. No TBDs. ✅
- **Type consistency:** `Wizard`/`WizardStep<T>` generic + `stepStatuses`/`wizardProgressPercent`/`isLastStep` names consistent across Task 1 impl + test + consumers (Tasks 2–3); `reassuranceKey`/`submitLabelKey`/`onComplete`/`isSubmitting`/`errorSlot` props consistent. ✅
- **No backend:** confirmed — no task touches a backend repo or migration. ✅
