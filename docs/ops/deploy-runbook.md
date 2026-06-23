# Production Deploy Runbook — Register System

> Companion to `docs/specs/2026-06-23-production-deployment-design.md` (issue #121).
> Model: **one-time manual setup (accounts + OAuth + tokens), then an idempotent script for the repeatable steps.** Tags: **[MANUAL]** = you, in a browser/terminal · **[SCRIPT]** = `docs/ops/deploy.sh` · **[ASSISTED]** = Claude via MCP/CLI.

## Ops file layout & secret model
| File | Committed? | Holds |
|---|---|---|
| `docs/ops/deploy-runbook.md` | ✅ | this doc |
| `docs/ops/deploy.env.example` | ✅ | key **names** + where to get them |
| `docs/ops/deploy.sh` | ✅ | the automation (no secrets inside) |
| `~/Documents/register_workspace/.register-ops.env` | ❌ **never** | the real secret **values** |

The real env file lives at the **workspace root, which is not a git repo** — it physically cannot be committed into any cloned repo. `chmod 600` it. The script `source`s it and never prints values.

## Prerequisites
- CLIs: `vercel` (`npm i -g vercel`), `jq`, `curl`. (`render` CLI optional — Render is mostly dashboard + `render.yaml`.)
- Accounts: Vercel, Render, Cloudflare (have — `rohan2jos.com`), Supabase (have), cron-job.org.

---

## Phase 0 — One-time setup [MANUAL]

### 0.1 Secrets file
```bash
cp dentail-register-docs/docs/ops/deploy.env.example ~/Documents/register_workspace/.register-ops.env
chmod 600 ~/Documents/register_workspace/.register-ops.env
# generate the tick secret:
openssl rand -hex 24    # paste as HOOK_TICK_SECRET (and reuse it on Render, step 0.3)
```

### 0.2 Vercel (frontend)
1. Vercel → **Add New → Project** → import `dentist-registry-frontend` from GitHub (authorize the GitHub app). Framework auto-detected (Next.js).
2. Set **Production Branch = main** (Settings → Git), then **disable production auto-deploy** (Settings → Git → turn off automatic production deployments / set `git.deploymentEnabled=false`). Keep **preview deployments on** (per-PR QA). Production is promoted manually during a release.
3. Add domain **register.rohan2jos.com** (Settings → Domains) → copy the **CNAME target** Vercel shows → put in `VERCEL_CNAME_TARGET`.
4. Terminal: `vercel login` (interactive — token stays with the CLI, not in any file).

### 0.3 Render (backend)
1. Add `render.yaml` to the **backend repo root** (`dentist-registry-backend/render.yaml`) — content below — and also add a `dentist-registry-backend/.python-version` containing `3.12`. (This is a backend-repo change: do it on a feature branch → PR, per the branch/PR rule.)
2. Render → **New → Blueprint** → connect `dentist-registry-backend` → it reads `render.yaml` and creates the **free** web service.
3. In the service → **Environment**, set the `sync:false` secrets: `DATABASE_URL` (the Supabase **pooler** string from dev `.env`), `HOOK_TICK_SECRET` (**same** value as 0.1), and optionally `RESEND_API_KEY`.
4. Settings → **Custom Domain** → add **api.rohan2jos.com** → copy the **CNAME target** → put in `RENDER_CNAME_TARGET`.
5. Settings → **Deploy Hook** → copy the secret URL → put in `RENDER_DEPLOY_HOOK_URL` (this is how the release triggers the backend deploy; `autoDeploy` is off).

`dentist-registry-backend/render.yaml`:
```yaml
services:
  - type: web
    name: register-api
    runtime: python
    plan: free
    buildCommand: pip install uv && uv sync --frozen
    startCommand: uv run uvicorn app.main:app --host 0.0.0.0 --port $PORT
    healthCheckPath: /health
    autoDeploy: false          # Golden Rule §19.1 — no auto-deploy; release is manual via the deploy hook
    envVars:
      - key: ENVIRONMENT
        value: production
      - key: CORS_ORIGINS
        value: '["https://register.rohan2jos.com"]'
      - key: SUPABASE_URL
        value: https://wxwasnshmnttiixvzeod.supabase.co
      - key: APP_BASE_URL
        value: https://register.rohan2jos.com
      - key: HOOK_WORKER_ENABLED
        value: "true"
      - key: EMAIL_FROM
        value: "Register <onboarding@resend.dev>"
      - key: DATABASE_URL
        sync: false          # set in dashboard (secret)
      - key: HOOK_TICK_SECRET
        sync: false
      - key: RESEND_API_KEY
        sync: false
```
> Note: `startCommand` runs **only** uvicorn — **no `alembic upgrade`**. Migrations stay controller-only (Phase 3.2).

### 0.4 Cloudflare token
- Cloudflare → My Profile → **API Tokens → Create** → template "Edit zone DNS", **scoped to `rohan2jos.com` only** → put in `CF_API_TOKEN`. Zone Overview → **Zone ID** → `CF_ZONE_ID`.

### 0.5 cron-job.org
- Sign up → Settings → **API** → key → `CRONJOB_API_KEY`.

### 0.6 Fill the env file
- Open `~/Documents/register_workspace/.register-ops.env` and fill every blank from steps above.

---

## Phase 1 — Run the automation [SCRIPT]
From the docs repo (any worktree), `cd docs/ops` then:
```bash
./deploy.sh preflight     # validates env + Vercel session
./deploy.sh vercel-env    # sets FE env (prod+preview), attaches the domain
./deploy.sh cf-dns        # upserts register/api CNAMEs (DNS-only)
./deploy.sh cron          # creates/updates the 1/min tick job
./deploy.sh smoke         # status-code smoke test
# or: ./deploy.sh all
```
Each phase is idempotent — safe to re-run.

---

## Phase 2 — First deploy [MANUAL, ordered backend→frontend]
This is a release — do it in order (Golden Rule §19.3). Use the script's release flow, or by hand:
- **Backend first:** trigger the Render deploy (`curl -fsS -X POST "$RENDER_DEPLOY_HOOK_URL"`), wait until `https://api.rohan2jos.com/health` is 200. First free-tier build takes a few minutes; the service sleeps when idle (the cron tick wakes it).
- **Frontend next:** from the FE dir, `vercel --prod` → live at `*.vercel.app`, then `register.rohan2jos.com` once DNS+SSL settle.
- (See `release-playbook.md` for the versioned, automated version of this.)

## Phase 3 — Supabase [ASSISTED]
1. **Auth URLs:** add `https://register.rohan2jos.com` to Auth → URL Configuration → **Site URL + Redirect URLs** (keep localhost for dev). *(Claude can apply via the Supabase MCP, or do it in the dashboard.)*
2. **Migrations (controller-only):** after any backend PR with a new migration merges, apply it to Supabase via MCP `apply_migration` (offline-review the SQL first) — exactly as for prior migrations. **Never** runs on deploy.

## Phase 4 — Verify / cutover
- `./deploy.sh smoke` → FE 200/308, API `/health` 200, tick 200 (with secret).
- Browser: load `register.rohan2jos.com` → sign in (email/password) → a clinic-scoped call succeeds (no CORS error in console).
- cron-job.org dashboard → the job shows successful 1-minute runs.
- Confirm SSL is "Active" on both custom domains (Vercel + Render).

---

## Ongoing releases (manual — Golden Rule §19)
- **No auto-deploy.** Merging a PR does **not** deploy. Every PR still gets a Vercel **preview URL** (your FE QA surface).
- After a PR merges, do a **release** per `release-playbook.md`: Claude asks "release? major/minor?", then `./deploy.sh release <major|minor>` runs **backend→frontend** (apply migration via MCP if any → deploy BE + health-check → deploy FE → smoke → tag `vX.Y.0`).
- Re-run `./deploy.sh cf-dns`/`cron` only if DNS or the tick job changes.

## Troubleshooting
- **CORS error in browser:** `CORS_ORIGINS` on Render must be exactly `["https://register.rohan2jos.com"]`; redeploy after changing.
- **SSL "pending"/cert error:** ensure the Cloudflare CNAME is **DNS-only (grey cloud)** — proxied (orange) conflicts with platform-managed certs.
- **First request slow (~30–60s):** free Render cold start after idle; the cron tick keeps it warmer. Upgrade to Starter (instance-type change, no teardown) for always-on.
- **Tick 401:** `X-Hook-Tick-Secret` header must equal `HOOK_TICK_SECRET` set on Render.
- **Auth redirect fails:** the prod URL isn't in Supabase Auth redirect URLs (Phase 3.1).

## Security notes (Golden Rules §11)
- Real secrets only in `~/Documents/register_workspace/.register-ops.env` (outside repos, `chmod 600`) + the platform dashboards. Never committed.
- Vercel/Render account auth stays in their CLIs via interactive `login` (not in any file). The Cloudflare token is **DNS-edit, single-zone** scoped.
- Rotate the Supabase **service-role** key before onboarding real clinics (it is admin-level). The script never echoes secret values.
