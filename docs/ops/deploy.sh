#!/usr/bin/env bash
# Register System — production deploy automation (idempotent).
#
# NO auto-deploy (Golden Rule §19). Releases are MANUAL and ordered backend→frontend.
# One-time account creation, GitHub OAuth, Render service creation, `vercel login`,
# and creating the deploy hooks are MANUAL — see deploy-runbook.md.
#
# Secrets are NEVER in this file. They are sourced from a local env file that lives
# OUTSIDE every git repo (default: ~/Documents/register_workspace/.register-ops.env).
# Secret values are never echoed. Deploys use deploy-hook URLs (build `main` from
# GitHub) so this script never touches the shared working trees.
#
# Usage:
#   ./deploy.sh preflight                 validate env
#   ./deploy.sh vercel-env                push FE env (prod+preview), attach domain  [one-time / on change]
#   ./deploy.sh cf-dns                    upsert register/api CNAMEs (DNS-only)       [one-time / on change]
#   ./deploy.sh cron                      create/update the 1/min hook tick           [one-time / on change]
#   ./deploy.sh deploy-be                 trigger backend deploy + wait for /health
#   ./deploy.sh deploy-fe                 trigger frontend production deploy
#   ./deploy.sh release <major|minor>     FULL release: BE → health → FE → smoke → tag both repos
#   ./deploy.sh smoke                     status-code smoke test
set -euo pipefail

ENV_FILE="${REGISTER_OPS_ENV:-$HOME/Documents/register_workspace/.register-ops.env}"
GH_CLI="${GH_CLI:-gh-personal}"
HEALTH_TRIES="${HEALTH_TRIES:-40}"      # × 15s ≈ 10 min max wait for backend health
HEALTH_SLEEP="${HEALTH_SLEEP:-15}"

log()  { printf '\033[1;36m[deploy]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[deploy:error]\033[0m %s\n' "$*" >&2; exit 1; }
require() { for v in "$@"; do [ -n "${!v:-}" ] || die "missing required env var: $v"; done; }

load_env() {
  [ -f "$ENV_FILE" ] || die "secrets file not found: $ENV_FILE — copy docs/ops/deploy.env.example, fill it, chmod 600"
  # shellcheck disable=SC1090
  set -a; source "$ENV_FILE"; set +a
}

preflight() {
  load_env
  for c in curl jq; do command -v "$c" >/dev/null || die "missing CLI: $c"; done
  require FRONTEND_DOMAIN BACKEND_DOMAIN HOOK_TICK_SECRET
  log "preflight OK — env loaded"
}

# ---------- One-time: Vercel env + domain (needs `vercel login`) ----------
_vercel_set_env() {  # NAME VALUE
  local name="$1" val="$2" tgt
  for tgt in production preview; do
    vercel env rm "$name" "$tgt" -y >/dev/null 2>&1 || true
    printf '%s' "$val" | vercel env add "$name" "$tgt" >/dev/null
  done
  log "vercel env set: $name (production+preview)"   # value never printed
}
vercel_env() {
  preflight
  command -v vercel >/dev/null || die "missing CLI: vercel (npm i -g vercel)"
  vercel whoami >/dev/null 2>&1 || die "not logged in to Vercel — run: vercel login"
  require NEXT_PUBLIC_API_BASE_URL NEXT_PUBLIC_SUPABASE_URL NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY VERCEL_PROJECT_DIR FRONTEND_DOMAIN
  pushd "$VERCEL_PROJECT_DIR" >/dev/null || die "frontend dir not found: $VERCEL_PROJECT_DIR"
  vercel link --yes >/dev/null 2>&1 || true
  _vercel_set_env NEXT_PUBLIC_API_BASE_URL "$NEXT_PUBLIC_API_BASE_URL"
  _vercel_set_env NEXT_PUBLIC_SUPABASE_URL "$NEXT_PUBLIC_SUPABASE_URL"
  _vercel_set_env NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY "$NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY"
  vercel domains add "$FRONTEND_DOMAIN" >/dev/null 2>&1 || log "domain likely already attached: $FRONTEND_DOMAIN"
  popd >/dev/null
  log "vercel-env done"
}

# ---------- One-time: Cloudflare DNS (upsert CNAME, DNS-only) ----------
_cf_upsert_cname() {  # subdomain target
  local sub="$1" target="$2"
  local api="https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records"
  local fqdn="$sub.$CF_ZONE_NAME" existing body
  existing=$(curl -fsS -H "Authorization: Bearer $CF_API_TOKEN" "$api?type=CNAME&name=$fqdn" | jq -r '.result[0].id // empty')
  body=$(jq -nc --arg n "$sub" --arg c "$target" '{type:"CNAME",name:$n,content:$c,proxied:false,ttl:1}')
  if [ -n "$existing" ]; then
    curl -fsS -X PATCH "$api/$existing" -H "Authorization: Bearer $CF_API_TOKEN" -H "Content-Type: application/json" --data "$body" \
      | jq -e '.success' >/dev/null || die "Cloudflare update failed: $fqdn"
    log "cloudflare CNAME updated: $fqdn → $target (DNS-only)"
  else
    curl -fsS -X POST "$api" -H "Authorization: Bearer $CF_API_TOKEN" -H "Content-Type: application/json" --data "$body" \
      | jq -e '.success' >/dev/null || die "Cloudflare create failed: $fqdn"
    log "cloudflare CNAME created: $fqdn → $target (DNS-only)"
  fi
}
cf_dns() {
  preflight
  require CF_API_TOKEN CF_ZONE_ID CF_ZONE_NAME VERCEL_CNAME_TARGET RENDER_CNAME_TARGET
  _cf_upsert_cname "${FRONTEND_SUB:-register}" "$VERCEL_CNAME_TARGET"
  _cf_upsert_cname "${BACKEND_SUB:-api}" "$RENDER_CNAME_TARGET"
}

# ---------- One-time: cron-job.org tick (every minute) ----------
cron() {
  preflight
  require CRONJOB_API_KEY
  local url="https://$BACKEND_DOMAIN/internal/hooks/tick" jid payload
  jid=$(curl -fsS -H "Authorization: Bearer $CRONJOB_API_KEY" https://api.cron-job.org/jobs \
        | jq -r --arg u "$url" '.jobs[]? | select(.url==$u) | .jobId' | head -1)
  payload=$(jq -nc --arg u "$url" --arg s "$HOOK_TICK_SECRET" \
    '{job:{url:$u,enabled:true,saveResponses:false,
           schedule:{timezone:"Asia/Kolkata",minutes:[-1],hours:[-1],mdays:[-1],months:[-1],wdays:[-1]},
           requestMethod:1,extendedData:{headers:{"X-Hook-Tick-Secret":$s}}}}')
  if [ -n "$jid" ]; then
    curl -fsS -X PATCH "https://api.cron-job.org/jobs/$jid" -H "Authorization: Bearer $CRONJOB_API_KEY" \
      -H "Content-Type: application/json" --data "$payload" >/dev/null
    log "cron-job.org job updated (1/min → $url)"
  else
    curl -fsS -X PUT "https://api.cron-job.org/jobs" -H "Authorization: Bearer $CRONJOB_API_KEY" \
      -H "Content-Type: application/json" --data "$payload" >/dev/null
    log "cron-job.org job created (1/min → $url)"
  fi
}

# ---------- Deploys (via deploy hooks → build `main` from GitHub) ----------
_wait_health() {
  local url="https://$BACKEND_DOMAIN/health" i code
  for ((i=1; i<=HEALTH_TRIES; i++)); do
    code=$(curl -sS -o /dev/null -w '%{http_code}' "$url" || true)
    [ "$code" = "200" ] && { log "backend healthy ($url)"; return 0; }
    log "waiting for backend health… ($i/$HEALTH_TRIES, last=$code)"
    sleep "$HEALTH_SLEEP"
  done
  die "backend did not become healthy after $((HEALTH_TRIES*HEALTH_SLEEP))s — aborting (frontend NOT deployed)"
}
deploy_be() {
  preflight
  require RENDER_DEPLOY_HOOK_URL
  log "BACKEND: triggering Render deploy (builds main)…"
  curl -fsS -X POST "$RENDER_DEPLOY_HOOK_URL" >/dev/null
  _wait_health
}
deploy_fe() {
  preflight
  require VERCEL_DEPLOY_HOOK_URL
  log "FRONTEND: triggering Vercel production deploy (builds main)…"
  curl -fsS -X POST "$VERCEL_DEPLOY_HOOK_URL" >/dev/null
  log "frontend deploy queued — verify https://$FRONTEND_DOMAIN shortly"
}

# ---------- Versioning + tagging (remote, via gh — never touches working trees) ----------
_next_version() {  # bump-type  -> echoes vX.Y.0
  local bump="$1" cur ma mi
  cur=$("$GH_CLI" api "repos/$BE_REPO/tags" --jq '[.[].name | select(test("^v[0-9]+\\.[0-9]+\\.[0-9]+$"))] | sort_by(. | ltrimstr("v") | split(".") | map(tonumber)) | last // "v0.0.0"' 2>/dev/null || echo "v0.0.0")
  IFS=. read -r ma mi _ <<< "${cur#v}"
  case "$bump" in
    major) ma=$((ma+1)); mi=0 ;;
    minor) mi=$((mi+1)) ;;
    *) die "bump must be 'major' or 'minor'" ;;
  esac
  echo "v${ma}.${mi}.0"
}
_tag_repo() {  # repo version
  local repo="$1" ver="$2" sha
  sha=$("$GH_CLI" api "repos/$repo/commits/main" --jq .sha)
  "$GH_CLI" api "repos/$repo/git/refs" -f ref="refs/tags/$ver" -f sha="$sha" >/dev/null 2>&1 \
    && log "tagged $repo @ main → $ver" \
    || log "tag $ver may already exist on $repo (skipped)"
}

release() {
  local bump="${1:-}"; [ -n "$bump" ] || die "usage: $0 release <major|minor>"
  preflight
  require RENDER_DEPLOY_HOOK_URL VERCEL_DEPLOY_HOOK_URL BE_REPO FE_REPO
  command -v "$GH_CLI" >/dev/null || die "missing CLI: $GH_CLI"
  local ver; ver=$(_next_version "$bump")
  log "RELEASE $ver ($bump) — order: backend → frontend (Golden Rule §19.3)"
  log "Reminder: apply any additive Supabase migration via MCP BEFORE this (controller-only)."
  deploy_be          # aborts if backend never goes healthy → FE never ships ahead
  deploy_fe
  smoke
  _tag_repo "$BE_REPO" "$ver"
  _tag_repo "$FE_REPO" "$ver"
  log "RELEASE $ver complete."
}

# ---------- smoke (status codes only; no secrets in output) ----------
smoke() {
  preflight
  curl -sS -o /dev/null -w "[smoke] %{http_code}  https://$FRONTEND_DOMAIN\n" "https://$FRONTEND_DOMAIN" || true
  curl -sS -o /dev/null -w "[smoke] %{http_code}  https://$BACKEND_DOMAIN/health\n" "https://$BACKEND_DOMAIN/health" || true
  curl -sS -o /dev/null -w "[smoke] %{http_code}  POST /internal/hooks/tick\n" \
    -X POST "https://$BACKEND_DOMAIN/internal/hooks/tick" -H "X-Hook-Tick-Secret: $HOOK_TICK_SECRET" || true
  log "smoke done — expect 200s (FE 200/308; tick 200 with the secret, 401 without)"
}

case "${1:-}" in
  preflight)  preflight ;;
  vercel-env) vercel_env ;;
  cf-dns)     cf_dns ;;
  cron)       cron ;;
  deploy-be)  deploy_be ;;
  deploy-fe)  deploy_fe ;;
  release)    release "${2:-}" ;;
  smoke)      smoke ;;
  *) die "usage: $0 {preflight|vercel-env|cf-dns|cron|deploy-be|deploy-fe|release <major|minor>|smoke}" ;;
esac
