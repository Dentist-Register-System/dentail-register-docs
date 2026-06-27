# Today's Schedule — Design Spec (clinic-wide day grid)

**Status:** Approved in brainstorm (2026-06-27), interactive mockups signed off via the visual companion. **Phase 2 of the owner-nav redesign** (Phase 1 = Team consolidation, shipped). Register Design System (Rule 17.0), i18n-first (en/hi), both themes, WCAG 2.2 AA per `testing/ux-standards-runbook.md`. **Frontend-heavy + one new backend read endpoint. No migration.**

**Requirement source:** A clinic owner needs to see *"what's on the plate today"* at a glance. Today the only way is to open each doctor's schedule and build a mental model. This adds a single clinic-wide, all-doctors view of the day. Brainstorm 2026-06-27.

**Type:** New nav item → a **doctor-column, time-proportional day grid** (a "minified calendar") of all doctors' appointments + requests for a day.

---

## 1. Goal

> *"An owner or assistant opens **Today's Schedule** and sees every doctor as a column, time running down, each appointment a block sized to its duration — confirmed in green, requested in amber, the current time marked — and can step to other days. They see who's busy, who's free, and what's pending, across the whole clinic, in one screen."*

---

## 2. Scope decisions (locked in brainstorm 2026-06-27)

1. **Access:** **owner + assistant** (operational coordinators, §1.3). Non-owner doctors keep **My Schedule** for their own day. Gates both the nav item and the endpoint.
2. **Primary layout (desktop/tablet): a doctor-column day grid.** Columns = active doctors; a **continuous 30-min time axis** down the side spanning the clinic's working window for the day; appointments rendered as **time-proportional blocks** (position by start, height ∝ duration). Empty space between blocks = free time.
3. **Slot length is handled for free.** Blocks are sized from `start_datetime` → `end_datetime`, so a future variable-length / 2-hour booking needs **no** model or layout change. **Overlaps** within one doctor (double-booking, allowed by `allow_multiple_bookings_per_slot`) render as **side-by-side sub-columns** — the MVP may render the common **no-overlap** case first and treat overlap sub-columns as a fast-follow (it must at minimum not visually corrupt — see §6).
4. **Many doctors:** a **doctor-filter pill row** ("All (N) · Dr. X · +N · Filter") narrows the columns; beyond ~3–4 doctors the grid **scrolls horizontally** with a **sticky time gutter + sticky doctor headers**.
5. **Mobile:** the grid can't fit a phone, so it **falls back to a merged vertical timeline** — same data, one column, time-ordered, each card labeled with its doctor. (We build both renderings.)
6. **Time axis = continuous working hours**, 30-min rows, across the clinic's working window for the day (§5 derivation). Per-doctor off-hours cells may be subtly greyed ("off") — enhancement.
7. **"Now" line** spans the columns at the exact current time — **only when the viewed day is today.**
8. **Cancelled/rejected/expired** items do **not** clutter the grid; they live in a **collapsed top strip** ("✕ N cancelled ›") that expands to a list. (See §4.3 — these are *request-side* today.)
9. **Date navigation:** **‹ prev / next ›** day stepper + a **"Today"** reset; the page title shows the selected date. Nav entry defaults to today. (No full date-picker this phase.)
10. **View + tap-through (no inline actions this phase):** tapping a card navigates to its existing home — a **request → Requests**, an **appointment → the patient** (their appointments). No approve/reject/arrived logic is duplicated into this view.
11. **Queue is OUT** (walk-ins + waitlist + overflow) — tracked in docs #158, designed next.

---

## 3. What exists today (verified 2026-06-27)

**Data (backend `scheduling`/`doctors` modules):**
- **Appointment** (`appointment_beta`): `id, clinic_id, patient_id, doctor_id, slot_id, start_datetime, end_datetime (naive), status, chief_complaint, …`. **`status` is only ever `"confirmed"`** in code — arrived/no-show/completed/cancelled are **not implemented**. `AppointmentRead` includes **`patient_name`** (PR #40).
- **AppointmentRequest**: `RequestListItem` → `id, patient_id, doctor_id, patient_name, patient_age/gender/phone, doctor_name, requested_by_name, start_datetime (naive, no end), status, chief_complaint, expires_at, expired (computed), created_at, updated_at`. Statuses: `pending | approved | rejected | cancelled`; `expired` computed for stale pendings.
- **Doctor** (`DoctorRead`): `id, name, specialty, status (invited|active|inactive), …`.
- **AvailabilityWindow** (`availability_window_beta`): `doctor_id, kind ("recurring"|"one_off"), day_of_week (0–6, recurring), specific_date (one_off), start_time, end_time, status`.
- **Datetimes are naive** (no tz) — front and back share local interpretation (existing convention).

**Endpoints today:**
- `GET /clinics/{id}/doctors/{doctor_id}/appointments?from=&to=` → `list[AppointmentRead]`, **per-doctor only**, **confirmed only**.
- `GET /clinics/{id}/appointment-requests?date_from=&date_to=&status=&doctor_id=&…` → `RequestListPage` — **clinic-wide**, paginated.
- `GET /clinics/{id}/doctors?status=active` → active doctors.
- `GET /clinics/{id}/doctors/{doctor_id}/availability` → per-doctor windows.
- **No** clinic-wide appointments endpoint; **no** availability aggregation.

**Reusable:** the `request-row`/`request-status` colour language (pending→warning, confirmed→success, rejected→destructive); `card`/`icon`/`badge` ui primitives; `useDoctors`; the `app-shell` nav + `require_role` pattern.

---

## 4. Frontend design

### 4.1 Nav (`destinations.ts` + `app-shell.tsx`)
- Add `{ key: "today", labelKey: "nav.today", icon: "today", href: "/today" }`, placed in the schedule cluster (right after `clinic-schedules`). Label **"Today"** (concise for the rail); page title is the full "Today's Schedule" / selected date.
- **Role-gate it:** in `visibleDestinations`, `if (d.key === "today") return role === "owner" || role === "assistant";`. `activePrefixes` not needed (no sub-routes).

### 4.2 Route + responsive split (`src/app/today/page.tsx`)
- `AuthGate` › `useMe` (clinicId, role) › `AppShell` › `ListPageTemplate`/header. Guard: if role ∉ {owner, assistant}, render a "not available" message (defense-in-depth alongside the nav gate).
- **Header:** day stepper — `‹` / **selected-date title** / `Today` reset / `›` — plus the **cancelled strip** and (when >1 doctor) the **doctor-filter pills**.
- **Body:** at `lg`+ render `<DayGrid>`; below `lg` render `<DayTimeline>`. Single data hook feeds both (§4.5).

### 4.3 The cancelled/rejected/expired strip
- Collapsed pill: *"✕ {{count}} not on the schedule ›"* (cancelled + rejected appointments-requests + expired pendings for the day). Expands to a simple list (patient · doctor · status · time). Empty → strip hidden.
- **Today's data reality:** since appointments are only `confirmed`, the strip is **request-side** (rejected/cancelled/expired requests). When appointment-cancellation lands, cancelled appointments join it with no redesign.

### 4.4 `<DayGrid>` (desktop) — the proportional grid
- Columns = filtered active doctors (sticky headers: avatar + name). Left **sticky time gutter** with 30-min labels across `[working_window.start, working_window.end]`.
- **Each appointment** = an absolutely-positioned block: `top = (start − window.start) / 30min × ROW_H`, `height = (end − start) / 30min × ROW_H`. Rounded M3 card, left status-accent + tinted bg + status; patient name, time range, duration when >30m, doctor implicit (column). Composed from `ui/card`-style tokens — **no per-page CSS**.
- **Pending requests** have no `end_datetime` → render at the clinic **`default_slot_size_minutes`** length at their `start` (amber).
- **Off-hours** (cells outside a doctor's `windows`) optionally greyed — enhancement, not MVP-blocking.
- **Now line:** absolute horizontal rule at `(now − window.start)/30min × ROW_H`, only when viewing today and now ∈ window.
- **Overlap:** if two of a doctor's blocks overlap in time, split that doctor's column into side-by-side sub-columns (calendar standard). MVP: render no-overlap precisely; overlapping blocks must at least not render on top of each other illegibly (fall back to narrowed side-by-side) — covered by a test.
- Horizontal scroll past the visible doctor width; gutter + headers stay pinned.

### 4.5 `<DayTimeline>` (mobile) — fallback
- One vertical column: the day's items in time order (confirmed + pending), each a card with **time · patient · doctor · status**, grouped under hour headers (reuse the `doctor-appointments-tab` diary pattern). Now marker, cancelled strip, day stepper, tap-through identical. Proportional sizing is not required here (list semantics).

### 4.6 Data hook
- `useTodaySchedule(clinicId, date)` → TanStack Query on `qk.schedule(clinicId, date)` calling `GET /clinics/{id}/schedule?date=`. Returns `{ date, working_window, doctors, appointments, requests }`. Buckets: grid = confirmed appointments + `pending` requests; strip = `rejected|cancelled` requests + `expired` pendings.

### 4.7 Tap-through
- Appointment card → `/patients` focused on that patient (their appointments). Request card → `/requests` focused on that request. (Reuse existing routes; exact deep-link mechanism per the plan.)

---

## 5. Backend design (one new read endpoint — no migration)

`GET /api/v1/clinics/{clinic_id}/schedule?date=YYYY-MM-DD` — in `scheduling/router.py`, `require_role(MemberRole.owner, MemberRole.assistant)`.

**Response `ScheduleRead`:**
```
ScheduleRead:
  date: date
  working_window: { start: time, end: time }
  doctors: [ DoctorColumn ]          # active doctors, stable order (name)
  appointments: [ ScheduleAppt ]     # confirmed, for `date`, across all doctors
  requests: [ ScheduleReq ]          # ALL statuses, for `date`, across all doctors

DoctorColumn: { id, name, specialty, windows: [ { start_time, end_time } ] }   # this doctor's availability for `date`
ScheduleAppt: { id, doctor_id, patient_id, patient_name, start_datetime, end_datetime, status, chief_complaint }
ScheduleReq:  { id, doctor_id, patient_id, patient_name, doctor_name, start_datetime, status, expired, chief_complaint }
```

**Service aggregation (one transaction):**
1. Active doctors for the clinic → columns (ordered by name).
2. For each doctor, that day's **availability windows**: `kind=recurring & day_of_week == date.weekday()` **or** `kind=one_off & specific_date == date`, `status=active` → `windows`.
3. **Appointments**: `clinic_id`, `status="confirmed"`, `date(start_datetime) == date`.
4. **Requests**: `clinic_id`, `date(start_datetime) == date`, all statuses; compute `expired`.
5. **`working_window`** = `[ min(all windows.start_time), max(all windows.end_time) ]`. Fallbacks: if no windows, span of the day's appointments+requests (rounded to 30-min); if still empty, default **09:00–18:00**.

Notes: reuses the patient-name join already added in #40; no new tables/columns → **no migration**. One round-trip replaces N per-doctor calls.

---

## 6. Permission matrix (this phase)

| Capability | Owner | Doctor (non-owner) | Assistant | Notes |
|---|:--:|:--:|:--:|---|
| See **Today's Schedule** nav + view | ✓ | ✗ | ✓ | doctors use My Schedule |
| `GET /clinics/{id}/schedule` | ✓ | ✗ | ✓ | `require_role(owner, assistant)` |

---

## 7. i18n (Rule §16)

New keys in `en.json` + `hi.json` (no hardcoded strings; counts/dates interpolated):
- `nav.today` — "Today"
- `today.title` — "Today's Schedule"
- `today.todayPill` — "Today"
- `today.notCancelled` — "{{count}} not on the schedule" (strip)
- `today.empty` — "Nothing scheduled for this day."
- `today.now` — "now"
- `today.allDoctors` — "All ({{count}})"
- `today.filter` — "Filter"
- `today.duration.hours` / `today.duration.minutes` — "{{count}}h" / "{{count}}m"
- statuses reuse existing `requests.status.*`.

Dates/times via `toLocaleDateString`/`toLocaleTimeString` with `i18n.language` (existing pattern).

---

## 8. UX-standards mapping (`testing/ux-standards-runbook.md`)

**[AUTO]** asserted in the Playwright journey:
- **Recognition over recall (h6):** doctors are labeled columns/cards; statuses are explicit coloured badges, not colour-only — pair colour with the status word (also **WCAG 1.4.1**).
- **Visibility of status (h1):** confirmed/requested clearly labeled; the "now" line shows current time; the cancelled strip surfaces non-active items rather than hiding them.
- **Consistency (h4 / Rule 17.0):** AppShell + tokens + `ui` components; no per-page CSS; nav item like the others.
- **Nav correctness (`nav`):** tap appointment → `/patients` (that patient); tap request → `/requests`; Today nav → `/today`.
- **Target size (2.5.8 / Rule 17.4):** cards/blocks and pills ≥44px touch targets (small blocks remain tappable — enforce min height/hit area).
- **Both themes (17.3), keyboard/focus (2.4.7):** grid blocks are focusable links with `ring-ring`.
- **Efficiency (ISO 9241-11):** one screen replaces N per-doctor visits.
- **`neg`:** a non-owner **doctor** session sees **no** Today nav item and the route returns "not available"; the API returns **403**.

**[HEURISTIC]:** the grid reads as a calm premium calendar, not a dense ERP grid; horizontal scroll past ~4 doctors is discoverable.

---

## 9. Testing (P0, Rule §10.1)

**Backend (pytest):**
- `GET /schedule?date=`: owner & assistant → 200 with the four sections; **non-owner doctor → 403**.
- Aggregation: confirmed appointments + requests for the date are returned across multiple doctors; date filtering excludes other days; `working_window` = union of availability (and each fallback path).
- `expired` computed on stale pendings.

**Frontend (Playwright e2e, mocked):**
- Grid (desktop viewport): renders a column per doctor; a **2-hour** appointment block is ~4× a 30-min block's height (proportional); a pending request renders amber.
- **Now** line present for today, **absent** when stepped to another day.
- Day stepper: `›` advances the date + refetches; **Today** resets.
- Doctor-filter pills narrow the visible columns.
- Cancelled strip shows rejected/cancelled/expired count; expands.
- **Mobile viewport:** the timeline fallback renders (no grid).
- Tap an appointment → `/patients`; tap a request → `/requests`.
- **Access:** owner/assistant see the nav item + view; **non-owner doctor does not** (nav absent; route blocked).
- Overlap: two overlapping blocks in one doctor column don't render illegibly on top of each other.

---

## 10. Out of scope / future

- **Queue** (walk-ins + waitlist + overflow) — docs **#158**, designed next.
- **Inline actions** (approve/reject/arrived from the card) — view + tap-through only this phase.
- **Appointment lifecycle states** (arrived/no-show/completed/cancelled) — not in the backend; grid adapts when they exist.
- **Overlap sub-columns** — precise side-by-side rendering is a fast-follow (MVP: legible, not corrupt).
- **Full date picker / week view** — only the day stepper now.
- **Per-doctor off-hours greying** — enhancement.

---

## 11. Verification checklist (release gate)

- [ ] Owner + assistant see "Today" nav + `/today`; non-owner doctor does not; API 403 for doctor.
- [ ] Desktop grid: doctor columns, 30-min axis over the working window, proportional blocks (2h spans 4 rows), now line (today only), filter pills, horizontal scroll + sticky gutter/headers.
- [ ] Mobile: timeline fallback renders the same data.
- [ ] Cancelled/rejected/expired strip works; grid shows confirmed + pending only.
- [ ] Day stepper (prev/next/today) refetches; title = selected date.
- [ ] Tap appointment → patient; tap request → Requests.
- [ ] New `GET /schedule` returns doctors+appointments+requests+working_window; **no migration**.
- [ ] All new strings en + hi; both themes; a11y (focus, ≥44px, colour+label).
- [ ] FE `tsc` + eslint + Playwright green; BE pytest + ruff green.

---

## 12. Docs to update
- This spec → implementation **plan** (`docs/plans/2026-06-27-today-schedule-plan.md`).
- Note in Golden Rules §18 (navigation) that **Today's Schedule** joins My Schedule / Doctors Schedules as a distinct schedule surface.
