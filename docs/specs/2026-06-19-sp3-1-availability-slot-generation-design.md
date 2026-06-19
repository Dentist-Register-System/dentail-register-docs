# SP3.1 — Doctor Availability & Slot Generation — Design Spec

> Status: Draft for review · Date: 2026-06-19 · Requirement source: issue #43 (slice of epic #9, SP3 Scheduling engine)
> Scope: doctor availability (recurring + one-off windows + vacation blocks) and the **virtual slot-generation engine** that all later booking builds on. **No booking** in this slice (SP3.2). Communication/notifications and hooks are deferred (SP4/SP5); the scheduling engine here is the pure state/derivation layer, surfaced via pull (lists/queries), not push.

---

## 1. Context & Purpose
SP3 (Scheduling engine) is decomposed into slices; this is the first. SP3.1 lets doctors (and owner/practice_manager on their behalf) define **when a doctor is available**, and derives the **bookable 30-minute slots** from that. Slots are the anchor every later slice books against (requests → approval → appointments, cancellation, waitlist).

Per the brainstorming session, the slot model is **virtual + lazy-materialize**: slots are *computed on read* from availability windows minus blocks; a physical `slot_beta` row is created only when a slot is first booked — which happens in **SP3.2**, not here. So SP3.1 persists availability, computes slots, and exposes read APIs + UI; it does **not** persist slots.

## 2. Scope Decisions (locked during brainstorming)
- **Virtual + lazy-materialize slots.** No `slot_beta` table in this slice. Slots are computed DTOs. The `slot_beta` table (capacity/occupancy, atomic-lock target) is introduced in SP3.2 when booking first materializes a row.
- **Full availability model:** weekly **recurring** windows + **one-off** (specific-date) windows + **vacation blocks**. One-off windows are **additive** to recurring; blocks **subtract**.
- **Blocks are time-range within a date**, with **both times null ⇒ full-day** block.
- **Write permission = doctor (own) + owner/practice_manager.** Assistants are read-only. (Recorded deviation from Entities/07 "doctor-only", mirroring the SP2 owner/PM decision.) All active clinic members may **read** availability + slots (Entities/07 visibility).
- **Slot size** from `clinic_settings.default_slot_size_minutes` (default 30); **trailing partial chunk dropped**. **Capacity** from `clinic_settings`: `allow_multiple_bookings_per_slot ? max_bookings_per_slot : 1`.
- **Weekday convention: 0 = Monday … 6 = Sunday** (Python `date.weekday()`).
- **Times are clinic-local (Asia/Kolkata, IST), stored naive-local.** V1 is single-location India; no UTC conversion. (Revisit if multi-location lands.)
- **Slot queries are bounded to a 62-day range** to cap response size.
- **New "Schedule" nav destination is explicitly approved** (Rule 17.0 requires explicit approval for new navigation; granted in brainstorming).
- **Out of scope:** appointment requests/booking, atomic capacity, appointment lifecycle, cancellation/reschedule, waitlist (later SP3 slices); notifications, WhatsApp/Calendar hooks (SP4/SP5); follow-up (SP6); multi-location/timezone conversion; recurrence beyond weekly.

## 3. Data Model (migration 0009, `_beta` tables)

### `availability_window_beta`
| Column | Type | Notes |
|---|---|---|
| `id` | UUID PK | |
| `clinic_id` | UUID | tenancy anchor, always set |
| `doctor_id` | UUID → `doctor_beta.id` | |
| `kind` | enum(`recurring`,`one_off`) | |
| `day_of_week` | smallint (0–6) | recurring only; null for one_off |
| `specific_date` | date | one_off only; null for recurring |
| `start_time` | time | clinic-local |
| `end_time` | time | clinic-local |
| `status` | enum(`active`,`removed`) | default `active` |
| `created_by` | UUID | actor |
| `created_at` / `updated_at` | timestamptz | |

CHECKs: `(kind='recurring' AND day_of_week IS NOT NULL AND specific_date IS NULL) OR (kind='one_off' AND specific_date IS NOT NULL AND day_of_week IS NULL)`; `end_time > start_time`; `day_of_week BETWEEN 0 AND 6`.

### `availability_block_beta`
| Column | Type | Notes |
|---|---|---|
| `id` | UUID PK | |
| `clinic_id` | UUID | |
| `doctor_id` | UUID → `doctor_beta.id` | |
| `block_date` | date | |
| `start_time` | time NULL | null (with end null) ⇒ full-day block |
| `end_time` | time NULL | |
| `reason` | text NULL | optional |
| `status` | enum(`active`,`removed`) | default `active` |
| `created_by` | UUID | |
| `created_at` | timestamptz | |

CHECK: `(start_time IS NULL AND end_time IS NULL) OR (start_time IS NOT NULL AND end_time IS NOT NULL AND end_time > start_time)`.

Indexes: both tables on `(doctor_id, status)`; block also on `(doctor_id, block_date)`.

## 4. Slot Computation Engine (pure function, backend)
`compute_slots(doctor_id, date_from, date_to, settings) -> list[SlotDTO]`:

For each date `D` in `[date_from, date_to]` (inclusive, ≤ 62 days):
1. **Collect active windows for D:** recurring windows with `day_of_week == D.weekday()` **plus** one-off windows with `specific_date == D`, all `status='active'`.
2. **Chunk** each window `[start_time, end_time)` into `slot_size_minutes` pieces; **drop a trailing piece** shorter than `slot_size_minutes`.
3. **Dedupe** candidate slots by `(date, start_time)` — overlapping windows collapse to one slot per start time.
4. **Subtract blocks:** for each active block on `D`, drop candidates whose `[start,end)` **overlaps** the block range; a full-day block (null times) drops every candidate on `D`.
5. **Emit** `SlotDTO { doctor_id, date, start_time, end_time, start_datetime (local), capacity, occupancy: 0, status: "available" }`.
   - `capacity = settings.allow_multiple_bookings_per_slot ? settings.max_bookings_per_slot : 1`.
   - `occupancy` is always `0` in SP3.1 (no bookings exist). It becomes real in SP3.2.

Result sorted by `start_datetime`. Pure/deterministic → unit-testable without DB.

## 5. API (clinic-scoped via the existing membership/auth dependency chain; routes follow the doctors-module conventions — the plan pins exact prefixes)
**Availability windows**
- `POST   …/doctors/{doctor_id}/availability` — create (recurring or one_off).
- `GET    …/doctors/{doctor_id}/availability` — list active windows for a doctor.
- `PATCH  …/doctors/{doctor_id}/availability/{id}` — edit times/day/date.
- `DELETE …/doctors/{doctor_id}/availability/{id}` — soft-remove (`status='removed'`).

**Availability blocks**
- `POST   …/doctors/{doctor_id}/availability/blocks` — create block.
- `GET    …/doctors/{doctor_id}/availability/blocks` — list active blocks.
- `DELETE …/doctors/{doctor_id}/availability/blocks/{id}` — soft-remove.

**Slots**
- `GET …/doctors/{doctor_id}/slots?from=YYYY-MM-DD&to=YYYY-MM-DD` — computed slots (422 if range > 62 days or `to < from`).

Validation: `end_time > start_time`; `kind` field constraints; `day_of_week ∈ 0..6`; block time-pair both-null-or-both-set; date range bound. Errors use the uniform envelope + stable codes.

## 6. Permissions & Audit
- **Write (windows + blocks):** the doctor whose `doctor_beta.linked_user_id == current_user.id`, **or** `owner` / `practice_manager` for any doctor in the clinic. Assistants → 403 on write. Outsiders (non-members) → 403.
- **Read (windows, blocks, slots):** any active clinic member.
- **Audit (in-transaction):** `availability_window.created/updated/removed`, `availability_block.created/removed`, with before/after where applicable (Entities/07 audit requirement).

## 7. Frontend (Rule 17.0 framework, i18n en+hi, both themes, mobile-first, a11y)
- **Doctor detail screen — Availability management:** a section (visible to doctor-self + owner/PM) to add/edit/remove **recurring** windows (a weekly editor), **one-off** date windows, and **vacation blocks**. RHF + Zod (times, day/date, kind), framework `ui/*` components, semantic tokens, no per-page CSS. Read-only rendering for assistants.
- **New "Schedule" nav destination (`/schedule`)** — explicitly approved. Hosts the **read-only slot viewer**: pick a doctor + date range (default next 14 days) → the computed slots list/day-grouped view showing time + capacity. This route is the future home for the appointments calendar (later SP3 slices). Nav order: **Home · Schedule · Doctors · Assistants · Patients**; icon `calendar_month`; `nav.schedule` i18n key (en + hi).
- All new strings via `t()` in both locales (parity enforced by `tests/e2e/i18n.spec.ts`).

## 8. Testing
- **Backend (pytest):** the `compute_slots` function across cases — recurring only; one-off additive to recurring; overlapping-window dedupe; trailing-partial drop; full-day block clears the date; time-range block subtracts overlaps only; capacity reflects single vs multi-booking settings; empty day → no slots; 62-day cap + `to<from` → 422. Window/block CRUD happy-path + validation (time ordering, kind constraints, block time-pair). Permission matrix: doctor-self write ✓, owner/PM write ✓, assistant write 403 + read ✓, outsider 403. Audit rows written. Migration 0009 applies (tests run `alembic upgrade head`).
- **Frontend:** `tsc --noEmit` + `npm run build` clean; i18n en/hi parity; component coverage for the availability editor and the slot viewer (pure helpers unit-tested via the Playwright-runner pattern, as in `clinic-completeness.spec.ts`).

## 9. Execution shape
One spec, one plan. **Backend first** (migration 0009 + models + `compute_slots` + APIs + tests), then **frontend** (doctor-detail availability editor + `/schedule` slot viewer + nav destination). Migration 0009 applied to Supabase by the controller post-merge (offline-generated SQL via MCP `apply_migration`); implementers validate via `make test` only.

## 10. Docs to update (this spec's PR or the plan's)
- `Entities/07-availability-window.md` — note recurring+one-off kinds, status model, owner/PM write deviation.
- `Entities/08-slot.md` — note slots are **virtual** in V1 (computed; materialized on booking in SP3.2).
- PRD §15 scheduling section — reflect the virtual-slot + availability model as built.
- Golden Rules — record the owner/PM availability-write deviation and the new "Schedule" nav approval.
