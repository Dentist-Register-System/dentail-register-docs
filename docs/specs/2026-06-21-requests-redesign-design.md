# Requests Page Redesign — Design Spec (#89)

**Status:** Approved (brainstorm 2026-06-21; mockup `Mockups/requests_mockup_final.png`). System-wide: **db + backend + frontend**. Calm Soft-Purple (#65); Settings/Patients design language.
**Type:** Redesign the Requests page into enriched, status-colour-coded, **server-paginated** carded rows with tabs-with-counts + filters + search; plus a `gender` field added across the patient surface.

## 1. Goal
Replace the bare Requests list (datetime + complaint only) with the approved mockup: each request shows the patient (name, age, gender, phone), doctor, chief complaint, requested date/time, and a colour-coded status with its decision timestamp — plus status tabs with exact counts, a Filters popover, search, and pagination. Make triage instant and informative.

## 2. Scope decisions (locked in brainstorm)
- **Server-side** list (pagination + filtering + search) and a **counts** endpoint. Rationale: requests grow unbounded (every booking leaves a row), so client-side-over-one-fetch would ship stale/over-large data and produce inexact tab counts. Server-side ships only the visible page and returns exact counts.
- **Multi-device freshness** is handled by TanStack Query `refetchOnWindowFocus` + invalidate-on-mutation (orthogonal to pagination; no realtime needed now).
- **Gender** is added as a real nullable field (`male`/`female`/`other`) on the patient and flows through **Add Patient + Edit Patient + patient-detail** as well as the requests card (not a card-only cosmetic).
- **Filters** popover is built now: by **doctor** + **requested-date range**.
- **"New"** badge = status `pending` AND `created_at` within the last 24h (deterministic; computed on the FE from `created_at`).
- Approve/Reject gating unchanged (`canDecide` = linked doctor; hidden in `direct_booking` mode per #87). Cancel/Resend = coordinator, in the ⋮ menu.

## 3. Data model
- **Migration (next number, via Supabase MCP):** `ALTER TABLE patient_beta ADD COLUMN gender VARCHAR(10)` (nullable) + `CHECK (gender IN ('male','female','other'))` (the CHECK allows NULL). No backfill.
- **Patient model:** `gender: Mapped[str | None]`.
- No new columns on `AppointmentRequest` — `created_at` ("Requested on") and `updated_at` (set `onupdate` → decision time) already exist.

## 4. Backend
### 4a. Patient gender (schemas + service)
- `PatientCreate` / `PatientUpdate`: add `gender: str | None` (validated ∈ {male,female,other} or None). `PatientRead`: add `gender: str | None`. `create_patient`/`update_patient` persist it. (Patient endpoints live in `app/modules/patients/`.)

### 4b. Enriched, paginated, searchable requests list
- **Endpoint:** `GET /clinics/{clinic_id}/appointment-requests` gains query params: `status` (one of pending/approved/rejected/cancelled, or omitted = all), `q` (search), `doctor_id`, `date_from`, `date_to` (filter on the requested `start_datetime` date), `limit` (default 5, max 100), `offset` (default 0). Response changes from a bare list to **`{ "items": [RequestListItem...], "total": int }`** (total = count of the filtered set, ignoring limit/offset, for the pagination footer).
- **`RequestListItem` (enriched):** existing fields **+** `patient_name: str`, `patient_age: int | None`, `patient_gender: str | None`, `patient_phone: str | None`, `doctor_name: str`, `created_at: datetime`, `updated_at: datetime`. (Keep `expires_at`, `expired`.)
- **`list_requests` (service):** build a single query joining `AppointmentRequest → patient_beta → doctor_beta` (via the patients/doctors services or a scheduling-owned join that respects module boundaries — read from the other modules' services where required by CLAUDE.md; a read-only join on their tables within scheduling's query is acceptable if it doesn't reach into their internals — implementer to choose the cleanest boundary-respecting approach). Apply `clinic_id` + filters; `q` = case-insensitive ILIKE across `patient.name`, `patient.phone`, `doctor.name`, `req.chief_complaint`. Order `created_at desc`. Return the page slice + `total`.
- **Counts endpoint:** `GET /clinics/{clinic_id}/appointment-requests/counts` → `{ all, pending, approved, rejected, cancelled }` via a single `GROUP BY status` query (+ `all` = sum). (Generalizes the existing `pending-count`; keep `pending-count` if other callers use it, or have the nav badge read `counts.pending`.)
- **Authz:** unchanged clinic-membership gating (any member may list; decide/coordinate gating unchanged).
- **Tests (pytest):** enriched fields present + correct; status filter; `q` matches name/phone/doctor/complaint; doctor_id + date range filters; limit/offset + total; counts endpoint returns correct per-status numbers; gender persists on patient create/update + appears in the request item.

## 5. Frontend
### 5a. Patient gender in forms + detail
- **Add Patient + Edit Patient** (`src/features/patients/*` dialog/form): add a Gender control (select/segmented: Male / Female / Other, optional/clearable). Wire into the create/update payloads + the patient Zod schema + `Patient` type.
- **Patient detail** (`patient-detail.tsx` Personal Information): show **Gender** in the 2-col grid (it currently omits it) — fills the existing gap.
- i18n keys for the gender label + options (en/hi).

### 5b. Requests redesign (the mockup)
Rebuild `src/app/requests/page.tsx` + new components in `src/features/scheduling/` (e.g. `requests-list.tsx`, `request-row.tsx`, `requests-filters.tsx`, a small pure `request-status.ts` for status→token/label mapping + "new"/timestamp-label logic, unit-tested). Replace the old `requests-queue.tsx`.
- **Header:** "Requests" + "Manage appointment requests and patient inquiries."
- **Toolbar:** status **tabs** All / Pending / Approved / Rejected / Cancelled, each with a **count** from the counts endpoint (active tab styled like the Settings/Patients sub-nav active pill / mockup); **Filters** button → popover (Doctor select from clinic doctors + Requested-date From/To); **Search** input (debounced ~300ms → `q`).
- **Rows (carded, status-tinted):** each row a soft card with a left status-tinted accent/background (warning/success/destructive/muted at low opacity):
  - **Avatar:** initials on a status-tinted circle.
  - **Identity:** `patient_name` (+ **New** badge when pending & <24h) · `{age} yrs • {Gender}` · phone (with `call` icon).
  - **Doctor:** label "Doctor" + `doctor_name` (with icon).
  - **Chief Complaint:** label + text.
  - **Requested Date & Time:** label + date (calendar icon) + time (clock icon) from `start_datetime`.
  - **Status block:** a status **chip** (Pending/Approved/Rejected/Cancelled, coloured) + a muted line "Requested on / Approved on / Rejected on / Cancelled on {created_at|updated_at}".
  - **Actions:** **Approve** (filled) + **Reject** (outlined) when `canDecide && status==="pending" && !expired` (hidden in direct mode via the #87 gate); **⋮** overflow menu on every row → Cancel (coordinator, pending), Resend (coordinator, expired pending). Reuse the body-portaled menu pattern from the Patients table to escape clip contexts.
- **Pagination footer:** "Showing {from}–{to} of {total}" + Prev/Next + page chips + a "{n} per page" selector (default 5). Drives `limit`/`offset`.
- **Empty state:** calm centered empty-state per active tab/search.
- **Data/hooks:** `useRequests(clinicId, { status, q, doctorId, dateFrom, dateTo, limit, offset })` (query key includes all params) returning `{items,total}`; `useRequestCounts(clinicId)`; `useRequestAction` (existing) — all with `refetchOnWindowFocus: true`; actions invalidate the requests list + counts. Debounce search in the component.
- Status colour mapping via a pure helper (tokens only): pending→`warning`, approved→`success`, rejected→`destructive`, cancelled→`muted`.

## 6. Quality
- **Backend:** `uv run ruff check .` clean; `make test` (incl. new tests) green; migration via Supabase MCP (controller-only) — implementers validate on local PG :5433.
- **Frontend:** `tsc --noEmit` + `npm run build` + i18n parity (`tests/e2e/i18n.spec.ts`) green; a pure-logic unit test for the status/new/label helper + any pagination math.
- **Rule 17.0** (semantic tokens only, compose `components/ui/*`, no per-page CSS, no new tokens); both themes; mobile-first (rows stack; toolbar wraps); WCAG AA (status conveyed by chip text + colour, not colour alone). Match Patients/Settings conventions.
- **CI:** never merge red (verify `gh-personal pr checks`). **Frontend PR held for user test;** backend may merge after green review.
- Faithful to `Mockups/requests_mockup_final.png` within the design system.

## 7. Scope guards / deferred
- Realtime live updates (Supabase realtime) — deferred (refetch-on-focus covers it now). Bulk actions; CSV export; saved filter presets — deferred. No change to the booking/approval logic itself (only the list read + gender). "All" tab counts come from the counts endpoint.

## 8. Self-review (against the request)
- Enriched rows (name/age/gender/phone, doctor, complaint, requested date/time, status + timestamp): §4b/§5b. ✅
- Status colour-coding (pending/approved/rejected/cancelled): §5b helper + tokens. ✅
- Tabs with exact counts + Filters + Search + Pagination, server-side: §4b/§5b. ✅
- Approve/Reject per-row (gated) + ⋮ menu placement per mockup: §5b. ✅
- "New" badge (pending & <24h): §2/§5b. ✅
- Gender added across patient create/edit/detail + card: §3/§4a/§5a. ✅
- Multi-device freshness via refetch/invalidation: §2/§5b. ✅
- Rule 17.0 + i18n + both themes + tests + merge policy: §6. ✅
- Placeholder scan: concrete endpoints/params/fields/components/testids; no TBD. ✅
