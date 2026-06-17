# Walking Skeleton (Sub-project 0) — Design Spec

> Status: Revised after design review (v2)
> Date: 2026-06-17
> Author: Brainstormed via Claude Code (superpowers:brainstorming)
> Sub-project: 0 of the Register System build sequence

---

## 1. Context & Purpose

The Register System is a clinic scheduling & coordination platform (FastAPI backend +
Next.js frontend + Supabase), spanning 19 entities and 13 workflows. It is too large for a
single implementation. We are decomposing it into sub-projects, each with its own
spec → plan → implementation cycle:

| # | Sub-project | Delivers |
|---|---|---|
| **0** | **Walking skeleton (this spec)** | Both repos scaffolded, local Postgres wired, one throwaway vertical slice proving every layer, tests + CI + dev workflow + conventions |
| 1 | Auth + clinic workspace | Supabase phone-OTP + email/pw, clinic boundary, roles |
| 2 | Core entities | Clinic, settings, doctor, assistant, patient CRUD + patient search |
| 3 | Scheduling engine | Availability → slots → requests → approval → appointments (atomic capacity) |
| 4 | Audit + hooks | Append-only audit, DB-backed hook worker |
| 5 | Integrations | WhatsApp + Google Calendar adapters (downstream only) |
| 6 | Notifications, follow-ups, dashboards, AI brief | Coordination surface |

**This sub-project's job:** prove the entire stack end-to-end and harden the conventions
every future feature will copy — *before* any real domain logic is built. It de-risks
everything downstream.

The slice built here is **throwaway**: it is deleted once real features begin. Its value is
the proven plumbing and the established conventions, not the feature itself. Because the
skeleton *sets the patterns* for all 19 entities, decisions that are cheap now but expensive
to retrofit later are deliberately locked here.

---

## 2. Scope Decisions (locked during brainstorming + design review)

- **Two separate repos** (per tech stack): `dentist-registry-backend` (FastAPI),
  `dentist-registry-frontend` (Next.js). No monorepo.
- **Local-first.** Nothing is provisioned yet (no Supabase/Render/Vercel). Provisioning and
  deployment (CD) are a *later step within this sub-project*, after local works end-to-end.
- **Local Postgres via Docker Compose** for the DB. `DATABASE_URL` repoints to Supabase
  Postgres later with no code change.
- **Full read + write vertical slice** through a throwaway `ping_beta` entity, exercising
  every documented layer once.
- **Backend layout: feature-first modular monolith** — organized by domain module
  (`app/modules/<domain>/`), each module retaining a service layer (business logic
  backend-side, per Golden Rules 13.1/13.2). See §3a for the import-discipline rules that
  keep this from degrading into cross-module spaghetti.
- **Sync SQLAlchemy** (not async) — simplest for this scale; do not introduce async.
- **Database conventions locked now** (§4a): UUID primary keys, timezone-aware timestamps,
  and a `MetaData` constraint-naming convention.
- **Consistent API error contract** + FastAPI exception handlers from day one (§6).
- **Reproducible installs:** committed lockfiles in both repos; `uv` for Python tooling.
- **CI from day one** (lint + tests on every PR); CD remains deferred.
- **`CLAUDE.md` in each code repo** to orient AI-assisted development and onboarding.
- **Tests run against Postgres** (never SQLite).
- **Beta table naming** per Golden Rule 4.5: the throwaway table is `ping_beta`.

### Out of scope (explicit)
Auth / Supabase integration; any real domain entity (clinic, patient, etc.); deployment to
Render/Vercel (CD); WhatsApp / Google Calendar / hooks / audit / AI; shadcn theming beyond
defaults; OpenAPI→TypeScript type generation (planned for sub-project 2, not the throwaway
slice).

---

## 3. Architecture Overview

```
Next.js (App Router, :3000)  ──REST──▶  FastAPI (:8000)  ──SQLAlchemy 2.x (sync)──▶  Postgres (Docker, :5432)
  TanStack Query + RHF/Zod                /api/v1, feature modules                       table: ping_beta
  shadcn/ui + Tailwind                     services own DB access + logic
  typed api-client (parses error envelope) Pydantic schemas, Alembic migrations
```

The `ping_beta` entity flows through every layer once. CORS on the backend allows the
frontend origin (`http://localhost:3000`).

---

## 3a. Module Boundaries & Import Discipline (anti-spaghetti)

Feature-first structure only pays off if dependencies flow one way. These rules are
**mandatory** and belong in the backend `CLAUDE.md`:

1. **One-way dependency direction:** `core/` ← `modules/` ← `main.py`.
   - `core/` (config, database, deps, errors, logging) is shared and imports *nothing* from
     `modules/`.
   - A module may import from `core/`. A module must **not** reach into another module's
     internals.
2. **Cross-module calls go through the other module's `service`** (its public interface),
   never through its `models`/`router`/internal helpers. If two modules need shared types,
   the shared type moves to `core/` or a small shared module — it is not imported sideways.
3. **No circular imports.** SQLAlchemy relationships across modules use string-based
   references (e.g. `relationship("Patient")`, `ForeignKey("patient.id")`), so modules don't
   import each other's model classes at definition time.
4. **Single Alembic model registry:** one module (`app/db/base.py`) imports every model so
   Alembic autogenerate sees the full metadata. This is the *only* place that aggregates
   models; modules never import models from each other to "register" them.
5. **Small, single-purpose files.** When a module file grows large, split by responsibility
   within the module folder rather than spilling logic into routers or other modules.
6. **Routers are thin.** Routers parse/validate input, call a service, shape the response.
   No business logic or direct DB queries in routers (Golden Rule 13.2).

These rules are enforced by review (and, where cheap, by `ruff` import rules). The intent:
touching one feature should mean opening one folder, with imports that point only "inward."

---

## 4. Backend — `dentist-registry-backend`

### Directory layout (feature-first)
```
app/
├── main.py                      # app factory; CORS (:3000); mounts each module router under /api/v1
├── core/
│   ├── config.py                # Pydantic Settings (DATABASE_URL, CORS origins, env)
│   ├── database.py              # SQLAlchemy 2.x engine + Session dependency
│   ├── base.py                  # DeclarativeBase + MetaData naming convention (§4a)
│   ├── deps.py                  # shared FastAPI dependencies (db session)
│   ├── errors.py                # DomainError types + exception handlers + error envelope
│   └── logging.py               # minimal structured, PII-aware logging config
├── db/
│   └── base.py                  # imports ALL models for Alembic autogenerate (single registry)
├── modules/
│   └── ping/                    # THROWAWAY domain module
│       ├── router.py            # GET /pings, POST /pings (mounted at /api/v1/pings)
│       ├── schemas.py           # Pydantic request/response models
│       ├── models.py            # PingBeta ORM model → table `ping_beta`
│       └── service.py           # business logic: create_ping(), list_pings()
└── health.py                    # GET /health (liveness), GET /health/db (DB connectivity)
alembic/
├── env.py                       # imports app/db/base.py metadata for autogenerate
└── versions/0001_create_ping_beta.py
tests/
├── conftest.py                  # Postgres test DB fixtures, transactional rollback, TestClient
└── ping/
    ├── test_service.py          # unit: service against a session
    └── test_router.py           # integration: API via TestClient
.github/workflows/ci.yml         # ruff + pytest on PR (Postgres service container)
pyproject.toml                   # deps + tool config (ruff, pytest)
uv.lock                          # committed lockfile
alembic.ini
Makefile                         # install (uv sync), migrate, run, test, lint
docker-compose.yml               # postgres:16 service
.env.example                     # DATABASE_URL, CORS origins (no real secrets)
CLAUDE.md                        # conventions, structure, commands, source-of-truth links
README.md
```

### Health endpoints
- `GET /health` → liveness, no DB touch (used by deploy platforms later).
- `GET /health/db` → executes a trivial query to confirm DB connectivity.

### Dependencies (all permissive OSS — MIT/BSD/Apache, satisfying Golden Rule 3.1 and the
license-vetting habit)
`fastapi`, `uvicorn[standard]`, `sqlalchemy>=2`, `alembic`, `pydantic`, `pydantic-settings`,
`psycopg[binary]`; dev: `pytest`, `httpx`, `ruff`. Tooling: `uv`.

---

## 4a. Database Conventions (locked — expensive to retrofit)

1. **Primary keys: UUID.** Non-enumerable IDs avoid leaking record counts / enabling scraping
   via sequential URLs — appropriate for a healthcare-adjacent system. (UUIDv7 acceptable if
   index locality matters later; default UUID is fine at clinic scale.)
2. **Timestamps: timezone-aware.** `TIMESTAMP WITH TIME ZONE`, `server_default=func.now()`,
   storing UTC. Naive timestamps are forbidden — appointment times must be unambiguous.
3. **Constraint/index naming convention** set once on `Base.metadata.naming_convention`
   (standard `ix_/uq_/ck_/fk_/pk_` templates) so Alembic autogenerate emits consistent,
   named constraints and future `ALTER`/downgrade migrations are stable.

---

## 5. Frontend — `dentist-registry-frontend`

### Directory layout (feature-first)
```
src/
├── app/
│   ├── layout.tsx               # root layout; wraps providers
│   ├── providers.tsx            # 'use client' — TanStack Query QueryClientProvider
│   └── page.tsx                 # home: backend health badge + ping list + add-ping form
├── lib/
│   ├── api-client.ts            # typed fetch wrapper; base URL from env; parses error envelope
│   └── env.ts                   # zod-validated NEXT_PUBLIC_ env access
└── features/ping/
    ├── api.ts                   # query/mutation functions calling the backend
    ├── hooks.ts                 # usePings (useQuery), useCreatePing (useMutation)
    ├── schema.ts                # Zod schema for the form
    └── ping-form.tsx            # React Hook Form + Zod + shadcn form
components/ui/                    # shadcn components (button, input, form, card)
tests/e2e/ping.spec.ts            # Playwright full-stack happy-path
.github/workflows/ci.yml          # typecheck + build (+ optional Playwright) on PR
playwright.config.ts
components.json                   # shadcn config
tailwind config + globals.css
next.config.ts
package.json + package-lock.json  # committed lockfile
.env.local.example                # NEXT_PUBLIC_API_BASE_URL
CLAUDE.md                         # conventions, structure, commands, source-of-truth links
README.md
```

### Stack & conventions
Next.js (App Router) + TypeScript, shadcn/ui, Tailwind, React Hook Form, Zod, TanStack Query.
REST only; local component state + TanStack Query (no Redux). Client-side data fetching
against FastAPI is the chosen pattern (the app is effectively a client talking to a separate
API) — providers and forms are client components; we don't fight RSC by forcing server-side
fetching here.

**Going-forward testing split (documented now, not built in the skeleton):** Vitest + React
Testing Library for component/logic units (API mocked); Playwright reserved for true
end-to-end flows. The skeleton ships the one full-stack Playwright happy-path only.

---

## 6. API Contract — `ping_beta` + error envelope

All routes are mounted under **`/api/v1`**.

**Entity fields:** `id` (UUID, PK), `message` (string, required, non-empty),
`created_at` (timestamptz, server-set).

**Success endpoints:**
| Method | Path | Request | Response |
|---|---|---|---|
| `POST` | `/api/v1/pings` | `{ "message": "<non-empty string>" }` | `201 { id, message, created_at }` |
| `GET` | `/api/v1/pings` | — | `200 [ { id, message, created_at }, ... ]` (newest first) |

**Error envelope** (uniform across the whole API):
```json
{ "error": { "code": "string", "message": "human-readable", "details": { } } }
```
- FastAPI exception handlers map validation errors and app-level `DomainError`s to this shape.
- The skeleton demonstrates it with one deliberate path: `POST /api/v1/pings` with an empty
  `message` returns `422` in the envelope, and the frontend `api-client` parses and surfaces it.

**Frontend behavior:** home page calls `GET /health/db` for a status badge, lists pings via
`useQuery`, and renders an RHF+Zod form that `POST`s a ping via `useMutation`; on success it
invalidates the pings query so the new row appears; on error it shows the parsed envelope
message.

---

## 7. Local Development Workflow

**Backend**
```bash
docker compose up -d     # start postgres:16
make install             # uv sync (creates venv + installs from uv.lock)
make migrate             # alembic upgrade head → creates ping_beta
make run                 # uvicorn on http://localhost:8000
make test                # pytest against the Postgres test database
make lint                # ruff
```

**Frontend**
```bash
npm install
npm run dev              # http://localhost:3000
npm run test:e2e         # Playwright happy-path (full stack must be up)
```

**Env files** (`.example` committed, real values local only — Golden Rule 11.2):
- Backend `.env`: `DATABASE_URL=postgresql+psycopg://...localhost:5432/...`, CORS origins.
  docker-compose credentials must match this.
- Frontend `.env.local`: `NEXT_PUBLIC_API_BASE_URL=http://localhost:8000`.

---

## 8. Testing (establishes the P0 pattern)

- **Engine: Postgres, never SQLite.** Tests run against a dedicated test database on the same
  Docker Postgres. This matters because the scheduling engine (sub-project 3) depends on
  Postgres-specific row locking (`SELECT … FOR UPDATE`) for atomic capacity (Golden Rules 5.2,
  10.4); SQLite would give false confidence and can't express those concurrency tests.
- **Backend (pytest):**
  - *Unit* — `ping_service` create/list against a session.
  - *Integration* — API via `TestClient`, per-test transactional rollback for isolation.
  - *Error path* — empty `message` returns the `422` error envelope.
- **Frontend (Playwright):** one full-stack happy-path — load home, submit the form, assert
  the new ping appears. (Vitest component tests are the documented going-forward default but
  are not part of the skeleton.)

---

## 9. CI/CD

**CI (now):** GitHub Actions on every PR, per repo.
- Backend `ci.yml`: spin up a Postgres service container → `uv sync` → `make lint` (ruff) →
  `make migrate` → `make test` (pytest).
- Frontend `ci.yml`: `npm ci` → typecheck → `next build`. (Full-stack Playwright in CI is
  optional initially — it needs the backend; if enabled, run it as a separate job that boots
  both. Default: keep PR CI fast; run e2e locally / pre-merge.)

**CD (deferred):** deployment to Render (backend) / Vercel (frontend) + remote Supabase is a
follow-on step in this sub-project, started only once local + CI are green.

---

## 10. Git / PR Workflow

Per the personal-environment rules: never push to `main` directly; always feature branch →
PR → review → merge, using `gh-personal` and the `github-personal` remote.

Deliverables:
- **Spec PR** (this document) in `dentail-register-docs` from branch `spec/walking-skeleton`.
- **Plan** in `dentail-register-docs/docs/plans/` (written via writing-plans before code).
- **Backend PR** in `dentist-registry-backend` (scaffold + slice + CI + CLAUDE.md).
- **Frontend PR** in `dentist-registry-frontend` (scaffold + slice + CI + CLAUDE.md).

---

## 11. Acceptance Criteria

The walking skeleton is complete when:
1. `docker compose up -d` + `make migrate` + `make run` brings the backend up with
   `ping_beta` created; `GET /health` and `GET /health/db` both return healthy.
2. `npm run dev` serves the home page; it shows a healthy backend badge.
3. Submitting the form creates a ping; it appears in the list without a manual refresh.
4. Submitting an empty message surfaces the parsed error-envelope message in the UI.
5. Backend unit + integration + error-path tests pass against Postgres (`make test`).
6. Frontend Playwright happy-path passes.
7. **CI is green on both repos' PRs** (ruff + pytest; typecheck + build).
8. Committed **lockfiles** exist (`uv.lock`, `package-lock.json`).
9. **`CLAUDE.md`** exists in each code repo with structure, conventions, commands, and
   source-of-truth links.
10. DB conventions are in force: UUID PKs, tz-aware timestamps, `MetaData` naming convention.
11. `.env.example` / `.env.local.example` exist; no real secrets committed.
12. All three PRs (spec, backend, frontend) are merged via `gh-personal`.

(CD — Render/Vercel + remote Supabase — is a follow-on step once the above is green.)

---

## 12. Known Domain Ambiguities (deferred — do NOT touch the skeleton)

The domain digest surfaced ~13 ambiguities (e.g., availability-window state transitions,
slot lifecycle during schedule changes, `created_by`/`requested_by`/`approved_by` semantics,
patient-deletion vs. audit retention, follow-up status reversion). None affect the walking
skeleton. They should be resolved before the scheduling-engine sub-project (#3).

**Sequencing note (from review):** Golden Rule 7.1 requires audit events for scheduling
actions, but Audit (#4) currently follows the Scheduling engine (#3). When we reach #3 we
will build a minimal append-only audit primitive *alongside* the scheduling transitions
(within the same transaction, Golden Rule 13.3) and expand it in #4, rather than retrofitting
audit calls afterward. To be finalized at the #3 spec.
