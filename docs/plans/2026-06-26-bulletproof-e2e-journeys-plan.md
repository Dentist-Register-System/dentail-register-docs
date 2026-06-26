# Bulletproof Journey-Mapped E2E Tests — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild the `register-test-suite` E2E suite so a green run is authoritative — every journey verifies UI + backend (API **and** invariant DB) + navigation + negative, vacuous tests are structurally impossible, and every UX flow is checked against the UX Standards Runbook.

**Architecture:** A two-tier **journey catalogue** (`journeys/*.journey.yaml`) co-located in the suite drives hand-written Playwright tests through a thin `journeyTest()` wrapper whose layer-tagged `assert.*` helpers are the assertion points. A **static guard** fails the build if any journey lacks a test or any declared layer lacks an assertion. New **API read-back** (authenticated, as the role) and **read-only DB** helpers verify backend reality. Foundation is built TDD-first (Phase 0); journeys are then rewritten one at a time through an empirical author→run→triage→confirm loop (Phases 1+).

**Tech Stack:** TypeScript, Playwright, Vitest (unit/guard), `pg` (node-postgres, MIT) for DB read-back, `@cucumber/gherkin` (already present) replaced/augmented by a small YAML journey loader (`yaml`, MIT), Zod (already present) for journey schema validation.

## Global Constraints

- **Repo:** all work in `register-test-suite`. Never edit product code (FE/BE) here; product bugs are **filed** `[BUG][E2E testing]` and changes gated on explicit user approval (no silent fixes).
- **Reserved ports — TEST SUITE ONLY:** Postgres **5434**, backend **8001**, frontend **3001**. Never dev ports (5433/8000/3000). (Golden Rule 10.6)
- **`e2e` marker:** all data `[E2E]`-prefixed / `e2e+…@<domain>` / `-e2e`; DB access is **read-only**; teardown owned by the suite. (Golden Rule 10.7)
- **No mocks** for product behaviour — real UI, real API, real DB. (README invariant; Golden Rule 10.3 = mocks are for unit tests only)
- **Permissive-OSS deps only** (MIT/Apache/BSD/ISC). New deps: `pg` (MIT), `yaml` (ISC) — both pass. Never commit secrets.
- **Triple-layer mandatory** per journey: `ui` + `api` + `db` (where the op persists/transitions) + `nav` + `neg`. No failure-swallowing (`.catch(()=>{})`). No count-only assertions.
- **UX bar:** every journey walked against `dentail-register-docs/testing/ux-standards-runbook.md`; [AUTO] items asserted, [HEURISTIC] violations filed.
- **Spec:** `dentail-register-docs/docs/specs/2026-06-26-bulletproof-e2e-journeys-design.md` is the source of truth for this plan.

---

## File structure (created/modified)

**Phase 0 — foundation (new):**
- `src/journeys/schema.ts` — Zod schema + TS types for a journey YAML.
- `src/journeys/loader.ts` — load + validate `journeys/*.journey.yaml`; helpers (`declaredLayers`, `allJourneyIds`).
- `src/journeys/journey-test.ts` — `journeyTest(id, fn)` wrapper + layer-tagged `assert.*` helpers (the assertion points).
- `src/api/as-user.ts` — `tokenFromPage(page)` + `apiAs(page)` → authenticated `ApiClient` for the current role.
- `src/db/client.ts` — read-only `pg` query helper against the 5434 Postgres (`dbQuery`, `dbOne`).
- `tests-unit/journeys-guard.test.ts` — static guard: journey↔test parity + per-layer assertion coverage.
- `tests-unit/no-swallow.test.ts` — honesty guard: bans failure-swallows in `src/pages` + `tests/functional`.
- `src/config.ts` (modify) — add optional `DATABASE_URL`.
- `.env.example` / `.env.prod.example` (modify) — document `DATABASE_URL`.
- `package.json` (modify) — add `pg`, `@types/pg`, `yaml`.

**Phase 1+ — journeys (per journey):**
- `journeys/<id>.journey.yaml` — the journey definition.
- `tests/functional/<area>.spec.ts` (rewrite) — the `journeyTest` implementation.
- `src/pages/*` (modify) — page-object actions, with swallows removed.

**Removed/retired:**
- `scenarios/*.feature` + `src/scenarios/*` + `tests-unit/scenarios-guard.test.ts` + `tests-unit/scenarios-loader.test.ts` — superseded by the journey catalogue once Wave 1 lands (retired in the cleanup task, not before, to keep the build green).

---

## Phase 0 — Foundation (TDD; deterministic; subagent-friendly)

### Task 1: Journey schema + loader

**Files:**
- Create: `src/journeys/schema.ts`, `src/journeys/loader.ts`
- Test: `tests-unit/journeys-loader.test.ts`
- Create (fixture): `tests-unit/fixtures/sample.journey.yaml`

**Interfaces:**
- Produces: `type Journey = { id: string; title: string; tier: "atomic"|"composite"; persona: { role: Role; archetype: "solo"|"multi"|"any" }; preconditions: string[]; chains?: string[]; steps: JourneyStep[] }`; `type JourneyStep = { action: string; expect?: Partial<Record<"ui"|"api"|"db"|"nav"|"neg", string>> }`; `loadJourneys(dir: string): Journey[]`; `declaredLayers(j: Journey): Set<Layer>`; `type Layer = "ui"|"api"|"db"|"nav"|"neg"`.

- [ ] **Step 1: Write the failing test**

```typescript
// tests-unit/journeys-loader.test.ts
import { describe, it, expect } from "vitest";
import { loadJourneys, declaredLayers } from "../src/journeys/loader.js";

describe("journey loader", () => {
  it("loads + validates a journey and reports declared layers", () => {
    const journeys = loadJourneys("tests-unit/fixtures");
    const j = journeys.find((x) => x.id === "sample.create")!;
    expect(j.tier).toBe("atomic");
    expect(j.persona.role).toBe("assistant");
    expect([...declaredLayers(j)].sort()).toEqual(["api", "nav", "neg", "ui"]);
  });

  it("throws on a journey missing required fields", () => {
    expect(() => loadJourneys("tests-unit/fixtures/bad")).toThrow();
  });
});
```

- [ ] **Step 2: Create the fixture**

```yaml
# tests-unit/fixtures/sample.journey.yaml
id: sample.create
title: Sample create
tier: atomic
persona: { role: assistant, archetype: multi }
preconditions:
  - Signed in
steps:
  - action: page.openNew
    expect:
      ui: dialog visible
      nav: still on /x
  - action: page.submit
    expect:
      api: GET /x returns the row
      neg: no error toast
```

- [ ] **Step 3: Run test to verify it fails**

Run: `npm run test:unit -- journeys-loader`
Expected: FAIL ("Cannot find module '../src/journeys/loader.js'").

- [ ] **Step 4: Write the schema**

```typescript
// src/journeys/schema.ts
import { z } from "zod";

export const LAYERS = ["ui", "api", "db", "nav", "neg"] as const;
export type Layer = (typeof LAYERS)[number];

export const JourneyStepSchema = z.object({
  action: z.string().min(1),
  expect: z.partialRecord(z.enum(LAYERS), z.string()).optional(),
});

export const JourneySchema = z.object({
  id: z.string().min(1),
  title: z.string().min(1),
  tier: z.enum(["atomic", "composite"]),
  persona: z.object({
    role: z.enum(["owner_doctor", "doctor", "assistant"]),
    archetype: z.enum(["solo", "multi", "any"]),
  }),
  preconditions: z.array(z.string()).default([]),
  chains: z.array(z.string()).optional(),
  steps: z.array(JourneyStepSchema).min(1),
});

export type Journey = z.infer<typeof JourneySchema>;
export type JourneyStep = z.infer<typeof JourneyStepSchema>;
```

> Note: `z.partialRecord` requires Zod ≥3.23 (verify the installed version; if older, use `z.record(z.enum(LAYERS), z.string()).optional()` and treat missing keys as absent).

- [ ] **Step 5: Write the loader**

```typescript
// src/journeys/loader.ts
import { readFileSync, readdirSync } from "node:fs";
import path from "node:path";
import { parse } from "yaml";
import { JourneySchema, LAYERS, type Journey, type Layer } from "./schema.js";

export function loadJourneys(dir: string): Journey[] {
  return readdirSync(dir)
    .filter((f) => f.endsWith(".journey.yaml"))
    .map((f) => JourneySchema.parse(parse(readFileSync(path.join(dir, f), "utf8"))));
}

export function declaredLayers(j: Journey): Set<Layer> {
  const s = new Set<Layer>();
  for (const step of j.steps)
    for (const l of LAYERS) if (step.expect?.[l]) s.add(l);
  return s;
}

export function allJourneyIds(journeys: Journey[]): string[] {
  return journeys.map((j) => j.id);
}
```

- [ ] **Step 6: Install deps**

Run: `npm install yaml && npm install -D @types/node`
Expected: `yaml` (ISC) added. (Confirm license in `node_modules/yaml/package.json`.)

- [ ] **Step 7: Add the `bad` fixture (missing `steps`)**

```yaml
# tests-unit/fixtures/bad/broken.journey.yaml
id: broken
title: Broken
tier: atomic
persona: { role: assistant, archetype: any }
```

- [ ] **Step 8: Run test to verify it passes**

Run: `npm run test:unit -- journeys-loader && npm run typecheck`
Expected: PASS (2 tests), typecheck clean.

- [ ] **Step 9: Commit**

```bash
git add src/journeys/schema.ts src/journeys/loader.ts tests-unit/journeys-loader.test.ts tests-unit/fixtures package.json package-lock.json
git commit -m "feat(journeys): journey YAML schema + loader"
```

---

### Task 2: `journeyTest` wrapper + layer-tagged assertions

**Files:**
- Create: `src/journeys/journey-test.ts`
- Test: exercised via the guard (Task 3) + first real journey (Phase 1); no unit test (needs a browser).

**Interfaces:**
- Consumes: Playwright `test` from `src/fixtures/metrics.ts` (the `measure` fixture).
- Produces: `journeyTest(id: string, fn: (ctx: { page: Page; measure: Measure; api: () => Promise<ApiClient>; assert: LayerAsserts }) => Promise<void>): void`; `type LayerAsserts = { ui(label: string, fn: () => Promise<void>): Promise<void>; api(...); db(...); nav(...); neg(...) }`. Each `assert.<layer>` runs `fn` (which performs the real Playwright/API/DB expectation) and records that the layer was asserted for this `id`.

- [ ] **Step 1: Implement the wrapper**

```typescript
// src/journeys/journey-test.ts
import { test, expect } from "../fixtures/metrics.js";
import type { Page } from "@playwright/test";
import { apiAs } from "../api/as-user.js";
import type { ApiClient } from "../api/client.js";
import type { Layer } from "./schema.js";

// Layer-tagged assertion runner. The label is for trace readability; fn does the
// actual assertion. Calling it is what the static guard counts as "this layer is
// asserted" — but fn MUST contain a real expect()/throw (enforced by review + the
// no-swallow guard), never an empty body.
export type LayerAsserts = Record<Layer, (label: string, fn: () => Promise<void>) => Promise<void>>;

function makeAsserts(): LayerAsserts {
  const run = (layer: Layer) => async (label: string, fn: () => Promise<void>) => {
    await test.step(`[${layer}] ${label}`, fn);
  };
  return { ui: run("ui"), api: run("api"), db: run("db"), nav: run("nav"), neg: run("neg") };
}

export function journeyTest(
  id: string,
  fn: (ctx: {
    page: Page;
    measure: (op: string, f: () => Promise<void>) => Promise<void>;
    api: () => Promise<ApiClient>;
    assert: LayerAsserts;
    expect: typeof expect;
  }) => Promise<void>,
): void {
  test(`journey:${id}`, async ({ page, measure }) => {
    await fn({ page, measure, api: () => apiAs(page), assert: makeAsserts(), expect });
  });
}

export { expect };
```

> The guard (Task 3) verifies layer coverage **statically** by parsing for `assert.<layer>(` inside each `journeyTest("<id>", …)` block — so the wrapper's job is only to (a) name the test `journey:<id>` and (b) expose the tagged `assert.*` API the guard recognises.

- [ ] **Step 2: Typecheck**

Run: `npm run typecheck`
Expected: PASS (will fail until Task 4 `apiAs` exists — implement Task 4 first or stub the import). **Order: do Task 4 before Step 2 here**, or temporarily `// @ts-expect-error` the import and resolve in Task 4.

- [ ] **Step 3: Commit**

```bash
git add src/journeys/journey-test.ts
git commit -m "feat(journeys): journeyTest wrapper + layer-tagged assert API"
```

---

### Task 3: Static honesty/parity guard

**Files:**
- Create: `tests-unit/journeys-guard.test.ts`
- Create: `src/journeys/guard.ts` (pure functions, unit-testable)
- Test: `tests-unit/journeys-guard.unit.test.ts`

**Interfaces:**
- Consumes: `loadJourneys`, `declaredLayers` (Task 1); `OPERATIONS` (`src/operations.ts`).
- Produces: `parseTestCoverage(testDir: string): Map<string, Set<Layer>>` (journeyId → layers asserted, parsed statically from `journeyTest`/`assert.*` usage); `journeysWithoutTest(journeys, coverage): string[]`; `layerGaps(journeys, coverage): {id: string; missing: Layer[]}[]`; `unknownJourneyTests(journeys, coverage): string[]`.

- [ ] **Step 1: Write the failing unit test for the parser**

```typescript
// tests-unit/journeys-guard.unit.test.ts
import { describe, it, expect } from "vitest";
import { layerGaps, journeysWithoutTest } from "../src/journeys/guard.js";
import type { Journey } from "../src/journeys/schema.js";

const j: Journey = {
  id: "x.create", title: "X", tier: "atomic",
  persona: { role: "assistant", archetype: "any" }, preconditions: [],
  steps: [{ action: "a", expect: { ui: "u", api: "a", neg: "n" } }],
};

describe("journey guard logic", () => {
  it("flags a declared layer with no assertion", () => {
    const cov = new Map([["x.create", new Set(["ui", "api"] as const)]]);
    expect(layerGaps([j], cov)).toEqual([{ id: "x.create", missing: ["neg"] }]);
  });
  it("flags a journey with no test at all", () => {
    expect(journeysWithoutTest([j], new Map())).toEqual(["x.create"]);
  });
});
```

- [ ] **Step 2: Run to verify it fails**

Run: `npm run test:unit -- journeys-guard.unit`
Expected: FAIL (module missing).

- [ ] **Step 3: Implement the guard logic + static parser**

```typescript
// src/journeys/guard.ts
import { readFileSync, readdirSync } from "node:fs";
import path from "node:path";
import { LAYERS, type Layer, type Journey } from "./schema.js";
import { declaredLayers } from "./loader.js";

// Static parse: for each `journeyTest("<id>", …)` block, collect which
// `assert.<layer>(` calls appear before the block's matching close. Block
// boundaries are found by brace-depth scan from the journeyTest call site.
export function parseTestCoverage(testDir: string): Map<string, Set<Layer>> {
  const out = new Map<string, Set<Layer>>();
  const files = walk(testDir).filter((f) => f.endsWith(".spec.ts"));
  for (const file of files) {
    const src = readFileSync(file, "utf8");
    const re = /journeyTest\(\s*["'`]([^"'`]+)["'`]/g;
    let m: RegExpExecArray | null;
    while ((m = re.exec(src))) {
      const id = m[1];
      const block = sliceBlock(src, re.lastIndex);
      const layers = new Set<Layer>();
      for (const l of LAYERS)
        if (new RegExp(`assert\\.${l}\\(`).test(block)) layers.add(l);
      out.set(id, new Set([...(out.get(id) ?? []), ...layers]));
    }
  }
  return out;
}

// From the char after the journeyTest id, find the enclosing arg list's end by
// brace/paren depth; return the block text.
function sliceBlock(src: string, from: number): string {
  let depth = 0, started = false, i = from;
  for (; i < src.length; i++) {
    const c = src[i];
    if (c === "(" || c === "{") { depth++; started = true; }
    else if (c === ")" || c === "}") { depth--; if (started && depth <= 0) break; }
  }
  return src.slice(from, i);
}

function walk(dir: string): string[] {
  return readdirSync(dir, { withFileTypes: true }).flatMap((e) =>
    e.isDirectory() ? walk(path.join(dir, e.name)) : [path.join(dir, e.name)],
  );
}

export function journeysWithoutTest(journeys: Journey[], cov: Map<string, Set<Layer>>): string[] {
  return journeys.filter((j) => !cov.has(j.id)).map((j) => j.id);
}

export function layerGaps(journeys: Journey[], cov: Map<string, Set<Layer>>): { id: string; missing: Layer[] }[] {
  const gaps: { id: string; missing: Layer[] }[] = [];
  for (const j of journeys) {
    const declared = declaredLayers(j);
    const asserted = cov.get(j.id) ?? new Set<Layer>();
    const missing = [...declared].filter((l) => !asserted.has(l));
    if (missing.length) gaps.push({ id: j.id, missing });
  }
  return gaps;
}

export function unknownJourneyTests(journeys: Journey[], cov: Map<string, Set<Layer>>): string[] {
  const ids = new Set(journeys.map((j) => j.id));
  return [...cov.keys()].filter((id) => !ids.has(id));
}
```

- [ ] **Step 4: Run unit test to verify it passes**

Run: `npm run test:unit -- journeys-guard.unit`
Expected: PASS.

- [ ] **Step 5: Write the build-failing guard test**

```typescript
// tests-unit/journeys-guard.test.ts
import { describe, it, expect } from "vitest";
import { loadJourneys } from "../src/journeys/loader.js";
import { parseTestCoverage, journeysWithoutTest, layerGaps, unknownJourneyTests } from "../src/journeys/guard.js";

const journeys = loadJourneys("journeys");
const coverage = parseTestCoverage("tests/functional");

describe("journey ↔ test parity (the anti-vacuous-test guard)", () => {
  it("every journey has a journeyTest", () => {
    expect(journeysWithoutTest(journeys, coverage)).toEqual([]);
  });
  it("every declared expect-layer is asserted in its test", () => {
    expect(layerGaps(journeys, coverage)).toEqual([]);
  });
  it("no journeyTest references an unknown journey id", () => {
    expect(unknownJourneyTests(journeys, coverage)).toEqual([]);
  });
});
```

- [ ] **Step 6: Create an empty `journeys/.gitkeep`** so the guard runs green on an empty catalogue until Phase 1 adds the first journey.

Run: `mkdir -p journeys && touch journeys/.gitkeep && npm run test:unit -- journeys-guard`
Expected: PASS (0 journeys → no gaps).

- [ ] **Step 7: Commit**

```bash
git add src/journeys/guard.ts tests-unit/journeys-guard.test.ts tests-unit/journeys-guard.unit.test.ts journeys/.gitkeep
git commit -m "feat(journeys): static honesty/parity guard (journey↔test + layer coverage)"
```

---

### Task 4: Authenticated API read-back helper

**Files:**
- Create: `src/api/as-user.ts`
- Test: `tests-unit/as-user.test.ts` (unit-test `tokenKey` + token extraction logic with a fake page)

**Interfaces:**
- Consumes: `ApiClient` (`src/api/client.ts`); `loadConfig` (`src/config.ts`) for `backendBaseUrl` + `supabaseUrl`.
- Produces: `tokenFromPage(page: Pick<Page, "evaluate">): Promise<string>`; `apiAs(page): Promise<ApiClient>`; `projectRef(supabaseUrl: string): string`.

- [ ] **Step 1: Write the failing unit test**

```typescript
// tests-unit/as-user.test.ts
import { describe, it, expect } from "vitest";
import { projectRef } from "../src/api/as-user.js";

describe("as-user", () => {
  it("derives the Supabase project ref from the URL", () => {
    expect(projectRef("https://wxwasnshmnttiixvzeod.supabase.co")).toBe("wxwasnshmnttiixvzeod");
  });
});
```

- [ ] **Step 2: Run to verify it fails**

Run: `npm run test:unit -- as-user`
Expected: FAIL (module missing).

- [ ] **Step 3: Implement**

```typescript
// src/api/as-user.ts
import type { Page } from "@playwright/test";
import { ApiClient } from "./client.js";
import { loadConfig } from "../config.js";

export function projectRef(supabaseUrl: string): string {
  return new URL(supabaseUrl).hostname.split(".")[0];
}

// Supabase-js stores the session under localStorage key `sb-<ref>-auth-token`
// as JSON containing { access_token, ... }.
export async function tokenFromPage(page: Pick<Page, "evaluate">): Promise<string> {
  const cfg = loadConfig();
  const key = `sb-${projectRef(cfg.supabaseUrl)}-auth-token`;
  const raw = await page.evaluate((k) => window.localStorage.getItem(k), key);
  if (!raw) throw new Error(`no Supabase session in localStorage under ${key}`);
  const token = JSON.parse(raw)?.access_token;
  if (!token) throw new Error(`no access_token in ${key}`);
  return token;
}

export async function apiAs(page: Page): Promise<ApiClient> {
  const cfg = loadConfig();
  return new ApiClient(cfg.backendBaseUrl, await tokenFromPage(page));
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `npm run test:unit -- as-user && npm run typecheck`
Expected: PASS; typecheck clean (also unblocks Task 2's import).

- [ ] **Step 5: Commit**

```bash
git add src/api/as-user.ts tests-unit/as-user.test.ts
git commit -m "feat(api): authenticated as-user API read-back helper"
```

---

### Task 5: Read-only DB helper

**Files:**
- Create: `src/db/client.ts`
- Modify: `src/config.ts` (add optional `DATABASE_URL`), `.env.example`, `.env.prod.example`
- Test: `tests-unit/db-client.test.ts` (guards the read-only assertion + missing-URL error; no real DB in unit tests)

**Interfaces:**
- Produces: `dbQuery<T>(sql: string, params?: unknown[]): Promise<T[]>`; `dbOne<T>(sql: string, params?: unknown[]): Promise<T | null>`; both throw if `DATABASE_URL` is unset or if `sql` is not a single read-only statement.

- [ ] **Step 1: Write the failing test**

```typescript
// tests-unit/db-client.test.ts
import { describe, it, expect } from "vitest";
import { assertReadOnly } from "../src/db/client.js";

describe("db read-only guard", () => {
  it("allows a SELECT", () => {
    expect(() => assertReadOnly("SELECT * FROM app_patient_beta WHERE id = $1")).not.toThrow();
  });
  it("rejects a mutation", () => {
    expect(() => assertReadOnly("DELETE FROM app_patient_beta")).toThrow(/read-only/i);
    expect(() => assertReadOnly("UPDATE x SET y=1")).toThrow(/read-only/i);
    expect(() => assertReadOnly("SELECT 1; DROP TABLE x")).toThrow(/single/i);
  });
});
```

- [ ] **Step 2: Run to verify it fails**

Run: `npm run test:unit -- db-client`
Expected: FAIL (module missing).

- [ ] **Step 3: Install `pg` (MIT)**

Run: `npm install pg && npm install -D @types/pg`
Expected: added. (Confirm MIT in `node_modules/pg/package.json`.)

- [ ] **Step 4: Implement**

```typescript
// src/db/client.ts
import { Pool } from "pg";

let pool: Pool | undefined;

function getPool(): Pool {
  const url = process.env.DATABASE_URL;
  if (!url) throw new Error("DATABASE_URL is not set (DB read-back unavailable in this env)");
  pool ??= new Pool({ connectionString: url, max: 2 });
  return pool;
}

export function assertReadOnly(sql: string): void {
  const trimmed = sql.trim().replace(/;+\s*$/, "");
  if (trimmed.includes(";")) throw new Error("DB read helper accepts a single statement only");
  if (!/^(select|with)\b/i.test(trimmed)) throw new Error("DB read helper is read-only (SELECT/WITH only)");
}

export async function dbQuery<T>(sql: string, params: unknown[] = []): Promise<T[]> {
  assertReadOnly(sql);
  const res = await getPool().query(sql, params as never[]);
  return res.rows as T[];
}

export async function dbOne<T>(sql: string, params: unknown[] = []): Promise<T | null> {
  const rows = await dbQuery<T>(sql, params);
  return rows[0] ?? null;
}

export async function closeDb(): Promise<void> {
  await pool?.end();
  pool = undefined;
}
```

- [ ] **Step 5: Add `DATABASE_URL` to config + env examples**

In `src/config.ts` add to the Zod schema: `DATABASE_URL: z.string().default(""),` and to `Config` + `parseConfig`: `databaseUrl: p.DATABASE_URL`. In `.env.example` add:

```bash
# Read-only DB read-back for journey `db` assertions (local/beta only).
# Isolated E2E Postgres on port 5434. Driver: standard pg (no +psycopg here).
DATABASE_URL=postgresql://postgres:postgres@localhost:5434/register_e2e
```

- [ ] **Step 6: Run to verify it passes**

Run: `npm run test:unit -- db-client && npm run typecheck`
Expected: PASS; typecheck clean.

- [ ] **Step 7: Commit**

```bash
git add src/db/client.ts src/config.ts .env.example .env.prod.example tests-unit/db-client.test.ts package.json package-lock.json
git commit -m "feat(db): read-only pg read-back helper + DATABASE_URL config"
```

---

### Task 6: Honesty guard — ban failure-swallowing

**Files:**
- Create: `tests-unit/no-swallow.test.ts`

**Interfaces:**
- Produces: a Vitest test that scans `src/pages/**` and `tests/functional/**` for swallow patterns and fails listing offenders.

- [ ] **Step 1: Write the guard**

```typescript
// tests-unit/no-swallow.test.ts
import { describe, it, expect } from "vitest";
import { readFileSync, readdirSync } from "node:fs";
import path from "node:path";

function walk(dir: string): string[] {
  return readdirSync(dir, { withFileTypes: true }).flatMap((e) =>
    e.isDirectory() ? walk(path.join(dir, e.name)) : [path.join(dir, e.name)],
  );
}

// Bans patterns that let a missing/failed element pass silently:
//   .catch(() => {})   .catch(() => false)   .catch(() => true)   .catch(() => undefined)
const SWALLOW = /\.catch\(\s*\(\s*[\w]*\s*\)\s*=>\s*(\{\s*\}|false|true|undefined|null)\s*\)/;

describe("honesty: no failure-swallowing in journeys/pages", () => {
  const files = [...walk("src/pages"), ...walk("tests/functional")].filter((f) => f.endsWith(".ts"));
  it("contains no swallowed catches", () => {
    const offenders = files.filter((f) => SWALLOW.test(readFileSync(f, "utf8")));
    expect(offenders, `swallowed catches found in:\n${offenders.join("\n")}`).toEqual([]);
  });
});
```

- [ ] **Step 2: Run — expect it to FAIL against current code (proves it works)**

Run: `npm run test:unit -- no-swallow`
Expected: FAIL, listing `src/pages/patients-page.ts` (the `.catch(() => false)` / `.catch(() => {})` swallows). **This failure is correct** — it's the loophole. It will be cleared as pages are rewritten in Phase 1+. Mark the test `it.fails(...)` is NOT acceptable; instead, **skip enforcement until Wave 1 page rewrites** by scoping the scan to rewritten files via an allowlist comment, OR land this task AFTER the first page rewrite. **Decision:** land Task 6 immediately but scope `files` to `tests/functional` only first; add `src/pages` to the scan in the Wave 1 cleanup task once swallows are removed. (Document this in the commit.)

- [ ] **Step 3: Commit**

```bash
git add tests-unit/no-swallow.test.ts
git commit -m "feat(guard): ban failure-swallowing (scoped to tests; pages added post-Wave-1)"
```

---

## Phase 1 — First journey end-to-end (prove the loop)

### Task 7: `auth.login_email` journey — the worked template

This task establishes the **per-journey loop** every later journey repeats. Login is first because every other journey's session depends on it.

**Files:**
- Create: `journeys/auth.login_email.journey.yaml`
- Rewrite: `tests/functional/auth.spec.ts` (new; uses `journeyTest`)
- Reference (do not edit): `src/pages/login-page.ts` (already switches off the default Phone tab to Email)

**Interfaces:**
- Consumes: `journeyTest` (Task 2), `apiAs` (Task 4); `LoginPage.loginWithEmail`.

- [ ] **Step 1: Author the journey YAML (grounded in the real login UI)**

```yaml
# journeys/auth.login_email.journey.yaml
id: auth.login_email
title: Log in with email and password
tier: atomic
persona: { role: assistant, archetype: multi }
preconditions:
  - A seeded [E2E] assistant user exists with a known password
steps:
  - action: login.loginWithEmail { email, password }
    expect:
      ui:  Authenticated shell (clinic-shell) is visible
      api: GET /api/v1/me returns the signed-in user (needs_onboarding false; a membership present)
      nav: URL is "/" (the app root), not /login
      neg: No auth error is shown; not stuck on /login
```

- [ ] **Step 2: Write the journey test**

```typescript
// tests/functional/auth.spec.ts
import { journeyTest, expect } from "../../src/journeys/journey-test.js";
import { LoginPage } from "../../src/pages/login-page.js";
import { readManifest } from "../../src/seed/manifest.js";

journeyTest("auth.login_email", async ({ page, assert, api }) => {
  // Pick a seeded assistant from the run manifest (real credentials, no mocks).
  const manifest = readManifest(process.env.RUN_DIR!);
  const user = manifest.users.find((u) => u.role === "assistant")!;
  const login = new LoginPage(page);

  await login.loginWithEmail(user.email, process.env.TEST_USER_PASSWORD!);

  await assert.ui("clinic shell visible", async () => {
    await expect(page.getByTestId("clinic-shell")).toBeVisible();
  });
  await assert.nav("landed on app root, not /login", async () => {
    await expect(page).toHaveURL(/\/$/);
  });
  await assert.api("GET /me returns the signed-in user", async () => {
    const client = await api();
    const me = await client.get<{ needs_onboarding: boolean; memberships: unknown[] }>("/api/v1/me");
    expect(me.needs_onboarding).toBe(false);
    expect(me.memberships.length).toBeGreaterThan(0);
  });
  await assert.neg("no auth error visible", async () => {
    await expect(page.getByTestId("login-error")).toHaveCount(0);
  });
});
```

> The exact `/me` response shape and the `login-error` testid are **assumptions to verify on first run** (Step 4). If they differ, fix the journey/test (report it), or if the product misbehaves, file `[BUG]`.

- [ ] **Step 3: Bring up the isolated stack**

Run (see README): start backend-e2e on **8001** against the **5434** DB, frontend-e2e on **3001**, then seed:
```bash
npx tsx pipeline/run.ts --env local   # seeds + runs; or run stack-up.sh + seed-once.ts for an interactive loop
```
Expected: stack healthy on 5434/8001/3001; manifest written to `RUN_DIR`.

- [ ] **Step 4: Run the journey against the live stack**

Run: `RUN_DIR=<run> npm run pw -- tests/functional/auth.spec.ts`
Expected: PASS — **or** a real failure to triage.

- [ ] **Step 5: Triage (the loop's core)**
  - **Test/journey wrong** (e.g., `/me` shape differs, `login-error` testid differs, URL not `/`): fix the journey/test, **report the change**, re-run. Never loosen an assertion to force green.
  - **Product bug** (e.g., login routes to the wrong screen, `/me` says `needs_onboarding` wrongly): **stop, surface, confirm with the user, file `[BUG][E2E testing]`**. No product code edited without approval.

- [ ] **Step 6: Run the guard — confirm the journey is covered**

Run: `npm run test:unit -- journeys-guard`
Expected: PASS (declared layers ui/api/nav/neg all asserted; journey has a test).

- [ ] **Step 7: Prove it's not theatre (inject-the-bug check)**

Temporarily break one assertion's premise (e.g., point `loginWithEmail` at a wrong password locally, or assert `needs_onboarding` true) and confirm the journey **FAILS**; then revert. Record the evidence (paste the failing output into the PR).

- [ ] **Step 8: Commit**

```bash
git add journeys/auth.login_email.journey.yaml tests/functional/auth.spec.ts
git commit -m "test(journey): auth.login_email — triple-layer, proven to fail on injected bug"
```

---

## Phase 2 — Wave 1 (core operational loop), one journey at a time

> **These tasks are NOT pre-scripted with exact assertions.** Per the spec's iterative model, each journey's real assertions are discovered by running against the live app (the `auth` task is the worked template). Pre-writing fake assertions for unrun flows would be dishonest and is forbidden. Each task below = **one application of the Task 7 loop**: author YAML → write `journeyTest` (triple-layer) → run live → triage (fix-and-report / file-bug-and-confirm) → guard green → inject-bug proof → commit.

**Before Wave 1, do the gap-audit (Task 8). Then journeys (Tasks 9–N).**

### Task 8: Gap-audit of the existing suite

**Files:** Create `journeys/AUDIT.md` (a findings catalogue; not shipped to product).

- [ ] **Step 1:** For each existing area (`patients`, `requests`, `scheduling`, `settings`, `staff`, `invites`), list every current test and grade it against the doctrine: which layers are missing, which assertions are count-only, which swallow failures, which lack nav/neg. Cite `file:line`.
- [ ] **Step 2:** Map each shipped `OPERATIONS` id → the atomic journey it needs + which composite flows it participates in.
- [ ] **Step 3:** List candidate product bugs surfaced by the audit (e.g., the phone-OTP-default-leads-nowhere login trap; the duplicate `data-testid="edit-patient-button"`). These are **filed on user confirmation**, not silently.
- [ ] **Step 4:** Commit `journeys/AUDIT.md`. This catalogue orders the rest of Wave 1.

### Tasks 9–N: Wave 1 journeys (each = one Task-7 loop)

Author + rewrite, in this order (atomic first, then the composites that chain them):

1. `onboarding.create_clinic`, `onboarding.join_clinic`
2. `owner.add_doctor_profile`
3. `patient.create`, `patient.edit`, `patient.delete` (remove the `dismissSuccess`/duplicate-warning swallows in `patients-page.ts`; assert the success card per Rule 18.5; DB read-back `app_patient_beta` + `audit_event_beta`)
4. `request.create`, `request.approve`, `request.reject`, `request.cancel` (replace count-only asserts: assert the **specific** request's new state + `audit_event_beta` prev→new + appointment row + capacity on approve)
5. `availability.add_window`
6. Composites: `flow.book_approve_confirm`, `flow.book_reject_stays_unconfirmed`, `flow.assistant_cancel_pending`

Each task’s checklist mirrors Task 7 Steps 1–8. For every journey, also walk the UX Standards Runbook [AUTO] items into `ui`/`neg` (success card present, destructive-action confirmation, right translated error, no false success, touch-target/focus where observable) and file [HEURISTIC] violations.

### Task (cleanup): retire scenarios + widen the no-swallow scan

- [ ] Remove `scenarios/*.feature`, `src/scenarios/*`, `tests-unit/scenarios-guard.test.ts`, `tests-unit/scenarios-loader.test.ts` (superseded once every Wave 1 op has a journey).
- [ ] Widen `tests-unit/no-swallow.test.ts` to include `src/pages` (now swallow-free); run — expect PASS.
- [ ] Update `pipeline/run.ts` if it references the retired scenario loader; run the full pipeline `npx tsx pipeline/run.ts --env local` green.
- [ ] Commit.

---

## Phase 3 — Wave 2 (peripheral), one journey at a time

Same loop, for: `settings.update_profile`, `settings.update_preferences`, `settings.update_clinic`, `staff.edit_member`, `staff.deactivate_member`, `clinic.invite_by_email`.

---

## Self-review (run before handing off)

- **Spec coverage:** Buckets A (schema → Tasks 1–2, 7), B (doctrine → Tasks 2,3,6,7), C (API+DB → Tasks 4,5), D (catalogue+guard → Tasks 1,3), E (waves → Tasks 8–N, Phase 3), F (deterministic regression → assertions in every journey), G (hand-written + guard → all journey tasks), H (iterative loop → Task 7 template + Phase 2/3), UX runbook (every journey task). ✔ all mapped.
- **No placeholders in foundation tasks:** all code shown. Phase 2/3 journey tasks deliberately carry the **procedure** not fake assertions — justified by the empirical model (documented at the top of Phase 2).
- **Type consistency:** `Journey`/`JourneyStep`/`Layer` (Task 1) used consistently in Tasks 2,3; `apiAs`/`tokenFromPage` (Task 4) consumed in Task 2,7; `dbQuery`/`dbOne` (Task 5) used in Wave 1 db asserts; `journeyTest`/`assert.*` (Task 2) used by the guard (Task 3) and all journeys.

## Acceptance (mirrors the spec §10)

- [ ] Journey YAML schema + loader + guard live; build fails on missing test / unasserted declared layer / unknown journey id.
- [ ] API + read-only DB read-back helpers in place.
- [ ] `journeys/AUDIT.md` catalogues every loophole across the 6 areas.
- [ ] Wave 1 journeys rewritten via the loop; each proven to fail on an injected bug.
- [ ] Wave 2 journeys rewritten.
- [ ] All `.catch(()=>{})` swallows removed; `no-swallow` guard covers `src/pages` + `tests/functional`; no count-only assertions remain.
- [ ] Each journey walked against the UX Standards Runbook; [AUTO] asserted, [HEURISTIC] filed.
- [ ] Product bugs filed `[BUG][E2E testing]`; no product code changed without explicit approval.
