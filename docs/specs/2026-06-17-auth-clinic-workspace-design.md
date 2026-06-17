# Auth + Clinic Workspace (Sub-project 1) — Design Spec

> Status: Draft for review
> Date: 2026-06-17
> Author: Brainstormed via Claude Code (superpowers:brainstorming)
> Sub-project: 1 of the Register System build sequence (follows Sub-project 0, the walking skeleton)

---

## 1. Context & Purpose

The walking skeleton (Sub-project 0) proved the FastAPI + Next.js + Postgres stack end-to-end.
Sub-project 1 establishes the **identity, multi-tenancy, and authorization foundation** that
every later feature builds on: who you are (Supabase Auth), which clinic you belong to and as
what role (clinic membership), and the authoritative clinic-boundary + role enforcement that
guards all future clinic-scoped data.

**This sub-project delivers:** users can sign up (phone-OTP or email/password), either create a
new clinic (self-serve → owner) or join an existing one via a role-specific invite, reach an
authenticated clinic workspace, and have every request gated by clinic boundary + role. It is
multi-tenant from day one (many clinics; strict isolation per Golden Rule 9.1).

**Boundary with Sub-project 2 (Core entities):** SP1 models roles **generically** via
`clinic_member.role`. The rich **Doctor** and **Assistant** entities (specialty, availability
ownership, title), the **doctor invite → activation** lifecycle, and **Patient** + search are
SP2 — built on top of SP1's proven authz layer. In SP1, "this user is a doctor" is simply
`clinic_member.role = 'doctor'`.

---

## 2. Scope Decisions (locked during brainstorming)

- **Multi-tenant.** Many clinics; a user enters a clinic only by creating one or accepting an
  invite. Cross-clinic data access is impossible by construction (Golden Rule 9.1).
- **Auth split:** frontend authenticates directly with **Supabase Auth** via `supabase-js`
  (phone-OTP primary, email/password secondary), holds the session, and sends the Supabase
  **JWT** as a Bearer token to FastAPI. **FastAPI validates the JWT and is the authoritative
  authz + tenancy gate.** Supabase = identity only.
- **Generic roles now:** `clinic_member.role ∈ {owner, practice_manager, doctor, assistant}`.
  Rich Doctor/Assistant entities deferred to SP2.
- **Onboarding:** after sign-up, the user is asked whether they have an invite.
  - **Has invite →** join that clinic with the **role the invite specifies** (inviter decides).
  - **No invite →** self-serve onboarding creates a **new clinic**; that user becomes its **owner**.
- **Invite-gated joining:** joining an existing clinic ALWAYS requires a human-issued,
  role-specific invite (health-data safety). Owner is reserved for the self-serve creator.
- **Data-API / RLS posture:** app tables are **not exposed to the Supabase Data API** (the
  browser uses Supabase only for auth, never for data); FastAPI (privileged DB connection) is
  the sole, authoritative tenant gate. **RLS is enabled on app tables as defense-in-depth.**
- **`_beta` table naming** during implementation/testing (Golden Rule 4.5), suffix dropped at
  production cutover: `clinic_beta`, `clinic_settings_beta`, `app_user_beta`,
  `clinic_member_beta`, `clinic_invite_beta`, `audit_event_beta`.
- **Minimal audit table now:** an append-only `audit_event_beta` written in-transaction with
  each change. Full audit infrastructure (retry/dead-letter/observability) is SP4.
- **`DATABASE_URL` repoints** from the skeleton's local Postgres (5433) to the Supabase project
  (`wxwasnshmnttiixvzeod`); no application code change (the skeleton was built Supabase-free on
  purpose). Local 5433 remains usable for offline dev.

### Out of scope (explicit)
Rich Doctor/Assistant entities + the doctor invite→activation lifecycle; Patient + search
(all SP2). Dashboards / AI brief (SP6). Full audit infra with retry/dead-letter (SP4).
Multi-clinic switcher UI polish, org/billing, password reset flows beyond Supabase defaults,
SSO/social login, and any scheduling logic.

---

## 3. Architecture

```
Next.js ──(supabase-js: phone-OTP / email-pw)──▶ Supabase Auth ──issues JWT──▶ browser session
   │
   └──(REST + Authorization: Bearer <supabase JWT>)──▶ FastAPI
                                                          │ 1. validate JWT (asymmetric / JWKS)
                                                          │ 2. resolve auth user → app_user
                                                          │ 3. resolve clinic_member(role) for the
                                                          │    clinic in the route; enforce boundary
                                                          │ 4. role guard
                                                          └──SQLAlchemy (privileged conn)──▶ Supabase Postgres
```

Supabase owns identity; FastAPI owns authorization and tenancy (tech-stack rule: business logic
in FastAPI, not RLS/edge functions). The frontend talks to **two** backends: Supabase (auth
only) and FastAPI (everything else).

---

## 4. Data Model (new tables — `_beta` suffix during implementation)

All tables live in the `public` schema with **RLS enabled** (defense-in-depth) and are **not
granted** to `anon`/`authenticated` (not exposed via the Data API). UUID PKs, tz-aware
timestamps, and the `MetaData` naming convention from the skeleton apply.

- **`clinic_beta`** — `id`, `name`, `phone`, `whatsapp_number` (nullable), `operating_hours`
  (jsonb, nullable), `address` (nullable), `status {active, inactive}`, `created_at`, `created_by`.
- **`clinic_settings_beta`** — `id`, `clinic_id` (FK, unique), `allow_multiple_bookings_per_slot`
  (bool, default false), `max_bookings_per_slot` (int, default 3), `default_slot_size_minutes`
  (default 30), `appointment_request_expiry_minutes` (default 120),
  `post_confirmation_hook_delay_minutes` (default 5), `reminders_enabled` (bool),
  `whatsapp_enabled` (bool), `google_calendar_enabled` (bool), `created_at`, `updated_at`.
  Created with defaults when a clinic is created.
- **`app_user_beta`** — `id`, `auth_user_id` (uuid, FK→`auth.users.id`, unique), `name`,
  `phone` (nullable), `email` (nullable), `status {invited, active, inactive}`, `created_at`.
  The app-side profile mirroring the Supabase identity. (At least one of phone/email is present,
  matching the auth method used.)
- **`clinic_member_beta`** — `id`, `clinic_id` (FK), `user_id` (FK→`app_user_beta`),
  `role {owner, practice_manager, doctor, assistant}`, `status {active, inactive}`,
  `created_at`, `created_by` (nullable for self-serve owner). **Unique (`clinic_id`, `user_id`).**
  This is the membership + role record; clinic boundary derives from it.
- **`clinic_invite_beta`** — `id`, `clinic_id` (FK), `role` (the role to grant), `token`
  (secure random, unique, **single-use**), `created_by` (FK→`app_user_beta`),
  `status {pending, accepted, revoked, expired}`, `expires_at`, `accepted_by` (nullable),
  `accepted_at` (nullable), `created_at`. Optional `invited_contact` (phone/email) for display.
- **`audit_event_beta`** (append-only) — `id`, `clinic_id` (FK, nullable), `actor_user_id`
  (FK→`app_user_beta`, nullable for system), `action` (string), `entity_type` (string),
  `entity_id` (uuid), `previous_value` (jsonb, nullable), `new_value` (jsonb, nullable),
  `reason` (text, nullable), `created_at`. No UPDATE/DELETE (Golden Rule 7.4); written in the
  same transaction as the change (Golden Rule 13.3).

---

## 5. Authentication & JWT Validation

- **Methods:** phone-OTP (primary) and email/password (secondary), both via Supabase Auth /
  `supabase-js`. No autonomous sign-up into an existing clinic — membership is invite-gated.
- **JWT validation in FastAPI:** verify the Supabase JWT using **asymmetric keys via the
  project's JWKS endpoint** (the modern Supabase approach; the legacy shared HS256 secret is
  deprecated). Validate signature, issuer, audience, and expiry; extract `sub` (the stable
  `auth.users.id`). The exact JWKS URL and claim set will be **confirmed against current
  Supabase docs at implementation time** (skill principle: verify before implementing).
- **Identity → app mapping:** on each authenticated request, FastAPI loads the `app_user` by
  `auth_user_id = sub`. If none exists, the user is in the *needs-onboarding* state (only
  `/me`, `POST /clinics`, and `POST /clinics/join` are reachable).
- **JWKS caching:** cache JWKS with periodic refresh; never call Supabase per request for keys.

---

## 6. Onboarding Flows

**A. Sign up → needs onboarding.** User authenticates via Supabase. First FastAPI call finds no
`app_user` → response indicates onboarding required.

**B. Join via invite** — `POST /clinics/join { token }`:
1. Look up `clinic_invite_beta` by `token`; reject if not `pending`, expired, or revoked.
2. Create `app_user` (if absent) from the JWT identity.
3. Create `clinic_member_beta` with the invite's `clinic_id` + **`role`**, status `active`.
4. Mark invite `accepted` (`accepted_by`, `accepted_at`). Single-use enforced atomically
   (a second redemption fails cleanly).
5. Audit: `clinic_member.created` + `clinic_invite.accepted` (same transaction).

**C. Self-serve new clinic** — `POST /clinics { name, phone, ... }`:
1. Create `app_user` (if absent).
2. Create `clinic_beta` + `clinic_settings_beta` (defaults).
3. Create `clinic_member_beta` with `role = owner`, status `active`.
4. Audit: `clinic.created` + `clinic_member.created` (same transaction).

All three steps in B and C are atomic (single DB transaction).

---

## 7. Invites

- **Creation** — `POST /clinics/{clinic_id}/invites { role }` by an authorized member. Generates
  a single-use, expiring token; returns the invite link/token. (SP1: **owner** and
  **practice_manager** may create invites for any non-owner role. SP2 extends this — e.g.,
  assistants issuing doctor invites — per the PRD's doctor lifecycle.)
- **Listing / revocation** — `GET /clinics/{clinic_id}/invites`, `DELETE …/invites/{id}` (sets
  `revoked`). Authorized members only.
- **Expiry** — invites past `expires_at` are treated as `expired` on read; a background sweep is
  not required in SP1 (lazy expiry on redemption/list).
- Audit: `clinic_invite.created` / `.revoked`.

---

## 8. Authorization & Tenancy (the reusable core)

A dependency chain every clinic-scoped endpoint composes:
- `current_auth` — validate JWT → `auth_user_id`.
- `current_user` — load `app_user`; 401/onboarding if absent.
- `current_membership(clinic_id)` — load the user's `clinic_member` for the route's `clinic_id`;
  **reject if the user has no active membership in that clinic** (the clinic-boundary gate).
- `require_role(*roles)` — assert the membership role is permitted.

Consequences: a user can only ever address clinics they belong to; role determines which
actions are allowed. Settings edits are restricted to `owner`/`practice_manager` (Golden Rule
9.3). A user may belong to multiple clinics; the clinic is identified by the route (`clinic_id`),
validated against membership — no ambient "current clinic" global.

---

## 9. Audit (minimal, append-only)

`audit_event_beta` rows are written **in the same transaction** as the business change, so an
event and its audit record commit or roll back together (no silent loss; Golden Rule 7.3's
retry/dead-letter is SP4). Captured in SP1: `clinic.created`, `clinic_member.created`,
`clinic_member.role_changed`, `clinic_member.status_changed`, `clinic_invite.created`,
`clinic_invite.accepted`, `clinic_invite.revoked`, `clinic_settings.updated`. Each records actor,
timestamp, action, entity type/id, and previous/new values where applicable (Golden Rule 7.2).
Append-only: corrections are new events, never edits (Golden Rule 7.4).

---

## 10. API Endpoints (SP1)

- `GET /api/v1/me` — current user, memberships (clinic + role), onboarding status.
- `POST /api/v1/clinics` — self-serve create clinic (caller becomes owner).
- `POST /api/v1/clinics/join` — accept an invite `{ token }`.
- `GET /api/v1/clinics/{clinic_id}` — clinic details (members only).
- `GET /api/v1/clinics/{clinic_id}/members` — list members (members only).
- `PATCH /api/v1/clinics/{clinic_id}/members/{id}` — change member role/status (owner).
- `GET|PATCH /api/v1/clinics/{clinic_id}/settings` — clinic settings (owner/practice_manager).
- `POST /api/v1/clinics/{clinic_id}/invites` — create role-specific invite (authorized).
- `GET /api/v1/clinics/{clinic_id}/invites` — list invites (authorized).
- `DELETE /api/v1/clinics/{clinic_id}/invites/{id}` — revoke invite (authorized).

All errors use the skeleton's uniform error envelope.

---

## 11. Frontend (minimal — not dashboards)

- `supabase-js` client + zod-validated public env (Supabase URL + publishable key).
- **Login** screen: phone-OTP and email/password tabs.
- **Onboarding**: post-login, if `needs onboarding` → "Have an invite? Paste it" **or** "Create a
  new clinic." Invite path joins with the invite's role; create path makes a clinic (owner).
- **Authed shell**: shows current clinic + role; route guard redirects unauthenticated users to
  login. The `api-client` attaches the Supabase JWT as `Authorization: Bearer`.
- Rich dashboards/feature screens remain SP6. Feature-first structure (`src/features/auth`,
  `src/features/clinic`).

---

## 12. Backend Module Structure (feature-first)

New modules under `app/modules/`, each with `router.py`, `schemas.py`, `models.py`,
`service.py`:
- `auth` — JWT validation, JWKS client, the `current_auth`/`current_user` dependencies,
  `GET /me`.
- `clinics` — clinic + clinic_settings models, create/get, settings.
- `members` — clinic_member model, membership resolution dependency, list/patch.
- `invites` — clinic_invite model, create/accept/list/revoke.
- `audit` — `audit_event` model + a small `record_audit(db, ...)` helper used in-transaction by
  the other services.

Shared authz dependencies (`current_membership`, `require_role`) live in `app/core/` since they
are cross-module. Import discipline from the skeleton holds (one-way `core/ ← modules/ ← main`).
The throwaway `ping` module is **deleted** as part of SP1 (its job is done).

---

## 13. Testing

- **Backend (pytest, Postgres):**
  - JWT validation with a **test keypair + mocked JWKS** — never call real Supabase
    (Golden Rule 10.3). Valid, expired, wrong-issuer/audience, bad-signature cases.
  - Onboarding: self-serve create (owner + settings + audit), invite-accept (role from invite +
    audit), needs-onboarding gating.
  - Invites: single-use (second redemption fails), expired, revoked, wrong-clinic, role honored.
  - **Authz isolation:** user in clinic A is denied clinic B's endpoints; role guards
    (assistant blocked from settings; only owner patches members).
  - **Audit assertions:** each mutating action writes the expected `audit_event` row in the same
    transaction (and rolls back with the change on failure).
- **Frontend (Playwright):** login + onboarding happy path with **Supabase Auth mocked** (no real
  OTP). 
- Concurrency: simultaneous redemption of the same single-use invite — exactly one succeeds.

---

## 14. Migrations & Database

- Alembic migrations (the skeleton's pattern; tests build the schema by running migrations).
- Supabase: enable **RLS** on every new `public` table; do **not** grant `anon`/`authenticated`
  (tables stay off the Data API). Run `get_advisors` after schema changes and resolve findings.
- `auth.users` is Supabase-managed; we reference it by id via `app_user_beta.auth_user_id` (no
  FK enforcement across the `auth` schema is assumed — validated by JWT `sub` + a soft reference;
  exact FK feasibility confirmed at implementation).
- `DATABASE_URL` set to the Supabase Postgres connection string (pooled connection as
  appropriate); local 5433 remains available for offline work.

---

## 15. Acceptance Criteria

1. A new user can sign up via phone-OTP and via email/password (Supabase), and FastAPI validates
   their JWT.
2. With no invite, a user can create a clinic and becomes its `owner`; `clinic_settings` is
   created with defaults.
3. An authorized member can create a role-specific invite; a second user can redeem it once and
   joins with exactly that role; a second redemption fails cleanly; expired/revoked invites are
   rejected.
4. `GET /me` reports the user, memberships (clinic + role), and onboarding status.
5. A user cannot access or address a clinic they don't belong to (cross-clinic denied); role
   guards enforce settings/member-management restrictions.
6. Every mutating action writes the expected append-only `audit_event` row in the same
   transaction.
7. The frontend supports login + onboarding (invite or create) and reaches an authed shell
   showing clinic + role.
8. RLS is enabled on all new tables; none are exposed to the Data API; `get_advisors` is clean.
9. Backend unit/integration tests (incl. authz isolation, invite edge cases, audit) and the
   frontend Playwright happy-path pass; CI green on both repos.
10. The throwaway `ping` slice is removed.

---

## 16. Known Domain Ambiguities — resolved here / deferred

- **User ↔ Doctor/Assistant linkage** (digest ambiguity): resolved for SP1 via generic
  `clinic_member.role`; the rich entity linkage (`Doctor.linked_user_id`) is SP2.
- **Who may invite whom:** SP1 = owner/practice_manager issue invites for any non-owner role;
  SP2 refines per the PRD (assistant issues doctor invites alongside creating the Doctor entity).
- **Multi-clinic membership:** modeled (membership is many-per-user) but the in-app clinic
  switcher UX is minimal in SP1; richer UX deferred.
