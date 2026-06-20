# Patients Page Redesign — Design Spec (#80, first slice)

**Status:** Approved (brainstorm + visual-companion + frontend-design 2026-06-20; ref `Mockups/patients_page.png`). First slice of the #80 design-language consistency pass.
**Type:** Frontend-only composition redesign — compose the existing shared components (Card/Table/PageHeader/CardSeparator + palette) so Patients matches the Settings (#65) language. **No new CSS, no new tokens, no backend** (uses the existing list endpoint).

## 1. Goal
Replace the current flat master-detail Patients page with the carded, sub-panel + table layout matching `patients_page.png` and the Settings look — cohesive, premium. Card-ify the patient detail too so the whole flow is consistent.

## 2. Layout (matches the approved render)
Within `AppShell`, the Patients route renders a two-region content area:

**Left sub-panel** (`Card`, persistent on desktop):
- "Patients" heading.
- **New patient** button — **outlined** style (`Button variant="outlined"`, full-width, `person_add` icon + label). Opens the existing `AddPatientDialog` flow. (NOT solid purple; NOT duplicated in the header.)
- **Search** input (search by name or phone).
- **Sub-nav** (bordered `Card` rows, Settings pattern): **All Patients** (active) and **Recent Patients**, each with a count badge; active row uses the softer `bg-primary-container/55` pill (matching Settings sub-nav). "Recent" = patients `created_at` within the last 30 days (client-side).

**Main content:**
- **PageHeader:** title = the active segment ("All Patients" / "Recent Patients"), subtitle "Manage and view all your clinic patients". **No top-right New patient.**
- **Carded table** (`Card` + the `Table` primitive from `components/ui/table.tsx`): columns
  - **Patient** — coloured avatar initials circle + name.
  - **Phone** — `call` icon + number.
  - **Age** — `{age} yrs`, or `—` when null.
  - **Created on** — friendly date (e.g. "10 May 2025").
  - **⋮** row overflow menu — Edit / Delete (reuse existing mutations).
  - Soft hairline row dividers (`border-border`), row hover (`bg-background`/`bg-muted/40`), comfy padding.
- **Pagination footer** inside the card: "Showing X–Y of N" + Prev/Next (and page chips). Client-side (see §3).
- **Empty state** (no patients): a calm centered empty-state (not a heavy grey block).

**Patient detail (card-ified):** selecting a row shows the patient detail in the content area (full width, with a "← All Patients" back affordance; mobile already list→detail). Detail = `Card`(s) with header + `CardSeparator`: an **Overview** card (Phone / Age / Referral source / Medical conditions / Notes as label-value rows), an **Appointments** card with a **soft** empty-state ("No appointments yet…") replacing the current heavy `bg-muted` block, and Edit / Delete actions. Success card (#61) on edit/delete as today.

## 3. Data & behavior (V1, frontend-only)
- **Single fetch:** load patients via the existing `GET /clinics/{id}/patients?limit=200` (endpoint max), then do **search, Recent filter, segment counts, and pagination client-side**. Counts = lengths of the filtered sets; pagination = 10/page over the active segment.
- **Search:** client-side substring match on name/phone over the loaded set (V1). (Server trigram `q` search retained as a deferred enhancement.)
- **Cap note:** this V1 handles up to 200 patients well (fine for current clinics). **True server-side pagination + total count for >200 patients is a deferred follow-up** (needs a count; see §5).
- Reuse: `AddPatientDialog` (New patient), `useUpdatePatient`/`useDeletePatient`, the patient detail edit/delete + duplicate-check flow — unchanged.

## 4. Components
- Reuse `Card`/`CardHeader`/`CardContent`/`CardSeparator`, `PageHeader`, `PageContainer`, `Table`/`TableHeader`/`TableRow`/`TableCell` (`components/ui/table.tsx`), `Button` (outlined), `Icon`, the success-card hook. Coloured avatar = initials on a tinted circle (a small deterministic colour pick from the name — pure + unit-testable).
- New small pieces in `src/features/patients/`: a `patients-table.tsx`, a `patients-sidepanel.tsx` (New patient + search + sub-nav), and a pure helper (`recent` filter + pagination slice + avatar-colour) with a unit test. The page composes them; the detail view (`patient-detail.tsx`) is card-ified.

## 5. Scope guards / deferred (logged on #80)
- **Deferred (need data/backend):** Last Visit column + PT-#### human IDs (appointment join / ID scheme); **Inactive** segment (needs patient `status`); Filter dropdown; Import/Export; true server-side pagination + total count (>200 patients) + server trigram search.
- **In V1:** everything in §2 with All + Recent segments, client-side over ≤200.

## 6. Quality
- Rule 17.0 (semantic tokens, compose `components/ui/*`, no per-page CSS); i18n en/hi parity for new strings; both themes; mobile-first (sub-panel collapses / list→detail); WCAG AA; `tsc --noEmit` + `npm run build` clean; pure-logic unit test (recent/pagination/avatar-colour) via the Playwright runner.
