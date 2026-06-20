# Success Cards — Design Spec (#61)

**Status:** Approved (brainstorm + visual mockup approved 2026-06-20)
**Scope:** Frontend-only. No backend / API / schema / migration.

## 1. Problem & Goal

The app has **no toast/notification system at all**. After important mutations the only feedback is implicit — a dialog silently closes and a list quietly refreshes. Non-technical users (assistants, owner-doctors) are left unsure whether the action actually worked.

**Goal:** after every important action, show an explicit, reassuring **success card** that states what happened, shows the key details in plain language, and offers a relevant next action — replacing silence (not a toast) with a calm, premium confirmation. This is the first of the pre-launch UX-trust features.

## 2. Approach

A **global success-feedback primitive**: one provider mounted once, a hook any mutation can call.

- **`SuccessProvider`** mounted in `src/app/providers.tsx` (wraps both auth and app routes), rendering a single modal.
- **`useSuccess()`** hook → `const success = useSuccess(); success(payload)` from any `onSuccess` handler.
- Reuses the existing base-ui **`Dialog`** primitive (`src/components/ui/dialog.tsx`) for the overlay + backdrop + focus management.

Alternatives rejected: per-feature local `<SuccessCard>` (boilerplate, drifts out of consistency); adding a toast library e.g. sonner (new dependency, and the explicit requirement is *cards, not toasts*).

### Interaction model (approved)
- **Must-acknowledge modal.** No auto-dismiss. The user taps the primary action or **Dismiss** to continue.
- **Responsive:** centered card on `md+`, **bottom-sheet** on mobile (anchored bottom, rounded top, slide-up, drag-handle affordance).
- **One at a time:** no queue. A second `success()` call replaces the current payload (modal stays open with the new content). Acceptable because actions are user-initiated and sequential.

## 3. Components (`src/components/success/`)

- **`success-context.ts`** — pure reducer + context. State = `{ payload: SuccessPayload | null }`. Actions: `show(payload)` (set/replace), `dismiss()` (clear). **Pure → unit-tested.**
- **`success-provider.tsx`** — `<SuccessProvider>`: holds reducer state, exposes `show`/`dismiss` via context, renders the modal (Dialog) with `<SuccessCard>` when `payload != null`.
- **`success-card.tsx`** — presentational. Props = the payload. Renders: ✓ badge → title → detail rows → actions.
- **`use-success.ts`** — `useSuccess()` returns the `show` function (typed). Throws a clear error if used outside the provider.

### Payload shape
```ts
type SuccessDetail = { labelKey: string; value: string };      // value already human-readable
type SuccessAction = { labelKey: string; href: string };       // optional deep-link
type SuccessPayload = {
  titleKey: string;                 // e.g. "success.appointmentConfirmed"
  details?: SuccessDetail[];        // resolved names / friendly date-time; EMPTY rows omitted by caller
  action?: SuccessAction;           // optional primary button (navigates); Dismiss always present
};
```
Callers build `details` with `t()` + existing formatters (names, friendly date/time, `+91 …` phone). **Rows whose value is empty/unknown are simply omitted** (e.g. a patient with no age) — never render a blank row.

## 4. Presentation (Register Design System · Rule 17.0)

- **Badge:** ✓ in a circular chip using the **existing** `success` token — `bg-success/10` circle + `text-success` check (mirrors the existing `border-warning bg-warning/10 text-warning` pattern in `create-profile-banner.tsx`). `--color-success` / `--color-success-foreground` already exist in `globals.css` (both themes). **No new tokens.**
- **Title:** centered, prominent.
- **Detail rows:** label (muted) left, value (emphasis) right, inside a subtle `surface-2` group; right-aligned values.
- **Actions:** stacked — optional primary **filled** button (the deep-link) + **Dismiss** (ghost). When there's no deep-link, a single filled **Dismiss**.
- **Desktop:** centered card (~min-w 300px, max-w ~360px) over a dimmed scrim. **Mobile:** full-width bottom-sheet with drag handle.
- Semantic tokens only, both themes, i18n, **WCAG AA**: focus moves to the title on open; Esc and Dismiss close; backdrop click closes; restore focus to the trigger on close.

## 5. V1 Wiring (all approved groups)

Each row = one `onSuccess` calling `success(...)`. Titles are i18n keys under `success.*`.

| Action | Source | Title | Details | Primary action |
|---|---|---|---|---|
| Appointment **request submitted** (assistant) | `scheduling/request-dialog` | Request sent | patient · doctor · when | — |
| Request **approved** (doctor) | `scheduling` approve | Appointment confirmed | patient · doctor · when | View appointment |
| Request **rejected** (doctor) | `scheduling` reject | Request declined | patient · doctor | — |
| **Patient added** | `patients/add-patient-form` | Patient added | name · age · phone *(omit empty)* | View patient |
| **Schedule saved** (window / block) | `scheduling/availability-editor` | Schedule saved | availability summary | — |
| **Doctor added** | `doctors/add-doctor-dialog` | Doctor added | name | — |
| **Assistant added** | `assistants/add-assistant-dialog` | Assistant added | name | — |
| **Doctor profile created** | `doctors/doctor-profile-wizard` | Profile created | name | — |
| **Clinic details saved** | `clinic/edit-clinic-details-dialog` | Clinic details saved | — | — |

"View appointment" / "View patient" deep-link to the relevant route. Existing dialogs still close on success; the success modal opens after (one modal visible — the success card — since the source dialog closes first).

## 6. i18n

Add a `success` block to `en.json` + `hi.json` (parity enforced): titles for each action above, detail row labels (`success.label.patient/doctor/when/name/age/phone/availability`), and action labels (`success.viewAppointment`, `success.viewPatient`, `success.dismiss`). All user-facing copy via `t()`.

## 7. Testing & gates

- **Unit:** pure `success-context` reducer (show sets/replaces payload; dismiss clears) via the Playwright runner (no Vitest).
- **i18n:** en/hi parity (`tests/e2e/i18n.spec.ts`).
- **Gates:** `tsc --noEmit` + `npm run build` clean.

## 8. Scope guards (YAGNI)

- **No** WhatsApp "confirmation sent" card (SP5/6 — no data yet).
- **No** auto-dismiss (must-acknowledge, by decision).
- **No** queue (replace-on-new).
- **No** backend/migration. **No** new design tokens (reuses existing `success`).

## 9. Out of scope / future

Confirmation **preview before** actions (#60) and the success card are complementary but separate; #60 is its own slice. Undo affordances, notification center (#40), and per-action sound/haptics are future.
