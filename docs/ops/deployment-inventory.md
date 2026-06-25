# Deployment Inventory — Register System (LIVE)

> **Single source of truth for what is deployed, where, and how to reach it.** Anyone — devs or Claude sessions — should be able to find every URL, ID, and the exact release procedure from here.
> **Procedure:** [release-playbook.md](./release-playbook.md) (how to release) · [deploy-runbook.md](./deploy-runbook.md) (one-time setup + troubleshooting).
> **Status:** first **beta/production LIVE as of 2026-06-25** (issue #121).

## 🌐 Live URLs (all HTTPS, valid SSL)
| What | URL | Hosted on |
|---|---|---|
| **App (frontend)** | https://register.rohan2jos.com | Render web service `register-web` (`register-web-3y2t.onrender.com`, Oregon, Node/Next.js 16) |
| **API (backend)** | https://api.rohan2jos.com | Render web service `register-api` (`register-api-nc0i.onrender.com`, id `srv-d8uf2kkm0tmc73a5hh90`, Oregon, Python/FastAPI) |
| API health | https://api.rohan2jos.com/health · /health/db | (liveness · DB connectivity) |
| **Reports dashboard** | https://reports.rohan2jos.com | Cloudflare Pages + Access (E2E nightly) |

## 🧩 Platforms & accounts
- **Supabase (DB + Auth):** project **`register-beta`**, ref **`wmfvsrujgzbcucwmlcrs`**, region **ap-south-1 (Mumbai)**, URL `https://wmfvsrujgzbcucwmlcrs.supabase.co`. **Separate** from the dev/E2E project (`wxwasnshmnttiixvzeod`) — isolated auth pool for real testers. Schema kept at the repo's Alembic head. Email-confirmation **ON** with **custom Resend SMTP** (sender `noreply@rohan2jos.com`, 100/hr). *Where things are:* DB connection strings = the titlebar **"Connect"** button; API keys = **Settings → API**.
- **Render (compute):** two **free** web services (`register-api`, `register-web`), region **Oregon**, **`autoDeploy: false`** (manual release). Each deploys from its repo's **`render.yaml`** Blueprint. Free tier sleeps when idle → ~50s cold start on first request.
- **Cloudflare (DNS + SSL):** zone **`rohan2jos.com`**. CNAMEs `api` + `register` → the onrender hosts, **DNS-only (grey cloud)** so Render issues the certs.
- **Resend (email):** domain **`rohan2jos.com`** verified; all transactional + auth email sends from **`noreply@rohan2jos.com`**.
- **GitHub (private org):** `Dentist-Register-System/{dentist-registry-backend, dentist-registry-frontend}`.

## 🏗️ Architecture (as-built)
```
Browser → register.rohan2jos.com (Render · Next.js)
            │  API calls (CORS allows this origin)
            ▼
         api.rohan2jos.com (Render · FastAPI)
            │  postgresql+psycopg:// (session pooler)
            ▼
         Supabase beta Postgres (Mumbai)   ── Auth (email/pw) ── Resend SMTP
```

> ### ⚠️ Deviations from the original plan (spec #122 / runbook) — read this
> - **Frontend is on Render, NOT Vercel.** Vercel's free Hobby plan can't deploy private-org repos, and we keep the source private → FE runs as a Render web service (`register-web`), same platform as the backend.
> - **DB/Auth is a SEPARATE beta Supabase project** (`register-beta`), not the dev/E2E project the spec assumed — clean auth pool for real testers.
> - **Cron tick + hook worker are DEFERRED** until SP5.1/#116 ships (the worker code isn't on `main` yet). `HOOK_*` env vars are set but inert.

## 🔐 Secret model (no values live here)
Real values exist **only** in: **Bitwarden** (master vault, items named `Register — …`) **+** `~/Documents/register_workspace/.register-ops.env` (`chmod 600`, outside every repo, **never committed**) **+** the platform dashboards. Key **names** + where to obtain each: [deploy.env.example](./deploy.env.example).

## 🚀 How to deploy / release (summary — full steps in the playbook)
- **Manual, ordered backend → frontend, never auto-deploy.** Procedure: **[release-playbook.md](./release-playbook.md)**.
- **Migrations are controller-only**, never on deploy. **Migration-parity gate:** the beta DB must equal the repo's Alembic head *before* any backend deploy.
- Releases are owned and run **through the QA/DevOps gatekeeper** (one accountable owner).

## ⚠️ Gotchas (learned in the first deploy)
- Supabase hands you `postgresql://…` but the app **and** Alembic need **`postgresql+psycopg://…`** (driver). Render's `DATABASE_URL` uses the `+psycopg`, port-5432 session-pooler form.
- Render custom-domain CNAMEs **must be DNS-only** (proxied/orange cloud breaks the platform SSL cert).
- Free Render = cold starts (~50s after idle) on both services.

---
_Last updated: 2026-06-25 (first beta live). **Keep this current on every deploy/release** — it's the map everyone relies on._
