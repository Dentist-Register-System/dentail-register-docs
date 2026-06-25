# Missing-Information Detection — Design Spec (#63)

**Status:** Approved in brainstorm (2026-06-25). Issue **#63** (Critical, pre-launch — UX trust/safety). Builds on the completeness pattern from **#39** (`computeClinicCompleteness`) and coordinates tightly with **#59** (patient detection + quick-add), **#62** (server `is_complete` + Home aggregate), and **#139** (appointment day-of surface). Register Design System (Rule 17.0), i18n-first (en/hi), both themes, a11y. **Frontend-led**, one small backend coordination point (see §8). Directional mockups to follow; dev fine-tunes at render sign-off.

**Type:** Surface **deterministic, plain-English missing-information warnings** on the **patient** and **appointment** records, each item **one tap from a precise fix**. No AI in V1. Record-level only — clinic-wide aggregation stays with #62.

---

## 1. Goal

*"A non-tech-savvy dentist or assistant always sees, calmly, what's missing on a patient or appointment record — and fixes it in one tap, landing exactly on the field, never hunting."*

The feature exists to **catch gaps before they bite** (e.g. a confirmation that can't send because there's no phone) and to **guide staff to complete records without nagging**. The hard design constraint — and the reason this is Critical — is that it must read like a helpful receptionist nudge, never like an error screen. We deliberately take the *harder* build (precise field-level deep-links, auto-clearing card, smart ordering) because that is what makes completion feel effortless for a non-technical user.

---

## 2. Scope decisions (locked in brainstorm 2026-06-25)

1. **#63 is additive — it ships a helper + a card, not a page.** It mounts on surfaces other issues own. No net-new appointment-detail page is invented here.
2. **One shared detection rule, defined once** (§4). #59's `isPatientComplete` is *derived from* the same helper #63's card uses — there is no second copy of the patient rule on the frontend.
3. **The patient warning card absorbs #59's generic banner.** #59 ships the Patients-list **!** badge; #63 owns the **itemized, jump-to-fix card** on `patient-detail` (it *replaces* #59's single "Please complete patient details" banner — one component, not two).
4. **The appointment card mounts on #139's day-of appointment surface** (arrival/no-show/completion/cancel). #63 contributes the card + helper; #139 owns the surface. We do **not** mint a second appointment surface.
5. **Honest, substrate-gated checks.** Checks whose data does not exist yet are **designed in the helper but not wired** — flag-gated dark until their column lands. A *shipped* check must read a real field; a vacuous/always-false check is forbidden.
6. **Show the full set, calmly (decision A).** We warn on every genuinely-missing item, tiered and calm — we do **not** hide soft fields. Nagging is solved by **tone + behaviour**, not by omission (§6).
7. **Record-level only.** No new clinic-wide aggregate — #62 owns the Home "patients missing details (N)" count. #63 complements Clinic Health *at the record level* (the issue's own framing).
8. **Calm warning, never an error.** Amber/attention semantic tokens, icon **+ text** (never colour-only), friendly plain-English copy, auto-clears on completion.

---

## 3. What exists today (verified against code, 2026-06-25)

- **Patient** (`patient_beta` / `PatientRead`): `name`✦, `phone`✦, `age`✦, `gender`(nullable), `referral_source`(nullable), `medical_conditions`(nullable), `chief_complaint`(nullable), `notes`(nullable). **No** `date_of_birth`, `email`, `address`. (✦ = NOT NULL today.)
- **Appointment** (`appointment_beta` / `AppointmentRead`): `chief_complaint`(nullable), `notes`(nullable), `status`, times, `doctor_id`, `patient_id`. **No** `confirmation_sent`, `reminder_sent`, `follow_up`, completion fields *(the latter arrive with #139)*.
- **No appointment-detail page** exists; appointments render as rows in lists and inside `patient-detail`. **#139** introduces the day-of action surface.
- **Patient edit** is a single dialog (`EditPatientDialog`) with all fields — **no per-field focus today**.
- **Pattern to mirror:** `src/features/clinic/completeness.ts` → `computeClinicCompleteness(clinic): { items, percent }` (pure, client-side).

---

## 4. One shared rule, one helper

`src/features/shared/missing-info.ts` — pure, unit-testable, mirrors `computeClinicCompleteness`:

```ts
type MissingTier = "attention" | "complete";   // "attention" = bites operationally/clinically; "complete" = record hygiene
type MissingCode =
  | "patient.phone" | "patient.medicalHistory" | "patient.age" | "patient.gender" | "patient.referralSource"
  | "appointment.reason"
  | "appointment.confirmationSent"  // DARK — reserved (SP5)
  | "appointment.followUp";         // DARK — reserved (SP6/follow-up)

interface MissingItem {
  code: MissingCode;
  labelKey: string;            // i18n key → plain-English label
  tier: MissingTier;           // display ordering/emphasis only
  completenessMember: boolean; // true ⟺ this item participates in the canonical completeness rule
  fixTarget: FixTarget;        // { kind: "patientField"; field } | { kind: "appointmentField"; field } | { kind: "none" }
}

function isPatientComplete(p: PatientRead): boolean;                 // THE canonical rule — single source
function patientMissingInfo(p: PatientRead): MissingItem[];          // richer display list (superset of the rule)
function appointmentMissingInfo(a: AppointmentRead, opts: { darkChecksEnabled?: boolean }): MissingItem[];
```

- **The canonical completeness rule lives in exactly one predicate: `isPatientComplete(p)`** = `name && phone && (age|DOB) && gender`. #59 imports *this predicate* for its badge; #62's server `is_complete` mirrors *this same rule*.
- **`patientMissingInfo` is a superset for display.** It returns the completeness-rule gaps **and** extra hygiene items (medical history, referral source). **`tier` is not completeness:** `phone` is `attention` *and* a completeness member; `medicalHistory` is `attention` but **not** a completeness member; `age`/`gender` are `complete` tier *and* completeness members. So completeness membership is carried explicitly by `completenessMember`, **never inferred from `tier`** — this is the bug-prone trap the parity test (§8.2) guards.
- **Invariant (asserted in tests):** `isPatientComplete(p) === (patientMissingInfo(p).every(i => !i.completenessMember))`. The display card may still show non-completeness items on an otherwise "complete" patient.
- **Dark appointment checks** (`confirmationSent`, `followUp`) are returned **only** when `darkChecksEnabled` is true, which stays `false` until the backing column ships. They are present in the type and unit tests as `pending`, never rendered in V1.
- **Pure & deterministic:** no I/O, no AI; same input → same output; trivially unit-testable like the clinic helper.

---

## 5. The checks

### Patient (all live today)

| Item | Tier | Why it bites |
|---|---|---|
| **Phone** | attention | Can't send a confirmation/reminder without it |
| **Medical history** (`medical_conditions`) | attention | Clinical safety before treatment |
| **Age / DOB** (`age`) | complete | Clinical context; member of the completeness rule |
| **Gender** | complete | Member of the completeness rule |
| **Referral source** | complete (lowest priority) | Practice analytics; weakest operational bite |

`name` is always present (NOT NULL, no creation path omits it) → never an item.

### Appointment

| Item | Status | Why |
|---|---|---|
| **Reason** (`chief_complaint`) | **live** | Weak visit/history context for the doctor without it |
| Confirmation sent | **dark — reserved (SP5)** | No `confirmation_sent` column yet; designed, not wired |
| Follow-up marked | **dark — reserved (SP6/follow-up)** | No follow-up substrate yet; designed, not wired |

**Explicitly *not* checks** (would nag or are impossible): completion notes (Golden Rule 5.8 — completion is *never* blocked); no-show / cancel reason (#139 makes these **required at the transition**, so they cannot be missing on a persisted record).

---

## 6. The card — `<MissingInfoCard>`

A single reusable component, parameterised by `items: MissingItem[]` + a title.

- **Tone:** calm **warning**, never destructive. Amber/attention semantic tokens (`bg-accent`/attention surface), an info/alert icon **plus** text — never colour-only.
- **Copy:** reassuring, plain English, in the #59 circled-*i* voice — e.g. *"A few details are missing — tap to add them whenever you like."* Per-item labels are plain English ("Phone number missing"), never field codes.
- **Ordering:** items sorted **attention-first**, then completeness order — so the *first* affordance fixes the thing that bites most.
- **Density:** when there are **> 2** items, the card renders a one-line summary ("3 details missing") that **expands** to the list — never a wall of warnings.
- **Auto-clear:** the card is **hidden the moment the record is complete** (no lingering, no guilt). Empty `items` → renders nothing.
- **Per-item Fix:** each item has a **Fix** affordance wired to its `fixTarget` (§7). Dark items are never emitted, so never shown.
- **System rules:** Rule 17.0 (compose `components/ui/*`, semantic tokens, no per-page CSS), both themes, mobile-first, WCAG AA (status by icon+text, ≥44px targets, visible focus, contrast in both themes).

**Mount points:** top of `patient-detail` (replacing #59's banner); the **#139 day-of appointment surface** for the appointment instance.

---

## 7. Jump-to-fix (the harder, better build)

The point of the feature is that a non-technical user fixes a gap **without hunting**.

- **Patient:** extend `EditPatientDialog` with a **`focusField`** prop. A patient item's **Fix** opens the dialog **scrolled to and focused on exactly that field**. (Net-new: the dialog must accept and honour `focusField`; today it opens unfocused.)
- **Appointment:** the **reason** item deep-links to the appointment's edit affordance on the **#139 surface**, focused on the reason field. Until that affordance exists, the reason item still renders but its Fix routes to wherever reason is editable on the #139 surface — **coordinated with #139, not duplicated here**.
- **Dark items** carry `fixTarget: { kind: "none" }` and are not emitted in V1, so there is no danger of a Fix that goes nowhere.

**Deferred enhancement (deliberately out of V1):** *inline-fix* — editing the field directly inside the card without opening the dialog. Easiest possible UX, but it fragments the single edit surface into many per-field editors. **V1 uses focused-dialog**; inline-fix is a documented fast-follow if we later choose to push ease further.

---

## 8. Backend / data coordination

**#63 adds no backend of its own.** It does, however, **depend on** two things owned by neighbouring issues — recorded here so they are not discovered in production:

1. **`Patient.age` is `NOT NULL` today, but #59's quick-add persists name + phone only.** #63's "age missing" check assumes age **can** be absent. **Blocking dependency on #59:** `age` (and/or a future `date_of_birth`) must be made **nullable** (migration via Supabase MCP, controller-only) before quick-add patients can exist *and* before the age check is meaningful. If #59 ships without this, quick-add cannot persist and the age check is dead. **The dev must resolve this in #59's implementation.**
2. **Drift guard with #62's server `is_complete`.** #62 computes `is_complete` **server-side** for the Home count. The frontend `isPatientComplete(p)` predicate (§4) and #62's server bool encode the *same* rule. To prevent drift, a **parity contract test** asserts, over shared fixtures: `isPatientComplete(p) === server is_complete` (equivalently, `patientMissingInfo(p)` has no `completenessMember` item ⟺ `is_complete === true`). *(Rejected for V1: having the backend return `missing_info: string[]` codes — it bloats every `PatientRead`, hard-codes presentation codes into the API, and breaks #59's FE-only detection path for no real gain at this scale.)*

---

## 9. Frontend components

- `src/features/shared/missing-info.ts` — `patientMissingInfo`, `appointmentMissingInfo`, the canonical completeness rule, `MissingItem`/`MissingTier`/`MissingCode`/`FixTarget` types. (Consumed by #59's badge, this card, and the derived `isPatientComplete`.)
- `src/components/missing-info-card.tsx` — the reusable `<MissingInfoCard items title />` (tone, ordering, collapse-when->2, auto-clear, per-item Fix).
- `patient-detail.tsx` — mount the patient card atop the record; **remove** #59's generic banner; add `focusField` to `EditPatientDialog` and wire each Fix.
- **#139 appointment surface** — mount the appointment instance of the card (coordination point; #63 provides the card, #139 hosts it).
- i18n: new `missingInfo.*` namespace (en + hi parity) — card copy + per-code plain-English labels.

---

## 10. System rules

- **i18n** en+hi parity for every new string (`missingInfo.*`) — gated by `tests/e2e/i18n.spec.ts`; plain-language; no field codes shown to users.
- **Rule 17.0** — semantic tokens only, compose `components/ui/*`, no per-page CSS; both themes; mobile-first; WCAG AA (icon+text status, ≥44px, focus, contrast in both themes).
- **Determinism / Golden Rules** — pure helper, no AI (issue requirement); no warning on completion notes (5.8); humans complete records, software only surfaces gaps (1.1).
- **Render sign-off before build** (the card on `patient-detail`, the focused-field Fix, the collapsed/expanded states, both themes, the appointment instance). FE PR held for user QA.

---

## 11. Test plan

- **Unit (`missing-info.ts`):** patient rule (each field present/absent → expected items + tiers; complete patient → `[]`); ordering is attention-first; `appointmentMissingInfo` returns the reason item when `chief_complaint` empty; dark checks emitted **only** when `darkChecksEnabled` (default off → never in output). The §4 invariant holds: `isPatientComplete(p) === patientMissingInfo(p).every(i => !i.completenessMember)`.
- **Parity contract:** shared fixtures → `isPatientComplete(p) === server is_complete` (guards #62 drift).
- **Component (RTL):** card hidden when `items` empty (auto-clear); collapses to summary when > 2 items and expands; each Fix calls the right `fixTarget`; status conveyed by icon+text (not colour-only); both themes render tokens.
- **`EditPatientDialog` focus:** opening with `focusField="phone"` focuses/scrolls to phone; same for each field.
- **e2e (Playwright, mocked):** incomplete patient shows the calm card with the right items ordered attention-first; tapping "Phone number missing → Fix" opens the edit dialog focused on phone; completing the record makes the card disappear; en/hi parity for all card copy.

---

## 12. Coordination summary

- **#39** — reuse the `computeClinicCompleteness` shape (pure helper → items). ✅
- **#59** — ships the Patients-list **!** badge + quick-add; **imports** the shared rule; its generic banner is **replaced** by #63's card. **Must** make `age`/DOB nullable (§8.1).
- **#62** — owns the Home aggregate + server `is_complete`; #63 stays record-level and adds the **parity test** (§8.2).
- **#139** — owns the appointment day-of surface that **hosts** #63's appointment card; reason-fix deep-link coordinates with #139's edit affordance.
- **#60** — unrelated to detection, but the same calm-confirmation philosophy; no shared code required here.

---

## 13. Acceptance-criteria mapping

- *Missing required/important info visible on patient + appointment via a warning card/chip (not an error state)* → §5, §6 (calm amber, icon+text). ✅
- *User can jump straight to fixing the missing field* → §7 (focused-dialog deep-link + #139 reason-fix). ✅
- *Checks are deterministic (no AI) for V1* → §4 (pure helper). ✅
- *M3 (Rule 17.0), i18n en/hi, both themes, a11y* → §6, §10. ✅
- *Helper per entity, pure + unit-testable (like `computeClinicCompleteness`); reuse #39 pattern* → §4, §9, §11. ✅
- *Gate confirmation-sent / follow-up until SP5/6; start with fields that exist today* → §2.5, §4 (dark/reserved), §5. ✅
- *Feeds Clinic Health at the record level; no AI* → §2.7 (record-level; #62 owns aggregate). ✅
