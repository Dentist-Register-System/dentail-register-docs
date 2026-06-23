# Release Playbook (Claude Code — follow this exactly)

> Governs Golden Rule §19. **This is what Claude Code does after a PR merges.** No auto-deploy exists; releases are manual, deliberate, and ordered **backend → frontend**.

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
- **Migrations:** if the backend PR added a migration, **apply it to Supabase first** via the Supabase MCP (`apply_migration`, offline-review the SQL) — controller-only, never on deploy. Ensure it is **additive/backward-compatible** so the currently-live frontend keeps working (Golden Rule §19.3).
- The secrets file exists: `~/Documents/register_workspace/.register-ops.env` (the script validates).

## Run the release (ordered backend → frontend)
From the docs repo, `cd docs/ops`:
```bash
./deploy.sh release <major|minor>
```
This does, in order (and **aborts before touching the frontend if the backend never goes healthy**):
1. Computes the next version `vX.Y.0` from the latest backend tag.
2. **Backend:** triggers the Render deploy hook (builds `main`) → polls `https://api.rohan2jos.com/health` until 200.
3. **Frontend:** triggers the Vercel production deploy hook (builds `main`).
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

## Future (not now)
Once a separate **beta** environment exists: beta may auto-deploy on merge; **production stays a manual laptop push** following this same backend→frontend order.
