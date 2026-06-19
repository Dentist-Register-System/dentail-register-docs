# SP3.2 — Appointment Requests → Approval → Appointments (Atomic Slot Capacity) — Design Spec

> Status: Draft for review · Date: 2026-06-20 · Requirement source: issue #46 (slice of epic #9, SP3 Scheduling engine)
> Scope: the core booking loop — an assistant creates an appointment **request** against a slot; the **assigned doctor** approves (→ a confirmed **appointment**) or rejects; with **atomic slot capacity** enforced. Builds on SP3.1 (availability windows + virtual `compute_slots`, merged). Communication/notifications + hooks remain deferred (pull-based; SP4/SP5).

---

## 1. Context & Purpose
SP3.1 produced doctor availability and **virtual** slots (computed on read, no `slot_beta` table). SP3.2 makes slots **bookable**: an assistant (or owner/practice_manager) submits an appointment request against a computed slot; the request reserves capacity **atomically**; the **assigned doctor** approves (creating a Confirmed appointment) or rejects. This is the heart of the scheduling engine and the place the concurrency/overbooking guarantees (Golden Rules §5.2, §6.2) are realized.

Per the brainstorming session, slots are **lazy-materialized**: a `slot_beta` row is created the first time a slot is booked, and it is the row-level **lock anchor** for atomic capacity. There is **no background scheduler**: request expiry is **derived** from timestamps.

## 2. Scope Decisions (locked during brainstorming)
- **Atomic capacity = pessimistic row lock + count.** Lazy-create `slot_beta` (UNIQUE `doctor_id,start_datetime`; `INSERT … ON CONFLICT DO NOTHING` then re-select), `SELECT … FOR UPDATE` it, **count active consumers** under the lock, reject if at capacity. Source of truth = the actual request/appointment rows (no denormalized counter). Capacity is read **live** from clinic settings at check time.
- **Capacity consumers** = `appointment_request_beta` that are `pending` (incl. derived-expired-but-still-pending) **+** `appointment_beta` that are `confirmed`. `rejected`/`cancelled` requests do **not** count (capacity released). Waitlist entries do not count (waitlist is SP3.6, out of scope).
- **Full derived expiry.** `expires_at = created_at + clinic_settings.appointment_request_expiry_minutes` (default 120). "Expired" is **derived** (`status='pending' AND now > expires_at`) — not a stored status, no background job. Approval is **blocked** once expired. **Expired requests keep their capacity** (still counted) until an assistant acts (Golden Rule §5.5). Assistant **Cancel** → `cancelled` (releases); **Resend** → extends `expires_at` (new clock).
- **Approve/Reject = the assigned doctor ONLY** (`doctor_beta.linked_user_id == current user`). Owner/practice_manager/assistant cannot approve or reject — "doctors decide." **Create / Cancel / Resend** = assistant + owner + practice_manager (the coordinators).
- **Capacity-full → 409 `slot_full`** (clean reject). No waitlist fallback this slice (SP3.6).
- **First-committed-wins / stale-state:** every transition re-checks current state under the slot lock; a stale action (approve-after-cancel, approve-after-expire, double-approve) fails with a clear 409.
- **IA:** a new **Requests** nav destination (approvals/queue) + a derived **blue dot** (role-scoped: doctor → requests pending their approval; assistant/owner/PM → requests pending or expired) + a **Home** "pending requests" card shown to all. The dot/count is **derived from a live count** — no per-user seen/unread tracking (that needs the in-app notifications system, #40).
- Out of scope: direct booking + capacity override + retroactive (SP3.4); appointment lifecycle arrived/no-show/completed (SP3.3); cancellation-request + reschedule (SP3.5); waitlist (SP3.6); real push/WhatsApp/Calendar hooks (SP4/SP5); times remain clinic-local IST naive (SP3.1 decision); status/kind columns are `String` + CHECK (SP3.1 convention).

## 3. Data Model (migration 0010, `_beta` tables)
**`slot_beta`** — lazy-materialized lock anchor.
| Column | Notes |
|---|---|
| `id` UUID PK | |
| `clinic_id` UUID → clinic_beta | |
| `doctor_id` UUID → doctor_beta | |
| `start_datetime` timestamp (naive local) | |
| `end_datetime` timestamp | `start + default_slot_size_minutes` at create |
| `created_at` timestamptz | |
| **UNIQUE(`doctor_id`,`start_datetime`)** | the get-or-create + lock key |

Capacity is **not** stored on the slot (read live from settings).

**`appointment_request_beta`**
`id`, `clinic_id`, `patient_id`→patient_beta, `doctor_id`→doctor_beta, `slot_id`→slot_beta, `start_datetime`, `status` String+CHECK in (`pending`,`approved`,`rejected`,`cancelled`) default `pending`, `chief_complaint` text null, `notes` text null, `requested_by` UUID, `expires_at` timestamp, `created_appointment_id` UUID null, `created_at`/`updated_at`. Index `(clinic_id,doctor_id,status)`.

**`appointment_beta`**
`id`, `clinic_id`, `patient_id`, `doctor_id`, `slot_id`, `start_datetime`, `end_datetime`, `status` String+CHECK in (`confirmed`) default `confirmed` (lifecycle states added SP3.3), `source` String+CHECK in (`request_approval`) (extended SP3.4), `request_id` UUID null, `requested_by` UUID, `approved_by` UUID, `chief_complaint` text null, `notes` text null, `created_at`. Index `(clinic_id,doctor_id,start_datetime)`.

## 4. Atomic Capacity Engine (service, one transaction)
`reserve_slot(db, *, clinic_id, doctor_id, start_datetime)`:
1. **Validate slot legitimacy:** recompute SP3.1 `compute_slots` for `(doctor, start_datetime.date())` and assert `start_datetime` matches an emitted, non-blocked slot → else `ValidationError` (422). (Guards against booking arbitrary times / blocked/vacation times.)
2. **Get-or-create** `slot_beta` (`ON CONFLICT(doctor_id,start_datetime) DO NOTHING`, then select).
3. **`SELECT … FOR UPDATE`** the slot row (serializes concurrent reservations on this slot).
4. **Capacity** = `allow_multiple_bookings_per_slot ? max_bookings_per_slot : 1` (live from settings).
5. **Count consumers** under the lock = `pending` requests on this slot + `confirmed` appointments on this slot. If `>= capacity` → `ConflictError` (409, `slot_full`).
6. Caller proceeds to insert the request (or, on approval, the appointment) within the same transaction; commit.

`create_request` calls `reserve_slot` then inserts the request. `approve` re-enters the lock to re-validate state + capacity before inserting the appointment (the appointment replaces the request as the consumer — net capacity unchanged; the appointment counts, the now-`approved` request does not).

## 5. Request Lifecycle & Expiry
States: `pending → approved | rejected | cancelled`. **Expired** = derived overlay (`pending AND now > expires_at`), surfaced in reads as `expired` and enforced at approve.
- **Create:** `pending`, `expires_at = now + expiry_minutes`, capacity reserved.
- **Approve** (assigned doctor; re-check `pending` & not expired under lock): create `appointment_beta` (`confirmed`), set request `approved` + `created_appointment_id` + `approved_by`. Stale (not pending / expired) → 409.
- **Reject** (assigned doctor; re-check `pending`): set `rejected` (capacity released). Expired requests cannot be approved but **can** be rejected/cancelled.
- **Cancel** (coordinator; `pending` incl. expired): set `cancelled` (capacity released).
- **Resend** (coordinator; `pending` incl. expired): set `expires_at = now + expiry_minutes` (fresh clock); stays `pending`.
- Terminal states (`approved`/`rejected`/`cancelled`) cannot be reopened (Golden Rule §6.3).

## 6. API (clinic-scoped via existing membership/auth chain; routes follow the scheduling-module conventions)
- `POST   …/doctors/{doctor_id}/appointment-requests` — create (atomic reserve). Body: `patient_id`, `start_datetime`, `chief_complaint?`, `notes?`. → 201 request, 409 `slot_full`, 422 invalid slot.
- `GET    …/doctors/{doctor_id}/appointment-requests?status=` — list (per doctor). Also `GET …/appointment-requests?scope=` clinic-wide queue for the Requests screen (returns requests with derived `expired` flag).
- `POST   …/appointment-requests/{id}/approve` · `/reject` — assigned doctor only.
- `POST   …/appointment-requests/{id}/cancel` · `/resend` — coordinator only.
- `GET    …/appointment-requests/pending-count?scope=` — lightweight count for nav dot + Home card (role-scoped).
- `GET    …/doctors/{doctor_id}/appointments?from=&to=` — confirmed appointments (minimal list).
- `GET    …/doctors/{doctor_id}/slots` (SP3.1) — now returns real **occupancy** = consumer count per slot, so the viewer renders fullness; `status` becomes `full` when occupancy ≥ capacity.
Errors via the uniform envelope + stable codes (`slot_full`, `forbidden`, `validation_error`, `not_found`, `conflict`).

## 7. Permissions & Audit
- **Create / Cancel / Resend request:** `assistant` + `owner` + `practice_manager`.
- **Approve / Reject:** the **assigned doctor only** — `doctor_beta.linked_user_id == current_user.id` for the request's doctor. No one else (owner/PM included) may approve or reject.
- **Read** (requests, slots, appointments, counts): any active clinic member.
- All operations clinic-scoped; **audit in-transaction**: `appointment_request.created/approved/rejected/cancelled/resent`, `appointment.created`.

## 8. Frontend (Rule 17.0 framework, i18n en/hi parity, both themes, mobile-first, a11y)
- **Bookable Schedule:** the SP3.1 slot viewer shows occupancy/capacity per slot; an available slot is clickable → **Request appointment** dialog: patient picker (existing patient search), chief complaint, notes → POST. Full slots render non-interactive ("Full"); waitlist deferred (SP3.6).
- **New "Requests" nav destination** (`/requests`, explicitly approved per Rule 17.0) with a **blue dot** when the role-scoped pending count > 0. Queue rows: assigned doctor sees **Approve / Reject**; coordinators see **Cancel / Resend**; expired rows flagged. Status filter (pending/expired/approved/rejected/cancelled).
- **Home:** an always-shown "Pending requests" card (count + a few items, links to Requests).
- **Dot + counts** come from `pending-count` via TanStack Query (polled/`refetch`). No seen/unread state.
- All new strings via `t()` in en + hi (parity enforced by `tests/e2e/i18n.spec.ts`).

## 9. Testing
- **Backend (pytest), concurrency-focused:** two simultaneous `reserve_slot` on a capacity-1 slot → exactly one succeeds, the other 409 (exercise the `FOR UPDATE` path); multi-booking capacity (N succeed, N+1 → 409); expired request still counts toward capacity; approve creates appointment + links + leaves net capacity unchanged; reject/cancel release capacity; approve-after-cancel / approve-after-expire / double-approve → 409 (stale-state); slot validation rejects non-availability / blocked times (422); permission matrix — create allowed for assistant/owner/PM and **403 for a doctor** (doctors direct-book in SP3.4, not via requests); approve/reject allowed for the **assigned doctor only** and 403 for everyone else (incl. owner/PM and a different doctor); cancel/resend coordinator-only; pending-count role scoping; audit rows for every transition.
- **Frontend:** tsc + build; i18n en/hi parity; the booking dialog, requests queue (approve/reject/cancel/resend), nav dot + Home card, occupancy rendering.

## 10. Execution shape
One spec, one plan. **Backend first** (migration 0010 + models + `reserve_slot` engine + request/appointment services + endpoints + concurrency tests), then **frontend** (api/hooks, i18n + Requests nav, bookable slot dialog, requests queue, Home card + dot). Migration 0010 applied to Supabase by the controller post-merge (offline-generated SQL via MCP `apply_migration`); implementers validate via `make test` only.

## 11. Docs to update (this PR or the plan)
- `Entities/08-slot.md` — slot now materialized on booking (SP3.2); occupancy = consumer count.
- `Entities/09-appointment-request.md` — implemented states + derived expiry + capacity semantics.
- `Entities/10-appointment.md` — confirmed appointments from request approval (lifecycle SP3.3).
- PRD §15–§17 — reflect atomic capacity + request/approval as built; note approve/reject = assigned doctor only (vs any-doctor wording).
- Golden Rules — record approve/reject assigned-doctor-only + the new Requests nav approval.
