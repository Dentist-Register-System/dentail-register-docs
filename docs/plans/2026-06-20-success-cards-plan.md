# Success Cards Implementation Plan (#61)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace silent post-mutation feedback with an explicit, reassuring **success card** (must-acknowledge modal on desktop / bottom-sheet on mobile) after important actions.

**Architecture:** A global `SuccessProvider` mounted in `src/app/providers.tsx` exposes a `useSuccess()` hook; any mutation's `onSuccess` calls `success(payload)`. The provider renders one modal (reusing the base-ui `Dialog` primitive) with a presentational `SuccessCard`. A pure reducer holds the payload (unit-tested). Frontend-only.

**Tech Stack:** Next.js App Router (client components), TanStack Query, base-ui `Dialog`, react-i18next, Tailwind v4 semantic tokens, Playwright runner (pure-logic + i18n; tsc + build are CI gates).

## Global Constraints

- **Frontend-only.** No backend / API / schema / migration. No new dependencies. No new design tokens (reuse existing `success` token: `bg-success/10` + `text-success`, mirroring `border-warning bg-warning/10 text-warning` in `create-profile-banner.tsx`).
- **Interaction:** must-acknowledge (NO auto-dismiss); centered card on `sm+`, bottom-sheet on mobile; one at a time (a new `success()` replaces the current payload — no queue).
- **V1 cards are Dismiss-only.** The `action` deep-link is supported by the component but NOT wired in V1 (no patient/appointment detail routes exist yet).
- **Detail rows with empty/missing values are omitted** (never render a blank row).
- **Rule 17.0:** semantic tokens only (no raw colours), compose `components/ui/*`, no per-page CSS. **i18n-first:** every string via `t()`, in BOTH `en.json` + `hi.json` (parity enforced by `tests/e2e/i18n.spec.ts`).
- Commit trailer: `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`. Feature branch → PR (never push `main`). Do NOT modify `.env.local`.

---

## File Structure
- Create: `src/components/success/success-context.ts` — pure reducer + types + context (testable).
- Create: `src/components/success/success-card.tsx` — presentational card.
- Create: `src/components/success/success-provider.tsx` — provider + modal render.
- Create: `src/components/success/use-success.ts` — `useSuccess()` hook.
- Create: `tests/e2e/success-context.spec.ts` — reducer unit test.
- Modify: `src/app/providers.tsx` — mount `<SuccessProvider>`.
- Modify: `src/i18n/locales/en.json` + `hi.json` — `success.*` keys.
- Modify (wiring): `src/features/scheduling/request-dialog.tsx`, `requests-queue.tsx`, `src/features/patients/add-patient-form.tsx`, `src/features/scheduling/availability-editor.tsx`, `src/features/doctors/doctor-profile-wizard.tsx`, `src/features/clinic/edit-clinic-details-dialog.tsx`.
- Modify (docs repo): design-system + Golden Rules.

---

## Task 1: Success primitive (context + card + provider + hook + mount + i18n + test)

**Files:** Create the four `src/components/success/*` files + `tests/e2e/success-context.spec.ts`; Modify `src/app/providers.tsx`, `src/i18n/locales/en.json`, `src/i18n/locales/hi.json`.

**Interfaces:**
- Produces: `SuccessPayload`/`SuccessDetail`/`SuccessAction` types; `successReducer`, `successInitialState`; `SuccessProvider`; `useSuccess(): (payload: SuccessPayload) => void`.

- [ ] **Step 1: Write the failing reducer test** — `tests/e2e/success-context.spec.ts`:
```typescript
import { test, expect } from "@playwright/test";

import { successInitialState, successReducer } from "../../src/components/success/success-context";

test("show sets the payload", () => {
  const s = successReducer(successInitialState, { type: "show", payload: { titleKey: "success.patientAdded" } });
  expect(s.payload?.titleKey).toBe("success.patientAdded");
});

test("show replaces an existing payload", () => {
  const a = successReducer(successInitialState, { type: "show", payload: { titleKey: "success.requestSent" } });
  const b = successReducer(a, { type: "show", payload: { titleKey: "success.appointmentConfirmed" } });
  expect(b.payload?.titleKey).toBe("success.appointmentConfirmed");
});

test("dismiss clears the payload", () => {
  const a = successReducer(successInitialState, { type: "show", payload: { titleKey: "success.scheduleSaved" } });
  const b = successReducer(a, { type: "dismiss" });
  expect(b.payload).toBeNull();
});
```

- [ ] **Step 2: Run → fail** — `npx playwright test tests/e2e/success-context.spec.ts` (module not found).

- [ ] **Step 3: Implement the context/reducer** — `src/components/success/success-context.ts`:
```typescript
export type SuccessDetail = { labelKey: string; value: string };
export type SuccessAction = { labelKey: string; href: string };
export type SuccessPayload = {
  titleKey: string;
  details?: SuccessDetail[];
  action?: SuccessAction;
};

export type SuccessState = { payload: SuccessPayload | null };
export type SuccessEvent = { type: "show"; payload: SuccessPayload } | { type: "dismiss" };

export const successInitialState: SuccessState = { payload: null };

export function successReducer(state: SuccessState, event: SuccessEvent): SuccessState {
  switch (event.type) {
    case "show":
      return { payload: event.payload };
    case "dismiss":
      return { payload: null };
    default:
      return state;
  }
}
```

- [ ] **Step 4: Run → pass** — `npx playwright test tests/e2e/success-context.spec.ts`.

- [ ] **Step 5: Presentational card** — `src/components/success/success-card.tsx`:
```tsx
"use client";

import { useTranslation } from "react-i18next";

import { Button, buttonVariants } from "@/components/ui/button";
import { DialogTitle } from "@/components/ui/dialog";
import { Icon } from "@/components/ui/icon";
import type { SuccessPayload } from "@/components/success/success-context";

export function SuccessCard({ payload, onDismiss }: { payload: SuccessPayload; onDismiss: () => void }) {
  const { t } = useTranslation();
  const rows = (payload.details ?? []).filter((d) => d.value);

  return (
    <div data-testid="success-card">
      <div className="mx-auto mb-4 flex size-14 items-center justify-center rounded-full bg-success/10">
        <Icon name="check" size={30} className="text-success" aria-hidden />
      </div>
      <DialogTitle className="mb-4 text-center text-lg font-semibold text-foreground" data-testid="success-title">
        {t(payload.titleKey)}
      </DialogTitle>
      {rows.length > 0 && (
        <dl className="mb-5 space-y-1 rounded-xl bg-muted/40 px-4 py-3">
          {rows.map((d) => (
            <div key={d.labelKey} className="flex justify-between gap-3 py-0.5 text-sm">
              <dt className="text-muted-foreground">{t(d.labelKey)}</dt>
              <dd className="text-right font-medium text-foreground">{d.value}</dd>
            </div>
          ))}
        </dl>
      )}
      <div className="flex flex-col gap-2">
        {payload.action && (
          <a href={payload.action.href} onClick={onDismiss} className={buttonVariants({ variant: "filled" })} data-testid="success-action">
            {t(payload.action.labelKey)}
          </a>
        )}
        <Button variant={payload.action ? "ghost" : "filled"} onClick={onDismiss} data-testid="success-dismiss">
          {t("success.dismiss")}
        </Button>
      </div>
    </div>
  );
}
```
> `DialogTitle` (rendered inside the Dialog popup) supplies the accessible label. `Icon name="check"` + `bg-success/10`/`text-success` are existing. `buttonVariants` is exported from `button.tsx` (used elsewhere).

- [ ] **Step 6: Provider + modal** — `src/components/success/success-provider.tsx`:
```tsx
"use client";

import { createContext, useMemo, useReducer } from "react";

import { DialogPopup, DialogRoot } from "@/components/ui/dialog";
import { SuccessCard } from "@/components/success/success-card";
import { successInitialState, successReducer, type SuccessPayload } from "@/components/success/success-context";

export type SuccessShow = (payload: SuccessPayload) => void;
export const SuccessContext = createContext<SuccessShow | null>(null);

export function SuccessProvider({ children }: { children: React.ReactNode }) {
  const [state, dispatch] = useReducer(successReducer, successInitialState);
  const show = useMemo<SuccessShow>(() => (payload) => dispatch({ type: "show", payload }), []);
  const dismiss = () => dispatch({ type: "dismiss" });

  return (
    <SuccessContext.Provider value={show}>
      {children}
      <DialogRoot open={state.payload != null} onOpenChange={(o) => { if (!o) dismiss(); }}>
        {state.payload && (
          <DialogPopup className="left-0 right-0 top-auto bottom-0 max-w-full translate-x-0 translate-y-0 rounded-b-none rounded-t-3xl sm:left-1/2 sm:right-auto sm:top-1/2 sm:bottom-auto sm:max-w-sm sm:-translate-x-1/2 sm:-translate-y-1/2 sm:rounded-xl">
            <SuccessCard payload={state.payload} onDismiss={dismiss} />
          </DialogPopup>
        )}
      </DialogRoot>
    </SuccessContext.Provider>
  );
}
```
> The `className` overrides the popup's default centered positioning: bottom-sheet on mobile, restored centered card at `sm+` (tailwind-merge: later classes win). `cn()` in `dialog.tsx` uses tailwind-merge so conflicting positioning/rounding/max-width classes resolve to these.

- [ ] **Step 7: Hook** — `src/components/success/use-success.ts`:
```tsx
"use client";

import { useContext } from "react";

import { SuccessContext } from "@/components/success/success-provider";

export function useSuccess() {
  const show = useContext(SuccessContext);
  if (!show) throw new Error("useSuccess must be used within SuccessProvider");
  return show;
}
```

- [ ] **Step 8: Mount the provider** — `src/app/providers.tsx`, wrap `children` inside `QueryClientProvider`:
```tsx
import { SuccessProvider } from "@/components/success/success-provider";
// ...
        <QueryClientProvider client={client}>
          <SuccessProvider>{children}</SuccessProvider>
        </QueryClientProvider>
```

- [ ] **Step 9: i18n (en)** — add to `src/i18n/locales/en.json`:
```json
  "success": {
    "dismiss": "Done",
    "requestSent": "Request sent",
    "appointmentConfirmed": "Appointment confirmed",
    "requestDeclined": "Request declined",
    "patientAdded": "Patient added",
    "scheduleSaved": "Schedule saved",
    "profileCreated": "Profile created",
    "clinicDetailsSaved": "Clinic details saved",
    "label": {
      "patient": "Patient",
      "when": "When",
      "name": "Name",
      "age": "Age",
      "phone": "Phone",
      "availability": "Availability",
      "complaint": "Reason"
    }
  },
```

- [ ] **Step 10: i18n (hi)** — mirror in `src/i18n/locales/hi.json`:
```json
  "success": {
    "dismiss": "हो गया",
    "requestSent": "अनुरोध भेजा गया",
    "appointmentConfirmed": "अपॉइंटमेंट पुष्ट हुई",
    "requestDeclined": "अनुरोध अस्वीकृत",
    "patientAdded": "मरीज़ जोड़ा गया",
    "scheduleSaved": "शेड्यूल सहेजा गया",
    "profileCreated": "प्रोफ़ाइल बनाई गई",
    "clinicDetailsSaved": "क्लिनिक विवरण सहेजा गया",
    "label": {
      "patient": "मरीज़",
      "when": "कब",
      "name": "नाम",
      "age": "उम्र",
      "phone": "फ़ोन",
      "availability": "उपलब्धता",
      "complaint": "कारण"
    }
  },
```

- [ ] **Step 11: Verify** — `npx playwright test tests/e2e/success-context.spec.ts tests/e2e/i18n.spec.ts` pass; `npx tsc --noEmit && npm run build` clean.

- [ ] **Step 12: Commit**
```bash
git add src/components/success/ tests/e2e/success-context.spec.ts src/app/providers.tsx src/i18n/locales/
git commit -m "feat(success): global success-card provider + hook + reducer + i18n

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: Wire scheduling (request sent · approved · rejected)

**Files:** Modify `src/features/scheduling/request-dialog.tsx`, `src/features/scheduling/requests-queue.tsx`.

**Interfaces:** Consumes `useSuccess()` (Task 1). `RequestDialog` has props `startDatetime`, `label`; tracks selected patient. `requests-queue` renders `RequestListItem` rows (`{ id, start_datetime, chief_complaint, status, expired }`) and calls `action.mutate({ id, action })`.

- [ ] **Step 1: request-dialog — track patient name + success on submit.** In `src/features/scheduling/request-dialog.tsx`:
  - Add import: `import { useSuccess } from "@/components/success/use-success";`
  - Add `const success = useSuccess();` near the other hooks.
  - Add state `const [patientName, setPatientName] = useState("");`
  - In the patient-option `onClick`, also set the name: change `onClick={() => { setPatientId(p.id); setQ(p.name); }}` → `onClick={() => { setPatientId(p.id); setQ(p.name); setPatientName(p.name); }}`
  - In `submit()`, extend the existing `onSuccess` to show the card and reset the name:
```tsx
  function submit() {
    createReq.mutate(
      { patient_id: patientId, start_datetime: startDatetime, chief_complaint: complaint || undefined, notes: notes || undefined },
      {
        onSuccess: () => {
          setOpen(false); setPatientId(""); setQ(""); setComplaint(""); setNotes("");
          success({
            titleKey: "success.requestSent",
            details: [
              { labelKey: "success.label.patient", value: patientName },
              { labelKey: "success.label.when", value: label },
            ],
          });
          setPatientName("");
        },
      },
    );
  }
```

- [ ] **Step 2: requests-queue — success on approve/reject.** In `src/features/scheduling/requests-queue.tsx`:
  - Add import: `import { useSuccess } from "@/components/success/use-success";`
  - Add `const success = useSuccess();` near `const action = useRequestAction(clinicId);`
  - Add a helper above the return (uses the existing display format `r.start_datetime.replace("T", " ").slice(0, 16)`):
```tsx
  function decide(r: { id: string; start_datetime: string; chief_complaint: string | null }, act: "approve" | "reject") {
    action.mutate(
      { id: r.id, action: act },
      {
        onSuccess: () => {
          const details = [
            { labelKey: "success.label.when", value: r.start_datetime.replace("T", " ").slice(0, 16) },
            ...(r.chief_complaint ? [{ labelKey: "success.label.complaint", value: r.chief_complaint }] : []),
          ];
          success({ titleKey: act === "approve" ? "success.appointmentConfirmed" : "success.requestDeclined", details });
        },
      },
    );
  }
```
  - Repoint the approve/reject buttons to the helper (leave cancel/resend unchanged):
    - `onClick={() => action.mutate({ id: r.id, action: "approve" })}` → `onClick={() => decide(r, "approve")}`
    - `onClick={() => action.mutate({ id: r.id, action: "reject" })}` → `onClick={() => decide(r, "reject")}`

- [ ] **Step 3: Verify** — `npx tsc --noEmit && npm run build` clean.

- [ ] **Step 4: Commit**
```bash
git add src/features/scheduling/request-dialog.tsx src/features/scheduling/requests-queue.tsx
git commit -m "feat(scheduling): success cards for request sent / approved / declined

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: Wire patient added + schedule saved

**Files:** Modify `src/features/patients/add-patient-form.tsx`, `src/features/scheduling/availability-editor.tsx`.

**Interfaces:** Consumes `useSuccess()`. `createPatient` returns a `Patient` (`{ id, name, phone, age: number | null, ... }`). `availability-editor` calls `createWindow.mutate(...)` / `createBlock.mutate(...)`.

- [ ] **Step 1: patient added — success card with name·age·phone.** In `src/features/patients/add-patient-form.tsx`:
  - Add import: `import { useSuccess } from "@/components/success/use-success";`
  - Add import for the type: `import type { Patient } from "@/features/patients/api";` (only if not already imported; if `Patient` is already imported, reuse it).
  - Add `const success = useSuccess();` near `const createPatient = useCreatePatient(clinicId);`
  - Change `handleCreateSuccess` to receive the created patient and show the card:
```tsx
  function handleCreateSuccess(data: Patient) {
    setOpen(false);
    success({
      titleKey: "success.patientAdded",
      details: [
        { labelKey: "success.label.name", value: data.name },
        ...(data.age != null ? [{ labelKey: "success.label.age", value: String(data.age) }] : []),
        { labelKey: "success.label.phone", value: data.phone },
      ],
    });
  }
```
  > The three `createPatient.mutate(..., { onSuccess: handleCreateSuccess })` call sites already pass the created patient as the callback arg — no call-site change needed. (Empty age omitted per Global Constraints.)

- [ ] **Step 2: schedule saved — success on each create site.** In `src/features/scheduling/availability-editor.tsx`:
  - Add import: `import { useSuccess } from "@/components/success/use-success";`
  - Add `const success = useSuccess();` near the other hooks.
  - Add a helper above the return:
```tsx
  function savedSchedule(value: string) {
    return { titleKey: "success.scheduleSaved", details: [{ labelKey: "success.label.availability", value }] };
  }
```
  - Recurring window site — `onClick={() => createWindow.mutate({ kind: "recurring", day_of_week: Number(dow), start_time: rStart, end_time: rEnd })}` →
```tsx
    onClick={() => createWindow.mutate(
      { kind: "recurring", day_of_week: Number(dow), start_time: rStart, end_time: rEnd },
      { onSuccess: () => success(savedSchedule(`${rStart}–${rEnd}`)) },
    )}
```
  - One-off window site — `createWindow.mutate({ kind: "one_off", specific_date: oDate, start_time: oStart, end_time: oEnd })` →
```tsx
    onClick={() => createWindow.mutate(
      { kind: "one_off", specific_date: oDate, start_time: oStart, end_time: oEnd },
      { onSuccess: () => success(savedSchedule(`${oDate} · ${oStart}–${oEnd}`)) },
    )}
```
  - Block site — `createBlock.mutate({ block_date: bDate, reason: bReason || null })` →
```tsx
    onClick={() => createBlock.mutate(
      { block_date: bDate, reason: bReason || null },
      { onSuccess: () => success(savedSchedule(bDate)) },
    )}
```

- [ ] **Step 3: Verify** — `npx tsc --noEmit && npm run build` clean.

- [ ] **Step 4: Commit**
```bash
git add src/features/patients/add-patient-form.tsx src/features/scheduling/availability-editor.tsx
git commit -m "feat(patients,scheduling): success cards for patient added / schedule saved

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: Wire doctor-profile created + clinic-details saved

**Files:** Modify `src/features/doctors/doctor-profile-wizard.tsx`, `src/features/clinic/edit-clinic-details-dialog.tsx`.

**Interfaces:** Consumes `useSuccess()`. doctor-profile-wizard's `onComplete(values)` calls `create.mutate({...}, { onSuccess: onClose })` with `values.name`. edit-clinic-details `onSubmit` calls `updateClinic.mutate(payload, { onSuccess: () => setOpen(false) })`.

> **Note (read first):** Doctor-add and assistant-add are intentionally **excluded** — those dialogs reveal an invite token in-place as their success UX, so a modal on top would conflict. The "Team & profile" group is covered here by profile-created + clinic-details-saved.

- [ ] **Step 1: doctor-profile-wizard.** In `src/features/doctors/doctor-profile-wizard.tsx`:
  - Add import: `import { useSuccess } from "@/components/success/use-success";`
  - Add `const success = useSuccess();` inside the component.
  - Change `onComplete` to show the card after closing:
```tsx
  function onComplete(values: ProfileValues) {
    create.mutate(
      { name: values.name, phone: values.phone, specialty: values.specialty || undefined },
      { onSuccess: () => {
          onClose();
          success({ titleKey: "success.profileCreated", details: [{ labelKey: "success.label.name", value: values.name }] });
        } },
    );
  }
```

- [ ] **Step 2: edit-clinic-details-dialog.** In `src/features/clinic/edit-clinic-details-dialog.tsx`:
  - Add import: `import { useSuccess } from "@/components/success/use-success";`
  - Add `const success = useSuccess();` near `const updateClinic = ...`.
  - Change the submit `onSuccess`:
```tsx
    updateClinic.mutate(payload, { onSuccess: () => { setOpen(false); success({ titleKey: "success.clinicDetailsSaved" }); } });
```

- [ ] **Step 3: Verify** — `npx tsc --noEmit && npm run build` clean.

- [ ] **Step 4: Commit**
```bash
git add src/features/doctors/doctor-profile-wizard.tsx src/features/clinic/edit-clinic-details-dialog.tsx
git commit -m "feat(doctors,clinic): success cards for profile created / clinic details saved

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: Docs (design-system note + Golden Rule)

**Files (in `dentail-register-docs`):** `Design/02-design-system.md`, `Rules/register-golden-rules.md`.

- [ ] **Step 1:** `git checkout main && git pull --ff-only && git checkout -b docs/success-cards-61`.
- [ ] **Step 2:** Add a **Success Card** entry to `Design/02-design-system.md` (alongside the other B.x component notes): must-acknowledge modal (centered desktop / bottom-sheet mobile), ✓ badge (`success` token), title + plain-language detail rows (omit empty) + Dismiss (optional deep-link action when a target route exists); used after important create/save/decide actions; replaces silent feedback (the app has no toasts). Reference `docs/specs/2026-06-20-success-cards-design.md` (#61).
- [ ] **Step 3:** Add a brief rule under §18 of `Rules/register-golden-rules.md`: important actions (create/save/approve/reject) confirm with a success card stating what happened + key details; do not rely on silent dialog-close. Match the existing §18 numbering/format.
- [ ] **Step 4: Commit** (docs repo) with the trailer.

---

## Final Verification (before PRs)
- [ ] Frontend: `npx tsc --noEmit && npm run build` clean; `npx playwright test tests/e2e/success-context.spec.ts tests/e2e/i18n.spec.ts` pass.
- [ ] Frontend PR `Closes #61`; docs PR `Part of #61`.
- [ ] No backend/migration/Supabase change; no new dependency; no new design token.

## Self-Review (against the spec)
- **§2 approach (global provider + `useSuccess()` mounted in providers.tsx; reuses Dialog):** Task 1. ✅
- **§2 interaction (must-acknowledge, centered desktop / bottom-sheet mobile, replace-on-new):** Task 1 provider `className` + reducer. ✅
- **§3 components (context reducer tested, card, provider, hook) + payload shape:** Task 1. ✅
- **§4 presentation (✓ badge `bg-success/10`+`text-success`, title=DialogTitle, detail rows omit empty, Dismiss; no new tokens):** Task 1 card. ✅
- **§5 wiring:** request sent (Task 2), approved/declined (Task 2), patient added name·age·phone (Task 3), schedule saved (Task 3), profile created + clinic details saved (Task 4). **Deviations from the spec table, by data availability (documented):** (a) approve/reject show *when* [+ reason] only — `RequestListItem` carries no patient/doctor name; (b) all V1 cards are **Dismiss-only** — no patient/appointment detail routes exist for deep-links; (c) **doctor-added/assistant-added excluded** — their invite-token reveal is the success UX (a modal would conflict). These are flagged for the human in the execution summary. ✅ (with noted, intentional reductions)
- **§6 i18n (success.* en/hi parity):** Task 1 steps 9–10. ✅
- **§7 testing (reducer unit test; i18n parity; tsc/build):** Task 1 + Final Verification. ✅
- **§8 scope guards (no WhatsApp, no auto-dismiss, no queue, no backend, no new token):** honored throughout. ✅
- **Placeholder scan:** none — every wiring step shows the exact before/after code with real local variable names confirmed from the source. ✅
- **Type consistency:** `SuccessPayload`/`SuccessShow`/`successReducer`/`useSuccess` names consistent across Task 1 and consumers; `Patient` import in Task 3 matches `features/patients/api.ts`. ✅
