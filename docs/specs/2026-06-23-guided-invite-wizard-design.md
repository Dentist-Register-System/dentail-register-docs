# Guided Invite Wizard — Design Spec

**Status:** Approved (brainstorm 2026-06-23; issue #126, sub of #25). **Frontend-only** (no backend / no migration). Register Design System, Rule 17.0, i18n-first.
**Type:** Replace the single-form invite with a **guided multi-step wizard** (one flow, no mode toggle) for Doctors & Assistants, with a data-driven **stepper** header and a final **Review** card that summarizes all entered details before sending.

## 1. Goal
Make inviting a teammate feel guided and reassuring for non-tech-savvy clinic owners — clear one-thing-per-step input, a confirm-before-send review, visible progress — without adding a mode choice or extra friction. Quick for power users, hand-holding for first-timers, in a single flow.

## 2. Scope decisions (locked in brainstorm)
- **One guided flow, NO guided/direct toggle.** A mode toggle adds choice-friction + two code paths — it makes the UI *harder*, not easier. The single flow is short, so it serves both audiences.
- **Stepper header** at the top of the invite card: numbered nodes + connectors, each turning a **green tick** when its step is completed. **Data-driven** — renders exactly as many steps as the flow defines (no hardcoded count).
- **Steps now (2):** (1) **Details**, (2) **Review & Send**. Permission toggles are **deferred to #125**; this flow reserves a slot so a **Permissions** step drops in (for assistants) with zero rework.
- **Final Review card** lists every entered detail (name · role · email · specialty/title) so the owner confirms before sending — matches #60 "confirmation preview before important actions."
- **Frontend-only**: reuses the existing create-with-invite endpoints (`POST /clinics/{id}/doctors|assistants` → `{…, invite_token}`) and the `<ShareInvite>` delivery component. No backend, no migration.
- Replaces the current single-form `<InviteDialog>` body; keeps the dialog shell + the "Invite Doctor"/"Invite Assistant" trigger.

## 3. Components
### 3a. `<Stepper>` primitive — `src/components/ui/stepper.tsx`
- `<Stepper steps={{key,label}[]} current={number} completed={Set<number>|number} />` — horizontal row of numbered nodes joined by connectors. A step shows: a **green check** (`bg-success`/`text-success-foreground`) when completed; the **primary** fill when it's the current step; muted otherwise. Connector line fills (primary/success tone) up to the current step. Label under/beside each node. Semantic tokens only (Rule 17.0), both themes, responsive (labels may collapse on mobile). Accessible: `aria-current="step"` on the active node, the list has an accessible name. testids `stepper`, `stepper-node-${index}`.

### 3b. `<InviteWizard>` — `src/features/invitations/invite-wizard.tsx`
- `<InviteWizard kind="doctor"|"assistant" clinicId />` rendered inside the existing invite Dialog (the trigger button + `DialogPopup` shell stay).
- Holds wizard state: `stepIndex`, the form values, and `submitted`/`inviteToken`/`inviteEmail` for the success state. Uses react-hook-form + zod (mirror the current `InviteDialog`).
- **Defines its steps as data** (so the Stepper is driven from the same source): `STEPS = [{ key:"details", label:t("invite.step.details") }, { key:"review", label:t("invite.step.review") }]`. (A `permissions` step is inserted between for assistants when #125 ships — out of scope here, but the array shape supports it.)
- **Step 1 — Details:** name (required), email (required + valid), specialty (doctor) / title (assistant, optional). Inline validation via the form; **"Next" disabled until the step is valid**; on Next, mark step 1 completed (green tick) and advance.
- **Step 2 — Review & Send:** a **review card** rendering every field entered (name, role label, email, specialty/title) in a read-only summary; a **Back** button (returns to Details, preserving values); a **Send invite** button → calls `useCreateDoctor`/`useCreateAssistant` with the values. On success → success view: "Invitation sent to {email}" + `<ShareInvite token={invite_token} email={email} />` (Copy Link + email). Errors surfaced via `apiErrors.*`.
- Reset wizard (step, form, submitted) when the dialog closes.
- testids: `invite-wizard`, `invite-step-next`, `invite-step-back`, `invite-review`, `invite-send`, `invite-sent`, plus the existing `invite-name-input`/`invite-email-input` and the trigger `add-doctor-button`/`add-assistant-button` (preserve for e2e).

## 4. Frontend integration
- `<InviteWizard>` replaces the body of the current `<InviteDialog>` (or `InviteDialog` is refactored to host the wizard). Wherever `<InviteDialog kind clinicId/>` is used (doctors/assistants tabs), the trigger + behavior stay; only the dialog's inner content becomes the wizard.
- Keep the create hooks + `<ShareInvite>` exactly as-is.
- No change to the Team table, drawer, or settings.

## 5. Quality
- **Render on :8753** (stepper with green ticks across steps + Details + Review card + success) — user sign-off before building.
- `tsc --noEmit` + `npm run build` clean; Rule 17.0 (semantic tokens only, both themes, mobile-first, WCAG AA — visible focus, `aria-current`); the universal CLAUDE.md behavior rules.
- i18n en+hi parity for all new keys (`invite.step.*`, `invite.review.*`, step nav labels). Reuse existing `invitations.*` / `common.*` keys where possible.
- e2e (Playwright, mocked): step-1 validation gates Next; Next advances + ticks the node; Review card shows the entered details; Back preserves values; Send creates the invite (mocked) and shows the success + Copy Link; both doctor & assistant.
- FE PR **held for user QA**.

## 6. Scope guards / deferred
- **Per-assistant permission toggles** (approve requests / manage availability) → **#125**; this wizard reserves the step slot but does not build them.
- No guided/direct mode toggle.
- No bulk/multi-invite (single member per invite).
- No backend changes.

## 7. Self-review (against the request)
- Guided multi-step wizard, one flow, no toggle: §2/§3b. ✅
- Stepper header, numbered nodes + connectors + green ticks, data-driven: §3a. ✅
- Final review card of all entered details before send: §3b step 2. ✅
- Doctor & assistant; reserves Permissions slot for #125: §2/§3b. ✅
- Frontend-only, reuses create endpoints + ShareInvite: §2/§4. ✅
- Render-before-build + Rule 17.0 + i18n + e2e + FE-held-for-QA: §5. ✅
- Placeholder scan: concrete components/props/steps/testids; no TBD. ✅
