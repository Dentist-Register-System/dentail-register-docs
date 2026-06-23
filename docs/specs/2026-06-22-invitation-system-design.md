# Invitation System (Slice 1) — Design Spec

**Status:** Approved (brainstorm 2026-06-22; issue #25; UI direction from the user's Assistants-page mockup). System-wide: **db + backend + frontend + docs**. Register Design System (M3 Soft/Dark Purple), Rule 17.0, i18n-first.
**Type:** Make invitations first-class with **multiple delivery channels** (Copy Link + Email this slice; WhatsApp later), an **invitation-management UI** (Pending Invites card + Invites tab with Resend/Copy/Cancel), and a proper **`/invite/[token]` acceptance flow** that opens a clinic-name-contextualized sign-up and auto-joins. Applies to **both Doctors and Assistants**.

## 1. Goal
A clinic owner/assistant invites a doctor or assistant once; one invitation + token is created; it is delivered by email and/or a copied link; its lifecycle is trackable (Pending · Accepted · Expired · Cancelled); and the recipient joins by opening the link — no token pasting. Built for non-tech-savvy users: the invitee provides only what's needed (their account), and the clinic sees a clean, contextual list of who's been invited.

## 2. Scope decisions (locked in brainstorm)
- **Channels this slice:** **Copy Link + Email** (Resend). **WhatsApp deferred** (the delivery component leaves a slot for it).
- **Management UI** lives **inside the Doctors & Assistants pages** as a tabbed shell: **Overview** (Team list as-is + a new **Pending Invites** card) and a dedicated **Invites** tab (table). Both pages, this slice.
- **Acceptance:** the invite link opens a **clinic-name-contextualized sign-up** ("You've been invited to join *Clinic* as *Role*"); after auth the user is **auto-added** to the clinic (skips the onboarding create/join choice). No raw-token pasting.
- **Email-centric invites:** the Invite dialog collects **Name + Email**. `phone` becomes **nullable** on doctor/assistant; the invitee fills phone/details after joining via the existing self-update endpoints.
- **Invite permissions** mirror entity-management permissions from #91: **doctor** invites = owner **+ assistant**; **assistant** invites = **owner only**.
- **Email language:** **bilingual** (English + Hindi in one body) — the recipient has no account yet, so we don't know their language preference.
- **Decomposition:** the full mockup spans more than invitations. This spec is **Slice 1 (invitations)**. The rest become **sub-issues under #25**, picked up immediately after: (2) Team table search/filter/pagination (#80), (3) expanded profile drawer + new member fields (DOB/gender/address/working hours), (4) Permissions management (new), (5) Member Activity feed (new). The mockup's top-right Light/Dark/System + EN/हिं cluster is **superseded** by the shipped compact theme toggle — keep the current header.

## 3. Data model — migration `0017_invite_email_centric`
- **`doctor_beta.phone` → nullable.** **`assistant_beta.phone` → nullable.**
- No new tables. `clinic_invite_beta` is already first-class: `id, clinic_id, doctor_id (nullable), assistant_id (nullable), role, token, created_by, status (pending/accepted/revoked/expired), invited_contact (nullable), expires_at, accepted_by, accepted_at, created_at`.
  - `invited_contact` holds the **email**.
  - Invitee **name/avatar** come from the linked `doctor_beta`/`assistant_beta` row (entity-linked invites — the reason the list can show real names).
  - No schema change needed for `clinic_invite_beta` itself.

## 4. Backend

### 4a. Email module — `app/modules/email/`
- `service.py` → `send_invite_email(*, to, clinic_name, inviter_name, role, accept_url) -> None`. Calls the **Resend HTTP API** (`POST https://api.resend.com/emails`, `Authorization: Bearer {RESEND_API_KEY}`) via **httpx** (already a backend dep — no SDK, no new license).
- **Bilingual HTML template** (English block + Hindi block) with clinic name, inviter, role, the accept URL, and expiry. Plain, accessible, no external CSS.
- **Settings (`app/core/config.py`):** `RESEND_API_KEY: str | None = None`, `EMAIL_FROM: str = "Register <onboarding@…>"`, `APP_BASE_URL: str` (build `{APP_BASE_URL}/invite/{token}`).
- **No-op guard:** if `RESEND_API_KEY` is unset, log a warning and return without sending (dev/CI never send). Network failures are caught and logged — **a failed email never fails the invite creation** (the link still works; user can Resend).
- Clean import direction: `core ← email`; doctors/assistants/invites services call `email.service` at their boundary (local import if needed to avoid cycles).

### 4b. Invitation service + endpoints (`app/modules/invites/`)
- **Create (existing `POST …/doctors`, `POST …/assistants`)** → after the invite is created, **send the invite email** when `invited_contact` (email) is present. Email failure is swallowed (logged), invite still returned.
- **Resend — `POST /clinics/{cid}/invites/{id}/resend`** (new) → only for `pending`/`expired` invites: **keep the same token**, set `expires_at = now + ttl`, set status back to `pending`, re-send the email, audit `clinic_invite.resent`. Returns the updated `InviteRead`.
- **Cancel — `DELETE /clinics/{cid}/invites/{id}`** (exists) → status `revoked`, audit `clinic_invite.revoked`.
- **List — `GET /clinics/{cid}/invites`** (exists) → **enriched + display status**. Each row returns `{ id, invitee_name, email, role, status, created_at, expires_at, accepted_at }` where `invitee_name`/`email` are resolved from the linked doctor/assistant (fallback to `invited_contact`), and **display status derives expiry**: a `pending` invite past `expires_at` is reported as `expired`. Filterable by `role` (doctor/assistant) so each page lists only its invites.
- **Public preview — `GET /api/v1/invites/{token}`** (new, **no auth**) → `{ clinic_name, role, inviter_name, invitee_name, status, expires_at }`. `status ∈ {valid, expired, accepted, revoked, invalid}` (invalid = token not found). Returns only non-sensitive display fields. Used by the acceptance page; rate-agnostic, read-only.
- **Accept — `POST /clinics/join`** (exists) → unchanged; powers auto-join. Re-confirm it: validates token + status + expiry, `ensure_user`, links doctor/assistant, marks accepted, creates membership.
- **Permissions:** `list/resend/cancel` for **doctor** invites → `require_role(owner, assistant)`; for **assistant** invites → `require_role(owner)`. The generic create paths already follow this via the doctors/assistants routers (#91). The invite-management routes resolve the entity type from the invite to apply the right gate (or split into doctor-scoped/assistant-scoped routes — implementer's call at plan time, gate must match).

### 4c. Backend tests (pytest, PG :5433)
- Resend keeps the token, extends expiry, flips back to pending, audits, re-sends (email mocked).
- Cancel → revoked; cancelling a non-pending invite → error.
- List enrichment: invitee name from linked entity; `pending`-past-expiry surfaces as `expired`; `role` filter scopes results.
- Public preview: valid/expired/accepted/revoked/invalid each return the right `status`; no auth required; no sensitive fields leaked.
- Auto-join via `POST /clinics/join` still works end-to-end; already-member → conflict.
- Email sender is **mocked**; one test asserts `send_invite_email` is called on create when email present, and **not** called (no error) when `RESEND_API_KEY` is unset.
- Phone-nullable: creating a doctor/assistant with only name + email succeeds.

## 5. Frontend

### 5a. Invitations feature — `src/features/invitations/`
- `api.ts` — `Invite` type (`id, invitee_name, email, role, status, created_at, expires_at, accepted_at`); `fetchInvites(clinicId, role)`, `resendInvite(clinicId, id)`, `cancelInvite(clinicId, id)`, `fetchInvitePreview(token)` (public, unauthenticated fetch).
- `hooks.ts` — TanStack Query hooks; mutations invalidate the invites + team queries.
- **`<ShareInvite>`** — reusable delivery component: **Copy Link** (builds `${origin}/invite/${token}`, clipboard, "Copied" feedback) + **Send/Resend email** button. **WhatsApp slot reserved** (commented, not built).
- **`<InviteDialog>`** — "Invite Doctor"/"Invite Assistant": Name + Email form → on submit creates the entity+invite (existing create endpoints) → success view shows "Invitation sent to {email}" + `<ShareInvite>` Copy Link backup.
- **`<PendingInvitesCard>`** — Overview-tab card: count + list (avatar initials, name, email, Pending badge, invited-on) + "View all invites" → Invites tab.
- **`<InvitesTable>`** — Invites tab: Invitee · Email · Invited on · Status (`Pending`/`Accepted`/`Expired`/`Cancelled` chips) · Expires on · actions (**Resend · Copy Link · Cancel**; **View** when accepted).

### 5b. Tabbed Doctors & Assistants pages
- Add a tab shell **Overview / Team / Invites** to both `doctors` and `assistants` pages (compose `components/ui/*`; no per-page CSS).
- **Overview:** existing Team list (unchanged) + `<PendingInvitesCard>`.
- **Team:** today's list/table as-is (search/filter/pagination is sub-issue 2).
- **Invites:** `<InvitesTable>`.
- Top-right action button becomes **"Invite Doctor"/"Invite Assistant"** opening `<InviteDialog>` (replaces today's add-doctor/add-assistant dialog's raw-token view).

### 5c. Acceptance flow — `/invite/[token]`
- New route `src/app/invite/[token]/page.tsx` → `fetchInvitePreview(token)`:
  - **invalid/expired/revoked** → friendly dead-end card ("This invitation is no longer valid — ask the clinic to resend.").
  - **accepted** → "already accepted — sign in".
  - **valid** → contextual card "You've been invited to join **{clinic}** as a **{role}**." → "Sign in / Create account". The token is stashed in `localStorage["register.invite_token"]` so it survives Supabase's auth redirect.
- **Post-auth auto-join hook** (in the authed shell): if a stashed invite token exists, `POST /clinics/join`, then clear it, invalidate `["me"]`, land in the clinic shell (bypasses onboarding create/join). Already-a-member → friendly toast.
- **Already logged in** when opening the link → the route offers a one-tap "Accept & join {clinic}".
- The `/login` auth screen accepts an optional **invite-context banner** (clinic name + role) when arriving from an invite.

### 5d. i18n + design
- All UI strings en+hi (`invitations.*`, `invites.status.*`, acceptance copy, dialog copy). Rule 17.0 semantic tokens, both themes, mobile-first, WCAG AA.
- **Interactive HTML render on :8753** of: the tabbed page (Overview + Invites), the Invite dialog (form + success/ShareInvite), and the acceptance screen — **user sign-off before building**.

## 6. Quality
- Backend: `uv run ruff check .` clean; `make test` green (new invite/email/preview/auto-join tests); migration `0017` validated on local PG :5433 by implementers; controller applies to Supabase via MCP + bumps `alembic_version`.
- Frontend: `tsc --noEmit` + `npm run build` green; i18n en/hi parity; e2e for the invite-create + acceptance flows (Supabase + backend mocked). FE PR **held for user QA**.
- Secrets: `RESEND_API_KEY` provided by the user, set in backend env (never committed). `.env`/`.env.local` untouched by the agent.
- Never merge red. `gh-personal` only; branch → PR → squash + delete.

## 7. Scope guards / deferred (→ sub-issues under #25, picked up next)
- **WhatsApp delivery** channel (slot reserved in `<ShareInvite>`).
- **Team table** search/filter/status/pagination → folds into **#80**.
- **Profile drawer** Overview tab + new member fields (DOB/gender/address/working hours).
- **Permissions** management tab (needs its own granular-permissions design — new issue).
- **Member Activity** feed tab (needs an audit read API — new issue).
- Hindi-only email template variant (we ship **bilingual** now, so this is satisfied).

## 8. Self-review (against the request + #25)
- First-class invitation + single token, multiple delivery channels (Copy + Email; WhatsApp slotted): §2/§4/§5a. ✅
- Invite Doctor/Assistant flow → create once → deliver: §4b/§5a. ✅
- Tracking (status, created/accepted, expires) + management (Resend/Copy/Cancel): §4b/§5a/§5b. ✅
- Acceptance via link → contextual sign-up → auto-join, no token pasting: §2/§5c. ✅
- Email via Resend, decided at design time; bilingual; failure-tolerant: §4a. ✅
- Both Doctors & Assistants: §2/§5b. ✅
- Email-centric (phone nullable) + per-entity permissions + decomposition into sub-issues: §2/§3/§7. ✅
- Rule 17.0 + i18n + tests + render-before-build + merge policy: §5d/§6. ✅
- Placeholder scan: concrete tables/endpoints/fields/components/migration number; no TBD. ✅
