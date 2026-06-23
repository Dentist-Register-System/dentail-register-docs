# Gherkin Scenario Specs — Implementation Plan (#114)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Gherkin `.feature` journey specs + a typed loader so the nightly intelligence can triage failures (real-bug / test-fault / flaky / dependency-outage) using documented behavioral contracts, and inject that context into bug bodies (fuels #113).

**Architecture:** Gherkin `.feature` files under `register-test-suite/scenarios/` are the readable contract. A pure loader (`src/scenarios/`) parses them with `@cucumber/gherkin` (MIT) into a typed model indexed by `@op:` operationId. Playwright stays the native runner — nothing about test execution or the ease-metrics fixtures changes. The intelligence step (`intelligence/e2e-nightly.md`) consumes scenarios at triage time; `FailureAnalysis` gains a classification + scenario excerpt rendered in the email + bug body.

**Tech Stack:** TypeScript · `@cucumber/gherkin` (MIT) + `@cucumber/messages` (MIT) · Vitest. Spec: `docs/specs/2026-06-23-gherkin-scenario-specs-design.md`.

## Global Constraints
- Repo: `register-test-suite`; all work on branch `feat/scenario-specs` (never `main`; remote `github-personal`; commit email `rohan2jos@gmail.com`; commits end with the Co-Authored-By trailer). PR via `gh-personal`.
- **Three Claude sessions share these repos — use branches/worktrees; never touch a shared repo's checked-out tree or `main` directly.**
- Permissive-OSS only: `@cucumber/gherkin` + `@cucumber/messages` are MIT (document in README per Golden Rule 3.4).
- **Parser-only:** do NOT add Cucumber/playwright-bdd execution. Playwright remains the native runner; the ease-metrics `measure()` fixture, captured-APIs, and `storageState` are untouched.
- Tag taxonomy: `@op:<operationId>`, `@dep:<name>` (`supabase-auth`|`backend`|`frontend`|`resend`), `@role:<owner_doctor|doctor|assistant>`. Scenarios inherit feature-level tags.

## File Structure
```
register-test-suite/
  scenarios/                      # Gherkin .feature journeys (one per domain)
    patients.feature
    invites.feature
  src/scenarios/
    types.ts                      # Scenario + ScenarioStep types + DEPENDENCIES taxonomy
    loader.ts                     # parse .feature -> Scenario[]; indexes; coverage helper
  tests-unit/
    scenarios-loader.test.ts      # parse a fixture feature -> assert ops/deps/role/steps
    scenarios-guard.test.ts       # consistency: valid @op/@dep, every scenario has a Then
  src/report/types.ts             # FailureAnalysis += classification, scenario
  src/report/render.ts            # failure card shows classification + scenario excerpt
  intelligence/e2e-nightly.md     # triage consumes scenarios
  README.md                       # dependency table + scenarios note
```

---

## Task 1: Gherkin loader + types + first feature

**Files:**
- Modify: `package.json` (add deps)
- Create: `src/scenarios/types.ts`, `src/scenarios/loader.ts`, `scenarios/patients.feature`
- Test: `tests-unit/scenarios-loader.test.ts`

**Interfaces:**
- Consumes: `Role` from `src/seed/manifest.js`.
- Produces:
  - `type ScenarioStep = { keyword: string; text: string }` (keyword is the trimmed Gherkin keyword, e.g. `"Given"`, `"When"`, `"Then"`, `"And"`).
  - `type Scenario = { feature: string; name: string; role?: Role; operationIds: string[]; dependencies: string[]; steps: ScenarioStep[] }`.
  - `parseFeature(text: string): Scenario[]` — parse one feature file's text.
  - `loadScenarios(dir: string): Scenario[]` — parse every `*.feature` in `dir`.
  - `byOperationId(scenarios: Scenario[]): Map<string, Scenario[]>`.

- [ ] **Step 1: Install deps**

```bash
cd ~/Documents/register_workspace/register-test-suite
npm install @cucumber/gherkin @cucumber/messages
```
Confirm both resolve to MIT (they are). Do not add any other dependency.

- [ ] **Step 2: Create the fixture feature `scenarios/patients.feature`**

```gherkin
@role:assistant
Feature: Manage patients
  So that the clinic register is accurate, an assistant adds, edits, and removes patients.

  @op:patient.create @dep:backend @dep:frontend
  Scenario: Assistant adds a patient
    Given an assistant is signed in to their clinic
    When they open the patients page and add a patient with name and phone
    Then the new patient appears in the patients list

  @op:patient.edit @dep:backend @dep:frontend
  Scenario: Assistant edits a patient
    Given a patient exists in the clinic
    When the assistant opens the patient and changes the name
    Then the updated name appears in the patients list

  @op:patient.delete @dep:backend @dep:frontend
  Scenario: Assistant deletes a patient
    Given a patient exists in the clinic
    When the assistant deletes the patient and confirms
    Then the patient no longer appears in the patients list
```

- [ ] **Step 3: Write the failing test `tests-unit/scenarios-loader.test.ts`**

```ts
import { describe, it, expect } from "vitest";
import { parseFeature, loadScenarios, byOperationId } from "../src/scenarios/loader.js";

const FEATURE = `@role:assistant
Feature: Manage patients
  Narrative line.

  @op:patient.create @dep:backend @dep:frontend
  Scenario: Assistant adds a patient
    Given an assistant is signed in
    When they add a patient
    Then the new patient appears in the list
`;

describe("scenario loader", () => {
  it("parses feature + scenario tags, role, ops, deps, and steps", () => {
    const [s] = parseFeature(FEATURE);
    expect(s.feature).toBe("Manage patients");
    expect(s.name).toBe("Assistant adds a patient");
    expect(s.role).toBe("assistant");                 // inherited from feature tag
    expect(s.operationIds).toEqual(["patient.create"]);
    expect(s.dependencies.sort()).toEqual(["backend", "frontend"]);
    expect(s.steps.map((x) => x.keyword)).toEqual(["Given", "When", "Then"]);
    expect(s.steps[2].text).toContain("appears");
  });
  it("loadScenarios reads the scenarios/ dir and byOperationId indexes them", () => {
    const all = loadScenarios("scenarios");
    expect(all.length).toBeGreaterThanOrEqual(3);
    const idx = byOperationId(all);
    expect(idx.get("patient.create")?.length).toBeGreaterThanOrEqual(1);
  });
});
```

- [ ] **Step 4: Run it — verify FAIL** — `npm run test:unit` → fails (no loader module).

- [ ] **Step 5: Implement `src/scenarios/types.ts`**

```ts
import type { Role } from "../seed/manifest.js";

export const DEPENDENCIES = ["supabase-auth", "backend", "frontend", "resend"] as const;
export type Dependency = (typeof DEPENDENCIES)[number];

export type ScenarioStep = { keyword: string; text: string };
export type Scenario = {
  feature: string;
  name: string;
  role?: Role;
  operationIds: string[];
  dependencies: string[];
  steps: ScenarioStep[];
};
```

- [ ] **Step 6: Implement `src/scenarios/loader.ts`**

```ts
import { readFileSync, readdirSync } from "node:fs";
import path from "node:path";
import { Parser, AstBuilder, GherkinClassicTokenMatcher } from "@cucumber/gherkin";
import { IdGenerator } from "@cucumber/messages";
import type { Role } from "../seed/manifest.js";
import type { Scenario, ScenarioStep } from "./types.js";

function newParser(): Parser<unknown> {
  return new Parser(new AstBuilder(IdGenerator.uuid()), new GherkinClassicTokenMatcher());
}

function tagValues(tags: readonly { name: string }[], prefix: string): string[] {
  return tags
    .map((t) => t.name)
    .filter((n) => n.startsWith(prefix))
    .map((n) => n.slice(prefix.length));
}

export function parseFeature(text: string): Scenario[] {
  const doc = newParser().parse(text) as {
    feature?: {
      name: string;
      tags: { name: string }[];
      children: { scenario?: { name: string; tags: { name: string }[]; steps: { keyword: string; text: string }[] } }[];
    };
  };
  const feature = doc.feature;
  if (!feature) return [];
  const featureTags = feature.tags ?? [];
  const out: Scenario[] = [];
  for (const child of feature.children) {
    const sc = child.scenario;
    if (!sc) continue;
    const tags = [...featureTags, ...(sc.tags ?? [])];
    const role = tagValues(tags, "@role:")[0] as Role | undefined;
    const steps: ScenarioStep[] = sc.steps.map((s) => ({ keyword: s.keyword.trim(), text: s.text.trim() }));
    out.push({
      feature: feature.name,
      name: sc.name,
      role,
      operationIds: tagValues(tags, "@op:"),
      dependencies: tagValues(tags, "@dep:"),
      steps,
    });
  }
  return out;
}

export function loadScenarios(dir: string): Scenario[] {
  const files = readdirSync(dir).filter((f) => f.endsWith(".feature"));
  return files.flatMap((f) => parseFeature(readFileSync(path.join(dir, f), "utf8")));
}

export function byOperationId(scenarios: Scenario[]): Map<string, Scenario[]> {
  const m = new Map<string, Scenario[]>();
  for (const s of scenarios) for (const op of s.operationIds) {
    m.set(op, [...(m.get(op) ?? []), s]);
  }
  return m;
}
```
> Note: `@cucumber/gherkin`'s `parse` returns a `GherkinDocument`; `step.keyword` includes a trailing space (e.g. `"Given "`) — `.trim()` handles it. `And`/`But` keep their literal keyword (don't normalize — the intelligence reads them as prose).

- [ ] **Step 7: Run — verify PASS** — `npm run test:unit` → all pass. `npm run typecheck` → 0.
- [ ] **Step 8: Commit** — `git commit -am "feat(scenarios): @cucumber/gherkin loader + patients.feature"`

---

## Task 2: Consistency guard + coverage helper

**Files:**
- Modify: `src/scenarios/loader.ts` (add helpers)
- Test: `tests-unit/scenarios-guard.test.ts`

**Interfaces:**
- Consumes: `loadScenarios`, `Scenario` (Task 1); `OPERATIONS` from `src/operations.js`; `DEPENDENCIES` from `src/scenarios/types.js`.
- Produces:
  - `invalidOpRefs(scenarios, validOpIds: Set<string>): string[]` — `@op` ids that aren't real operations.
  - `invalidDepRefs(scenarios): string[]` — `@dep` values not in `DEPENDENCIES`.
  - `scenariosMissingThen(scenarios): string[]` — scenario names with no `Then` step.
  - `uncoveredOperations(scenarios, allOpIds: string[]): string[]` — operations with no `@op:` scenario (coverage report, NOT a failing assertion — authoring is incremental per the spec).

- [ ] **Step 1: Write failing test `tests-unit/scenarios-guard.test.ts`**

```ts
import { describe, it, expect } from "vitest";
import { loadScenarios, invalidOpRefs, invalidDepRefs, scenariosMissingThen } from "../src/scenarios/loader.js";
import { OPERATIONS } from "../src/operations.js";

const scenarios = loadScenarios("scenarios");
const validOps = new Set(OPERATIONS.map((o) => o.id));

describe("scenario consistency", () => {
  it("every @op tag references a real operation", () => {
    expect(invalidOpRefs(scenarios, validOps)).toEqual([]);
  });
  it("every @dep tag is in the known taxonomy", () => {
    expect(invalidDepRefs(scenarios)).toEqual([]);
  });
  it("every scenario has at least one Then", () => {
    expect(scenariosMissingThen(scenarios)).toEqual([]);
  });
});
```

- [ ] **Step 2: Run — verify FAIL.**

- [ ] **Step 3: Implement the helpers in `src/scenarios/loader.ts`**

```ts
import { DEPENDENCIES } from "./types.js";

export function invalidOpRefs(scenarios: Scenario[], validOpIds: Set<string>): string[] {
  return [...new Set(scenarios.flatMap((s) => s.operationIds).filter((op) => !validOpIds.has(op)))];
}
export function invalidDepRefs(scenarios: Scenario[]): string[] {
  const known = new Set<string>(DEPENDENCIES);
  return [...new Set(scenarios.flatMap((s) => s.dependencies).filter((d) => !known.has(d)))];
}
export function scenariosMissingThen(scenarios: Scenario[]): string[] {
  return scenarios.filter((s) => !s.steps.some((st) => st.keyword === "Then")).map((s) => s.name);
}
export function uncoveredOperations(scenarios: Scenario[], allOpIds: string[]): string[] {
  const covered = new Set(scenarios.flatMap((s) => s.operationIds));
  return allOpIds.filter((id) => !covered.has(id));
}
```
(`And`/`But` after a `Then` still count as `Then`-context for humans, but the guard only requires an explicit `Then` keyword — keep it strict + simple.)

- [ ] **Step 4: Run — verify PASS** (with `scenarios/patients.feature` present, all three lists are empty). `npm run typecheck` → 0.
- [ ] **Step 5: Commit** — `git commit -am "feat(scenarios): consistency guard + coverage helper"`

---

## Task 3: Author the invite journey + register the operation

**Files:**
- Create: `scenarios/invites.feature`
- Modify: `src/operations.ts` (add `clinic.invite_by_email` if absent)

**Interfaces:**
- Consumes: the `Operation` type + `OPERATIONS` array (`src/operations.ts`).
- Produces: a multi-role journey feature; ensures all its `@op:` tags resolve (keeps Task 2's guard green).

- [ ] **Step 1: Ensure operations exist** — open `src/operations.ts`. `onboarding.join_clinic` already exists. Add `clinic.invite_by_email` if not present:
```ts
{ id: "clinic.invite_by_email", label: "Invite a teammate by email", role: "owner_doctor", archetype: "multi", idealClicks: 5, idealScreens: 3 },
```

- [ ] **Step 2: Create `scenarios/invites.feature`** (the user's journey — spans owner + invited user):
```gherkin
Feature: Invite a teammate
  So that a clinic can grow its staff, an owner invites a teammate who then joins and works.

  @op:clinic.invite_by_email @role:owner_doctor @dep:backend @dep:resend
  Scenario: Owner invites a teammate by email
    Given an owner is signed in to their clinic
    When they complete the guided invite flow with a teammate's email
    Then the invitation is created
    And an invitation email is sent

  @op:onboarding.join_clinic @role:assistant @dep:supabase-auth @dep:backend @dep:frontend
  Scenario: Invited teammate joins via the link
    Given a valid invitation link for the clinic
    When the invited user opens the link
    Then they see sign-up with the clinic name pre-filled
    And after signing up they land in the clinic and can create a schedule
```

- [ ] **Step 3: Run guard** — `npm run test:unit` (Task 2's `invalidOpRefs` stays empty → `clinic.invite_by_email` + `onboarding.join_clinic` are valid). `npm run typecheck` → 0.
- [ ] **Step 4: Commit** — `git commit -am "feat(scenarios): invite journey + clinic.invite_by_email op"`

> More `.feature` files (requests lifecycle, scheduling, settings, staff) are authored alongside Tasks 12c–f as those specs are built — each new flow ships with its scenario.

---

## Task 4: Scenario-aware triage (types + render + intelligence + README)

**Files:**
- Modify: `src/report/types.ts`, `src/report/render.ts`, `tests-unit/render.test.ts`, `intelligence/e2e-nightly.md`, `README.md`

**Interfaces:**
- Consumes: `FailureAnalysis` (Task-15 block), `renderHtml` (`src/report/render.ts`), the loader (Task 1).
- Produces: `FailureAnalysis` with `classification?` + `scenario?`; render shows them.

- [ ] **Step 1: Extend `FailureAnalysis` in `src/report/types.ts`**
```ts
export type FailureClassification = "real-bug" | "test-fault" | "flaky" | "dependency-outage";
export type FailureAnalysis = {
  title: string; operationId?: string;
  whatFailed: string; reason: string; expected: string; actual: string;
  suspectedCause: string; possibleFix: string; bugUrl?: string;
  classification?: FailureClassification;   // NEW
  scenario?: string;                        // NEW: matched Gherkin excerpt (feature › scenario + steps)
};
```

- [ ] **Step 2: Render the new fields — failing test in `tests-unit/render.test.ts`**

Add to the existing failures-section test an `intelligence.failures` entry with `classification: "dependency-outage"` and `scenario: "Manage patients › Assistant adds a patient"`, then:
```ts
expect(html).toContain("dependency-outage");
expect(html).toContain("Manage patients › Assistant adds a patient");
```
Run `npm run test:unit` → FAIL (render doesn't emit them yet).

- [ ] **Step 3: Update `renderFailureCard` in `src/report/render.ts`** to add two labelled rows when present (escape via `esc()`):
```ts
// inside the failure card's <tbody>, after the existing rows:
${f.classification ? `<tr><td><strong>Classification</strong></td><td>${esc(f.classification)}</td></tr>` : ""}
${f.scenario ? `<tr><td><strong>Scenario</strong></td><td>${esc(f.scenario)}</td></tr>` : ""}
```
Run `npm run test:unit` → PASS. `npm run typecheck` → 0.

- [ ] **Step 4: Update `intelligence/e2e-nightly.md`** — in the regression/triage step, add:
> Load scenarios with `loadScenarios("scenarios")` + `byOperationId`. For each real failure, look up the scenario by the failing test's `operationId`. Classify the failure as one of **real-bug** (outcome contradicts a documented `Then`), **test-fault** (selector/step drifted from the scenario, no product change), **flaky** (intermittent across the trend), or **dependency-outage** (a step's `@dep` shows 5xx/timeout in the captured network/errors). Set `FailureAnalysis.classification` + `FailureAnalysis.scenario` (the `feature › scenario` + key steps), and include both in the email failure card AND the filed bug body (fuels #113).

- [ ] **Step 5: Update `README.md`** — add `@cucumber/gherkin` (MIT) and `@cucumber/messages` (MIT) to the dependency table with purpose "parse Gherkin scenario specs for the intelligence"; add a one-line "Scenario specs" note under the layout (`scenarios/*.feature` + `src/scenarios/`).

- [ ] **Step 6: Commit** — `git commit -am "feat(scenarios): scenario-aware failure triage (types, render, intel, README)"`

---

## Task 5: PR
- [ ] `npm run typecheck && npm run test:unit` green. Open PR via `gh-personal` (base `main`, head `feat/scenario-specs`), title `feat(scenarios): Gherkin scenario specs + intelligent triage (#114)`, body links spec/plan + `Closes Dentist-Register-System/dentail-register-docs#114`. Final whole-branch review (opus) before merge; never merge red.

---

## Self-Review (plan vs spec)
- Spec §2 (granularity=journeys, format=Gherkin, parser-only, MIT) → Tasks 1, 3; Global Constraints. ✅
- Spec §3 (tags @op/@dep/@role, feature example) → Task 1 (feature) + loader tag parsing; Task 3 (invite journey). ✅
- Spec §4 (loader: loadScenarios/byOperationId, typed model) → Task 1. ✅
- Spec §5 (intelligence triage + classification + bug body) → Task 4 (types/render/e2e-nightly.md). ✅
- Spec §6 (consistency guard) → Task 2 (valid @op/@dep, has-Then) + `uncoveredOperations` coverage helper (spec's "every op has a scenario" → coverage report, since authoring is incremental). ✅
- Spec §7 (MIT dep documented; loader/guard unit-tested; no Playwright change) → Tasks 1/2/4 + README. ✅
- Spec §8 (no Cucumber execution; incremental authoring) → Global Constraints + Task 3 note. ✅
- Placeholder scan: loader/guard/types/feature carry full code; e2e-nightly.md + README are prose edits with exact content. No TBD. ✅
- Type consistency: `Scenario`/`ScenarioStep`/`Dependency`/`FailureClassification`/`FailureAnalysis` names consistent across tasks; loader fns (`parseFeature`/`loadScenarios`/`byOperationId`/`invalidOpRefs`/`invalidDepRefs`/`scenariosMissingThen`/`uncoveredOperations`) used consistently. ✅
