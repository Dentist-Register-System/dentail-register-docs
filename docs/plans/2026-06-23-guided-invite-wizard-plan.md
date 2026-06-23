# Guided Invite Wizard (#126) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the single-form invite into a guided 2-step wizard (Details → Review & Send) with a data-driven stepper header (green ticks) and a review card, for doctors & assistants.

**Architecture:** A new `<Stepper>` UI primitive (data-driven nodes/connectors, green check on complete). `<InviteWizard>` replaces the body of the existing `InviteDialog` (keeping its Dialog shell + trigger + create hooks + `<ShareInvite>` success view): step 1 collects details (react-hook-form + zod, "Next" gated on validity), step 2 shows a review card of all entered fields then sends. Frontend-only.

**Tech Stack:** Next.js App Router, react-hook-form + zod, Tailwind v4 semantic tokens, react-i18next, Playwright.

## Global Constraints
- Spec: `docs/specs/2026-06-23-guided-invite-wizard-design.md`. **Frontend-only — no backend / no migration.**
- Reuse the existing create-with-invite hooks (`useCreateDoctor`/`useCreateAssistant` → `{ ..., invite_token }`) and `<ShareInvite>`. Keep the trigger testids `add-doctor-button`/`add-assistant-button` and `invite-name-input`/`invite-email-input`/`invite-sent`.
- **One flow, NO guided/direct toggle.** Stepper is **data-driven** (renders from a steps array; no hardcoded count) so a Permissions step (#125) drops in later with no rework.
- Final **Review card** lists every entered detail before Send (name · role label · email · specialty/title).
- Rule 17.0: semantic tokens only, compose `components/ui/*`, no raw colors; both themes; mobile-first; WCAG AA (`aria-current="step"`, visible focus). The universal CLAUDE.md behavior rules apply.
- i18n en/hi parity for all new keys; reuse existing `invitations.*`/`common.*`/`validation.*`.
- **Render-before-build (controller):** serve the stepper + Details + Review + success on :8753 and get user sign-off before Task 2.
- CI = `tsc --noEmit` + `npm run build`; e2e local. FE PR held for user QA. `find .next -name "* [0-9].*" -delete` if iCloud dups break the build.

## File Structure
- Create: `src/components/ui/stepper.tsx` — the stepper primitive.
- Create: `src/features/invitations/invite-wizard.tsx` — the wizard.
- Modify: `src/features/invitations/invite-dialog.tsx` — host `<InviteWizard>` in its Popup (keep trigger/shell), OR re-export. (Keep `InviteDialog`'s public API `{kind, clinicId}` so the tabs don't change.)
- Modify: `src/i18n/locales/en.json`, `hi.json`.
- Test: `tests/e2e/invite-wizard.spec.ts`; update `tests/e2e/doctors.spec.ts`/`assistants.spec.ts` invite-flow assertions if they assert the old single-step submit.

---

### Task 1: `<Stepper>` primitive

**Files:** Create `src/components/ui/stepper.tsx`

**Interfaces:**
- Produces: `<Stepper steps={{ key: string; label: string }[]} current={number} />` (0-based `current`). A node at index `i` is **completed** when `i < current` (green check), **active** when `i === current` (primary), else **upcoming** (muted). Connectors between nodes fill (success/primary tone) for completed segments.

- [ ] **Step 1:** Implement (`"use client"` not required — pure presentational; but keep consistent with other ui primitives, no hooks needed so omit "use client"). Semantic tokens only.

```tsx
import * as React from "react";
import { Icon } from "@/components/ui/icon";
import { cn } from "@/lib/utils";

export interface StepperStep { key: string; label: string; }

export function Stepper({ steps, current, className }: { steps: StepperStep[]; current: number; className?: string }) {
  return (
    <ol className={cn("flex items-center w-full", className)} data-testid="stepper" aria-label="Progress">
      {steps.map((s, i) => {
        const done = i < current;
        const active = i === current;
        return (
          <li key={s.key} className={cn("flex items-center", i < steps.length - 1 && "flex-1")}>
            <div className="flex items-center gap-2" aria-current={active ? "step" : undefined} data-testid={`stepper-node-${i}`}>
              <span
                className={cn(
                  "flex h-7 w-7 shrink-0 items-center justify-center rounded-full text-xs font-semibold transition-colors",
                  done && "bg-success text-success-foreground",
                  active && "bg-primary text-primary-foreground",
                  !done && !active && "bg-muted text-muted-foreground",
                )}
              >
                {done ? <Icon name="check" size={16} aria-hidden /> : i + 1}
              </span>
              <span className={cn("text-sm font-medium hidden sm:inline", active ? "text-foreground" : "text-muted-foreground")}>
                {s.label}
              </span>
            </div>
            {i < steps.length - 1 && (
              <span className={cn("mx-3 h-px flex-1 transition-colors", done ? "bg-success" : "bg-border")} aria-hidden />
            )}
          </li>
        );
      })}
    </ol>
  );
}
```

> Confirm `--success`/`--success-foreground` tokens exist in `globals.css` (they do — used by Badge `success`). No raw colors.

- [ ] **Step 2:** `npx tsc --noEmit` clean. Commit `feat(ui): stepper primitive (data-driven, green ticks)`.

---

### Task 2: `<InviteWizard>` (render-gated)

> **Render gate:** controller serves the :8753 render (stepper across steps + Details + Review card + success) and gets user sign-off before this task.

**Files:** Create `src/features/invitations/invite-wizard.tsx`; Modify `src/features/invitations/invite-dialog.tsx`.

**Interfaces:**
- Consumes: `<Stepper>` (Task 1), `useCreateDoctor`/`useCreateAssistant`, `<ShareInvite>`.
- Produces: `<InviteWizard kind clinicId onSent? />` rendered inside the Dialog Popup. `InviteDialog`'s public props unchanged.

- [ ] **Step 1:** Build `invite-wizard.tsx`. Hold `stepIndex` (0=details, 1=review), the form (react-hook-form + zod, same schema as today: name req, email req+valid, specialty/title optional per kind), and `inviteToken`/`inviteEmail` for success. Define steps as data:

```tsx
const STEPS = [
  { key: "details", label: t("invite.step.details") },
  { key: "review", label: t("invite.step.review") },
];
```

- [ ] **Step 2:** Render `<Stepper steps={STEPS} current={inviteToken ? STEPS.length : stepIndex} />` at the top (after send, show all complete).
- [ ] **Step 3:** **Details step** (stepIndex 0): the name/email/specialty-or-title `FormField`s (lift from the current dialog verbatim, same testids). Footer: Cancel (`DialogClose`) + **Next** (`data-testid="invite-step-next"`) — `onClick` runs `form.trigger()`; if valid, `setStepIndex(1)`. Next disabled while invalid is optional; gating via trigger is sufficient.
- [ ] **Step 4:** **Review step** (stepIndex 1): a review card (`bg-secondary-container/40 rounded-xl p-4` or a `Card`) listing each entered value as label/value rows (Name, Role=specialty/title, Email). Footer: **Back** (`invite-step-back` → `setStepIndex(0)`, values preserved by RHF) + **Send invite** (`invite-send`, `disabled={mutation.isPending}`) → calls the create mutation (same `onSubmit` logic as today) → on success set token/email. Show `mutation.isError` via `apiErrors.*`.
- [ ] **Step 5:** **Success** (inviteToken set): the existing success block — `invite-sent` + `t("invitations.inviteSentTo")` + `<ShareInvite token email />` + a Close (`DialogClose`). (Lift from current dialog.)
- [ ] **Step 6:** In `invite-dialog.tsx`, keep `DialogRoot`/`DialogTrigger`(trigger testids)/`DialogPopup`(`invite-dialog` testid)/`DialogTitle`; replace the inline form/success body with `<InviteWizard kind clinicId />`. Reset wizard state on close (move the reset into the wizard via an effect on `open`, or keep `InviteDialog` controlling `open` and remount the wizard with a `key={open ? "open" : "closed"}` so it resets). Keep `handleOpenChange` semantics.
- [ ] **Step 7:** Add i18n keys to BOTH `en.json` + `hi.json` in parity: `invite.step.details`, `invite.step.review`, `invite.review.title`, `invite.next`, `invite.back`, `invite.send`, review row labels (reuse `invitations.name`/`email`/`specialty`/`titleField` + a `invitations.role` if needed). 
- [ ] **Step 8:** `tsc --noEmit` + `npm run build` clean. Commit `feat(invitations): guided invite wizard (stepper + review card)`.

---

### Task 3: e2e + i18n parity

**Files:** Create `tests/e2e/invite-wizard.spec.ts`; Modify `tests/e2e/doctors.spec.ts`/`assistants.spec.ts` if their invite tests assert the old one-step submit.

- [ ] **Step 1:** Update any existing invite-flow e2e: the old flow filled name+email then clicked `invite-submit` once. The new flow is: fill Details → click `invite-step-next` → (Review) click `invite-send`. Find invite tests in doctors/assistants specs and update them to the 2-step flow (keep mocking the create endpoint returning `invite_token`).
- [ ] **Step 2:** Write `tests/e2e/invite-wizard.spec.ts` (mock backend per `tests/e2e/test-env.ts`): open the dialog (`add-doctor-button`); assert `stepper` shows 2 nodes, node 0 active; **Next is gated** — clicking `invite-step-next` with empty name/email stays on step 1 (validation messages show); fill valid name+email → Next → `invite-review` visible + node 0 shows the green check (completed) + the review card shows the entered name/email; **Back** returns to Details with values preserved; from Review, **Send** (mock create → `invite_token`) → `invite-sent` + `invite-link` contains `/invite/`. Repeat minimal path for assistant.
- [ ] **Step 3:** Run `npx playwright test tests/e2e/invite-wizard.spec.ts tests/e2e/doctors.spec.ts tests/e2e/assistants.spec.ts tests/e2e/i18n.spec.ts` → all green. `npx tsc --noEmit` + `npm run build` clean. Commit `test(invitations): guided invite wizard e2e + i18n parity`.

---

## Self-Review (against the spec)
- §3a Stepper primitive (data-driven, green ticks, tokens, aria-current): Task 1. ✅
- §3b InviteWizard (Details → Review&Send, RHF+zod, Next gated, review card of all details, Back preserves, success+ShareInvite): Task 2. ✅
- §2 one flow no toggle; data-driven steps reserving Permissions slot: Task 1/2 (STEPS array). ✅
- §4 replaces InviteDialog body, keeps trigger/shell/props/testids; reuses create hooks + ShareInvite: Task 2. ✅
- §5 render-before-build, Rule 17.0, i18n en/hi, e2e, FE-held-for-QA: Task 2 gate + Task 3. ✅
- §6 no backend; no permission toggles (slot only); no bulk: confirmed (FE-only, STEPS has no permissions entry). ✅
- Type consistency: `StepperStep {key,label}` + `<Stepper steps current>` used in Task 2; testids (`stepper`, `stepper-node-*`, `invite-step-next/back`, `invite-review`, `invite-send`, `invite-sent`, `invite-name-input`, `invite-email-input`) consistent across Tasks 1–3. ✅
- Placeholder scan: concrete code/props/testids/keys; no TBD. ✅
