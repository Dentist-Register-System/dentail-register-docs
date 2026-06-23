#!/usr/bin/env bash
# Register System — production deploy automation (idempotent).
#
# Drives the REPEATABLE steps only. One-time account creation, GitHub→Vercel/Render
# OAuth, Render service creation, and `vercel login`/`render login` are MANUAL —
# see deploy-runbook.md.
#
# Secrets are NEVER in this file. They are sourced from a local env file that lives
# OUTSIDE every git repo (default: ~/Documents/register_workspace/.register-ops.env).
# Secret values are never echoed.
#
# Usage: ./deploy.sh {preflight|vercel-env|cf-dns|cron|smoke|all}
set -euo pipefail

ENV_FILE="${REGISTER_OPS_ENV:-$HOME/Documents/register_workspace/.register-ops.env}"

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
  for c in vercel curl jq; do command -v "$c" >/dev/null || die "missing CLI: $c"; done
  vercel whoami >/dev/null 2>&1 || die "not logged in to Vercel — run: vercel login"
  require FRONTEND_DOMAIN BACKEND_DOMAIN \
          NEXT_PUBLIC_API_BASE_URL NEXT_PUBLIC_SUPABASE_URL NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY \
          CF_API_TOKEN CF_ZONE_ID CF_ZONE_NAME VERCEL_CNAME_TARGET RENDER_CNAME_TARGET \
          HOOK_TICK_SECRET
  log "preflight OK — env loaded, CLIs present, Vercel session active"
}

# ---------- Vercel env + domain ----------
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
  pushd "${VERCEL_PROJECT_DIR:?set VERCEL_PROJECT_DIR in the env file}" >/dev/null || die "frontend dir not found"
  vercel link --yes >/dev/null 2>&1 || true
  _vercel_set_env NEXT_PUBLIC_API_BASE_URL "$NEXT_PUBLIC_API_BASE_URL"
  _vercel_set_env NEXT_PUBLIC_SUPABASE_URL "$NEXT_PUBLIC_SUPABASE_URL"
  _vercel_set_env NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY "$NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY"
  vercel domains add "$FRONTEND_DOMAIN" >/dev/null 2>&1 || log "domain likely already attached: $FRONTEND_DOMAIN"
  popd >/dev/null
  log "vercel-env done — production redeploys on next push to main (or: vercel --prod)"
}

# ---------- Cloudflare DNS (upsert CNAME, DNS-only / unproxied) ----------
_cf_upsert_cname() {  # subdomain target
  local sub="$1" target="$2"
  local api="https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records"
  local fqdn="$sub.$CF_ZONE_NAME"
  local existing
  existing=$(curl -fsS -H "Authorization: Bearer $CF_API_TOKEN" "$api?type=CNAME&name=$fqdn" | jq -r '.result[0].id // empty')
  local body
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
  _cf_upsert_cname "${FRONTEND_SUB:-register}" "$VERCEL_CNAME_TARGET"
  _cf_upsert_cname "${BACKEND_SUB:-api}" "$RENDER_CNAME_TARGET"
}

# ---------- cron-job.org tick job (every minute) ----------
cron() {
  preflight
  require CRONJOB_API_KEY
  local url="https://$BACKEND_DOMAIN/internal/hooks/tick" jid payload
  jid=$(curl -fsS -H "Authorization: Bearer $CRONJOB_API_KEY" https://api.cron-job.org/jobs \
        | jq -r --arg u "$url" '.jobs[]? | select(.url==$u) | .jobId' | head -1)
  # schedule -1 in every field = "every minute"; requestMethod 1 = POST
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

# ---------- smoke tests (status codes only; no secrets in output) ----------
smoke() {
  preflight
  curl -sS -o /dev/null -w "[smoke] %{http_code}  https://$FRONTEND_DOMAIN\n" "https://$FRONTEND_DOMAIN" || true
  curl -sS -o /dev/null -w "[smoke] %{http_code}  https://$BACKEND_DOMAIN/health\n" "https://$BACKEND_DOMAIN/health" || true
  curl -sS -o /dev/null -w "[smoke] %{http_code}  POST /internal/hooks/tick\n" \
    -X POST "https://$BACKEND_DOMAIN/internal/hooks/tick" -H "X-Hook-Tick-Secret: $HOOK_TICK_SECRET" || true
  log "smoke done — expect 200s (FE may 200/308; tick 200 with the secret, 401 without)"
}

case "${1:-}" in
  preflight)  preflight ;;
  vercel-env) vercel_env ;;
  cf-dns)     cf_dns ;;
  cron)       cron ;;
  smoke)      smoke ;;
  all)        vercel_env; cf_dns; cron; smoke ;;
  *) die "usage: $0 {preflight|vercel-env|cf-dns|cron|smoke|all}" ;;
esac
