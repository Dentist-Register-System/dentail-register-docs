# SP5.1 — Hook / Job Execution Substrate (Outbox + Polling Worker) — Design Spec

> Status: Draft for review · Date: 2026-06-23 · Requirement source: issue #116 (slice of epic #11, SP5 Integrations)
> Scope: the **internal** substrate that makes external side effects (WhatsApp, Google Calendar — later slices) reliable: a DB-backed **transactional outbox** (Hook entity #17), a **dual-trigger polling worker** that executes hooks idempotently with retry, and an assistant-facing **failed-integration recovery** surface. In this slice **all provider handlers are mock/log adapters** — SP5.2 (#117) and SP5.3 (#118) swap in real providers behind the same seam.

---

## 1. Context & Purpose
Golden Rules §8 fix the hard behavior for integrations: external side effects run **only after** the internal transition commits (8.1), a side-effect failure **never** rolls back valid appointment state (8.2), hooks **re-validate** state before executing (8.3), and execution is **at-least-once with idempotency** (8.4 + §6.4). Today the backend has **no** such substrate — the one existing outbound call (invite email, `app/modules/email/service.py`) fires *after* commit with no retry and silently logs on failure. That is precisely the anti-pattern this slice replaces.

The tech-stack doc already chose the architecture: a **database-backed hook system** polled by a background worker — explicitly **no Redis / Celery / Kafka** in V1. The Hook entity (`Entities/17-hook.md`) is already specified. `ClinicSettings` already carries the seam: `post_confirmation_hook_delay_minutes`, `whatsapp_enabled`, `google_calendar_enabled`, `reminders_enabled`.

This slice builds that substrate end-to-end with mock providers, wires it into the appointment transitions that exist today, and ships the recovery UI — so SP5.2/5.3 become "plug in a real adapter," not "build the plumbing."

## 2. Scope Decisions (locked during brainstorming)
- **One generic `hook_beta` table** (matches Hook entity #17), **not** per-feature outbox tables. `hook_type` + polymorphic entity ref + JSONB payload covers WhatsApp, Google Calendar, and anything future without new tables/migrations.
- **Transactional outbox.** Hooks are enqueued via a service helper that **`flush()`es inside the caller's transaction** (the caller still owns the single `db.commit()`), exactly like `record_audit`. This gives "after commit" + atomicity for free (§8.1) and means a rolled-back business transaction also discards its hooks.
- **Dual-trigger worker, free + resilient on Render free tier.** The poll-claim-execute logic is one pure function `run_due_hooks()`, triggered two ways: **(a)** an in-process **lifespan loop** (low latency while the API is awake — the primary path), and **(b)** a secret-protected **`POST /internal/hooks/tick`** pinged every minute by an **external free cron — cron-job.org** (the documented default: genuinely free, 1-minute granularity, reliable, with run history + failure alerts; it also doubles as a keep-alive so the free service never sleeps, keeping the in-process loop alive). (b) both **wakes the spun-down free service and drains the backlog**, so nothing is stranded during idle periods. Both triggers are safe to overlap because of `FOR UPDATE SKIP LOCKED` claiming + idempotency. **Not GitHub Actions:** at 1/min it exceeds the free-minutes budget and its scheduled runs are documented as delayed/dropped under load — wrong tool for a heartbeat. **Who calls the tick is a swappable deploy-config detail** (UptimeRobot at 5-min is a fine alternative); the real contract is the endpoint. **Upgrade path:** a paid always-on worker later is a config flip (`HOOK_WORKER_ENABLED` on a worker process, drop the cron) — no rewrite. Render free background-workers don't exist and a free web service sleeps after ~15 min idle, which is why an in-process loop *alone* is not acceptable. (No server is deployed yet — this is a deploy-time choice; the substrate + endpoint + loop are what this slice builds.)
- **All handlers are mock/log adapters this slice.** `hook_type` still names the *intended* side effect; the handler registry maps each to a mock handler that logs + returns a synthetic `provider_ref`. Real providers arrive in SP5.2/5.3 behind the same interface.
- **Wire the transitions that exist today.** Appointment **confirmation** (via both `request_approval` and `direct_booking` paths in `_materialize_appointment`) and **request cancellation** (`cancel_request`). Appointment cancel/reschedule transitions **do not exist yet** — the enqueue seam is built so those workstreams call `enqueue_hook(...)` when they land and the pipeline lights up automatically. No faking of non-existent transitions.
- **Idempotency is mandatory** (§6.4): a unique `idempotency_key` per logical side effect prevents both duplicate enqueue and duplicate user-visible effects on retry.
- **Recovery UI lives in Settings → Integrations** (Rule 18.6), not a new nav destination. The Home Clinic-Health card (#62) is **deferred** and out of scope.

## 3. Data Model — `hook_beta` (Alembic migration; verify latest revision at implementation — 0017 at design time → likely **0018**)
SQLAlchemy 2.x `Mapped[...]`, UUID PK, tz-aware server-default timestamps, `(str, enum.Enum)` + `SAEnum`, `_beta` suffix, project naming convention.

| Column | Type | Notes |
|---|---|---|
| `id` | UUID PK | `default=uuid4` |
| `clinic_id` | UUID FK `clinic_beta.id`, indexed | tenant scope |
| `hook_type` | `SAEnum(HookType)` | `whatsapp_confirmation`, `whatsapp_reminder`, `whatsapp_cancellation`, `whatsapp_postop`, `gcal_create`, `gcal_update`, `gcal_delete` (all dispatch to mock handlers in this slice) |
| `related_entity_type` | `String(50)` | e.g. `appointment`, `appointment_request` |
| `related_entity_id` | UUID | polymorphic ref (no hard FK — entity type varies) |
| `payload` | `JSONB` | **snapshot** of everything needed to execute (phone, names, times, locale) — no late joins/reads at execution time |
| `idempotency_key` | `String(200)`, **unique** | deterministic per logical effect, e.g. `appt:{id}:whatsapp_confirmation` |
| `status` | `SAEnum(HookStatus)` | `scheduled · running · succeeded · failed · cancelled` (entity #17) |
| `attempts` | int, default 0 | |
| `max_attempts` | int, default from config | |
| `scheduled_at` | timestamptz | earliest eligible run time (supports `post_confirmation_hook_delay_minutes`) |
| `next_attempt_at` | timestamptz | claim cursor; bumped by backoff on retry |
| `provider_ref` | `String(200)`, nullable | provider message/event id (mock = synthetic) |
| `last_error` | `Text`, nullable | failure reason (codes/metadata; no PHI per §11.1) |
| `created_at · updated_at · executed_at` | timestamptz | server default `clock_timestamp()`; `executed_at` set on terminal success |

**Indexes:** `(status, next_attempt_at)` (claim query) · `(clinic_id, status)` (recovery list) · unique `idempotency_key`.
**Check constraint:** status ∈ the five values.

## 4. Enqueue seam (transactional, in `app/modules/hooks/service.py`)
```
enqueue_hook(db, *, clinic_id, hook_type, related_entity_type, related_entity_id,
             payload, idempotency_key, scheduled_at=None) -> Hook
```
- Inserts a `scheduled` hook with `next_attempt_at = scheduled_at or now()`; **`flush()` only** (caller commits).
- **Idempotent enqueue:** `INSERT … ON CONFLICT (idempotency_key) DO NOTHING` then re-select — re-running a workflow path never double-enqueues.
- Records `record_audit(action="hook.enqueued", entity_type="hook", entity_id=hook.id, …)` in the same transaction (§7).
- **Wiring:** called in `_materialize_appointment` (confirmation hooks — emitted per enabled channel: `whatsapp_confirmation` gated on `whatsapp_enabled`, `gcal_create` gated on `google_calendar_enabled`; `scheduled_at = now + post_confirmation_hook_delay_minutes`), and in `cancel_request` (cancellation hooks). Future appointment cancel/reschedule call the same helper.

## 5. Execution flow — `run_due_hooks(db, batch_size)` (in `app/modules/hooks/worker.py`)
1. **Claim:** `SELECT … WHERE status='scheduled' AND next_attempt_at <= now() ORDER BY next_attempt_at FOR UPDATE SKIP LOCKED LIMIT batch_size`; set `status='running'`; commit the claim (so concurrent triggers/instances never grab the same row).
2. For each claimed hook, in its own transaction:
   - **Re-validate** (§8.3): a per-`hook_type` validator reloads the related entity and confirms the side effect still makes sense (e.g. a `whatsapp_confirmation` requires the appointment to still be `confirmed`). If invalid → `cancelled` with `last_error` reason + audit `hook.cancelled`; **do not** dispatch.
   - **Dispatch** to the handler registry (`hook_type → handler`). The mock handler logs structured metadata + returns a synthetic `provider_ref`. Handler is **idempotent** — receives `idempotency_key`; real providers pass it through / dedupe on `provider_ref`. (Tests inject a **failing mock** handler to exercise the retry/terminal path — see §9.)
   - **Success:** `status='succeeded'`, set `executed_at`, `provider_ref`; audit `hook.succeeded`.
   - **Failure:** `attempts += 1`; if `attempts < max_attempts` → `status='scheduled'`, `next_attempt_at = now() + backoff(attempts)` (**exponential + jitter**, e.g. base 60s × 2^n, capped), audit `hook.retried`; else terminal `status='failed'`, audit `hook.failed`.
3. **Crash safety:** a row stuck in `running` past a `stale_running_seconds` threshold is reclaimable by the next tick (treated as a failed attempt) — so a worker crash mid-execution self-heals.
4. **Guards:** transitions on already-`succeeded`/terminal hooks are no-ops (status-checked) — re-delivery never double-acts (§6.4).

A side-effect failure touches **only** the hook row — never the appointment/request (§8.2).

## 6. API (clinic-scoped via the existing membership/auth chain; new `app/modules/hooks/router.py`)
- `GET  /api/v1/clinics/{clinic_id}/integrations/hooks?status=&limit=&cursor=` — delivery activity (most-recent first), filterable by status.
- `POST /api/v1/clinics/{clinic_id}/integrations/hooks/{hook_id}/retry` — `failed` → `scheduled`, `next_attempt_at=now()`, allow a fresh attempt budget; audit `hook.manual_retried`. 409 if not in a retryable state.
- `POST /api/v1/clinics/{clinic_id}/integrations/hooks/{hook_id}/cancel` — operator discards a stuck/unwanted hook → `cancelled`; audit.
- `POST /internal/hooks/tick` — **not** clinic-scoped; protected by `HOOK_TICK_SECRET` (header) and bound to internal use; calls `run_due_hooks`. Returns counts.
- Responses use stable **`DomainError` codes** (`not_found`, `conflict`, …) — FE translates (Rule 16.2). New code `hook_not_retryable`.

## 7. Permissions & Audit
- **Permissions:** viewing/retrying hooks is an operational action — allowed for `owner`, `practice_manager`, `assistant` within their clinic (assistants manage operational recovery — Rule 12.3, PRD §29). Cross-clinic access forbidden (§9.1) via the existing membership guard.
- **Audit (§7):** every hook transition is auditable — `hook.enqueued`, `hook.succeeded`, `hook.failed`, `hook.retried`, `hook.manual_retried`, `hook.cancelled`. Audit writes share the worker's per-hook transaction; append-only (§7.4).

## 8. Frontend — Settings → Integrations pane (Rule 17.0 framework, i18n en/hi parity, both themes, mobile-first, a11y)
- New pane under `/settings` (Rule 18.6): composed from AppShell + existing settings template + `ui/*` components — **no per-page CSS**.
- **Connection section:** WhatsApp and Google Calendar cards reading the existing `whatsapp_enabled` / `google_calendar_enabled` clinic settings. The real **connect/OAuth** flows are SP5.2/5.3 — here the cards show status + a disabled/"coming soon" affordance (no fake connect).
- **Delivery activity section:** a list of recent hooks — type, target entity, status chip (semantic tokens; `failed` uses warning, not scary error), timestamp, and a **Retry** action on `failed` rows (calls the retry API, optimistic refetch via TanStack Query). Empty state is reassuring.
- All copy is i18n-keyed (en + hi); status chips driven by stable codes. AA contrast in both themes; ≥44px targets.

## 9. Testing (Golden Rules §10)
- **Unit:** `backoff(n)` schedule; idempotent-enqueue conflict path; per-type re-validation; status-guard no-ops.
- **Concurrency (§10.4):** two concurrent `run_due_hooks` over the same batch — `SKIP LOCKED` guarantees no double-execution; reclaim of stale `running`.
- **Integration:** enqueue-within-txn atomicity (rolled-back business txn ⇒ no hook); full pipeline with a **mock provider** (§10.3) → `succeeded` + `provider_ref`; failure → retry → terminal `failed` (via an injected **failing mock** handler); manual retry; re-validation-skip (entity changed ⇒ `cancelled`); `/internal/hooks/tick` auth (secret required).
- **FE:** pane renders each status; retry triggers the API + optimistic update; i18n/theme/a11y checks.

## 10. Execution shape
Backend-first: model + migration → `enqueue_hook` + audit actions → `run_due_hooks` + handler registry + mock providers → lifespan loop + `/internal/hooks/tick` + config → wire `_materialize_appointment` & `cancel_request` → recovery API. Then FE Integrations pane. Split into a **backend plan** and a **frontend plan** (the established pattern). External free-cron wiring (**cron-job.org** hitting `/internal/hooks/tick` every minute) is a deploy-config step documented in the plan.

## 11. Docs to update (this PR or the plan)
- `Entities/17-hook.md` — annotate with the realized table/columns + dual-trigger note.
- `tech stack/register-tech-stack.md` — Background Jobs section: record the dual-trigger (in-process loop + external-cron tick) decision and the free-tier rationale.
- Backend & frontend `README` (Rule: one rich README/repo, update every PR) — hooks substrate + how to run the worker/tick locally.
- Golden Rules: no change needed (§8 already governs); cross-reference this spec from the SP5 epic.
