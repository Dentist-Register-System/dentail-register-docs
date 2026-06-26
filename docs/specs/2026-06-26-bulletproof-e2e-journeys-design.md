# Bulletproof, Journey-Mapped E2E Tests — Design

- **Date:** 2026-06-26
- **Owner persona:** QA / DevOps Gatekeeper
- **Status:** Design (approved 2026-06-26) — implementation plan to follow
- **Repo of record for tests:** `register-test-suite`
- **Related:** `register-test-suite` (E2E harness, issue #103), `testing/test-rails-v2.md`, `testing/acceptance-test-plan-v2.md`, **`testing/ux-standards-runbook.md`** (UX bar for all flows), `Rules/register-golden-rules.md` (§5 capacity, §6 state transitions, §7 audit, §10 testing, §12/§17/§18 UI-UX)

---

## 1. Problem

The E2E suite is **not catching basic bugs**. A green run does not currently mean the product is correct. Three concrete loopholes, found in the existing suite (2026-06-26):

1. **Failures are swallowed → green can be vacuous.** `src/pages/patients-page.ts#dismissSuccess()` waits for the mandatory success card (Golden Rule 18.5) but `.catch(() => {})` on timeout. If the FE stops rendering the success card (a real regression), the test **still passes**. The same swallow hides a missing duplicate-warning.
2. **Assertions are positive-only and shallow.** `tests/functional/patients.spec.ts` "assistant creates a patient" asserts exactly one thing — a row with the name is visible. It never checks the **backend persisted** the patient, never checks phone/age, never checks the dialog closed, never checks that no error appeared. A FE that optimistically renders a row while the API 500s → **passes**.
3. **No path/navigation assertions → "wrong button → wrong workflow" is invisible.** `tests/functional/requests.spec.ts` "approve" asserts the pending **count** dropped by one. It never verifies *which* request changed, that it became Confirmed, or where the user landed. Approve the wrong row, or route to the wrong screen, and the count still drops by one → **passes**.

This is not a "write more tests" problem. The journeys are thin (single-line `Then`) and the assertions do not verify reality at the UI **and** backend layers. The fix is a **methodology**, an **audit** against it, and a **rewrite**.

## 2. Goals & non-goals

**Goals**
- Every E2E test is a **journey** with a precise, layered definition.
- A green run is **authoritative**: UI, backend (API **and** invariant DB), and navigation are all verified.
- The suite catches **UI bugs** (wrong-workflow routing), **backend bugs** (no persistence, wrong state, missing audit), and **regressions** — deterministically, every run.
- It is **impossible to claim a check that isn't made** (a build-failing guard enforces this).
- **Every UX flow is tested against published industry standards** — Nielsen–Molich heuristics, WCAG 2.2 AA, Material 3 / Apple HIG, and Baymard form guidelines — codified in `testing/ux-standards-runbook.md`. Usability is treated as correctness, not opinion.

**Non-goals (this effort)**
- Pixel/visual snapshot regression (deferred until UI stabilises post-launch; the Claude intelligence-diff remains the soft net for visual/ease drift).
- Coverage of unshipped flows (day-of lifecycle: arrival/no-show/complete; reschedule; WhatsApp) — added when their UI ships. No phantom coverage.
- Any change to product (FE/BE) source code without explicit, separate approval (see §9).

## 3. Decisions (locked 2026-06-26)

| # | Decision | Choice |
|---|---|---|
| A | Journey granularity | **Two tiers** — atomic operation-journeys + composite end-to-end flows. |
| B | Verification layers | **Triple-layer, all mandatory** — UI + backend (API **and** invariant DB) + navigation + negative. |
| C | Backend read-back | **Both** — authenticated API for the user-facing contract; direct SQL on the isolated Postgres for invariants the API hides (audit, exact state, capacity, idempotency). |
| D | Journey home & anti-drift | **Structured catalogue co-located in `register-test-suite`** + a build-failing **guard**. |
| E | Coverage & order | **All shipped ops + composites**; Wave 1 core loop → Wave 2 peripheral; exclude unshipped. |
| F | Regression strategy | **Deterministic assertions** are the net; intelligence-diff stays the soft net; **no pixel snapshots** pre-launch. |
| G | Execution model | **Hand-written, reality-grounded** journeys + guard. **No auto-inference** of UI. |
| H | Process | **Iterative** author → run → triage → confirm → re-test, journey by journey. |
| I | Deliverable | Spec → gap-audit of all 6 areas → rewrite (Wave 1, then Wave 2) → verified suite. |

## 4. Journey schema (Bucket A)

A **journey** is a structured, human-readable definition co-located with the test, in the section format the product owner specified (*what's the test case / role / steps / what should happen*), with the "what should happen" formalised into the mandatory layers.

Authored as YAML at `register-test-suite/journeys/<id>.journey.yaml`. `<id>` ties to the existing `OPERATIONS` registry (`src/operations.ts`) for atomic journeys; composite journeys use a `flow.*` id and `chains:` the atomic ids they traverse.

```yaml
id: patient.create                 # atomic → matches OPERATIONS registry
title: Assistant adds a patient
tier: atomic                       # atomic | composite
persona: { role: assistant, archetype: multi }
preconditions:
  - Signed in as assistant in the [E2E] multi-staff clinic
steps:
  - action: patients.openNew       # named page-object action (how to drive the UI)
    expect:
      ui:  Add-patient dialog is visible
      nav: Still on /patients
  - action: patients.fill { name, phone, age }
  - action: patients.submit
    expect:
      ui:  Success card shows {name} + {phone}; dialog closed; NO error toast
      api: GET /patients includes a row with matching name, phone, age
      db:  app_patient_beta has the row (name/phone/age snapshot);
           audit_event_beta has a 'patient.create' row (actor = this assistant)
      nav: Landed back on /patients list
      neg: Did NOT navigate to detail/edit; no duplicate row created
```

Composite example:

```yaml
id: flow.book_approve_confirm
tier: composite
chains: [request.create, request.approve]
persona: { role: owner_doctor, archetype: multi }
preconditions:
  - Doctor has a Mon–Fri availability window; patient [E2E] Asha exists
steps:
  - action: schedule.bookSlotForPatient { doctor: Owner, patient: "[E2E] Asha" }
    expect:
      ui:  Request submitted; success card shown
      db:  request row created, status = pending; audit 'request.create'
  - action: requests.approveByPatient { patient: "[E2E] Asha" }
    expect:
      ui:  Request no longer pending; that patient shows Confirmed
      api: GET /appointments includes a Confirmed appointment for the patient
      db:  request.status = confirmed; appointment row created;
           capacity decremented; audit 'request.approve' (prev=pending,new=confirmed);
           exactly ONE appointment (idempotent — no duplicate)
      nav: On the requests/schedule view, not an error page
      neg: Original request not duplicated; no second appointment
```

**Schema fields**
- `id`, `title`, `tier`, `persona {role, archetype}`, `preconditions[]`, `steps[]`.
- Each `step` has an `action` (a named page-object method + params) and an optional `expect` block.
- `expect` layers: `ui`, `api`, `db`, `nav`, `neg`. Declaring a layer is a **promise that the test asserts it** — enforced by the guard (§6).

## 5. Assertion doctrine (Bucket B) — what "bulletproof" means

1. **Triple-layer mandatory.** Every journey asserts UI + backend (API **and** invariant DB read-back where applicable) + navigation + negative. A persisting operation MUST read back from the backend; an operation that changes state MUST assert the *new state*, not a count.
2. **Honesty rules (kills §1 loopholes).**
   - **No failure-swallowing.** A required element being absent must **fail the test**. The `.catch(() => {})` patterns around success cards / duplicate warnings are removed; their presence becomes a hard assertion (the success card is mandated by Rule 18.5 — assert it, don't tolerate its absence).
   - **No count-only assertions.** Assert the *specific entity* reached the *specific state* (e.g. *this* request → Confirmed + audit row), never "count dropped by one."
   - **Navigation is asserted** on any step where a control moves the user — this is the direct catch for "button → wrong workflow."
   - **Negative assertions** confirm the *wrong* thing did **not** happen (no error toast, no duplicate row, no unexpected navigation).
3. **Backend invariants map to the P0 rails** (`testing/test-rails-v2.md`): `db` expectations cover **Audit** (an `audit_event_beta` row with actor + prev→new state, append-only — Golden Rule §7), **Capacity & Concurrency** (capacity never exceeds config; idempotent — §5.2/§6.4), and **Stale State** (transition validity — §6.1). The suite thereby *enforces* the rails rather than hoping for them.
4. **UX-standards conformance is a verification dimension, not an afterthought.** Every journey's flow is walked against `testing/ux-standards-runbook.md`. Its **[AUTO]** items (success card present per Rule 18.5, destructive-action confirmation, right translated error, touch-target size, visible focus, no false-success, no blocked paste on auth fields) fold into the journey's `ui`/`neg` assertions; its **[HEURISTIC]** items (aesthetic, tone, cross-platform parity) feed the intelligence review and are filed as `[BUG]`. *Deterministically observable → assertion; judged → filed finding; neither is skipped.*

## 6. Catalogue, helpers & the guard (Buckets D, C, F)

**Location.** Journeys live in `register-test-suite/journeys/*.journey.yaml`; tests in `register-test-suite/tests/functional/*.spec.ts`; page-objects in `src/pages/*`. The **methodology** (this spec) lives in the docs repo.

**Backend read-back helpers (new).**
- `src/api/client.ts` (exists) extended with authenticated **GET** read-backs using the role's real JWT against port **8001** — verifies the user-facing contract.
- A new **DB read helper** (`src/db/*`) runs parameterised, read-only SQL against the isolated Postgres on port **5434** (the `_beta` tables: `app_patient_beta`, `audit_event_beta`, request/appointment tables) — verifies invariants the API does not expose. **Read-only**: the harness never mutates via SQL; all mutation goes through the real product (no mocks — README invariant).

**The guard (build-failing, extends the existing `tests-unit/scenarios-guard.test.ts` approach).** A Vitest guard that fails CI when:
1. Any journey `id` has **no matching test**.
2. Any journey declares an `expect` layer with **no corresponding assertion** in its test (assertions are tagged by layer so the guard can verify coverage — e.g. a thin wrapper `expectLayer('db', ...)` the guard greps/AST-checks).
3. Any atomic journey references an **unknown `OPERATIONS` id**, or a shipped op has **no journey** (no silent coverage gaps), reusing `uncoveredOperations()` / `invalidOpRefs()`.
4. Any journey is missing a `Then`-equivalent (`expect`) — extends `scenariosMissingThen()`.

This is the permanent cure for vacuous tests: **a journey cannot claim a check it does not make.**

**Regression net.** The deterministic triple-layer + navigation assertions hard-fail on any behavioural drift, every run. The existing Claude intelligence-diff (`intelligence/e2e-nightly.md`) remains the **soft** net for visual / ease-of-use drift. No pixel snapshots.

## 7. Coverage & waves (Bucket E)

Boundary: **every operation with shipped UI** gets a hardened atomic journey; composite flows chain them. Unshipped ops are excluded (the registry already removed phantom day-of lifecycle ops, 2026-06-23).

- **Wave 1 — core operational loop:** `auth.login_email`, onboarding (`create`/`join`), `owner.add_doctor_profile`, `patient.*`, `request.*`, `availability.add_window`, scheduling/booking, plus composites: `flow.book_approve_confirm`, `flow.book_reject_stays_unconfirmed`, `flow.assistant_cancel_pending`.
- **Wave 2 — peripheral:** `settings.*`, `staff.*`, `clinic.invite_by_email`.
- **Excluded (until UI ships):** arrival / no-show / complete, reschedule, WhatsApp.

## 8. Iterative validation loop (Buckets G, H)

The rewrite is **not a code-dump**. Each journey goes through this loop, one at a time:

1. **Author** the journey grounded in the *real* implemented UI — read the actual component / `data-testid`s first; never assume an element exists. (Motivating example: `/login` defaults to **phone-OTP**, but the phone flow is **not implemented** — a journey authored blind would target a non-existent flow. The login journey routes via **email/password**; the phone-default-leads-nowhere trap is flagged as a candidate UX bug, separately.)
2. **Run** it against the live isolated stack (5434 / 8001 / 3001).
3. **Observe** the real pass/fail output.
4. **Triage** a failure honestly:
   - **Journey/test is wrong** (bad selector, wrong expectation, unimplemented flow) → fix the journey **and report it** (never silent); flag any change to the journey's *intended behaviour* before locking it.
   - **Product has a real bug** (wrong-workflow routing, no persistence, missing audit) → **stop, surface, confirm, file** `[BUG][E2E testing]`. No bending the test to go green.
5. **Re-run → green**, then proceed to the next journey.

**Proof-of-non-theatre:** for each rewritten journey, demonstrate it **fails when the corresponding bug is injected** and passes when correct — evidence the assertion is real, not decorative.

## 9. Governance & guardrails

- **No silent fixes — ever.** Every change is surfaced (what + why).
- **Any product (FE *and* BE) source-code change is confirmed with the user first.** This is the QA/Gatekeeper seat: product bugs are **filed**, not unilaterally patched. Fixes cross into `dentist-registry-frontend` / `dentist-registry-backend` only after explicit go-ahead — never into the `-e2e` clones as a fix target.
- **Reserved ports / isolation:** tests run only on **5434 / 8001 / 3001** (Golden Rule 10.6); dev ports are never touched.
- **`e2e` marker discipline:** all journey data is `[E2E]`-prefixed / `e2e+…` / `-e2e` and torn down (Golden Rule 10.7). DB reads are read-only.
- **No mocks** for product behaviour — real UI, real API, real DB (README invariant; Golden Rule 10.3 mocks are for *unit* tests, not this suite).
- **Docs-repo edits** happen in this git worktree on a feature branch → PR (never `main` directly).

## 10. Acceptance criteria for this effort

- [ ] Journey schema + assertion doctrine documented (this spec) and a working `journeys/*.journey.yaml` format in the suite.
- [ ] Guard test fails the build on: missing test, undeclared/unasserted layer, uncovered shipped op, missing `expect`.
- [ ] Backend read-back helpers (authenticated API GET + read-only DB) in place.
- [ ] Gap-audit of all 6 existing feature areas (patients, requests, scheduling, settings, staff, invites) against the doctrine, cataloguing every loophole.
- [ ] Wave 1 journeys rewritten through the iterative loop; each proven to fail on injected bug.
- [ ] Wave 2 journeys rewritten.
- [ ] All `.catch(() => {})` failure-swallows removed; no count-only assertions remain.
- [ ] Each journey's flow walked against `testing/ux-standards-runbook.md`; [AUTO] items asserted, [HEURISTIC] violations filed.
- [ ] Any product bugs found are filed `[BUG][E2E testing]`; no product code changed without explicit approval.

## 11. Open items (tracked, not blocking the spec)

- Confirm filing of the **phone-OTP-default-but-unimplemented** login trap as a UX bug (separate from the login journey's email routing).
- Confirm the duplicate `data-testid="edit-patient-button"` (noted in `patients-page.ts`) as a FE bug to file.
- Exact tagging mechanism for `expectLayer(...)` so the guard can verify layer coverage (AST vs. runtime registry) — settled in the implementation plan.
