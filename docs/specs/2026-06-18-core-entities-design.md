# Core Entities (Sub-project 2) — Design Spec

> Status: Draft for review
> Date: 2026-06-18
> Author: Brainstormed via Claude Code (superpowers:brainstorming)
> Sub-project: 2 of the Register System build sequence (follows Sub-project 1, auth + clinic workspace)

---

## 1. Context & Purpose

Sub-project 1 established identity, multi-tenancy, and authorization: who you are (Supabase
Auth), which clinic you belong to and as what generic **role** (`clinic_member.role ∈ {owner,
practice_manager, doctor, assistant}`), and the authoritative clinic-boundary + role enforcement
that guards all clinic-scoped data.

Sub-project 2 builds the **rich operational entities** the clinic actually works with on top of
that proven authz layer:

- the **Doctor** entity (specialty, lifecycle) and its **invite → activation** flow;
- the **Assistant** entity (title, lifecycle) and a mirrored invite → activation flow;
- the **Patient** entity with **fast search** and **duplicate-warning** on create.

**This sub-project delivers:** owners/practice-managers can create doctors and assistants (which
issues a role-specific invite and creates an `invited` entity row); those people accept the invite,
create an account, and the entity becomes `active` with a linked user + a `clinic_member` granting
access; and anyone in the clinic can create, search, edit, and delete patients, with a non-blocking
duplicate warning at create time. Everything is clinic-scoped, audited in-transaction, i18n-first,
and built on the SP1 dependency chain.

**Boundary with SP1.** SP1 modeled roles **generically** via `clinic_member.role`. SP2 introduces
the rich entities as **separate tables** (`doctor_beta`, `assistant_beta`) that *link to* a
`clinic_member`/`app_user` once the person signs up — it does not replace the membership record.
SP1's generic invite mechanism (`clinic_invite_beta`) is **reused** as the underlying transport;
SP2 extends it to carry the entity being activated.

**Boundary with SP3 (Scheduling engine).** Availability windows, slots, and appointments (Entities
07/08/10) FK to **`doctor_beta.id`** — that stable anchor is created here. SP2 does **not** build
any scheduling logic; "doctor submits availability → Active" (PRD §11) is simplified in SP2 to
"doctor accepts invite + links account → Active". Availability is SP3.

---

## 2. Scope Decisions (locked during brainstorming)

- **Separate entity tables.** `doctor_beta` and `assistant_beta` are first-class rows, each with
  `clinic_id` (the tenancy anchor, always set) and a **nullable `linked_user_id`** (set on
  activation). Rationale: (1) matches the Entities docs (Doctor/Assistant are distinct entities
  that "belong to clinic, may have a linked user"); (2) a doctor must exist in the `invited` state
  *before* any account exists; (3) SP3 scheduling FKs to `doctor_beta.id`; (4) distinct fields
  (`specialty` vs `title`) stay cohesive instead of nullable columns piled on `clinic_member`.
- **Create-doctor is one atomic action.** `POST …/doctors` inserts the `doctor_beta` row (`invited`)
  **and** issues a `clinic_invite` (role=doctor, carrying `doctor_id`) in one transaction, returning
  both. Avoids a "doctor exists but was never invited" limbo. A future "resend invite" reuses the row.
- **Doctor/Assistant creation authz = owner + practice_manager only.**
  **Recorded deviation from PRD §11**, which says "assistant creates doctor" (assistant-first). The
  decision narrows creation to owner/practice_manager for SP2; it can be widened to assistants later
  with no schema change. Recorded here per the rule against silently contradicting source docs.
- **Assistant mirrors the doctor flow.** Same create → `invited` entity + role=assistant invite →
  accept → link user + `clinic_member(role=assistant)` + `active`. One staff-onboarding mechanism.
- **Patient duplicate detection: warn, never block** (PRD §10). Matching: normalized **exact phone**
  (strong signal) **OR** (**trigram-similar name** AND **age within ±2**). Uses Postgres `pg_trgm`.
  The same trigram GIN index powers the fast **name/phone search** (PRD §9).
- **Patient deletion is a hard delete** (PRD §10 "delete means delete") with an explicit confirm and
  an audit event capturing a snapshot of the deleted row. (No appointments exist yet in SP2, so there
  is no historical record to preserve a snapshot *for*; Golden Rule 4.2/4.3 snapshotting becomes
  relevant once appointments exist in SP3+.)
- **`clinic_invite_beta` extended** with nullable `doctor_id` and `assistant_id` FK columns so an
  invite carries the entity it activates (two explicit nullable FKs, for referential integrity).
- **`_beta` table naming** continues (Golden Rule 4.5): `doctor_beta`, `assistant_beta`,
  `patient_beta`. Suffix dropped at production cutover.
- **Delivery = full-stack vertical slices**, built **Doctor → Assistant → Patient**, each a single
  backend+frontend PR; backend-first *within* each slice. Doctor establishes the entity +
  invite-activation pattern, Assistant reuses it, Patient is independent (search + duplicate).

### Out of scope (explicit)
Any scheduling/availability logic, slots, appointments (SP3). Patient merge (PRD notes "if supported
later"). Patient history summary / "last two visits" (depends on appointments → SP3+). Alternate
phone numbers (PRD "future"). Doctor self-service profile editing beyond what owner/PM can edit.
WhatsApp/notification delivery (SP5/SP6). Full audit infra with retry/dead-letter (SP4).

---

## 3. Architecture

SP2 adds three feature modules behind the **existing SP1 dependency chain** — no new auth/tenancy
machinery, only new clinic-scoped resources that compose `current_membership` + `require_role`.

```
Next.js (TanStack Query + RHF/Zod) ──REST + Bearer JWT──▶ FastAPI
                                                            │ current_auth → current_user
                                                            │ → current_membership(clinic_id)   [SP1 tenancy gate]
                                                            │ → require_role(...)               [SP1 role guard]
                                                            └──SQLAlchemy (privileged conn)──▶ Supabase Postgres
                                                                 doctor_beta / assistant_beta / patient_beta
                                                                 (+ pg_trgm index on patient name)
```

Identity + tenancy are unchanged from SP1. The new modules are thin routers → services → models,
following backend import discipline (`core/ ← modules/ ← main`). Cross-module work (e.g. activation
touching invites + members + the entity) goes through the other module's **service**, never its
models/router.

---

## 4. Data Model (new `_beta` tables; `public` schema, RLS enabled, not Data-API-exposed)

UUID PKs, tz-aware timestamps, and the SP1 `MetaData` naming convention apply. RLS is enabled as
defense-in-depth and tables are **not** granted to `anon`/`authenticated` (FastAPI privileged conn
is the sole gate, exactly as SP1).

### `doctor_beta`
- `id` (uuid PK), `clinic_id` → `clinic_beta.id` (FK, indexed)
- `linked_user_id` → `app_user_beta.id` (FK, **nullable**; set on activation)
- `name` (required), `phone` (required), `email` (nullable), `specialty` (nullable)
- `status` enum `doctor_status {invited, active, inactive}` (default `invited`)
- `created_by` → `app_user_beta.id`, `created_at`, `updated_at`
- **Unique partial index** on `(clinic_id, linked_user_id)` where `linked_user_id IS NOT NULL`
  (one doctor per user per clinic; many `invited` rows with null link are allowed).

### `assistant_beta`
- Identical shape, with `title` (nullable) in place of `specialty`, and
  `status` enum `assistant_status {invited, active, inactive}`.

### `patient_beta`
- `id` (uuid PK), `clinic_id` → `clinic_beta.id` (FK, indexed)
- `name` (required), `phone` (required), `age` (smallint; **required at create** per PRD §8)
- `phone_normalized` (string, digits-only; maintained by the service on write) — for exact-match
  dedup and phone search
- `referral_source` (nullable), `medical_conditions` (text, nullable),
  `chief_complaint` (text, nullable), `notes` (text, nullable)
- `created_by` → `app_user_beta.id`, `created_at`, `updated_at`
- **Indexes:** GIN trigram on `name` (`gin_trgm_ops`), btree on `phone_normalized`, btree on `clinic_id`.

### `clinic_invite_beta` (extend existing SP1 table)
- Add `doctor_id` → `doctor_beta.id` (FK, nullable) and `assistant_id` → `assistant_beta.id`
  (FK, nullable). An invite carries **at most one** of these; null for plain role invites
  (e.g. owner inviting a practice_manager still uses the SP1 generic path).

### Extensions / migrations
- Migration A: three tables + enums + the two `clinic_invite_beta` FK columns.
- Migration B: `CREATE EXTENSION IF NOT EXISTS pg_trgm;` + the trigram GIN index on
  `patient_beta.name`.
- RLS enabled on the three new tables (mirrors SP1 migration `0003`). `get_advisors` run clean
  after apply.

---

## 5. Entity Lifecycles & Flows

### 5.1 Doctor

**Create (owner / practice_manager)** — `POST /api/v1/clinics/{cid}/doctors {name, phone, specialty?}`
One transaction:
1. Insert `doctor_beta` (`status: invited`, `linked_user_id: NULL`, `created_by`).
2. Insert `clinic_invite_beta` (`role: doctor`, `doctor_id` set, single-use, expiring) — reusing the
   SP1 invite mechanism.
3. Audit `doctor.created` + `clinic_invite.created`.
Returns the doctor + the invite link/token.

**Activation** — extends SP1 `POST /api/v1/clinics/join {token}`.
If the redeemed invite carries `doctor_id`, then in one transaction:
1. Create `app_user` from the JWT identity (if absent).
2. Create `clinic_member` (`role: doctor`, `status: active`) — the SP1 access grant.
3. Set `doctor_beta.linked_user_id` + `status: active`.
4. Mark invite `accepted`; audit `clinic_member.created` + `clinic_invite.accepted` +
   `doctor.activated`. Single-use enforced atomically (a second redemption fails cleanly).

**Edit / Deactivate (owner / practice_manager)** — `PATCH …/doctors/{id}`.
Profile edits audit `doctor.updated` (before/after). Setting `status: inactive` (departure) keeps
the row + history and **also flips the linked `clinic_member.status` to `inactive`** so access is
revoked in the same transaction; audit `doctor.status_changed`. Reactivation is the inverse.

### 5.2 Assistant
Identical to 5.1 with `title` instead of `specialty`, `role: assistant`, and `assistant_id` on the
invite. Audit actions `assistant.created` / `.activated` / `.updated` / `.status_changed`.

### 5.3 Patient

**Create** — `POST /api/v1/clinics/{cid}/patients` (any active member):
1. Compute `phone_normalized`; run the **duplicate check** (§6).
2. If matches exist **and** the request lacks `acknowledge_duplicates: true` → return
   `409 {code: "duplicate_warning", details:{matches:[…]}}`. **No hard block** — the client
   resubmits with `acknowledge_duplicates: true`.
3. Otherwise (no matches, or acknowledged) insert `patient_beta`; audit `patient.created`
   (and `patient.duplicate_override` when acknowledged, per Patient entity audit requirements).

**Search** — `GET …/patients?q=` (any active member): trigram-ranked name match + `phone_normalized`
prefix/contains; empty `q` → most-recent patients. Designed to be fast (indexed).

**Edit** — `PATCH …/patients/{id}`: audit `patient.updated` (before/after).

**Delete** — `DELETE …/patients/{id}?confirm=true` (hard delete): requires explicit confirm; audit
`patient.deleted` capturing a snapshot of the row. Returns `409`/`400` if `confirm` is not set.

---

## 6. Patient Duplicate Detection & Search

Both features share one `pg_trgm` GIN index on `patient_beta.name`.

**Duplicate match** (warn-only, never blocks; PRD §10):
```
candidate is a potential duplicate within the same clinic if:
    normalized_phone == new.normalized_phone
 OR (similarity(name, new.name) > 0.4  AND  abs(age - new.age) <= 2)
```
- Phone is normalized to digits-only before comparison (the strong signal).
- Name similarity uses `pg_trgm` `similarity()` (threshold 0.4, tunable) to catch spelling variants.
- Age within ±2 corroborates a fuzzy name match.
- Exposed two ways: a **standalone pre-check** (`POST …/patients/duplicate-check {name, phone, age}`)
  so the UI can warn live before submit, **and** the create-time handshake (§5.3) so the server
  always enforces a conscious override.

**Search** (PRD §9 — name + phone only, must be fast):
- Name: trigram-ranked (`similarity` ordering) so partial/misspelled queries still match.
- Phone: match on `phone_normalized` (digits-only) so formatting differences don't matter.
- Clinic-scoped; paginated; empty query returns recent patients.

---

## 7. API Endpoints (SP2 — all under `/api/v1/clinics/{clinic_id}`)

Clinic boundary + role enforced via the SP1 dependency chain. Uniform error envelope throughout.

**Doctors**
- `POST /doctors` — create doctor + issue invite. **owner/practice_manager.** → doctor + invite link.
- `GET /doctors` — list (any active member); `?status=` filter.
- `GET /doctors/{id}` — detail (any active member).
- `PATCH /doctors/{id}` — edit profile / set status. **owner/practice_manager.**

**Assistants** — `POST|GET|GET/{id}|PATCH /assistants` — same shapes/guards, with `title`.

**Patients** (any active member)
- `POST /patients` — create with duplicate handshake (`acknowledge_duplicates?`).
- `POST /patients/duplicate-check` — standalone pre-check; returns candidate matches.
- `GET /patients?q=&limit=&offset=` — fast name/phone search; empty `q` → recent.
- `GET /patients/{id}` — detail.
- `PATCH /patients/{id}` — edit.
- `DELETE /patients/{id}?confirm=true` — hard delete.

**Activation** — no new endpoint; SP1's `POST /api/v1/clinics/join {token}` is extended to honor
`doctor_id`/`assistant_id` on the invite (§5).

**New stable error code:** `duplicate_warning`. Roles/statuses remain stable enums (the i18n
contract). No English message is ever the display source (Golden Rule 16.2).

---

## 8. Authorization & Tenancy (reuses SP1)

No new authz primitives. Each endpoint composes `current_membership(clinic_id)` (the clinic-boundary
gate) + `require_role(...)`:
- **Create/edit doctors & assistants:** `owner`, `practice_manager`.
- **All patient operations + listing/reading staff:** any **active** member of the clinic
  (Golden Rule 9: doctors and assistants both view all patient records; assistants create patients).
- Cross-clinic access remains impossible by construction (Golden Rule 9.1) — a user can only address
  clinics they have an active `clinic_member` row for.

---

## 9. Audit (minimal, append-only — reuses SP1 `audit_event_beta`)

Every mutating action writes an `audit_event_beta` row **in the same transaction** as the change
(Golden Rule 13.3; no fire-and-forget). New actions: `doctor.created`, `doctor.activated`,
`doctor.updated`, `doctor.status_changed`; the `assistant.*` equivalents; `patient.created`,
`patient.updated`, `patient.duplicate_override`, `patient.deleted` (with row snapshot). Each records
actor, timestamp, action, entity type/id, and previous/new values where applicable. Append-only;
corrections are new events (Golden Rule 7.4).

---

## 10. Frontend (per-entity slices; design-system + i18n)

Feature-first modules `src/features/doctors`, `…/assistants`, `…/patients`, each with `api.ts`,
`hooks.ts` (TanStack Query), `schema.ts` (Zod built with `t()`), and components. New shared shadcn
primitives (data table/list, dialog, status badge, search input) are hardened to `Design/02`
standards just-in-time. **All** user-facing strings via `t()` with new keys added to **both**
`en.json` and `hi.json` (parity enforced by the existing i18n test). Semantic tokens only (no raw
colours); light/dark/system; mobile-first; AA contrast.

- **Doctors / Assistants:** list (name, specialty/title, status badge), "Add" dialog → shows the
  invite link to copy, detail view, deactivate (confirm dialog).
- **Patients:** prominent debounced **search** bar (`GET ?q=`), results list; **Add patient** form
  that calls `duplicate-check` and renders a **non-blocking warning panel** of matches with a
  "Create anyway" action (resubmits with `acknowledge_duplicates`); edit form; delete with explicit
  typed confirmation.
- Errors shown via `t('apiErrors.<code>')` including the new `duplicate_warning`.

---

## 11. Backend Module Structure (feature-first)

New modules under `app/modules/`, each `router.py` / `schemas.py` / `models.py` / `service.py`:
- `doctors` — `doctor_beta` model, CRUD service, create-with-invite (calls `invites` service).
- `assistants` — `assistant_beta` model, mirrored service.
- `patients` — `patient_beta` model, create/search/edit/delete + duplicate-check service.

`invites` (SP1) gains `doctor_id`/`assistant_id` on its model + an activation branch that links the
entity; the join/activation logic lives in the `invites`/`members` services it already owns.
Cross-module calls go through services only. Routers stay thin. `app/db/base.py` imports the three
new models for Alembic.

---

## 12. Testing

- **Backend (pytest, Postgres 5433; per-test transactional rollback):**
  - Doctor/assistant **CRUD + authz**: owner/PM can create/edit; assistant/doctor are blocked
    (403); cross-clinic isolation (clinic A cannot address clinic B's entities).
  - **Invite → activation:** redeeming a doctor/assistant invite sets `linked_user_id`, creates the
    `clinic_member`, flips status to `active`; single-use (second redemption fails); expired/revoked
    rejected; wrong-clinic rejected.
  - **Deactivation** flips the linked `clinic_member.status` and revokes access, in one transaction.
  - **Patient duplicate matching:** phone-exact match; fuzzy-name + age-window match; non-match
    cases; warn-not-block (first POST returns `duplicate_warning`, resubmit with acknowledge
    succeeds); standalone duplicate-check endpoint.
  - **Patient search:** name (incl. partial/misspelled) and phone (formatting-insensitive) return
    expected rows, clinic-scoped.
  - **Delete:** hard delete requires `confirm`; audit snapshot written.
  - **Audit:** every mutation writes the expected append-only row in the same transaction (and rolls
    back with the change on failure).
- **Frontend (Vitest + RTL for components; Playwright for e2e, all services mocked):**
  add-doctor → invite-link rendered; patient search; duplicate-warning panel + "create anyway";
  i18n key parity for the new keys; semantic-token/theme conformance for new screens.

---

## 13. Migrations & Database

- Alembic migrations (SP1 pattern; tests build schema by running migrations): Migration A (tables +
  enums + invite FK columns), Migration B (`pg_trgm` + trigram index).
- Supabase: enable **RLS** on the three new tables; do **not** grant `anon`/`authenticated`. Run
  `get_advisors` after schema changes and resolve findings.
- `pg_trgm` is a standard Postgres contrib extension available on Supabase; confirmed before use
  (permissive/no-cost). No other new backend dependency. Frontend adds no new runtime dependency
  beyond existing shadcn primitives.

---

## 14. Acceptance Criteria

1. An owner/practice_manager can create a doctor (name, phone, specialty); a `doctor_beta` row is
   created `invited` and a role=doctor invite is issued in one transaction; the response includes the
   invite link. An assistant/doctor attempting this gets `403`.
2. Redeeming that invite creates the user's `app_user` (if needed) + a `clinic_member(role=doctor)`,
   sets `doctor_beta.linked_user_id`, flips the doctor to `active`, and is single-use.
3. Deactivating a doctor keeps the row/history and revokes the linked member's access in the same
   transaction.
4. The same create → activate → deactivate flow works for assistants (with `title`).
5. Any active member can create a patient (name, phone, age required); creating a likely-duplicate
   returns a non-blocking `duplicate_warning` with matches, and resubmitting with
   `acknowledge_duplicates` succeeds.
6. Patient search by name (including partial/misspelled) and phone (formatting-insensitive) returns
   the right clinic-scoped results quickly.
7. Patient edit and hard-delete (with confirm) work; deletion writes an audit snapshot.
8. Every mutating action writes the expected append-only `audit_event` row in the same transaction.
9. A user cannot access or address entities of a clinic they don't belong to; role guards enforce
   doctor/assistant creation restrictions.
10. RLS enabled on all three new tables; none exposed to the Data API; `get_advisors` clean.
11. New frontend screens are fully i18n'd (en/hi parity), use semantic tokens only, support
    light/dark/system, and are mobile-first / AA-contrast.
12. Backend tests (CRUD, authz isolation, invite/activation, duplicate, search, delete, audit) and
    frontend component/e2e tests pass; CI green on both repos.

---

## 15. Known Domain Ambiguities — resolved here / deferred

- **User ↔ Doctor/Assistant linkage** (the SP1-deferred ambiguity): resolved — separate entity
  tables with a nullable `linked_user_id` set on activation; `clinic_member` remains the access
  record. SP3 scheduling FKs to `doctor_beta.id`.
- **Who may create doctors/assistants:** resolved for SP2 as owner/practice_manager only — a
  **recorded deviation** from PRD §11's assistant-first wording; widenable later without schema
  change.
- **"Doctor Active" trigger:** PRD §11 ties Active to availability submission; SP2 has no scheduling,
  so Active = invite accepted + account linked. Availability-driven status is revisited in SP3.
- **Patient duplicate precision:** resolved — phone-exact OR (trigram name >0.4 AND age ±2), threshold
  tunable; warn-only.
- **Patient deletion semantics:** resolved — hard delete + confirm + audit snapshot now; appointment
  snapshotting (Golden Rule 4.2/4.3) becomes relevant in SP3+ when historical records exist.
- **Deferred to later sub-projects:** patient merge, patient history summary / last-two-visits,
  alternate phone numbers, doctor self-service profile editing, availability — all out of SP2 scope.
