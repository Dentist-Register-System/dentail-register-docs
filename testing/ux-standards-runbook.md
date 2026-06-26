# Register System — UX Standards Runbook

- **Date:** 2026-06-26
- **Owner persona:** QA / DevOps Gatekeeper
- **Status:** Reference (living document)
- **Audience:** This audit & rewrite of the E2E suite, and **all future QA**. Cite it.
- **Companion to:** `testing/test-rails-v2.md` (P0 rails), `testing/acceptance-test-plan-v2.md`, `Rules/register-golden-rules.md` (§12 UI/UX, §16 i18n, §17 design system, §18 navigation), and `docs/specs/2026-06-26-bulletproof-e2e-journeys-design.md` (E2E journeys).

> **Why this exists.** "Looks like it works" is not a standard. To make our E2E suite *authoritative*, every UX flow is tested against **named, published industry standards** — not opinion. This runbook is the bar. A journey's flow either meets it or we file a bug. The product serves non-tech-savvy dentists and assistants, so usability *is* correctness.

---

## 1. How to use this runbook

For **every journey** (atomic or composite) in the E2E suite:

1. **Walk the flow against §3–§6 below.** Each item is either **[AUTO]** (deterministically assertable in the Playwright journey — fold it into the journey's `ui` / `neg` expectations) or **[HEURISTIC]** (judged, fed into the Claude intelligence/ease review, and filed as a `[BUG]` when violated).
2. **[AUTO] items become assertions** in the journey — they are part of "bulletproof," not a side-check.
3. **[HEURISTIC] violations are filed**, not silently tolerated (QA persona: surface, confirm, file `[BUG][E2E testing]`; no product code changed without explicit approval).
4. When a standard and a Register Golden Rule overlap, **the Golden Rule is the local, binding expression** of the standard — assert against the rule (it is usually stricter).

The standards below are **industry-published and citable**. Access date: 2026-06-26.

---

## 2. The standards we hold UX flows to

| Standard | What it governs | Authority |
|---|---|---|
| **Nielsen–Molich 10 Usability Heuristics** | General interaction usability | Nielsen Norman Group (1994, maintained) |
| **WCAG 2.2 Level AA** | Accessibility (perceivable, operable, understandable, robust) | W3C / WAI (basis of ISO/IEC 40500) |
| **Material Design 3** | Component, layout, touch-target, motion conventions (our design system) | Google |
| **Apple HIG** | iOS touch-target / platform conventions (cross-platform parity) | Apple |
| **Baymard form-usability guidelines** | Forms, input fields, validation | Baymard Institute (evidence-based) |
| **ISO 9241-11** | Definition of usability: effectiveness, efficiency, satisfaction in context | ISO |

We adopt **WCAG 2.2 AA** as the accessibility bar (superset of the 2.1 AA already in Golden Rule §17.5).

---

## 3. Usability heuristics → testable checks (NN/g 10)

For each heuristic: the standard, the **[AUTO]/[HEURISTIC]** QA check, and the Register binding.

1. **Visibility of system status** — keep the user informed with timely feedback.
   - **[AUTO]** Every create/save/approve/reject ends in a **Success Card** that states what happened (Golden Rule 18.5) — assert it is shown and dismissable; **never** tolerate a silent dialog-close.
   - **[AUTO]** Loading/disabled/pending states are visible (buttons disable on submit; pending requests show a Pending state — Rule 12.1).
   - **[AUTO]** Failed integrations surface to the assistant (Rule 12.3) — not buried in logs.

2. **Match between system and the real world** — familiar language, real-world conventions, no jargon.
   - **[AUTO]** All user-facing copy comes from i18n resources (Rule 16.1) — no hardcoded English literals; status/error via stable codes (16.2).
   - **[HEURISTIC]** Labels read in clinic language ("appointment", "request"), not internal/DB terms.

3. **User control and freedom** — clearly marked exits, undo/redo, no dead ends.
   - **[AUTO]** Every dialog/sheet/wizard step has a visible Cancel/Back; a wizard's optional step shows Skip (Rule 18.4).
   - **[AUTO]** Reschedule preserves the original appointment until the replacement is confirmed (Rule 5.7); Undo arrival/no-show returns to Confirmed (Rule 5.9).
   - **[AUTO/nav]** A control returns the user to the expected screen — **this is the direct catch for "button → wrong workflow."**

4. **Consistency and standards** — follow platform/industry conventions; same word = same thing.
   - **[AUTO]** UI uses design-system tokens + components only; no per-page CSS / one-off styles (Rule 17.0–17.2).
   - **[AUTO]** Entity selection uses the M3 picker pattern, not a raw `<select>`, for 5+ items (Rule 18.3); My Schedule vs Clinic Schedules stay separate (18.2).
   - **[HEURISTIC]** Terminology/iconography identical across web/iOS/Android (Rule 17.6).

5. **Error prevention** — prevent problems before they happen; confirm risky actions.
   - **[AUTO]** Destructive actions (delete patient, cancel appointment, schedule changes) require confirmation (Rule 12.2).
   - **[AUTO/db]** Capacity is enforced; overbooking blocked except explicit doctor override (Rules 5.2/5.3); stale-state transitions rejected (6.1).
   - **[AUTO]** Required wizard steps gate Next until valid (Rule 18.4).

6. **Recognition rather than recall** — make options visible; minimize memory load.
   - **[AUTO]** Pickers present searchable options (DoctorPicker bottom-sheet, Rule 18.3) rather than free recall.
   - **[AUTO]** Workflow states are shown with explicit labels (Pending/Confirmed/…); not hidden behind generic text (Rule 12.1).

7. **Flexibility and efficiency of use** — accelerators for frequent paths; don't make the common case slow.
   - **[AUTO/efficiency]** The **ease-of-use index** already measures clicks/screens/fields vs the ideal path per operation (`src/operations.ts`); a flow exceeding its ideal is flagged (ISO 9241-11 *efficiency*).
   - **[HEURISTIC]** Owner-doctor happy path is fast and default (Rule 18.1).

8. **Aesthetic and minimalist design** — no irrelevant content competing with the essential.
   - **[AUTO]** Multi-field creation uses the guided one-question-per-card wizard, not a dense form (Rule 18.4); related fields grouped into one step (e.g., full address).
   - **[HEURISTIC]** Screens match the premium-SaaS visual benchmark (Rule 17.0), not an ERP/CRUD look.

9. **Help users recognize, diagnose, recover from errors** — plain-language, precise, constructive.
   - **[AUTO]** Errors render as human-readable, translated messages from stable backend codes (Rule 16.2) — assert the *right* error appears, in the user's language; assert **no raw code / stack / English fallback** leaks.
   - **[AUTO/neg]** A failed action does not falsely report success (no success card on a 4xx/5xx).

10. **Help and documentation** — task-focused help in context.
    - **[AUTO]** Each wizard card carries its reassurance line (circled-i + i18n italic muted text, Rule 18.4).
    - **[HEURISTIC]** Empty/loading states explain what to do next.

---

## 4. Accessibility checks (WCAG 2.2 AA)

Baseline AA, both light **and** dark themes (Rule 17.3). Key operable/understandable criteria for our flows:

- **[AUTO] 2.5.8 Target Size (Minimum)** — interactive targets ≥ **24×24 CSS px** (WCAG 2.2 AA). Register holds the **stricter** Material-3/HIG bar of **≥44–48px** with ≥8dp spacing (Rule 17.4) — assert against the stricter bar.
- **[AUTO] 2.4.7 Focus Visible** + **2.4.11 Focus Not Obscured (Minimum, AA)** — a keyboard-focused element shows a visible focus ring (`ring-ring` token) and is at least partially visible (not hidden under sticky headers/sheets/cards).
- **[AUTO] 1.4.3 Contrast (Minimum)** — text/icon contrast meets AA in both themes (Rule 17.3).
- **[AUTO] 3.3.8 Accessible Authentication (Minimum, AA)** — no cognitive-function test forced in login. **Concrete check: do not block paste/autofill** on the OTP and password fields (so password managers / code autofill work); OTP transcription must be pasteable.
- **[AUTO] 3.3.7 Redundant Entry (A)** — don't ask for the same info twice in one session (e.g., onboarding shouldn't re-collect data already given).
- **[AUTO] 2.5.7 Dragging Movements (AA)** — any drag interaction has a simple pointer (tap/click) alternative.
- **[AUTO] 3.2.6 Consistent Help (A)** — help/settings live in a consistent location (Rule 18.6: all settings under `/settings`).
- **[AUTO] keyboard operability** — primary flows completable by keyboard; honor reduced-motion + system theme (Rule 17.5).
- **[HEURISTIC] 1.4.1 Use of Color** — state/meaning never conveyed by color alone (pair with label/icon).

---

## 5. Form & input usability (Baymard) — applies to every create/edit flow

- **[AUTO]** **Clear labels** on every field; **required** fields marked; validation message is specific and inline (not a generic banner).
- **[AUTO]** **Minimize fields** — only what's needed; optional/rare fields hidden behind a link or a Skip step (aligns with wizard, Rule 18.4).
- **[HEURISTIC]** **Field width matches expected input** for fixed-length inputs (e.g., age, PIN, phone) — don't render a full-width box for a 2-digit age.
- **[AUTO]** **Don't split single identities** unnecessarily (e.g., one name field unless there's a real reason).
- **[AUTO]** **Intelligent defaults / prefill / autofill** are not blocked (also supports WCAG 3.3.8).
- **[AUTO/neg]** Submitting an invalid form does **not** navigate away or fake success; the user stays, sees the error, and can fix it (heuristics 5 + 9).

---

## 6. Mobile & cross-platform (Material 3 / Apple HIG) — mobile-first product

- **[AUTO]** Touch targets ≥ 44–48px, ≥8dp spacing (Rule 17.4; Material 48dp / HIG 44pt).
- **[AUTO]** Layout is mobile-first / responsive; no fixed-pixel layout widths that overflow small viewports.
- **[AUTO]** Navigation uses the app shell (bottom-nav mobile / rail web) — not improvised per-page nav (Rule 17.0).
- **[HEURISTIC]** Behavior/terminology identical across platforms; only native patterns vary (Rule 17.6).

---

## 7. Mapping to the E2E journey layers

How runbook checks land in a journey's `expect` block (see the E2E journeys spec):

| Runbook check type | Lands in journey layer |
|---|---|
| Success card / status visible / right error shown | `ui` |
| No false success, no wrong-nav, no color-only, no blocked paste | `neg` |
| Routed to the correct screen | `nav` |
| Capacity / state / audit invariants behind the UX | `db` |
| Efficiency vs ideal path | ease-of-use index (`measure()`), not a hard assert |
| Aesthetic / tone / cross-platform parity | `[HEURISTIC]` → intelligence review + `[BUG]` |

**Rule of thumb:** if a standard is **deterministically observable**, it is an **assertion**; if it is **judged**, it is a **filed finding**. Neither is skipped.

---

## 8. Sources (accessed 2026-06-26)

- Nielsen Norman Group — *10 Usability Heuristics for User Interface Design*: https://www.nngroup.com/articles/ten-usability-heuristics/
- W3C WAI — *What's New in WCAG 2.2*: https://www.w3.org/WAI/standards-guidelines/wcag/new-in-22/
- Material Design 3 — *Accessibility / structure* (touch targets): https://m3.material.io/foundations/designing/structure ; Android touch-target help: https://support.google.com/accessibility/android/answer/7101858
- Baymard Institute — *Form Design best practices*: https://baymard.com/learn/form-design ; *Input fields*: https://baymard.com/learn/input-fields
- ISO 9241-11 — *Ergonomics of human-system interaction — Usability: Definitions and concepts*.

> **Maintenance:** when WCAG, Material, or the Baymard guideline set updates, refresh §2–§6 and re-stamp the access date. New journeys are written against the then-current version.
