# Doctors Schedules — Redesign Spec (Clinic Schedules → doctor cards + Appointments tab)

**Status:** Approved in brainstorm (2026-06-26), interactive mockup signed off on :8753. Beta finding **F** from Sayali. Consolidates the existing buried `/doctors/[id]` availability page. Register Design System (Rule 17.0), i18n-first (en/hi), both themes, a11y. **Frontend-led**, one small backend enrich.

**Type:** Replace the confusing **Clinic Schedules** doctor-picker with **doctor cards → a tabbed doctor page (`Availability | Appointments`)**, and surface a doctor's upcoming appointments (which has no home today).

---

## 1. Goal

*"An owner (or permitted assistant) opens **Doctors Schedules**, sees a card per doctor, taps one, and immediately sees that doctor's **availability** and their **upcoming appointments** — colour-coded, at a glance."*

Today this is broken two ways: (a) Clinic Schedules uses a clumsy *"Viewing: choose doctor / change"* picker; (b) a doctor's appointments are **nowhere viewable**, and their availability is buried four clicks deep (Doctors → Team → click → drawer → "Manage availability" → `/doctors/[id]`).

---

## 2. Scope decisions (locked in brainstorm 2026-06-26)

1. **Consolidate onto `/doctors/[id]`** — do **not** build a second doctor surface. The existing doctor page becomes the **shared schedule home**, gaining page-level tabs.
2. **Rename the nav: "Clinic Schedules" → "Doctors Schedules".**
3. **Doctors Schedules = a grid of doctor cards** (replacing `DoctorPicker`). A card → navigates to `/doctors/[id]`.
4. **`/doctors/[id]` gains page-level tabs: `Availability` (existing view, unchanged) + `Appointments` (new).**
5. **Appointments tab** = the doctor's appointments for the **next 7 days**, grouped by day, as **request-style rows with status colours** (the `request-row` visual language).
6. **Access (tightened):** **Owner always; Assistant only if `allow_staff_manage_availability`** (Settings → Scheduling, "Allow staff to manage availability"). Today's nav shows Clinic Schedules to *every* assistant — this restricts it.
7. **Avatar (placeholder until real avatars):** coloured **initials** circle, a tint assigned **by position** in the doctor list (distinct per doctor), from our **existing semantic tokens** only.
8. **One small backend:** the per-doctor appointments endpoint already exists but returns `patient_id` only — add **`patient_name`** so rows are human-readable. **No migration.**

---

## 3. What exists today (verified, 2026-06-26)

- **Clinic Schedules** (`/clinic-schedules`): `DoctorPicker` (the "Viewing / change" UI) → `DoctorScheduleView` → `SlotViewer`. Owner/assistant nav-gated (no setting check).
- **`/doctors/[id]`**: `PageHeader` (name + door-6 Book action) + `AvailabilitySummaryCard` + `EditAvailabilityModal`. **Availability only; no appointments; not page-level tabbed.** Reached via the Team **member-profile drawer** → "Manage availability" (`member-profile-drawer.tsx` → `router.push('/doctors/{id}')`).
- **Appointments endpoint EXISTS:** `GET /api/v1/clinics/{cid}/doctors/{did}/appointments?from=&to=` → `list[AppointmentRead]` (`scheduling/router.py:273`; FE `listAppointments`). `AppointmentRead` has `patient_id, doctor_id, start_datetime, end_datetime, status, chief_complaint` — **no `patient_name`.**
- **Reusable:** `Tabs` primitive; `initials()` (helper); `Badge` variants (success/warning/destructive/secondary); the `request-row` status-colour language.

---

## 4. Doctors Schedules — the cards (`/clinic-schedules`, renamed)

- Page title **"Doctors Schedules"** + subtitle. A **responsive grid** (1 / 2 / 3 cols) of **doctor cards**.
- **Each card** (M3, our tokens, compose `components/ui/card`): coloured **initials avatar** + **doctor name** + **specialty** + a trailing chevron; whole card is the tap target → `/doctors/[id]`.
- **Avatar tint:** `tintFor(index)` cycling a 6-entry palette built from existing tokens (`bg-primary-container`, `bg-success/15`, `bg-tertiary-container`, `bg-info/15`, `bg-warning/20`, `bg-destructive/15`) — distinct per doctor by position; the only colour decision, fully token-based.
- **`DoctorPicker` is removed** (no remaining consumer after this).
- **Empty state:** if the clinic has no doctors, a calm "No doctors yet" with a link to invite (owner).

## 5. `/doctors/[id]` — tabbed (`Availability | Appointments`)

- Keep the existing **header** (avatar + name + specialty + the **Book appointment** action — owner/assistant).
- Wrap the body in **`TabsRoot`** with two page-level tabs (default **Appointments**, so the new value is visible):
  - **`Availability`** — the **existing** `AvailabilitySummaryCard` + `EditAvailabilityModal`, **unchanged** (same edit-hours / time-off behaviour and permissions).
  - **`Appointments`** — new `DoctorAppointmentsTab` (§6).

## 6. Appointments tab — `DoctorAppointmentsTab`

- Data: `useDoctorAppointments(clinicId, doctorId, from=today, to=today+6d)` over the existing `listAppointments` endpoint (§8 adds `patient_name`).
- **Grouped by day** (Today / Tomorrow / weekday-date), each a small section.
- **Each row** (request-style): **time** · **patient name** + **reason** (or "—") · a **status `Badge`** + a soft row tint by status:
  - `confirmed` / `completed` → **success** (green); `arrived` → **warning** (amber); `no_show` → **destructive** (red); `cancelled` → **secondary** (muted).
- **Empty state:** "No appointments in the next 7 days."
- **Read-only in V1** (no inline actions) — day-of actions (#139) are out of scope here.

## 7. Access / role-gating

- **Nav "Doctors Schedules" visibility:** `role === "owner" || (role === "assistant" && clinicSettings.allow_staff_manage_availability)`. *(Owner-doctors see it as owners; non-owner doctors use **My Schedule**, not this.)*
- The page itself enforces the same (defence in depth) — a non-permitted user hitting `/doctors/[id]` keeps today's behaviour for the Availability tab's edit gating (`canEdit`).
- **Booking doors reconciled:** old door 2 (Clinic-Schedules slot) now lives on the **Availability tab** (slot → `BookAppointmentFlow`); old door 3 (Clinic-Schedules header book) **merges into door 6** (the `/doctors/[id]` header Book action, doctor pre-filled). My Schedule (door 1), Patient (door 4), Requests (door 5) unchanged.

## 8. Backend (one small enrich — no migration)

- **Add `patient_name` to the per-doctor appointments response.** Extend `AppointmentRead` (or a dedicated read model for this endpoint) with `patient_name: str` by joining `patient_beta` in `list_appointments`. Rows then show "Asha Rao", not a UUID.
- **Tests:** the endpoint returns `patient_name`; role/clinic boundary unchanged (existing 403 tests hold).

## 9. Frontend components

- `src/app/clinic-schedules/page.tsx` → renders **`DoctorsScheduleGrid`** (cards). Rename nav label key. (Route path can stay `/clinic-schedules` to avoid churn; only the **label** changes — confirm in plan.)
- `src/features/scheduling/doctors-schedule-grid.tsx` (new) — the cards grid; `tintFor` avatar palette; links to `/doctors/[id]`.
- `src/app/doctors/[id]/page.tsx` — wrap body in `TabsRoot`; mount `AvailabilitySummaryCard` under Availability and `DoctorAppointmentsTab` under Appointments.
- `src/features/scheduling/doctor-appointments-tab.tsx` (new) — grouped, colour-coded rows.
- `src/features/scheduling/hooks.ts` — `useDoctorAppointments`.
- Remove `doctor-picker.tsx` (dead after the grid).
- `member-profile-drawer.tsx` — "Manage availability" still points at `/doctors/[id]` (now the tabbed page) — no change needed, but verify the label still fits (it lands on Availability).
- i18n `doctorsSchedules.*` / `doctorAppointments.*` (en + hi parity); status labels reuse existing keys where possible.

## 10. System rules

- **Rule 17.0** — compose `components/ui/*` (Card, Tabs, Badge, Button, Icon); semantic tokens only; **no raw colours** (avatar tints are token-based); both themes; mobile-first (cards stack; rows wrap gracefully); WCAG AA (status by **badge text + colour**, never colour-only; ≥44px tap targets; visible focus).
- **i18n-first** en+hi parity (gated by `tests/e2e/i18n.spec.ts`); plain language; friendly day/time via `Intl`.
- **Deterministic** — no AI.

## 11. Test plan (Playwright; FE has no Vitest)

- **e2e (mocked):**
  - Owner → Doctors Schedules shows a card per doctor (distinct avatars); clicking a card lands on `/doctors/[id]`.
  - `/doctors/[id]` shows **Availability + Appointments** tabs; Appointments lists the doctor's next-7-day rows with the right status colours + patient names.
  - **Access:** assistant **without** `allow_staff_manage_availability` does **not** see the Doctors Schedules nav; **with** it, they do.
  - Empty states (no doctors; no appointments).
- **Backend (pytest):** the appointments endpoint returns `patient_name`; clinic-boundary 403 unchanged.

## 12. Out of scope / deferred

- Real **avatar photos** (this ships the coloured-initials placeholder).
- **Day-of actions** on appointment rows (#139) — Appointments tab is read-only here.
- Changing the `/clinic-schedules` **route path** (only the nav *label* changes in V1, to avoid link churn) — revisit if desired.

## 13. Acceptance-criteria mapping

- Doctor cards (name + specialty + coloured-initials avatar), our design language → §4. ✅
- Click a doctor → **Availability + Appointments** tabs → §5. ✅
- Appointments = next 7 days, request-style rows, status colours → §6. ✅
- Remove "Viewing: choose doctor / change" → §4 (DoctorPicker removed). ✅
- Rename nav → Doctors Schedules → §2.2. ✅
- Owner + (assistant if manage-schedules setting) only → §7. ✅
- Backend: `patient_name` enrich (no migration) → §8. ✅
- M3 / i18n en+hi / both themes / a11y → §10. ✅
