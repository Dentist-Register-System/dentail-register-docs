# Daily E2E + Intelligence Testing Harness — Implementation Plan (#103)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `register-test-suite` — a standalone, never-deployed repo that seeds two clinic archetypes via the real API, drives the product exhaustively with Playwright (no mocks), and runs daily via Claude `/loop` to detect regressions, score per-operation ease-of-use, file deduped `[BUG][E2E testing]` issues, and email an HTML report.

**Architecture:** A deterministic TypeScript pipeline (`tsx pipeline/run.ts`) does the mechanical work — seed → login → run Playwright suites → capture artifacts → generate base HTML → prune → teardown. A separate daily Claude `/loop` session runs the pipeline, then does judgment-only work (regression analysis, ease index, bug filing, email, trend-store commit). Pure logic is unit-tested with Vitest (TDD); Playwright specs are integration-tested against real local services.

**Tech Stack:** TypeScript · Playwright (`@playwright/test`, Apache-2.0) · Vitest (MIT) · `@supabase/supabase-js` (MIT) · `resend` (MIT) · `tsx` (MIT) · `zod` (MIT). Node ≥ 20.

**Spec:** `docs/specs/2026-06-22-e2e-intelligence-harness-design.md`. Read it before starting.

## Global Constraints

- **Repo:** `register-test-suite` (org `Dentist-Register-System`), cloned at `~/Documents/register_workspace/register-test-suite`, remote `github-personal`, commit email `rohan2jos@gmail.com`. Never deployed.
- **Git:** never commit to `main` directly — feature branch → PR via `gh-personal`. The trend store commits to a dedicated `e2e-history` branch (data only), never `main`.
- **No mocks in e2e:** seed and Playwright specs make real calls (real backend, DB, Supabase auth). Mocks are allowed ONLY in Vitest unit tests of pure logic.
- **Permissive-OSS only** (MIT/Apache/BSD/ISC). Document every non-trivial dep in `README.md` (name, purpose, license).
- **Secrets:** all credentials via gitignored `.env.<env>`; never commit secrets. `.env.example` documents the shape.
- **Synthetic-data marking:** every seeded entity carries an `[E2E]` name prefix and a `e2e+<runId>@<TEST_EMAIL_DOMAIN>` email namespace. Teardown deletes only `[E2E]`-marked data.
- **Prod safety:** when `--env prod`, the runner hard-refuses any mutating spec; only the read-only smoke project runs. Never mutate prod.
- **Backend base path:** all backend endpoints are mounted under `/api/v1` (e.g. `POST /api/v1/clinics`).
- **AI is advisory** (Golden Rule 1.4): Claude files issues and writes reports for humans; it never changes product state.

---

## File Structure

```
register-test-suite/
  package.json, tsconfig.json, vitest.config.ts, playwright.config.ts
  .gitignore, .env.example, README.md
  src/
    config.ts              # env loader + zod validation + prod-safety flag
    operations.ts          # Operation Registry (id → label, role, archetype, idealPath)
    api/
      client.ts            # typed fetch wrapper (bearer auth + error-envelope parse)
    seed/
      supabase-admin.ts    # create/delete pre-confirmed users (service-role)
      archetypes.ts        # solo + multi-staff builders (API-driven)
      manifest.ts          # per-run manifest read/write (users, clinic ids)
      index.ts             # seed() + teardown() orchestration
    fixtures/
      metrics.ts           # Playwright fixture: per-operation interaction metrics
      metrics-core.ts      # pure aggregation (unit-tested)
    pages/
      base-page.ts         # POM base
      login-page.ts, onboarding-page.ts, home-page.ts,
      patients-page.ts, requests-page.ts, my-schedule-page.ts,
      clinic-schedules-page.ts, doctors-page.ts, assistants-page.ts,
      settings-page.ts, design-system-page.ts
    report/
      render.ts            # pure results+metrics → base HTML (unit-tested)
      report-core.ts       # pure summary/derivation helpers
    trend/
      store.ts             # read/write committed trend store
      diff.ts              # day-over-day regression diff (unit-tested)
      fingerprint.ts       # stable failure fingerprint + bug-dedup match (unit-tested)
    email/
      send.ts              # Resend send (+ Mailtrap toggle)
      email-core.ts        # pure subject/text/html composition (unit-tested)
    prune/
      prune.ts             # retention policy (unit-tested) + fs apply
  tests/
    auth.setup.ts          # log in each role via real UI → storageState
    functional/            # exhaustive specs, tagged by operationId
    sweep/i18n-theme.spec.ts
    smoke/prod-smoke.spec.ts
  pipeline/
    run.ts                 # deterministic orchestrator
  intelligence/
    e2e-nightly.md         # the Claude /loop instructions (regression/ease/bugs/email)
  runs/                    # (gitignored) raw artifacts
  tests-unit/              # Vitest unit tests for pure logic
```

---

## Task 1: Repo scaffold + tooling

**Files:**
- Create: `package.json`, `tsconfig.json`, `vitest.config.ts`, `playwright.config.ts`, `.gitignore`, `.env.example`, `README.md`
- Test: `tests-unit/smoke.test.ts`

**Interfaces:**
- Produces: npm scripts `test:unit` (vitest), `pw` (playwright test), `e2e` (tsx pipeline/run.ts), `typecheck` (tsc --noEmit).

- [ ] **Step 1: Initialize the repo on a feature branch**

```bash
cd ~/Documents/register_workspace/register-test-suite
git remote -v   # MUST show github-personal; abort if not
git config user.email   # MUST be rohan2jos@gmail.com
git checkout -b feat/harness-foundation
```

- [ ] **Step 2: Create `package.json`**

```json
{
  "name": "register-test-suite",
  "version": "0.1.0",
  "private": true,
  "type": "module",
  "engines": { "node": ">=20" },
  "scripts": {
    "typecheck": "tsc --noEmit",
    "test:unit": "vitest run",
    "pw": "playwright test",
    "e2e": "tsx pipeline/run.ts"
  },
  "devDependencies": {
    "@playwright/test": "^1.48.0",
    "@types/node": "^22.0.0",
    "tsx": "^4.19.0",
    "typescript": "^5.6.0",
    "vitest": "^2.1.0"
  },
  "dependencies": {
    "@supabase/supabase-js": "^2.45.0",
    "resend": "^4.0.0",
    "zod": "^3.23.0"
  }
}
```

- [ ] **Step 3: Create `tsconfig.json`, `vitest.config.ts`, `playwright.config.ts`, `.gitignore`, `.env.example`**

`tsconfig.json`:
```json
{
  "compilerOptions": {
    "target": "ES2022", "module": "ES2022", "moduleResolution": "bundler",
    "strict": true, "esModuleInterop": true, "skipLibCheck": true,
    "resolveJsonModule": true, "noEmit": true, "types": ["node"]
  },
  "include": ["src", "tests", "tests-unit", "pipeline"]
}
```

`vitest.config.ts`:
```ts
import { defineConfig } from "vitest/config";
export default defineConfig({ test: { include: ["tests-unit/**/*.test.ts"] } });
```

`playwright.config.ts` (projects wired in later tasks; start minimal):
```ts
import { defineConfig } from "@playwright/test";
export default defineConfig({
  testDir: "tests",
  reporter: [["json", { outputFile: "runs/_pw-report.json" }], ["line"]],
  use: { trace: "retain-on-failure", screenshot: "only-on-failure", video: "retain-on-failure" },
});
```

`.gitignore`:
```
node_modules/
runs/
.env
.env.local
.env.beta
.env.prod
test-results/
playwright-report/
```

`.env.example`:
```
ENV=local
FRONTEND_BASE_URL=http://localhost:3000
BACKEND_BASE_URL=http://localhost:8000
SUPABASE_URL=
SUPABASE_ANON_KEY=
SUPABASE_SERVICE_ROLE_KEY=
TEST_EMAIL_DOMAIN=e2e.example.com
TEST_USER_PASSWORD=
RESEND_API_KEY=
REPORT_EMAIL_TO=rohan2jos@gmail.com
EMAIL_PROVIDER=resend          # resend | mailtrap | none
RETAIN_RUNS=14                 # keep last N runs of raw artifacts
RETAIN_FAILURE_RUNS=60         # keep failure artifacts longer
```

- [ ] **Step 4: Write the failing smoke unit test**

`tests-unit/smoke.test.ts`:
```ts
import { describe, it, expect } from "vitest";
describe("toolchain", () => {
  it("runs vitest", () => { expect(1 + 1).toBe(2); });
});
```

- [ ] **Step 5: Install, run, verify it passes**

Run:
```bash
npm install
npx playwright install chromium
npm run test:unit
```
Expected: 1 passed. `npm run typecheck` exits 0.

- [ ] **Step 6: Write README skeleton and commit**

README documents: purpose, "never deployed / run locally", commands, env setup, and the dependency table (Playwright Apache-2.0; supabase-js, resend, zod, vitest, tsx MIT).

```bash
git add -A
git commit -m "chore: scaffold register-test-suite (toolchain, config, env)"
```

---

## Task 2: Env config loader + prod safety

**Files:**
- Create: `src/config.ts`
- Test: `tests-unit/config.test.ts`

**Interfaces:**
- Produces: `loadConfig(argv?: string[]): Config` where
  `Config = { env: "local"|"beta"|"prod"; frontendBaseUrl: string; backendBaseUrl: string; supabaseUrl: string; supabaseAnonKey: string; supabaseServiceRoleKey: string; testEmailDomain: string; testUserPassword: string; resendApiKey: string; reportEmailTo: string; emailProvider: "resend"|"mailtrap"|"none"; retainRuns: number; retainFailureRuns: number; allowMutation: boolean }`.
  `allowMutation === (env !== "prod")`.

- [ ] **Step 1: Write failing tests**

`tests-unit/config.test.ts`:
```ts
import { describe, it, expect } from "vitest";
import { parseConfig } from "../src/config.js";

const base = {
  ENV: "local", FRONTEND_BASE_URL: "http://localhost:3000",
  BACKEND_BASE_URL: "http://localhost:8000", SUPABASE_URL: "https://x.supabase.co",
  SUPABASE_ANON_KEY: "anon", SUPABASE_SERVICE_ROLE_KEY: "svc",
  TEST_EMAIL_DOMAIN: "e2e.example.com", TEST_USER_PASSWORD: "pw",
  RESEND_API_KEY: "re_x", REPORT_EMAIL_TO: "a@b.com",
  EMAIL_PROVIDER: "resend", RETAIN_RUNS: "14", RETAIN_FAILURE_RUNS: "60",
};

describe("parseConfig", () => {
  it("parses a valid local env", () => {
    const c = parseConfig(base);
    expect(c.env).toBe("local");
    expect(c.allowMutation).toBe(true);
    expect(c.retainRuns).toBe(14);
  });
  it("sets allowMutation=false for prod", () => {
    expect(parseConfig({ ...base, ENV: "prod" }).allowMutation).toBe(false);
  });
  it("throws when a required var is missing", () => {
    const { SUPABASE_URL, ...rest } = base;
    expect(() => parseConfig(rest as any)).toThrow();
  });
});
```

- [ ] **Step 2: Run, verify FAIL** — `npm run test:unit` → fails (no `parseConfig`).

- [ ] **Step 3: Implement `src/config.ts`**

```ts
import { z } from "zod";

const Schema = z.object({
  ENV: z.enum(["local", "beta", "prod"]),
  FRONTEND_BASE_URL: z.string().url(),
  BACKEND_BASE_URL: z.string().url(),
  SUPABASE_URL: z.string().url(),
  SUPABASE_ANON_KEY: z.string().min(1),
  SUPABASE_SERVICE_ROLE_KEY: z.string().min(1),
  TEST_EMAIL_DOMAIN: z.string().min(1),
  TEST_USER_PASSWORD: z.string().min(1),
  RESEND_API_KEY: z.string().default(""),
  REPORT_EMAIL_TO: z.string().email(),
  EMAIL_PROVIDER: z.enum(["resend", "mailtrap", "none"]).default("none"),
  RETAIN_RUNS: z.coerce.number().int().positive().default(14),
  RETAIN_FAILURE_RUNS: z.coerce.number().int().positive().default(60),
});

export type Config = {
  env: "local" | "beta" | "prod";
  frontendBaseUrl: string; backendBaseUrl: string;
  supabaseUrl: string; supabaseAnonKey: string; supabaseServiceRoleKey: string;
  testEmailDomain: string; testUserPassword: string;
  resendApiKey: string; reportEmailTo: string;
  emailProvider: "resend" | "mailtrap" | "none";
  retainRuns: number; retainFailureRuns: number; allowMutation: boolean;
};

export function parseConfig(raw: Record<string, string | undefined>): Config {
  const p = Schema.parse(raw);
  return {
    env: p.ENV, frontendBaseUrl: p.FRONTEND_BASE_URL, backendBaseUrl: p.BACKEND_BASE_URL,
    supabaseUrl: p.SUPABASE_URL, supabaseAnonKey: p.SUPABASE_ANON_KEY,
    supabaseServiceRoleKey: p.SUPABASE_SERVICE_ROLE_KEY,
    testEmailDomain: p.TEST_EMAIL_DOMAIN, testUserPassword: p.TEST_USER_PASSWORD,
    resendApiKey: p.RESEND_API_KEY, reportEmailTo: p.REPORT_EMAIL_TO,
    emailProvider: p.EMAIL_PROVIDER, retainRuns: p.RETAIN_RUNS,
    retainFailureRuns: p.RETAIN_FAILURE_RUNS, allowMutation: p.ENV !== "prod",
  };
}

export function loadConfig(argv: string[] = process.argv): Config {
  const envFlag = argv.find((a) => a.startsWith("--env="))?.split("=")[1]
    ?? (argv.includes("--env") ? argv[argv.indexOf("--env") + 1] : undefined);
  const env = envFlag ?? process.env.ENV ?? "local";
  // .env.<env> is loaded by the pipeline before calling loadConfig (see Task 16).
  return parseConfig({ ...process.env, ENV: env });
}
```

- [ ] **Step 4: Run, verify PASS** — `npm run test:unit` → all pass.

- [ ] **Step 5: Commit** — `git add -A && git commit -m "feat(config): env loader with zod validation + prod-safety flag"`

---

## Task 3: Typed API client

**Files:**
- Create: `src/api/client.ts`
- Test: `tests-unit/api-client.test.ts`

**Interfaces:**
- Produces: `class ApiClient { constructor(baseUrl: string, token?: string); setToken(t: string): void; get<T>(path: string): Promise<T>; post<T>(path: string, body: unknown): Promise<T>; patch<T>(path: string, body: unknown): Promise<T>; del(path: string): Promise<void> }`. Throws `ApiError { code: string; message: string; status: number }` parsed from the backend envelope `{ error: { code, message, details } }`.

- [ ] **Step 1: Write failing tests** (mock `fetch`)

`tests-unit/api-client.test.ts`:
```ts
import { describe, it, expect, vi } from "vitest";
import { ApiClient, ApiError } from "../src/api/client.js";

function mockFetch(status: number, body: unknown) {
  return vi.fn(async () => ({ status, ok: status < 400,
    json: async () => body, text: async () => JSON.stringify(body) })) as any;
}

describe("ApiClient", () => {
  it("attaches bearer token and parses JSON", async () => {
    global.fetch = mockFetch(200, { id: "c1" });
    const c = new ApiClient("http://b", "tok");
    const r = await c.get<{ id: string }>("/api/v1/clinics/c1");
    expect(r.id).toBe("c1");
    const call = (global.fetch as any).mock.calls[0];
    expect(call[1].headers.Authorization).toBe("Bearer tok");
  });
  it("throws ApiError with code from envelope", async () => {
    global.fetch = mockFetch(403, { error: { code: "forbidden", message: "no" } });
    const c = new ApiClient("http://b", "tok");
    await expect(c.get("/x")).rejects.toMatchObject({ code: "forbidden", status: 403 });
  });
});
```

- [ ] **Step 2: Run, verify FAIL.**

- [ ] **Step 3: Implement `src/api/client.ts`**

```ts
export class ApiError extends Error {
  constructor(public code: string, message: string, public status: number) { super(message); }
}

export class ApiClient {
  constructor(private baseUrl: string, private token?: string) {}
  setToken(t: string) { this.token = t; }

  private async req<T>(method: string, path: string, body?: unknown): Promise<T> {
    const headers: Record<string, string> = { "Content-Type": "application/json" };
    if (this.token) headers.Authorization = `Bearer ${this.token}`;
    const res = await fetch(`${this.baseUrl}${path}`, {
      method, headers, body: body === undefined ? undefined : JSON.stringify(body),
    });
    if (res.status === 204) return undefined as T;
    const text = await res.text();
    const json = text ? JSON.parse(text) : undefined;
    if (!res.ok) {
      const e = json?.error ?? {};
      throw new ApiError(e.code ?? "unknown", e.message ?? res.statusText, res.status);
    }
    return json as T;
  }
  get<T>(p: string) { return this.req<T>("GET", p); }
  post<T>(p: string, b: unknown) { return this.req<T>("POST", p, b); }
  patch<T>(p: string, b: unknown) { return this.req<T>("PATCH", p, b); }
  async del(p: string) { await this.req<void>("DELETE", p); }
}
```

- [ ] **Step 4: Run, verify PASS.**
- [ ] **Step 5: Commit** — `git commit -am "feat(api): typed client with bearer auth + error-envelope parsing"`

---

## Task 4: Supabase admin — user provisioning + teardown

**Files:**
- Create: `src/seed/supabase-admin.ts`
- Test: `tests-unit/supabase-admin.test.ts`

**Interfaces:**
- Produces: `createTestUser(admin, { email, password }): Promise<{ id: string; email: string }>` (email pre-confirmed), `deleteTestUser(admin, userId): Promise<void>`, `makeAdmin(cfg): SupabaseClient`. `admin` is the supabase-js client created with the service-role key.

- [ ] **Step 1: Write failing tests** (inject a fake admin client with `auth.admin.createUser/deleteUser`)

```ts
import { describe, it, expect, vi } from "vitest";
import { createTestUser, deleteTestUser } from "../src/seed/supabase-admin.js";

const fakeAdmin = () => ({ auth: { admin: {
  createUser: vi.fn(async (a: any) => ({ data: { user: { id: "u1", email: a.email } }, error: null })),
  deleteUser: vi.fn(async () => ({ error: null })),
}}});

describe("supabase-admin", () => {
  it("creates a pre-confirmed user", async () => {
    const a = fakeAdmin();
    const u = await createTestUser(a as any, { email: "e2e+1@x.com", password: "p" });
    expect(u.id).toBe("u1");
    expect(a.auth.admin.createUser).toHaveBeenCalledWith(
      expect.objectContaining({ email: "e2e+1@x.com", email_confirm: true }));
  });
  it("throws on error", async () => {
    const a = fakeAdmin(); a.auth.admin.createUser = vi.fn(async () => ({ data: { user: null }, error: { message: "boom" } }));
    await expect(createTestUser(a as any, { email: "x", password: "p" })).rejects.toThrow("boom");
  });
});
```

- [ ] **Step 2: Run, verify FAIL.**

- [ ] **Step 3: Implement `src/seed/supabase-admin.ts`**

```ts
import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import type { Config } from "../config.js";

export function makeAdmin(cfg: Config): SupabaseClient {
  return createClient(cfg.supabaseUrl, cfg.supabaseServiceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
}

export async function createTestUser(admin: SupabaseClient, p: { email: string; password: string }) {
  const { data, error } = await admin.auth.admin.createUser({
    email: p.email, password: p.password, email_confirm: true,
  });
  if (error || !data.user) throw new Error(error?.message ?? "createUser failed");
  return { id: data.user.id, email: data.user.email! };
}

export async function deleteTestUser(admin: SupabaseClient, userId: string) {
  const { error } = await admin.auth.admin.deleteUser(userId);
  if (error) throw new Error(error.message);
}
```

- [ ] **Step 4: Run, verify PASS.**
- [ ] **Step 5: Commit** — `git commit -am "feat(seed): supabase admin user provisioning + teardown"`

---

## Task 5: Run manifest

**Files:**
- Create: `src/seed/manifest.ts`
- Test: `tests-unit/manifest.test.ts`

**Interfaces:**
- Produces: `newRunId(now: Date): string` (e.g. `20260622-1830`), `type SeededUser = { role: "owner_doctor"|"doctor"|"assistant"; clinic: "solo"|"multi"; email: string; userId: string }`, `type Manifest = { runId: string; users: SeededUser[]; clinicIds: { solo?: string; multi?: string } }`, `writeManifest(dir, m)`, `readManifest(dir): Manifest`.

- [ ] **Step 1: Write failing tests** — `newRunId(new Date("2026-06-22T18:30:00Z"))` matches `/^\d{8}-\d{4}$/`; write-then-read round-trips a manifest via a temp dir (`os.tmpdir()`).
- [ ] **Step 2: Run, verify FAIL.**
- [ ] **Step 3: Implement** `manifest.ts` (pure date formatting + `fs.writeFileSync`/`readFileSync` JSON at `<dir>/manifest.json`).
- [ ] **Step 4: Run, verify PASS.**
- [ ] **Step 5: Commit** — `git commit -am "feat(seed): per-run manifest read/write"`

---

## Task 6: Operation Registry

**Files:**
- Create: `src/operations.ts`
- Test: `tests-unit/operations.test.ts`

**Interfaces:**
- Produces: `type Role = "owner_doctor"|"doctor"|"assistant"`, `type Archetype = "solo"|"multi"|"any"`, `type Operation = { id: string; label: string; role: Role; archetype: Archetype; idealClicks: number; idealScreens: number }`, `OPERATIONS: Operation[]`, `getOperation(id: string): Operation`.

- [ ] **Step 1: Write failing tests** — every `id` is unique; every op has `idealClicks > 0` and `idealScreens > 0`; `getOperation("doctor.approve_request")` returns an entry; `getOperation("nope")` throws.

- [ ] **Step 2: Run, verify FAIL.**

- [ ] **Step 3: Implement `src/operations.ts`** — seed the registry with the v1 operation set (extend as specs are added). Initial entries (idealClicks/Screens are the reviewer's estimate of the minimal path; tune during review):

```ts
export const OPERATIONS: Operation[] = [
  { id: "auth.login_email",            label: "Log in (email/password)", role: "assistant",    archetype: "any",   idealClicks: 3, idealScreens: 1 },
  { id: "onboarding.create_clinic",    label: "Create a clinic",         role: "owner_doctor", archetype: "any",   idealClicks: 6, idealScreens: 5 },
  { id: "onboarding.join_clinic",      label: "Join via invite",         role: "assistant",    archetype: "any",   idealClicks: 2, idealScreens: 1 },
  { id: "owner.add_doctor_profile",    label: "Add own doctor profile",  role: "owner_doctor", archetype: "any",   idealClicks: 4, idealScreens: 3 },
  { id: "clinic.add_doctor",           label: "Add a doctor",            role: "owner_doctor", archetype: "multi", idealClicks: 4, idealScreens: 3 },
  { id: "clinic.add_assistant",        label: "Add an assistant",        role: "owner_doctor", archetype: "multi", idealClicks: 4, idealScreens: 3 },
  { id: "patient.create",              label: "Add a patient",           role: "assistant",    archetype: "any",   idealClicks: 5, idealScreens: 1 },
  { id: "patient.edit",                label: "Edit a patient",          role: "assistant",    archetype: "any",   idealClicks: 4, idealScreens: 1 },
  { id: "patient.delete",              label: "Delete a patient",        role: "assistant",    archetype: "any",   idealClicks: 3, idealScreens: 1 },
  { id: "request.create",             label: "Create appointment request", role: "assistant", archetype: "any",   idealClicks: 6, idealScreens: 1 },
  { id: "request.approve",             label: "Approve request",         role: "doctor",       archetype: "any",   idealClicks: 2, idealScreens: 1 },
  { id: "request.reject",              label: "Reject request",          role: "doctor",       archetype: "any",   idealClicks: 2, idealScreens: 1 },
  { id: "request.cancel",              label: "Cancel request",          role: "assistant",    archetype: "any",   idealClicks: 3, idealScreens: 1 },
  { id: "appointment.mark_arrived",    label: "Mark arrived",            role: "assistant",    archetype: "any",   idealClicks: 2, idealScreens: 1 },
  { id: "appointment.mark_no_show",    label: "Mark no-show",            role: "assistant",    archetype: "any",   idealClicks: 2, idealScreens: 1 },
  { id: "appointment.complete",        label: "Complete appointment",    role: "assistant",    archetype: "any",   idealClicks: 3, idealScreens: 1 },
  { id: "availability.add_window",     label: "Add availability window", role: "doctor",       archetype: "any",   idealClicks: 5, idealScreens: 1 },
  { id: "settings.update_profile",     label: "Update own profile",      role: "assistant",    archetype: "any",   idealClicks: 4, idealScreens: 1 },
  { id: "settings.update_preferences", label: "Change theme/language",   role: "assistant",    archetype: "any",   idealClicks: 3, idealScreens: 1 },
  { id: "settings.update_clinic",      label: "Edit clinic details",     role: "owner_doctor", archetype: "any",   idealClicks: 5, idealScreens: 1 },
];
```

- [ ] **Step 4: Run, verify PASS.**
- [ ] **Step 5: Commit** — `git commit -am "feat(ops): operation registry with ideal-path metadata"`

---

## Task 7: Metrics — pure aggregation core

**Files:**
- Create: `src/fixtures/metrics-core.ts`
- Test: `tests-unit/metrics-core.test.ts`

**Interfaces:**
- Produces: `type RawEvent = { type: "click"|"nav"|"field"|"scroll"|"sheet"|"error"; at: number }`, `type OpMetrics = { operationId: string; clicks: number; screens: number; fields: number; scrolls: number; sheets: number; errors: number; durationMs: number }`, `aggregate(operationId: string, events: RawEvent[], startedAt: number, endedAt: number): OpMetrics`. `screens` = count of `nav` events + 1 (initial screen).

- [ ] **Step 1: Write failing tests** — given a mixed event list, `aggregate` returns correct per-type counts, `screens = navCount + 1`, and `durationMs = endedAt - startedAt`.
- [ ] **Step 2: Run, verify FAIL.**
- [ ] **Step 3: Implement** `metrics-core.ts` (pure reducer).
- [ ] **Step 4: Run, verify PASS.**
- [ ] **Step 5: Commit** — `git commit -am "feat(metrics): pure per-operation aggregation"`

---

## Task 8: Metrics — Playwright fixture

**Files:**
- Create: `src/fixtures/metrics.ts`
- Test: covered indirectly by Task 11's template spec (integration); add `tests-unit` only for any pure helper.

**Interfaces:**
- Consumes: `aggregate` (Task 7), `getOperation` (Task 6).
- Produces: a Playwright `test` extended with `measure(operationId: string, fn: () => Promise<void>): Promise<void>`. It records clicks via `page.on` instrumentation (inject a small init script that increments counters on `click`, `scroll`, `submit`; track `framenavigated` for `nav`; expose a binding to flush counts), times the block, calls `aggregate`, and appends the `OpMetrics` to `runs/<RUN_DIR>/metrics.json` (path from `process.env.RUN_DIR`).

- [ ] **Step 1: Implement the fixture**

```ts
import { test as base, expect } from "@playwright/test";
import fs from "node:fs";
import path from "node:path";
import { aggregate, type RawEvent } from "./metrics-core.js";
import { getOperation } from "../operations.js";

export const test = base.extend<{ measure: (id: string, fn: () => Promise<void>) => Promise<void> }>({
  measure: async ({ page }, use) => {
    await use(async (operationId, fn) => {
      getOperation(operationId); // validates id
      await page.addInitScript(() => {
        (window as any).__m = { click: 0, scroll: 0, field: 0, sheet: 0 };
        addEventListener("click", () => (window as any).__m.click++, true);
        addEventListener("scroll", () => (window as any).__m.scroll++, true);
        addEventListener("input", () => (window as any).__m.field++, true);
      });
      let navs = 0;
      const onNav = () => navs++;
      page.on("framenavigated", onNav);
      const started = Date.now();
      let errored = false;
      try { await fn(); } catch (e) { errored = true; throw e; }
      finally {
        const ended = Date.now();
        page.off("framenavigated", onNav);
        const m = await page.evaluate(() => (window as any).__m ?? { click: 0, scroll: 0, field: 0, sheet: 0 });
        const events: RawEvent[] = [
          ...Array(m.click).fill({ type: "click", at: started }),
          ...Array(navs).fill({ type: "nav", at: started }),
          ...Array(m.field).fill({ type: "field", at: started }),
          ...Array(m.scroll).fill({ type: "scroll", at: started }),
          ...(errored ? [{ type: "error" as const, at: ended }] : []),
        ];
        const om = aggregate(operationId, events, started, ended);
        const dir = process.env.RUN_DIR!;
        const file = path.join(dir, "metrics.json");
        const arr = fs.existsSync(file) ? JSON.parse(fs.readFileSync(file, "utf8")) : [];
        arr.push(om);
        fs.mkdirSync(dir, { recursive: true });
        fs.writeFileSync(file, JSON.stringify(arr, null, 2));
      }
    });
  },
});
export { expect };
```

- [ ] **Step 2: Typecheck** — `npm run typecheck` → 0 errors.
- [ ] **Step 3: Commit** — `git commit -am "feat(metrics): playwright measure() fixture writing metrics.json"`

> Note: this fixture is exercised end-to-end in Task 11. `field`/unique-screen nuance can be refined later; counts are directional signal for the ease index, not exact UX truth.

---

## Task 9: Seed archetype builders

**Files:**
- Create: `src/seed/archetypes.ts`
- Test: `tests-unit/archetypes.test.ts`

**Interfaces:**
- Consumes: `ApiClient` (Task 3), `createTestUser` (Task 4), `Manifest` types (Task 5).
- Produces: `buildSolo(deps): Promise<void>` and `buildMulti(deps): Promise<void>` where `deps = { admin, cfg, runId, manifest, login }`. `login(email,password): Promise<string>` returns an access token (a thin Supabase password sign-in helper, added here). Each builder: creates users → signs in → POSTs clinic/doctor/patients/requests via `/api/v1/...`, marking names with `[E2E][<runId>]`, recording ids + users into `manifest`.

- [ ] **Step 1: Write failing tests** (inject a fake `ApiClient` recording calls; fake `admin`/`login`)

Assert `buildSolo`:
- creates exactly one `owner_doctor` user,
- calls `POST /api/v1/clinics` with a name containing `[E2E]` and the runId,
- calls `POST /api/v1/clinics/{id}/doctors` (own profile) and ≥3 `POST /api/v1/clinics/{id}/patients`,
- pushes the clinic id into `manifest.clinicIds.solo`.

Assert `buildMulti` additionally creates a second doctor + an assistant (via invite `POST /api/v1/clinics/{id}/invites` then `POST /api/v1/clinics/join`) and ≥1 `POST /api/v1/clinics/{id}/appointment-requests`.

- [ ] **Step 2: Run, verify FAIL.**

- [ ] **Step 3: Implement `src/seed/archetypes.ts`** — concrete sequences using the real endpoints (verbatim paths):
  - Clinic: `POST /api/v1/clinics` `{ name: "[E2E][<runId>] Solo Clinic" }`.
  - Own doctor profile: `POST /api/v1/clinics/{clinicId}/doctors` (self-service owner-doctor; body per backend `DoctorCreate`).
  - Patients: `POST /api/v1/clinics/{clinicId}/patients` ×N (`name: "[E2E] <faker>"`, `gender`, `phone`).
  - Availability: `POST /api/v1/clinics/{clinicId}/availability-windows` (the scheduling `_BASE`).
  - Requests: `POST /api/v1/clinics/{clinicId}/appointment-requests` for the multi clinic.
  - Invite+join: `POST /api/v1/clinics/{clinicId}/invites` → use returned token → second user `POST /api/v1/clinics/join`.
  - `login` helper signs in via `supabase.auth.signInWithPassword` and returns `data.session.access_token`.

> Exact request bodies: derive field names from the backend `schemas.py` of each module at implementation time (read `dentist-registry-backend/app/modules/<m>/schemas.py`). The test asserts the call *shape*; the integration run validates the bodies against the live API.

- [ ] **Step 4: Run, verify PASS.**
- [ ] **Step 5: Commit** — `git commit -am "feat(seed): solo + multi-staff archetype builders (API-driven)"`

---

## Task 10: Seed orchestration + teardown

**Files:**
- Create: `src/seed/index.ts`
- Test: `tests-unit/seed-index.test.ts`

**Interfaces:**
- Consumes: `buildSolo`/`buildMulti` (Task 9), `makeAdmin`/`deleteTestUser` (Task 4), `writeManifest`/`readManifest`/`newRunId` (Task 5).
- Produces: `seed(cfg, runDir): Promise<Manifest>` and `teardown(cfg, runDir): Promise<void>`. `seed` refuses to run when `!cfg.allowMutation` (prod). `teardown` reads the manifest and deletes every seeded user (best-effort, continues on per-user error) — clinic rows are owned by deleted users / `[E2E]`-marked.

- [ ] **Step 1: Write failing tests** — `seed` throws when `allowMutation=false`; `teardown` calls `deleteTestUser` for each user in the manifest and does not throw if one deletion fails (mock one rejection).
- [ ] **Step 2: Run, verify FAIL.**
- [ ] **Step 3: Implement** `seed/index.ts`.
- [ ] **Step 4: Run, verify PASS.**
- [ ] **Step 5: Commit** — `git commit -am "feat(seed): orchestration + best-effort teardown + prod guard"`

---

## Task 11: Page objects + the template functional spec (vertical slice)

**Files:**
- Create: `src/pages/base-page.ts`, `src/pages/login-page.ts`, `src/pages/requests-page.ts`, `src/pages/patients-page.ts`
- Create: `tests/auth.setup.ts`
- Create: `tests/functional/requests.spec.ts`
- Modify: `playwright.config.ts` (add `setup` + role projects)

**Interfaces:**
- Consumes: `test`/`measure` (Task 8), seeded manifest (Task 10).
- Produces: the **reusable spec pattern** every later functional task follows: `test("<op label>", async ({ page, measure }) => { const p = new XPage(page); await measure("<operationId>", async () => { /* drive via POM + assert visible state */ }); })`. Login state per role via `storageState`.

- [ ] **Step 1: Implement `auth.setup.ts`** — for each role in the manifest, open `/login`, fill email/password (`data-testid` from the login form), submit, wait for `data-testid="clinic-shell"`, save `storageState` to `runs/<RUN_DIR>/state-<role>.json`.

- [ ] **Step 2: Wire `playwright.config.ts` projects**

```ts
projects: [
  { name: "setup", testMatch: /auth\.setup\.ts/ },
  { name: "assistant", dependencies: ["setup"], use: { storageState: `${process.env.RUN_DIR}/state-assistant.json` }, testIgnore: /sweep|smoke/ },
  { name: "doctor", dependencies: ["setup"], use: { storageState: `${process.env.RUN_DIR}/state-doctor.json` }, testMatch: /functional\/.*doctor.*/ },
]
```
(Refine role→spec mapping as specs are added; keep `baseURL` = `FRONTEND_BASE_URL`.)

- [ ] **Step 3: Implement the page objects** — `base-page.ts` (holds `page`, `goto(path)`), `requests-page.ts` and `patients-page.ts` using existing test-ids (e.g. `add-patient-form`, `create-patient-button`, `complaint`, request row Approve/Reject controls). List the test-ids each method targets; add a TODO list of missing test-ids to request from the frontend if a needed selector is absent.

- [ ] **Step 4: Write the template spec `tests/functional/requests.spec.ts`** — fully worked, e.g.:

```ts
import { test, expect } from "../../src/fixtures/metrics.js";
import { RequestsPage } from "../../src/pages/requests-page.js";

test("assistant creates an appointment request", async ({ page, measure }) => {
  const reqs = new RequestsPage(page);
  await reqs.goto();
  await measure("request.create", async () => {
    await reqs.openNewRequest();
    await reqs.fillRequest({ patient: "[E2E]", complaint: "Toothache", date: "tomorrow" });
    await reqs.submit();
    await expect(reqs.successCard()).toBeVisible(); // Golden Rule 18.5
  });
  await expect(reqs.rowByComplaint("Toothache")).toBeVisible();
});
```

- [ ] **Step 5: Integration run against local services**

Prereq: local backend (`make run`, DB on :5433) + frontend (`npm run dev`) + a real Supabase project, with `.env.local` filled. Then:
```bash
RUN_DIR=runs/dev-manual npm run pw -- --project=setup --project=assistant tests/functional/requests.spec.ts
```
Expected: PASS; `runs/dev-manual/metrics.json` contains a `request.create` entry with non-zero clicks/screens.

- [ ] **Step 6: Commit** — `git commit -am "feat(e2e): POM base + auth setup + requests template spec + metrics wiring"`

---

## Task 12: Exhaustive functional specs — by domain

Each sub-task follows the **Task 11 template** exactly (POM method + `measure(operationId, …)` + assert visible state incl. success cards). Each produces `tests/functional/<domain>.spec.ts` plus the page object(s) it needs, and registers any new operation in `src/operations.ts` (Task 6). Commit per domain.

For each domain: write the spec(s), run them against local services (`RUN_DIR=runs/dev-manual npm run pw -- <files>`), confirm green + metrics emitted, then commit.

- [ ] **12a — Auth & onboarding** (`auth.spec.ts`, `onboarding.spec.ts`; `login-page.ts`, `onboarding-page.ts`): `auth.login_email`; `onboarding.create_clinic` (guided wizard — Name/Phone/WhatsApp/Email/Address-as-one-card per Rule 18.4); `onboarding.join_clinic`; `owner.add_doctor_profile`. Assert wizard step gating + success card.
- [ ] **12b — Patients** (`patients.spec.ts`; `patients-page.ts`): `patient.create` (incl. gender), `patient.edit`, `patient.delete` (confirm dialog — Rule 12.2), duplicate-check path. Assert empty/loading/error states render (`patients-empty`, `*-loading`, `*-error` test-ids).
- [ ] **12c — Requests & approval lifecycle** (`requests.spec.ts` extends Task 11, `approvals.spec.ts`): `request.create`, `request.approve` (doctor), `request.reject` (doctor), `request.cancel`, `request.resend`; full lifecycle `appointment.mark_arrived` → `appointment.mark_no_show` → `appointment.complete`. Assert state chips visible (Rule 12.1) and doctor-approval gating (Rule 1.2).
- [ ] **12d — Scheduling** (`my-schedule.spec.ts`, `clinic-schedules.spec.ts`; page objects): `availability.add_window`, add block/one-off; My Schedule (no doctor picker) vs Clinic Schedules (DoctorPicker bottom-sheet) separation (Rule 18.2/18.3).
- [ ] **12e — Staff (multi only)** (`doctors.spec.ts`, `assistants.spec.ts`): `clinic.add_doctor`, `clinic.add_assistant` (invite flow), edit/deactivate. Assert against the multi-staff seeded clinic.
- [ ] **12f — Settings** (`settings.spec.ts`; `settings-page.ts`): `settings.update_profile`, `settings.update_preferences` (theme + language), `settings.update_clinic`. Assert all settings live under `/settings` (Rule 18.6).

> This is the "exhaustive" surface. The operation set above is the v1 floor; add operations + ideal-path entries as screens/fields are covered. Keep one operationId per distinct user task so the ease index stays meaningful.

---

## Task 13: i18n + theme sweep

**Files:**
- Create: `tests/sweep/i18n-theme.spec.ts`, `src/pages/design-system-page.ts`
- Modify: `playwright.config.ts` (add `sweep` project)

- [ ] **Step 1:** Implement a data-driven sweep over all 10 routes (`/login`, `/`, `/patients`, `/requests`, `/my-schedule`, `/clinic-schedules`, `/doctors`, `/assistants`, `/settings`, `/design-system`) × `{en, hi}` × `{light, dark}`. For each: set locale (localStorage `register.locale`) + theme (localStorage `theme`), navigate, assert no visible `MISSING_TRANSLATION`/raw key, assert `<html class="dark">` toggles, screenshot.
- [ ] **Step 2:** Run against local: `RUN_DIR=runs/dev-manual npm run pw -- --project=sweep`. Expected: all combinations pass.
- [ ] **Step 3: Commit** — `git commit -am "feat(e2e): i18n(en/hi) + light/dark sweep across all routes"`

---

## Task 14: Prod read-only smoke

**Files:**
- Create: `tests/smoke/prod-smoke.spec.ts`
- Modify: `playwright.config.ts` (`smoke` project; selected only when `--env prod`)

- [ ] **Step 1:** Implement read-only checks: each major route loads, login works, no mutating action is taken. The pipeline (Task 16) only runs this project when `cfg.env === "prod"` and never runs seed/functional/sweep on prod.
- [ ] **Step 2: Commit** — `git commit -am "feat(e2e): prod read-only smoke subset"`

---

## Task 15: Capture, report, prune, trend, fingerprint, email (pure-logic core)

This task groups the deterministic pure-logic modules; each gets its own TDD cycle and commit.

**Files / Tests:**
- `src/report/report-core.ts` + `tests-unit/report-core.test.ts`
- `src/report/render.ts` + `tests-unit/render.test.ts`
- `src/prune/prune.ts` + `tests-unit/prune.test.ts`
- `src/trend/fingerprint.ts` + `tests-unit/fingerprint.test.ts`
- `src/trend/diff.ts` + `tests-unit/diff.test.ts`
- `src/trend/store.ts` + `tests-unit/store.test.ts`
- `src/email/email-core.ts` + `tests-unit/email-core.test.ts`

**Interfaces (produced):**
- `summarize(results: PwResult[], metrics: OpMetrics[]): RunSummary` — counts pass/fail, joins metrics to operations.
- `renderHtml(summary: RunSummary, intelligence?: IntelligenceBlock): string` — self-contained HTML (inline CSS).
- `selectForPrune(runs: { dir: string; mtime: number; hasFailure: boolean }[], retainRuns: number, retainFailureRuns: number, now: number): string[]` — dirs to delete.
- `fingerprint(f: { operationId: string; assertion: string; errorMessage: string }): string` — stable hash (normalize volatile substrings: ids, timestamps, runId).
- `matchExistingBug(fp: string, openIssues: { number: number; fingerprint: string }[]): number | null`.
- `diffTrends(prev: TrendRow[], curr: TrendRow[]): { newFailures: string[]; recovered: string[]; easeRegressions: { op: string; delta: number }[]; slower: { op: string; deltaMs: number }[] }`.
- `readTrend(file): TrendRow[]`, `appendTrend(file, rows): void` (`TrendRow = { date: string; operationId: string; pass: boolean; ease: number|null; durationMs: number }`).
- `composeEmail(summary, intelligence): { subject: string; text: string; html: string }`.

- [ ] **Step 1 (report-core):** TDD `summarize` — given results+metrics, returns correct pass/fail counts and per-op rows. Implement. Commit.
- [ ] **Step 2 (render):** TDD `renderHtml` — output contains the run date, a pass/fail row per spec, and an ease-index table when intelligence is present; no external asset URLs. Implement. Commit.
- [ ] **Step 3 (prune):** TDD `selectForPrune` — keeps newest `retainRuns`; keeps failure runs up to `retainFailureRuns` days; returns the rest. Implement (+ a thin `applyPrune(dir)` that `fs.rm`s selected). Commit.
- [ ] **Step 4 (fingerprint):** TDD `fingerprint` stability (same logical failure → same hash across runIds/timestamps) + `matchExistingBug`. Implement. Commit.
- [ ] **Step 5 (diff):** TDD `diffTrends` — detects new failures, recoveries, ease drops beyond a threshold, and slowdowns. Implement. Commit.
- [ ] **Step 6 (store):** TDD `readTrend`/`appendTrend` round-trip via temp file. Implement. Commit.
- [ ] **Step 7 (email-core):** TDD `composeEmail` — subject includes run status + counts; text summary lists regressions/bugs/ease movers. Implement. Commit.

---

## Task 16: Email send + deterministic pipeline orchestrator

**Files:**
- Create: `src/email/send.ts`, `pipeline/run.ts`
- Test: `tests-unit/email-send.test.ts` (mock Resend client + assert Mailtrap/none toggles)

**Interfaces:**
- Consumes: everything above.
- Produces: `sendReport(cfg, { subject, text, html }): Promise<void>` (Resend when `emailProvider="resend"`, SMTP/Mailtrap when `"mailtrap"`, no-op + log when `"none"`); `pipeline/run.ts` as the `npm run e2e` entry point.

- [ ] **Step 1:** TDD `sendReport` — `resend` path calls the Resend client with `to=cfg.reportEmailTo`; `none` path sends nothing. Implement. 
- [ ] **Step 2: Implement `pipeline/run.ts`** (orchestration; integration-verified, not unit-tested):

```
1. load .env.<env> into process.env, then loadConfig()
2. RUN_DIR = runs/<newRunId()>; mkdir; set process.env.RUN_DIR
3. if cfg.env === "prod": run only the smoke project; skip to step 8 (report+email), no seed/teardown
4. seed(cfg, RUN_DIR) → manifest
5. run Playwright: spawn `playwright test` (setup + role projects + sweep); capture exit code
6. read runs/_pw-report.json + RUN_DIR/metrics.json → summarize() → renderHtml() → RUN_DIR/report.base.html
7. teardown(cfg, RUN_DIR) (always, even on test failure — wrap in finally)
8. applyPrune(runs/) using cfg retention
9. write a machine-readable RUN_DIR/results.json for the Claude step
10. exit non-zero if the pipeline itself broke (so /loop sees harness failure distinctly)
```

- [ ] **Step 3: Integration run** — with local services up and `.env.local` set: `npm run e2e -- --env local`. Expected: a `runs/<id>/` dir with `report.base.html`, `metrics.json`, `results.json`; seeded `[E2E]` data is gone after teardown.
- [ ] **Step 4: Commit** — `git commit -am "feat(pipeline): deterministic orchestrator (seed→test→capture→report→prune→teardown) + email send"`

---

## Task 17: Intelligence step + `/loop` wiring + trend branch

**Files:**
- Create: `intelligence/e2e-nightly.md` (the Claude instructions), `README.md` (run/loop section)
- Create: `scripts/commit-trend.sh` (commits the trend store to the `e2e-history` branch)

- [ ] **Step 1: Write `intelligence/e2e-nightly.md`** — the stable instruction doc the daily `/loop` Claude session follows:
  1. Run `npm run e2e -- --env local`.
  2. Read `runs/<latest>/results.json` + `metrics.json` + `report.base.html`; read the trend store (latest `e2e-history`).
  3. **Regression analysis:** call `diffTrends`; classify flaky vs real (compare against the last K runs in the trend store, not just yesterday).
  4. **Ease index:** for each operation, compare metrics to `idealClicks/idealScreens`, assign 0–100 + rationale + concrete simplification recommendations.
  5. **Bug filing:** for real failures, compute `fingerprint`, `matchExistingBug` against open `gh-personal issue list -S "[BUG][E2E testing]"`; file new `[BUG][E2E testing] <summary>` (labels `bug,infra`, add to Project #1) or comment "still failing on <date>"; reopen if recurred. Embed the fingerprint in the issue body.
  6. **Report + email:** `composeEmail` from summary+intelligence → inject intelligence into the HTML → `sendReport`.
  7. **Trend commit:** `appendTrend` today's rows → run `scripts/commit-trend.sh`.
  8. Honor Golden Rules: advisory only; never mutate the product; dedup before filing.

- [ ] **Step 2: Write `scripts/commit-trend.sh`** — checkout/create `e2e-history` branch in a separate worktree, copy the trend file, commit (`chore(trend): <date>`), push; never touches `main`. Include the pre-flight `github-personal` + email check.

- [ ] **Step 3: Document the `/loop` invocation in README**: `/loop "0 2 * * *" /e2e-nightly` (nightly 02:00) — the loop prompt stays stable; all logic lives in `intelligence/e2e-nightly.md`. (User runs this from the `register-test-suite` dir in the `claude-personal` session.)

- [ ] **Step 4: Commit** — `git commit -am "feat(intelligence): /loop e2e-nightly instructions + trend-branch commit script"`

---

## Task 18: Final wiring, PR

- [ ] **Step 1:** `npm run typecheck && npm run test:unit` → all green. Record the unit-test count in the README.
- [ ] **Step 2:** Full local dry run: `npm run e2e -- --env local` green end-to-end; manually run the `intelligence/e2e-nightly.md` steps once and confirm a test bug files correctly (then close it) and an email arrives (use the Mailtrap toggle first).
- [ ] **Step 3:** Open PR via `gh-personal pr create` (base `main`), title `feat: daily e2e + intelligence harness (#103)`, body linking the spec/plan and `Closes #103`. Hold for user review; never merge red.

---

## Self-Review (plan vs spec)

- **Spec §3 repo/stack/layout** → Task 1 (scaffold), File Structure map. ✅
- **Spec §4 env + data safety + prod guard** → Task 2 (`allowMutation`), Task 10 (seed prod guard), Task 14/16 (prod smoke-only path), `[E2E]` marking in Task 9. ✅
- **Spec §5 seed archetypes (solo + multi), API-driven, manifest, idempotent** → Tasks 3,4,5,9,10. ✅
- **Spec §6 auth via real UI + reused session** → Task 11 (`auth.setup.ts` + storageState). ✅
- **Spec §7 POM + operation registry + metrics fixture + coverage tiers** → Tasks 6,7,8,11,12,13,14. ✅
- **Spec §8 trend store (committed branch) + retention/prune** → Task 15 (store/diff/prune), Task 17 (`e2e-history` commit). ✅
- **Spec §9 intelligence (regression, ease index, deduped bug filing, email)** → Task 15 (fingerprint/diff/email-core), Task 17 (`e2e-nightly.md`). ✅
- **Spec §10 self-contained HTML + Resend (+ Mailtrap)** → Task 15 (render), Task 16 (send). ✅
- **Spec §11 deterministic pipeline + /loop split** → Task 16 (`pipeline/run.ts`), Task 17 (loop wiring). ✅
- **Spec §12 quality (unit-tested logic, permissive OSS, secrets, git hygiene)** → Tasks 2,7,15,16 (Vitest), Task 1 (deps/README), `.gitignore`/`.env.example`, Task 18 (PR, never red). ✅
- **Spec §13 deferred/limitations (time-states, phone-OTP, beta/prod not exercised)** → encoded: no time-dependent specs in Task 12; phone-OTP excluded in Task 11; v1 runs `--env local`. ✅
- **Placeholder scan:** infra/pure-logic tasks carry full code + tests; the exhaustive specs (Task 12) reference the fully-worked Task 11 template + concrete operation/test-id lists (intentional DRY — one template, enumerated instances), with exact request bodies derived from the named backend `schemas.py` at implementation time. No "TBD". ✅
- **Type consistency:** `OpMetrics`, `Operation`, `Manifest`/`SeededUser`, `Config`, `ApiError`, `TrendRow`, `RunSummary` names are used consistently across producing/consuming tasks. ✅
