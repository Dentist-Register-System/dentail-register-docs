# Guided One-Question Wizard (Clinic + Doctor-Profile Creation) — Design Spec

> Status: Draft for review · Date: 2026-06-20 · Requirement source: issue #50
> Scope: a reusable, premium M3 **guided wizard** (one question at a time) used for **clinic creation** (onboarding) and **doctor-profile creation** (#49). Frontend-only — no backend/API/schema changes (reuses the existing `POST /clinics` and `POST …/doctors/me` endpoints). Builds on merged #49.

---

## 1. Context & Purpose
Today clinic creation and doctor-profile creation are single dense forms. This slice replaces them with a **guided, one-question-at-a-time wizard** — a calmer, premium onboarding experience (mobile-first, India-first small clinics). The wizard is a **reusable component**; both flows are migrated onto it. Validated visually in the brainstorming session (mockups in `.superpowers/brainstorm/`).

## 2. Locked Design (from the visual brainstorm)
- **Layout:** a top **progress bar**; a centered **one-question card**; on **desktop** a **left step-rail** (vertical stepper: completed steps ✓, current highlighted, upcoming numbered); on **mobile** the rail collapses to a **horizontal dot row** (completed filled, current elongated, upcoming muted).
- **One question per card**, EXCEPT a cohesive unit stays one card: the clinic's **structured postal address is a single "Address" card** (not one card per field). (See [[wizard-step-granularity-preference]].)
- **Controls:** **Back** (except step 1), **Next** for required steps (disabled until valid), **Skip** for optional steps. The **last step's button submits** ("Create clinic" / "Create profile") — no separate review step.
- **Validation is per-step:** a required step must be valid before Next; optional steps may be skipped. Reuse the existing Zod rules (phone regex, PIN, email, required fields).
- **Reassurance line on every card:** a **circled-i** (M3 `info` icon) + **italic, muted** text, below the field(s), above the buttons. Per-flow copy:
  - Clinic wizard → *"Don't worry — you can change any of these later under Your clinic → Edit clinic details."*
  - Doctor-profile wizard → *"You can change any of these later in My Profile."* (My Profile is a future per-user Settings page — tracked as #54 under #35.)
- **Back-navigation** between already-answered steps preserves entered values.

## 3. Flows & Steps
**Clinic creation (5 steps)** — onboarding "Create a clinic":
1. Clinic name (required) · 2. Phone (required) · 3. WhatsApp (optional → Skip) · 4. Email (optional → Skip) · 5. **Address** (one card: address_line_1*, area*, city*, state*, pin_code* required; address_line_2, landmark, google_maps_url optional). Submit → `POST /api/v1/clinics`.

**Doctor-profile creation (3 steps)** — from the #49 create-profile banner / entry point:
1. Your name (required) · 2. Your phone (required) · 3. Specialty (optional → Skip). Submit → `POST /api/v1/clinics/{clinicId}/doctors/me`.

## 4. Architecture — reusable `Wizard`
A config-driven component on the M3 framework (Rule 17.0). Proposed shape (plan pins exact API):
- **`Wizard`** props: an ordered list of **steps**, each `{ key, labelKey, optional, isValid(values), content }` (where `content` renders that step's field(s) bound to shared form state), a `reassuranceKey` (the per-flow copy), and `onComplete(values)` (calls the mutation). The wizard owns: current-step index, the **progress bar**, the **desktop rail** + **mobile dots** (rendered from the step list + current index + per-step validity), the **Back/Next/Skip** controls (Skip shown iff `optional`; Next disabled until `isValid`), the **reassurance line**, step transitions, and submit on the last step.
- **Form state:** React Hook Form (existing pattern) holds all values across steps; each step renders its own fields; the wizard validates only the current step's fields before advancing (RHF `trigger(stepFields)`), and submits the whole form on the final Next.
- **Responsive:** the rail is `hidden` below `md`; the dot row is `md:hidden`. Both derive from the same step model. Semantic tokens only; both themes; a11y (focus moves to the step heading on advance; rail/dots have appropriate roles/labels; Back/Next keyboard-navigable; Enter submits the current step).
- **Reuse:** `CreateClinicForm` (onboarding) and the doctor-profile creation are re-expressed as step configs passed to `Wizard`. The #49 doctor-profile **dialog** is replaced by a **full-screen guided experience** (consistent with onboarding's full-screen `AuthShell`); the banner/entry CTA opens it. Clinic onboarding wizard renders within the existing onboarding/auth shell.

## 5. Out of Scope
Backend/API/schema changes (none); the **My Profile** Settings page (#54); the #35 Settings screen; any new fields beyond what the existing forms collect; a multi-step "review/confirm" screen (last Next submits).

## 6. Testing
- **Frontend:** `tsc --noEmit` + `npm run build` clean; i18n en/hi parity for all new keys (wizard controls, per-flow reassurance, step labels). Pure-logic unit test (Playwright-runner pattern) for the wizard's step/validity/progress logic (e.g., Next gating on required, Skip available only on optional, progress fraction, last-step submit). Component coverage for: clinic wizard advances through 5 steps and submits the correct `POST /clinics` payload; doctor wizard 3 steps → `POST …/doctors/me`; Back preserves values; reassurance line present on every step; desktop rail vs mobile dots both render from the step model.
- Rule 17.0: semantic tokens only (no raw colours), compose `components/ui/*`, no per-page CSS; all strings via `t()`.

## 7. Docs
- Add the **guided-wizard pattern** to the design-system notes / `/design-system` showcase.
- Golden Rules already carry §18 (no-dropdowns / M3 selection). Add a short note that multi-field creation flows use the guided wizard.

## 8. Execution shape
One spec, one plan, frontend-only. Build the reusable `Wizard` (+ its pure step/progress logic + unit test) first, then migrate clinic creation, then doctor-profile creation (replacing the #49 dialog), then i18n + docs. No migration, no Supabase change.
