# Production Deployment — Vercel + Render + Supabase — Design Spec

> Status: Draft for review · Date: 2026-06-23 · Requirement source: issue #121 (Infra)
> Scope: stand up the first reachable production environment for the Register System and document a repeatable deploy. Frontend → **Vercel** (`register.rohan2jos.com`), backend → **Render** (`api.rohan2jos.com`), DB/Auth → existing **Supabase** project. DNS/SSL via **Cloudflare**. Everything runs locally only today; this is the first deploy.

---

## 1. Context & Purpose
The product currently runs only on developer machines (dev ports 5433/8000/3000; E2E on 5434/8001/3001). There is no server. This spec defines the first production environment so the app is reachable for beta/QA, using the stack already decided: Vercel (Next.js), Render (FastAPI), Supabase (Postgres + Auth, existing project `wxwasnshmnttiixvzeod`). It must honor Golden Rules §11 (secrets never committed; credentials isolated per environment) and the existing **controller-only migration** discipline (the backend never auto-applies migrations to Supabase).

## 2. Scope Decisions (locked during brainstorming)
- **Frontend → Vercel**, domain `register.rohan2jos.com`; **production tracks `main`**; every PR gets a Vercel **preview URL** (the FE QA surface, since the FE is held for user QA).
- **Backend → Render**, domain `api.rohan2jos.com`, **free instance tier for now** (seamless in-place upgrade to Starter later — instance-type change, no teardown, URL/env preserved). Auto-deploys from `main`.
- **DB/Auth → Supabase (existing)**; connect via the **pooler** connection string; **migrations are controller-only** — applied to Supabase manually via the Supabase MCP after merge, never by Render on deploy/start.
- **Domain `rohan2jos.com`** is already owned and managed on **Cloudflare**. App lives on **subdomains** (`register.`, `api.`); the naked domain is untouched. Migrating to a future brand domain later = re-point DNS + swap a few env vars.
- **DNS records are DNS-only (grey-cloud)** in Cloudflare so Vercel and Render each issue/manage their own SSL (avoids Cloudflare-proxy ↔ platform-SSL conflicts).
- **Hook worker (SP5.1, #116):** in-process lifespan loop runs on the Render service; **cron-job.org** hits `POST /internal/hooks/tick` every minute to wake the free service and drain the backlog. Upgrade path = Render Starter (always-on) via instance flip.
- **Secrets** live only in the Vercel/Render dashboards (and Cloudflare/Supabase). The Supabase **service-role** key and any Cloudflare token never reach the frontend. `.env.example` documents key *names* only.
- **Auto-deploy** for both FE and BE; PR review + CI gates (FE: `tsc`/`build`; BE: `make test`) run before merge.

## 3. Topology
```
Browser ──HTTPS──► register.rohan2jos.com         (Vercel · Next.js · static + SSR)
                      │  fetch → NEXT_PUBLIC_API_BASE_URL
                      ▼
                   api.rohan2jos.com               (Render · FastAPI/uvicorn · free web service)
                      │
                      ├──► Supabase Postgres (pooler)   — app data + controller-applied migrations
                      └──► Supabase Auth / JWKS         — verify bearer tokens
cron-job.org ──POST /internal/hooks/tick (1/min, header X-Hook-Tick-Secret)──► api.rohan2jos.com
```
**DNS (Cloudflare):** CNAME `register` → Vercel target; CNAME `api` → Render target. Both **DNS-only**.

## 4. Frontend — Vercel
- **Import** the `dentist-registry-frontend` GitHub repo into a Vercel project; framework auto-detected (Next.js — `build`/`start` already standard, no `vercel.json` needed).
- **Production branch:** `main`. **Preview deployments:** automatic per PR (`*.vercel.app`).
- **Environment variables** (Production + Preview scopes):
  - `NEXT_PUBLIC_API_BASE_URL=https://api.rohan2jos.com`
  - `NEXT_PUBLIC_SUPABASE_URL=https://wxwasnshmnttiixvzeod.supabase.co`
  - `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY=<publishable key>` (exact env names verified against `src/lib/env.ts`; all three are Zod-validated at boot)
- **Domain:** add `register.rohan2jos.com` as the production domain; Vercel provides the CNAME target for Cloudflare.
- Preview deploys may point at the prod API or a separate preview API — for V1 previews use the prod API (read-mostly QA); revisit if previews need isolation.

## 5. Backend — Render
- **Service:** Web Service, **Free** instance, from the `dentist-registry-backend` repo. Reproduced via a committed **`render.yaml`** Blueprint.
- **Build command:** `pip install uv && uv sync --frozen` (the repo uses `uv`; no Dockerfile today). *Alternative:* a slim `python:3.12` Dockerfile — decide in the plan; native build is simpler for free tier.
- **Start command:** `uv run uvicorn app.main:app --host 0.0.0.0 --port $PORT` (Render injects `$PORT`).
- **Health check path:** `/health` (existing health router).
- **Environment variables:**
  - `DATABASE_URL=<Supabase pooler connection string>` (the `...pooler.supabase.com:5432/postgres` URL already used in dev `.env`)
  - `CORS_ORIGINS=["https://register.rohan2jos.com"]`
  - `SUPABASE_URL=https://wxwasnshmnttiixvzeod.supabase.co`
  - `ENVIRONMENT=production`
  - `HOOK_WORKER_ENABLED=true`, `HOOK_TICK_SECRET=<strong secret>`, `HOOK_POLL_INTERVAL_SECONDS`, `HOOK_MAX_ATTEMPTS`, `HOOK_BATCH_SIZE` (SP5.1 defaults fine)
  - `RESEND_API_KEY` (optional — invite/email is a safe no-op when unset), `EMAIL_FROM`, `APP_BASE_URL=https://register.rohan2jos.com`
- **Custom domain:** add `api.rohan2jos.com`; Render provides the CNAME target for Cloudflare and issues SSL.
- **Auto-deploy:** on push to `main`.
- **No migrations on deploy/start** — the start command runs only uvicorn; `alembic upgrade` is never in build/start (controller-only, §6).

## 6. Database / Auth — Supabase (existing)
- Keep project `wxwasnshmnttiixvzeod`. Backend connects via the **pooler** string in `DATABASE_URL`; app data lives there.
- **Auth:** add `https://register.rohan2jos.com` to **Authentication → URL Configuration → Site URL + Redirect URLs** so email/password + magic links redirect correctly in prod. Keep localhost entries for dev.
- **Migrations remain controller-only:** after a backend PR with a new migration merges, the controller applies it to Supabase via the Supabase MCP (`apply_migration`) — offline-reviewed SQL, exactly as done for prior migrations (e.g. 0017). Render never runs Alembic.

## 7. DNS & SSL — Cloudflare
- In the `rohan2jos.com` zone, add:
  - `CNAME register → <vercel-provided target>` — **DNS-only (grey cloud)**
  - `CNAME api → <render-provided target>` — **DNS-only (grey cloud)**
- DNS-only lets Vercel/Render terminate SSL on their own managed certs (no Cloudflare-proxy/origin-cert conflict). Cloudflare proxying/CDN can be revisited later if desired.

## 8. Secrets & Environments (Golden Rules §11.2 / §11.3)
- All secrets set in the **platform dashboards** (Vercel env, Render env, Supabase, Cloudflare) — never committed. `.env.example` in each repo lists key *names* only.
- **Local ≠ prod:** dev uses local `.env`/`.env.local`; prod uses dashboard values. The Supabase **service-role** key is backend/admin-only (never in the frontend bundle — only the publishable key is `NEXT_PUBLIC_*`).
- `HOOK_TICK_SECRET` is a strong random value, shared only with the cron-job.org job config.

## 9. CORS
- Backend `CORS_ORIGINS` = `["https://register.rohan2jos.com"]` for prod. (Add a preview origin pattern only if PR previews must call the prod API cross-origin and the current middleware requires an explicit origin — confirm against `app/main.py` CORS config in the plan.)

## 10. CI / Auto-deploy
- Vercel + Render both auto-build on push; **production = `main`**. PRs are gated by existing CI (FE `tsc`/`build`, BE `make test`) + review before merge.
- Optional follow-up (not required for first deploy): a GitHub Action that mirrors CI as a required check.

## 11. Cutover & Verification Checklist
1. Vercel project imported; env set (Prod + Preview); first deploy green on `*.vercel.app`.
2. Render service created from `render.yaml`; env set; first deploy green on `*.onrender.com`; `/health` 200.
3. Cloudflare CNAMEs added (DNS-only); `register.` + `api.` verified in Vercel/Render; SSL issued.
4. Supabase Auth Site/Redirect URLs include `https://register.rohan2jos.com`.
5. **Smoke test:** load `register.rohan2jos.com` → sign in (email/password) → a clinic-scoped API call succeeds (CORS OK) → `curl -XPOST https://api.rohan2jos.com/internal/hooks/tick -H "X-Hook-Tick-Secret: …"` returns counts.
6. cron-job.org job created (1/min POST to the tick URL with the secret header); confirm runs in its history.
7. Confirm no migration ran on deploy (controller applies pending migrations via MCP separately).

## 12. Out of Scope
- Custom-domain **purchase** (already owned), multi-region / autoscaling, a full observability/log-aggregation stack, paid tiers (documented as the upgrade path), Cloudflare CDN/WAF tuning, preview-environment DB isolation, blue-green/canary.

## 13. Docs to update (this PR or the plan)
- `tech stack/register-tech-stack.md` — Deployment section: record Vercel/Render/Supabase + domains + controller-only-migrations-in-prod + the hook tick.
- Both repo `README`s — a "Deployment" section (URLs, env var lists, how prod differs from local).
- Consider a Golden Rule note that **prod migrations are controller-applied** (reinforces existing §13.5 discipline).
