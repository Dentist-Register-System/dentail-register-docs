# Release Playbook (Claude Code — follow this exactly)

> Governs Golden Rule §19. **This is what Claude Code does after a PR merges.** No auto-deploy exists; releases are manual, deliberate, and ordered **backend → frontend**.
>
> **🟢 AS-BUILT (2026-06-25) — see [`deployment-inventory.md`](./deployment-inventory.md):** both FE and BE run on **Render** (the FE moved off Vercel). So the Vercel-specific bits below are superseded. Until `deploy.sh` is updated for the Render FE, run a release by triggering **each service's Render deploy hook** (`.register-ops.env`) **or** the Render dashboard → **Manual Deploy → Deploy latest commit**, **backend first**, then verify `api.rohan2jos.com/health` before the frontend.

## When this triggers
After development completes **and the PR is merged** (FE, BE, or both), Claude Code must offer a release. Do **not** release on your own initiative or before merge.

## The conversation (verbatim intent)
1. Ask: **"Do you want to do a release?"**
   - If **no** → stop. (Work is merged; deploy later.)
2. If yes, ask: **"Major or minor version?"**
   - *minor* = backward-compatible additions/fixes · *major* = breaking/large change.
3. Then run the release below. Confirm the computed version with the user before tagging if they want a say.

## Preconditions (check before releasing)
- The relevant PR(s) are **merged to `main`** (deploy hooks build `main`).
- **Migrations (parity gate):** before any backend deploy, the **beta Supabase DB must equal the repo's Alembic head**. If a backend PR added migrations, apply them to beta **first** — controller-only, never on deploy — via the Supabase MCP (`apply_migration`) **or** `alembic upgrade head` against the beta connection (the beta project isn't the MCP-scoped one, so Alembic-direct is typical). Offline-review the SQL; ensure it's **additive/backward-compatible** so the live frontend keeps working (Golden Rule §19.3). Abort the release if parity can't be reached.
- The secrets file exists: `~/Documents/register_workspace/.register-ops.env` (the script validates).

## Run the release (ordered backend → frontend)
From the docs repo, `cd docs/ops`:
```bash
./deploy.sh release <major|minor>
```
This does, in order (and **aborts before touching the frontend if the backend never goes healthy**):
1. Computes the next version `vX.Y.0` from the latest backend tag.
2. **Backend:** triggers the Render deploy hook (builds `main`) → polls `https://api.rohan2jos.com/health` until 200.
3. **Frontend:** triggers the **Render `register-web`** deploy hook (builds `main`). *(Was Vercel in the original plan; FE is now a Render service.)*
4. **Smoke:** FE / API `/health` / tick endpoint status codes.
5. **Tags** both repos at `main` → `vX.Y.0` (remote, via `gh` — never touches working trees).

Equivalent manual order if running by hand: `./deploy.sh deploy-be` (wait healthy) → `./deploy.sh deploy-fe` → `./deploy.sh smoke`.

## Hard rules (do not violate)
- **Backend first, always.** Never deploy the frontend ahead of the backend (Golden Rule §19.3). The script enforces this by aborting if the backend isn't healthy.
- **Never enable auto-deploy** to "save a step" (Golden Rule §19.1).
- **Never run `alembic upgrade` on deploy** — migrations are controller-only via MCP.
- **Never echo secret values.** The script sources them and prints only status.

## After the release
- Report: the version, BE/FE deploy results, smoke status codes, tags created.
- Move the relevant board item(s) to **In Review/Completed** as appropriate.
- If anything failed mid-release (e.g. BE healthy but FE deploy failed), say so plainly — the FE may be behind the BE, which is the safe direction, but flag it.

## Key rotation (standing)
Secrets pass through automation/Claude context during releases. **Rotate the deploy keys weekly** (see the standing weekly reminder): Cloudflare DNS token, Render & Vercel deploy-hook URLs, `HOOK_TICK_SECRET` (update on Render + cron-job.org together), cron-job.org API key, and the Supabase service-role key before real clinics. After rotating, update `~/Documents/register_workspace/.register-ops.env`.

## Environments
The live environment is **beta** (separate Supabase project `register-beta`; see [`deployment-inventory.md`](./deployment-inventory.md)) on Render free tier, released manually per the order above. A future dedicated **production** environment stays a manual push following this same backend→frontend order; beta could later auto-deploy on merge if desired.
