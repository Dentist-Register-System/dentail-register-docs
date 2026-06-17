# Walking Skeleton (Sub-project 0) — Design Spec

> Status: Draft for review
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
| **0** | **Walking skeleton (this spec)** | Both repos scaffolded, local Postgres wired, one throwaway vertical slice proving every layer, tests + dev workflow |
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
the proven plumbing and the established pattern, not the feature itself.

---

## 2. Scope Decisions (locked during brainstorming)

- **Two separate repos** (per tech stack): `dentist-registry-backend` (FastAPI),
  `dentist-registry-frontend` (Next.js). No monorepo.
- **Local-first.** Nothing is provisioned yet (no Supabase/Render/Vercel). Provisioning and
  deployment are a *later step within this sub-project*, after local works end-to-end.
- **Local Postgres via Docker Compose** for the DB. `DATABASE_URL` repoints to Supabase
  Postgres later with no code change.
- **Full read + write vertical slice** through a throwaway `ping_beta` entity, exercising
  every documented layer once.
- **Backend layout: layered modular monolith** (`routes → services → models`) from day one,
  per Golden Rules 13.1 (modular monolith) and 13.2 (business logic backend-side, not in UI
  or routes).
- **Beta table naming** per Golden Rule 4.5: the throwaway table is `ping_beta`.

### Out of scope (explicit)
Auth / Supabase integration; any real domain entity (clinic, patient, etc.); deployment to
Render/Vercel; WhatsApp / Google Calendar / hooks / audit / AI; shadcn theming beyond
defaults.

---

## 3. Architecture Overview

```
Next.js (App Router, :3000)  ──REST──▶  FastAPI (:8000)  ──SQLAlchemy 2.x──▶  Postgres (Docker, :5432)
  TanStack Query + RHF/Zod                routes → services → models                 table: ping_beta
  shadcn/ui + Tailwind                     Pydantic schemas, Alembic migrations
```

The `ping_beta` entity flows through every layer once. CORS on the backend allows the
frontend origin (`http://localhost:3000`).

---

## 4. Backend — `dentist-registry-backend`

### Directory layout
```
app/
├── main.py                      # FastAPI app factory; CORS (allow :3000); mounts routers
├── core/
│   ├── config.py                # Pydantic Settings (env-driven: DATABASE_URL, CORS origins)
│   └── database.py              # SQLAlchemy 2.x engine + session dependency
├── models/
│   └── ping.py                  # PingBeta ORM model → table `ping_beta`
├── schemas/
│   └── ping.py                  # Pydantic request/response models
├── services/
│   └── ping_service.py          # business logic: create_ping(), list_pings()
└── api/
    ├── deps.py                  # shared dependencies (db session)
    └── routes/
        ├── health.py            # GET /health (liveness), GET /health/db (DB connectivity)
        └── ping.py             # GET /api/pings, POST /api/pings
alembic/
├── env.py                       # wired to models' metadata
└── versions/0001_create_ping_beta.py
tests/
├── conftest.py                  # test DB fixtures, transactional rollback, TestClient
├── unit/test_ping_service.py
└── integration/test_ping_api.py
alembic.ini
pyproject.toml                   # dependency + tool config
Makefile                         # install, migrate, run, test, lint
docker-compose.yml               # postgres:16 service
.env.example                     # DATABASE_URL, CORS origins (no real secrets)
README.md
```

### Layering rule
Routes call services; services own all DB access and business logic; routes never touch the
DB session directly except to pass it into a service. This establishes the boundary the
Golden Rules require and is the pattern every future feature copies.

### Health endpoints
- `GET /health` → liveness, no DB touch (used by deploy platforms later).
- `GET /health/db` → executes a trivial query to confirm DB connectivity.

### Dependencies (all OSS — MIT/BSD/Apache, satisfying Golden Rule 3.1)
`fastapi`, `uvicorn[standard]`, `sqlalchemy>=2`, `alembic`, `pydantic`, `pydantic-settings`,
`psycopg[binary]`; dev: `pytest`, `httpx`, `ruff`.

---

## 5. Frontend — `dentist-registry-frontend`

### Directory layout
```
src/
├── app/
│   ├── layout.tsx               # root layout; wraps providers
│   ├── providers.tsx            # TanStack Query QueryClientProvider
│   └── page.tsx                 # home: backend health badge + ping list + add-ping form
├── lib/
│   ├── api-client.ts            # typed fetch wrapper; base URL from env
│   └── env.ts                   # zod-validated NEXT_PUBLIC_ env access
├── features/ping/
│   ├── api.ts                   # query/mutation functions calling the backend
│   ├── hooks.ts                 # usePings (useQuery), useCreatePing (useMutation)
│   ├── schema.ts                # Zod schema for the form
│   └── ping-form.tsx            # React Hook Form + Zod + shadcn form
└── components/ui/               # shadcn components (button, input, form, card)
tests/e2e/ping.spec.ts           # Playwright happy-path
playwright.config.ts
components.json                  # shadcn config
tailwind config + globals.css
next.config.ts
package.json
.env.local.example               # NEXT_PUBLIC_API_BASE_URL
README.md
```

### Stack (per tech stack doc)
Next.js (App Router) + TypeScript, shadcn/ui, Tailwind, React Hook Form, Zod, TanStack Query.
REST only. Local component state + TanStack Query (no Redux).

---

## 6. Vertical Slice Contract — `ping_beta`

**Entity fields:** `id` (primary key), `message` (string, required, non-empty),
`created_at` (timestamp, server-set).

**Endpoints:**
| Method | Path | Request | Response |
|---|---|---|---|
| `POST` | `/api/pings` | `{ "message": "<non-empty string>" }` | `201 { id, message, created_at }` |
| `GET` | `/api/pings` | — | `200 [ { id, message, created_at }, ... ]` (newest first) |

**Frontend behavior:** home page calls `GET /health/db` for a status badge, lists pings via
`useQuery`, and renders an RHF+Zod form that `POST`s a ping via `useMutation`; on success it
invalidates the pings query so the new row appears. Validation: message required, non-empty.

---

## 7. Local Development Workflow

**Backend**
```bash
docker compose up -d     # start postgres:16
make install             # create venv + install deps
make migrate             # alembic upgrade head → creates ping_beta
make run                 # uvicorn on http://localhost:8000
```

**Frontend**
```bash
npm install
npm run dev              # http://localhost:3000
```

**Env files** (`.example` committed, real values local only — Golden Rule 11.2):
- Backend `.env`: `DATABASE_URL=postgresql+psycopg://...localhost:5432/...`, CORS origins.
- Frontend `.env.local`: `NEXT_PUBLIC_API_BASE_URL=http://localhost:8000`.

---

## 8. Testing (establishes the P0 pattern)

- **Backend (pytest):**
  - *Unit* — `ping_service` create/list against a session.
  - *Integration* — API via `TestClient` against a test database, with per-test
    transactional rollback so tests are isolated and repeatable.
- **Frontend (Playwright):** one happy-path e2e — load home, submit the form, assert the new
  ping appears in the list.
- This is intentionally the smallest set that demonstrates the unit + integration + e2e
  layers future features will follow (Golden Rules 10.1–10.2).

---

## 9. Git / PR Workflow

Per the personal-environment rules: never push to `main` directly; always feature branch →
PR → review → merge, using `gh-personal` and the `github-personal` remote.

Deliverables:
- **Spec PR** (this document) in `dentail-register-docs` from branch `spec/walking-skeleton`.
- **Backend PR** in `dentist-registry-backend` (scaffold + slice).
- **Frontend PR** in `dentist-registry-frontend` (scaffold + slice).

---

## 10. Acceptance Criteria

The walking skeleton is complete when:
1. `docker compose up -d` + `make migrate` + `make run` brings the backend up with
   `ping_beta` created; `GET /health` and `GET /health/db` both return healthy.
2. `npm run dev` serves the home page; it shows a healthy backend badge.
3. Submitting the form creates a ping; it appears in the list without a manual refresh.
4. Backend unit + integration tests pass (`make test`).
5. Frontend Playwright happy-path passes.
6. `.env.example` / `.env.local.example` exist; no real secrets committed.
7. All three PRs (spec, backend, frontend) are merged via `gh-personal`.

(Deployment to Render/Vercel + remote Supabase is a follow-on step in this sub-project,
tracked separately once local is green.)

---

## 11. Known Domain Ambiguities (deferred — do NOT touch the skeleton)

The domain digest surfaced ~13 ambiguities (e.g., availability-window state transitions,
slot lifecycle during schedule changes, `created_by`/`requested_by`/`approved_by` semantics,
patient-deletion vs. audit retention, follow-up status reversion). None affect the walking
skeleton. They should be resolved before the scheduling-engine sub-project (#3).
