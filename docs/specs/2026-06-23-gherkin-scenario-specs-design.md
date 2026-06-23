# Gherkin Scenario Specs → Intelligent Failure Triage — Design Spec (#114)

**Status:** Approved (brainstorm 2026-06-23). Enhancement to the E2E + intelligence harness (`register-test-suite`, spec `2026-06-22-e2e-intelligence-harness-design.md`, #103). No product code; harness-only.
**Type:** Add human-readable **Gherkin `.feature` journey specs** as a living-documentation/contract layer that the nightly Claude intelligence uses to **triage failures** (test-fault / flaky / real-bug / dependency-outage) and to **enrich bug bodies** (fuel for the 9 AM auto-remediation loop, #113). Playwright stays the native runner.

## 1. Goal
Today the nightly intelligence infers *intent* from spec code. Give every user journey an explicit, readable behavioral contract (Given/When/Then) plus its external **dependencies**, so failure triage becomes precise: distinguish a stale test from a real product regression from a dependency outage — and write that context into the filed bug so the 9 AM loop (#113) can act on it.

## 2. Scope decisions (locked in brainstorm)
- **Granularity = journeys built from operation steps.** A scenario is a multi-step user journey (may span roles), each step optionally linked to an existing operation in the registry. Atomic operations are 1-step journeys.
- **Format = Gherkin `.feature`** (industry-standard, readable; BDD / Specification-by-Example / living-documentation).
- **Depth = parser-only living docs.** Playwright remains the **native** test runner — the ease-metrics `measure()` fixture, captured-APIs, and per-role `storageState` stay on `@playwright/test`. We add ONLY `@cucumber/gherkin` (MIT) to parse `.feature` files into data for the intelligence. **No Cucumber/playwright-bdd execution path** (it would complicate the fixtures that are the harness's core value).
- **Licensing:** `@cucumber/gherkin` is MIT — permissive, no fee/copyleft trap (Golden Rule 3.1, [[open-source-license-vetting]]).

## 3. Gherkin structure + tags
One `.feature` per domain/journey under `register-test-suite/scenarios/`. Tags wire each scenario/step to the harness:
- `@op:<operationId>` — links to the operation registry (`src/operations.ts`) → its ease score + live-captured APIs.
- `@dep:<name>` — external dependency the step relies on: `supabase-auth`, `backend`, `frontend`, `resend` (future: `google-calendar`, `whatsapp`).
- `@role:<role>` — `owner_doctor` | `doctor` | `assistant`.

Example (`scenarios/invites.feature`):
```gherkin
@role:owner_doctor
Feature: Invite a teammate
  So that a clinic can add staff, an owner invites a teammate who then joins.

  @op:clinic.invite_by_email @dep:backend @dep:resend
  Scenario: Owner invites a teammate by email
    Given an owner is signed in to their clinic
    When they complete the guided invite flow with a teammate's email
    Then the invitation is created
    And an invitation email is sent

  @op:onboarding.join_clinic @dep:supabase-auth @dep:backend
  Scenario: Invited user joins via the link
    Given a valid invitation link
    When the invited user opens it
    Then they see sign-up with the clinic name pre-filled
    And after signing up they land in that clinic and can create a schedule
```

## 4. Loader (`src/scenarios/loader.ts`)
- `loadScenarios(dir): Scenario[]` — parse every `scenarios/*.feature` with `@cucumber/gherkin` into a typed model:
  `Scenario = { feature: string; name: string; role?: Role; operationIds: string[]; dependencies: string[]; steps: { keyword: "Given"|"When"|"Then"|"And"|"But"; text: string }[] }`.
- `byOperationId(scenarios): Map<string, Scenario[]>` and `byName(...)` indexes for fast lookup at triage time.
- Tag parsing: collect `@op:`, `@dep:`, `@role:` from feature + scenario level (scenario inherits feature tags).
- Pure/deterministic → **Vitest-unit-tested** (parse a sample feature → assert extracted ops/deps/steps).

## 5. Intelligence consumption (update `intelligence/e2e-nightly.md`)
During failure triage, for each failure:
1. Resolve its scenario via the failing test's `operationId`/title (loader index).
2. Classify using the scenario + run data:
   - **Real bug** — the system produced an outcome that contradicts a documented **Then**.
   - **Test fault** — the failing step's selector/expectation drifted from the documented behavior (no product change).
   - **Flaky** — intermittent across the trend, though the scenario is deterministic.
   - **Dependency outage** — a step's `@dep` shows 5xx/timeout in the captured network/errors (e.g. `supabase-auth` 503) → not a product bug.
3. Put the matched Gherkin excerpt + classification into the email **failure card** and the filed **bug body** (so #113 inherits full context). Extends the existing `FailureAnalysis` (add `scenario` + `classification` fields).

## 6. Consistency guard (Vitest, pure)
- `tests-unit/scenarios.test.ts`: every operation in `OPERATIONS` is referenced by ≥1 `@op:` step; every `@dep:` is from the known taxonomy; every scenario has at least one `Then`.
- (Deferred v2) reconcile a scenario's declared APIs against the live-captured `apis.json` for that operation.

## 7. Quality
- New dep: `@cucumber/gherkin` (MIT) — documented in README dependency table (Golden Rule 3.4).
- Loader + guard unit-tested (Vitest); no Playwright execution change; `npm run typecheck` clean.
- Playwright remains the runner; ease-metrics/captured-APIs/storageState untouched.
- Authoring: seed `.feature` files for the flows we have/are building (patients, request→approve→complete lifecycle, the invite journey); more added as specs grow.

## 8. Scope guards / deferred
- **No Cucumber/playwright-bdd execution** — parser-only; scenarios are documentation + triage context, not a second test runner.
- Declared-API ↔ captured-API reconciliation: v2.
- Rendering `.feature` as a styled HTML doc site: out of scope (the files are readable as-is).
- Authoring scenarios for *every* screen up front: incremental — scenarios accompany the flows as they're built (pairs with Tasks 12–14).

## 9. Self-review (against the request)
- Human-readable step-by-step journey specs (the invite example): §3 (Gherkin journeys). ✅
- Industry standard: §2 (BDD/Gherkin/Specification-by-Example), §2 licensing (MIT). ✅
- Deterministic spec the intelligence uses to classify test-fault / flaky / real-bug / dependency-outage: §5. ✅
- Dependency-outage detection via `@dep` tags + captured errors: §3/§5. ✅
- Feeds bug bodies for the 9 AM loop (#113): §5. ✅
- No Playwright disruption / ease-metrics preserved (user's priority): §2/§7. ✅
- No licensing/fee trap: §2 (MIT). ✅
- Placeholder scan: concrete tags/loader types/feature example/guard; no TBD (v2 items explicitly deferred). ✅
