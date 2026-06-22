# Daily E2E + Intelligence Testing Harness — Design Spec (#103)

**Status:** Approved (brainstorm 2026-06-22). New **standalone repo** (`dentist-registry-e2e`), never deployed; run locally against local/beta/prod. Treats frontend+backend as a black box — no product code changes.
**Type:** A real-services (no-mock) end-to-end harness that seeds two clinic archetypes, drives the product exhaustively with Playwright, and runs once a day via Claude Code `/loop` — where Claude detects regressions, computes a per-operation **ease-of-use index**, files deduped `[BUG][E2E testing]` issues, and emails an HTML report.

## 1. Goal
Catch real breakages and quantify usability automatically, every day. The product is for **non-tech-savvy doctors and assistants**, so *ease of use is a first-class, measured product goal* — not just correctness. A deterministic pipeline runs the full product against real services; Claude's intelligence then turns raw results into regressions, an ease-of-use index with concrete simplification recommendations, auto-filed bugs, and an emailed report.

## 2. Scope decisions (locked in brainstorm)
- **One spec, one implementation plan** covering all layers (user chose "everything in one go").
- **No mocks.** Seed and tests make real calls through the real backend, DB, and Supabase auth.
- **Two clinic archetypes:** a **solo** owner-doctor clinic (Rule 18.1 happy path) and a **multi-staff** clinic (owner + extra doctor(s) + assistant(s)).
- **Seed = API-driven** (real REST + Supabase admin API), so it is env-portable and doubles as API-contract coverage.
- **Auth = email/password test users** (pre-confirmed via Supabase admin API), logged in through the **real login UI** once per role, session reused (`storageState`). Phone-OTP is excluded from automated runs.
- **Exhaustive functional coverage** of screens, fields, and states; **i18n (en/hi) parity** and **light/dark theme** verified via a dedicated sweep (not by running the whole functional suite 4×).
- **Env-parameterized** (`--env local|beta|prod`). v1 = local only (beta/prod not deployed yet). **Prod = read-only smoke subset only** — never mutates prod (Golden Rules §4, §15: preserve real clinic data/history).
- **Orchestration split:** a deterministic script does the mechanical pipeline; the daily `/loop` Claude session does only the judgment work.
- **Results accumulate locally** with a **retention/prune policy** (must not fill the disk); a tiny trend store is committed for durable day-over-day diffing.

## 3. Repo & stack
- **Repo:** `dentist-registry-e2e` under `~/Documents/register_workspace/`, `github-personal` remote. **Never deployed.**
- **Stack:** TypeScript + **Playwright** (Apache-2.0). Already used in `dentist-registry-frontend`; best-in-class traces/screenshots/video and native per-interaction signals for the ease index.
- **Libs (all permissive/MIT):** `@playwright/test`, `@supabase/supabase-js` (admin user creation + teardown), `resend` (email). HTML report is hand-rolled (no heavy templating dep). New non-trivial deps documented per Golden Rule 3.4.
- **Layout (proposed):**
  - `seed/` — archetype builders (API-driven) + Supabase admin user provisioning + teardown.
  - `src/pages/` — Page-Object Model (one object per screen; selectors centralized).
  - `src/operations.ts` — **Operation Registry** (`operationId → { label, role, archetype, idealPath }`).
  - `src/fixtures/metrics.ts` — Playwright fixture auto-recording per-operation interaction metrics.
  - `tests/` — functional specs (tagged with operation ids) + the i18n/theme sweep + the prod smoke subset.
  - `pipeline/` — `run` orchestrator, base-HTML report generator, prune step.
  - `intelligence/` — prompt + helpers for the Claude `/loop` step (analysis, bug filing, email).
  - `runs/` (gitignored) — raw artifacts. `.env.{local,beta,prod}` (gitignored) + `.env.example`.

## 4. Environments & data safety
- Config per env via `.env.<env>` (frontend base URL, backend base URL, Supabase URL + anon key + **service-role key** for admin/teardown, Resend key, target email). Selected with `--env`.
- All synthetic data carries an **`[E2E]` name prefix** and a dedicated `e2e+<run>@<testdomain>` email namespace → always identifiable and cleanable.
- **Teardown** deletes only `[E2E]`-marked clinics/users/data after a run (synthetic data, so deletion is safe and does not touch real history).
- **Prod guardrail:** the runner hard-refuses any mutating spec when `--env prod`; only the read-only smoke subset is allowed. (Defense-in-depth so a future test can't accidentally write to prod.)

## 5. Seed — archetypes & data model
API-driven builders create, per run, two fully-populated clinics:
- **Solo clinic** — 1 owner-doctor (created via the owner-doctor self-profile path), availability/schedule, a set of patients, and appointments/requests spanning states the API can produce (pending, approved→confirmed, rejected, cancelled, completed, arrived, no-show).
- **Multi-staff clinic** — owner + ≥1 additional doctor + ≥1 assistant (invited/joined), per-doctor availability, patients, and the full request→approval lifecycle across doctors.
- **Users** are created pre-confirmed via the Supabase **admin API** (one email/password user per role per clinic), recorded in a per-run manifest used for login and teardown.
- Seed is **idempotent per run** (unique run id in the `[E2E]` prefix) so overlapping/retried runs never collide.
- **Time-dependent states** (e.g. *Expired Approval* needs a request older than 120 min) cannot be created by API time-travel — see §13 (documented v1 limitation).

## 6. Auth
- A Playwright **setup project** logs each seeded role in through the **real `/login` UI** (email/password), saving one `storageState` per role.
- Functional specs run as **projects keyed by stored role state** — fast, no re-login per test, while still exercising the real login screen once.
- Phone-OTP is out of automated scope (no real SMS); noted as a manual smoke check.

## 7. Drive & capture
- **Page-Object Model:** one object per screen encapsulates selectors + actions, so the exhaustive suite stays maintainable and a UI change is fixed in one place. Prefer stable `data-testid`s (the frontend already uses them); gaps get a small list of test-ids to request from the frontend.
- **Operation Registry:** every meaningful user task is an `operationId` (e.g. `assistant.create_request`, `doctor.approve_request`, `owner.add_doctor_profile`, `assistant.complete_appointment`). Each carries an **idealPath** annotation (expected minimal clicks/screens) used by the ease index. Specs tag the operation(s) they exercise.
- **Metrics fixture:** wraps each operation and auto-records: clicks/taps, distinct route/screen changes ("window switching"), form fields touched, scrolls, sheets/modals opened, dead-ends/errors, and machine duration. Written to `metrics.json` keyed by `operationId`.
- **Coverage tiers:**
  - **Functional suite** — exhaustive screens/fields/states for both archetypes (default locale + theme).
  - **i18n/theme sweep** — visits each screen in **en + hi** and **light + dark**, asserting key parity (no missing keys/`MISSING_TRANSLATION`), AA-relevant rendering, and theme-token application — without re-running every functional test 4×.
  - **Prod smoke** — read-only subset (pages load, auth works, no writes).
- Captured per run into `runs/<timestamp>/`: `results.json`, `metrics.json`, `screenshots/`, `traces/`, `video/`, `report.base.html`.

## 8. Trend store & retention
- **Trend store (committed, durable):** a compact JSON/SQLite — per-operation ease scores, pass/fail, durations, and filed-bug fingerprints **over time** — committed to a dedicated **`e2e-history` branch** (never `main`, no per-run PR). This is what Claude diffs day-over-day. Tiny, so it persists indefinitely.
- **Raw artifacts (local only):** `runs/` is gitignored. A **prune step** runs at the end of every pipeline: keep the last **N runs / N days** of raw artifacts; keep **failure** artifacts longer than passes; the trend store is exempt (kept forever). Defaults tunable in config; the goal is bounded disk usage.

## 9. Intelligence — the daily Claude step
After the script finishes, the `/loop` Claude session reads `results.json` + `metrics.json` + screenshots + the trend store and performs judgment-only work:
1. **Regression / breakage detection** — diff vs the trend store: newly-failing operations, operations that grew in interaction count or duration, broken flows. **Distinguish flaky from real** (intermittent vs consistent across runs) before acting.
2. **Ease-of-use index** — per operation: compare actual metrics to the registry `idealPath`, assign a **0–100 score** with a written rationale, and emit **concrete simplification recommendations** (e.g. "approval is 8 clicks across 4 screens → one approval sheet ≈ 3 clicks"). Trended over time so usability regressions/improvements are visible.
3. **Auto-file bugs** — for *legitimate* failures only, create issues in **`dentail-register-docs`** via `gh-personal`, titled **`[BUG][E2E testing] <summary>`**, labelled `bug` + `infra`, added to **Project #1**, each carrying a stable **failure fingerprint** (operation + assertion + normalized error). **Dedup:** before filing, search open `[BUG][E2E testing]` issues by fingerprint — if one exists, comment "still failing on <date>" instead of duplicating; **reopen** if it was closed and recurs.
4. **Email** the report (§10).
- The Claude step is encapsulated in a stable slash command (e.g. `/e2e-nightly`) so the `/loop` prompt never changes.

## 10. Reporting & email
- **Self-contained HTML report** (single file): run summary, pass/fail matrix, regressions (flaky vs real), the **ease-of-use index table with day-over-day deltas**, top simplification recommendations, and links to bugs filed/updated. The script generates `report.base.html` (results + metrics + screenshots); Claude injects the intelligence sections.
- **Email via Resend** (free tier, MIT SDK; per the project's SMTP decision) to the configured address — HTML inline + a short text summary (run status, # regressions, # bugs filed, ease-index movers). A **Mailtrap sandbox** toggle exists for testing the harness itself without sending real mail.

## 11. Orchestration
- **Deterministic pipeline (one entry point):** `npm run e2e -- --env local` → seed → setup-login → functional + i18n/theme suites → capture → `report.base.html` → prune → teardown. Reliable, no token cost.
- **Daily run:** `/loop` (nightly) fires a Claude session that (a) runs the pipeline script, then (b) executes `/e2e-nightly` for the intelligence + bug filing + email + trend-store commit.
- Failures in the deterministic pipeline still produce a partial report and are surfaced in the email (the harness reports its own breakage, not just the product's).

## 12. Quality
- **Self-tested harness:** unit tests for pure logic (metrics aggregation, ease-score math, fingerprinting, dedup matching, prune policy); the Mailtrap toggle verifies email rendering without real sends.
- **Permissive-OSS only** (Playwright Apache-2.0; supabase-js, resend MIT) — Golden Rule 3.1/3.4.
- **Secrets:** all creds (service-role key, Resend key) via gitignored `.env.<env>`; never committed (Golden Rule 11.2). `.env.example` documents the shape.
- **Git hygiene:** `github-personal` remote, `rohan2jos@gmail.com`; feature-branch → PR for the repo; the `e2e-history` branch receives only the trend store (data), never code on `main`.
- **Respects product rules under test:** the harness never bypasses auth, never seeds via debug backdoors, and (prod) never mutates — it exercises the product as a real user would.

## 13. Scope guards / deferred / open questions
- **Time-dependent states** (Expired Approval at 120 min, time-based hooks): API seed can't fast-forward time. **v1 decision: document as a limitation** and cover the reachable parts; revisit a backend test-only time hook later if needed.
- **Phone-OTP login:** excluded from automation (manual smoke only).
- **Beta/prod targeting:** built into the design (`--env`) but **not exercised in v1** (not deployed yet).
- **Deferred:** external-store/dashboard for trends (Supabase), historical ease-index charts beyond the HTML deltas, WhatsApp/Calendar integration tests (those subsystems aren't built yet), visual-regression/pixel diffing, load/perf testing.
- **AI-advisory boundary:** Claude's outputs here (bugs, ease scores, recommendations) are **advisory** and operate only on the test harness/board — consistent with Golden Rule 1.4 (AI never drives product state); it files issues for humans, it does not change the product.

## 14. Self-review (against the request)
- Real, no-mock e2e making all the calls in the system: §2/§5/§7. ✅
- Seed two clinics (solo + multi-staff) via a seed script: §5. ✅
- Playwright drives the product against the seeded data: §6/§7. ✅
- Results accumulate somewhere (durable trend store + local artifacts + retention): §8. ✅
- Claude detects regressions/breakages/bugs: §9.1. ✅
- Legitimate bugs auto-filed with `[BUG][E2E testing]` prefix + dedup: §9.3. ✅
- Per-operation ease-of-use index + easier-way recommendations: §7 (metrics) + §9.2. ✅
- Own repo, never deployed, runs locally against beta/prod/local: §3/§4. ✅
- HTML report + email: §10. ✅
- Runs once a day via `/loop`: §9/§11. ✅
- Golden Rules honored (no prod mutation, preserve history, AI advisory, permissive OSS, secrets, git isolation): §4/§9/§12/§13. ✅
- Placeholder scan: concrete repo/layout/operations/flows/envs; remaining unknowns are explicit §13 decisions, no TBD. ✅
