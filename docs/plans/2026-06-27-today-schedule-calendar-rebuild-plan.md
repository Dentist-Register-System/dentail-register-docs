# Today's Schedule — Calendar-Library Rebuild Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the unusable hand-rolled day-grid with a FullCalendar `timeGrid` day view — doctor = colour (legend), diary-style event cards, overlap side-by-side, light + dark — plus a colour-coded mobile agenda, matching the approved mockup exactly.

**Architecture:** FE-only. FullCalendar (MIT) owns time-layout/overlap/now-line (kills the alignment-bug class); we supply custom `eventContent` (the diary card) + theme it with our tokens. A token-based doctor-colour palette assigns colours by stable doctor order. The `/schedule` endpoint, nav, day stepper, doctor filter, cancelled strip, tap-through, and empty frame are reused.

**Tech Stack:** Next.js 16 App Router, React 19, FullCalendar v6 (`@fullcalendar/react` + `core` + `timegrid`, MIT), TanStack Query, react-i18next, Tailwind v4 tokens, Playwright e2e (mocked).

**Spec:** `docs/specs/2026-06-27-today-schedule-calendar-rebuild-design.md`. **Approved mockup (fidelity reference):** `register_workspace/.superpowers/brainstorm/61922-1782536711/content/day-diary-lightdark.html` (and `…/day-diary-compare-v4.html`).

## Global Constraints

- **Exact mockup fidelity.** Event card = **patient (bold) · chief-complaint (muted, truncate) · a bottom row with [● dot + doctor name] and [status badge]**, left-accent + 12% tint in the doctor's colour; requests get a dashed border. Legend + agenda use the **same ● dot + name**. Match `day-diary-lightdark.html`.
- **Doctor = colour, status = badge.** Grid + agenda show **confirmed appointments + non-expired pending**; expired/cancelled/rejected stay in the cancelled strip. Never colour-only (WCAG 1.4.1) — colour is always paired with the doctor name.
- **Light + dark (Rule 17.3):** dark = real dark surfaces (tokens already flip), doctor colours brightened. All via tokens; **no per-page one-off colours** — doctor colours come from `--doctor-N` tokens, applied via inline `var(--doctor-N)` (dynamic per doctor is allowed; it is not a static style literal).
- **No alignment hand-rolling.** FullCalendar computes slot positions/overlap/now-line. We do not position events by px.
- **a11y:** event/agenda tap targets ≥44px (slot height 44px); focus-visible; AA contrast both themes.
- **i18n:** reuse `today.*` + `requests.status.*`; add keys only if new copy appears, in en **and** hi. No hardcoded strings; verify no FullCalendar default English leaks (we set `headerToolbar={false}`, `dayHeaders={false}`).
- **Ports:** dev FE `3000` only (never 3001/8001/5434). **TDD:** Playwright e2e (mocked). FE has no unit runner — pure helpers are covered by e2e. **No new dep beyond FullCalendar; pin versions; verify MIT + transitive licenses.** BE untouched; no migration.

---

### Task 1: Doctor-colour palette tokens + `doctorColorIndex` helper

**Files:**
- Modify: `src/app/globals.css` (add `--doctor-1..8` to the `:root` light block and the `.dark` block)
- Create: `src/features/today/doctor-colors.ts`

**Interfaces:**
- Produces: CSS vars `--doctor-1 … --doctor-8` (light + dark); `doctorColorIndex(doctorId: string, doctors: { id: string }[]): number` → `1..8` stable by position (cycles past 8). Consumers build the CSS value `` `var(--doctor-${idx})` ``.

- [ ] **Step 1: Add the palette tokens to `globals.css`**

In the `:root { … }` block (light), after the `--info* ` state colors, add:

```css
  /* ── Doctor categorical palette (light) — AA on card/bg ── */
  --doctor-1: #16A34A; --doctor-2: #2563EB; --doctor-3: #7C3AED; --doctor-4: #B45309;
  --doctor-5: #0D9488; --doctor-6: #E11D48; --doctor-7: #0891B2; --doctor-8: #A21CAF;
```

In the `.dark { … }` block, after its `--info*` colors, add (brightened for dark surfaces):

```css
  /* ── Doctor categorical palette (dark) — brightened for contrast ── */
  --doctor-1: #4ADE80; --doctor-2: #7AA2FF; --doctor-3: #C4A6FF; --doctor-4: #FCD34D;
  --doctor-5: #2DD4BF; --doctor-6: #FB7185; --doctor-7: #38BDF8; --doctor-8: #E879F9;
```

- [ ] **Step 2: Create the helper**

Create `src/features/today/doctor-colors.ts`:

```typescript
/** Number of distinct doctor colours defined in globals.css (--doctor-1..N). */
export const DOCTOR_PALETTE_SIZE = 8;

/** Stable 1..N colour index for a doctor, by position in the clinic's doctor list (cycles past N). */
export function doctorColorIndex(doctorId: string, doctors: { id: string }[]): number {
  const pos = doctors.findIndex((d) => d.id === doctorId);
  const i = pos < 0 ? 0 : pos;
  return (i % DOCTOR_PALETTE_SIZE) + 1;
}

/** CSS value for a doctor's colour, e.g. "var(--doctor-3)". */
export function doctorColorVar(doctorId: string, doctors: { id: string }[]): string {
  return `var(--doctor-${doctorColorIndex(doctorId, doctors)})`;
}
```

- [ ] **Step 3: Verify**

Run: `cd dentist-registry-frontend && npx tsc --noEmit && npx eslint src/features/today/doctor-colors.ts`
Run: `grep -c -- '--doctor-1:' src/app/globals.css` → expect `2` (one in `:root`, one in `.dark`).
Expected: tsc + eslint clean; grep prints `2`. (The helper is exercised by Task 3's e2e.)

- [ ] **Step 4: Commit**

```bash
git add src/app/globals.css src/features/today/doctor-colors.ts
git commit -m "feat(today): doctor-colour palette tokens (light+dark) + colour-index helper"
```

---

### Task 2: Add + license-vet FullCalendar

**Files:**
- Modify: `package.json` / `package-lock.json` (deps)
- Modify: `dentail-register-docs`-tracked? No — FE README + tech-stack are docs-repo; note them in Task 5. Here just the dep + a license check artifact.

**Interfaces:**
- Produces: `@fullcalendar/react`, `@fullcalendar/core`, `@fullcalendar/timegrid` installed (pinned, MIT-verified) and importable.

- [ ] **Step 1: Install pinned versions**

Run (from `dentist-registry-frontend`):
```bash
npm install @fullcalendar/react@^6.1.19 @fullcalendar/core@^6.1.19 @fullcalendar/timegrid@^6.1.19
```
(Use the matching latest 6.x the registry resolves; keep all three on the **same** 6.x version — FullCalendar requires version-matched packages.)

- [ ] **Step 2: Verify licenses are permissive (hard gate)**

Run:
```bash
for p in @fullcalendar/core @fullcalendar/react @fullcalendar/timegrid @fullcalendar/daygrid; do
  node -e "try{console.log('$p', require('$p/package.json').license)}catch(e){console.log('$p (not installed)')}"
done
npm ls @fullcalendar/core @fullcalendar/react @fullcalendar/timegrid
```
Expected: each prints `MIT`. **If any package (incl. a transitive `@fullcalendar/*` like `daygrid`/`common`) reports anything other than MIT/Apache-2.0/BSD/ISC, STOP and report BLOCKED** (do not proceed — Golden Rule §3.1 / open-source-license-vetting). FullCalendar premium packages (`@fullcalendar/resource*`, `@fullcalendar/timeline`) must **not** appear in the tree.

- [ ] **Step 3: Smoke-import to confirm it builds (v6 auto-injects CSS — no manual import)**

Run: `npx tsc --noEmit` (after Task 3 adds the import) — for now confirm install:
Run: `node -e "require('@fullcalendar/timegrid'); console.log('ok')"`
Expected: `ok`.

- [ ] **Step 4: Commit**

```bash
git add package.json package-lock.json
git commit -m "build(today): add FullCalendar v6 (MIT) — react/core/timegrid"
```

---

### Task 3: `<DayCalendar>` (FullCalendar desktop) + theming + wire-in; remove hand-rolled grid

**Files:**
- Create: `src/features/today/day-calendar.tsx`
- Modify: `src/app/globals.css` (FullCalendar theme block, scoped to `.today-cal`)
- Modify: `src/app/today/page.tsx` (render `<DayCalendar>` in the `lg` block instead of `<DayGrid>`)
- Delete: `src/features/today/day-grid.tsx`
- Modify/Replace: `tests/e2e/today-grid.spec.ts` (re-point to the FullCalendar render)

**Interfaces:**
- Consumes: `Schedule` (`@/features/today/api`), `useClinicSettings`, `doctorColorVar`/`doctorColorIndex` (Task 1).
- Produces: `<DayCalendar schedule date clinicId doctorIds />`; each event renders a card with `data-testid="appt-{id}"` / `data-testid="req-{id}"`; container `data-testid="today-grid"`.

- [ ] **Step 1: Write/replace the failing e2e**

Replace `tests/e2e/today-grid.spec.ts` with (uses the existing `_auth` helpers; FullCalendar renders our card testids):

```typescript
import { test, expect } from "@playwright/test";
import { CLINIC_ID, installAuth, meWithRole, gotoAuthed } from "./_auth";

function todayAt(hhmm: string) {
  const d = new Date();
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}T${hhmm}:00`;
}
const SCHED = {
  date: todayAt("00:00").slice(0, 10),
  working_window: { start: "09:00:00", end: "14:00:00" },
  doctors: [
    { id: "d1", name: "Dr. Sayali", specialty: null, windows: [] },
    { id: "d2", name: "Dr. Mehta", specialty: null, windows: [] },
  ],
  appointments: [
    { id: "a1", doctor_id: "d1", patient_id: "p1", patient_name: "Vinod Kambli", start_datetime: todayAt("10:00"), end_datetime: todayAt("12:00"), status: "confirmed", chief_complaint: "Follow up" },
    { id: "a2", doctor_id: "d1", patient_id: "p2", patient_name: "ABC", start_datetime: todayAt("10:30"), end_datetime: todayAt("11:00"), status: "confirmed", chief_complaint: "Bleeding gums" },
    { id: "a3", doctor_id: "d2", patient_id: "p3", patient_name: "Neha", start_datetime: todayAt("10:30"), end_datetime: todayAt("11:00"), status: "confirmed", chief_complaint: "Checkup" },
  ],
  requests: [
    { id: "r1", doctor_id: "d2", patient_id: "p4", patient_name: "Tara", doctor_name: "Dr. Mehta", start_datetime: todayAt("12:30"), status: "pending", expired: false, chief_complaint: "Consult" },
    { id: "rexp", doctor_id: "d1", patient_id: "p5", patient_name: "Old Req", doctor_name: "Dr. Sayali", start_datetime: todayAt("11:30"), status: "pending", expired: true, chief_complaint: null },
  ],
};
async function stub(page: import("@playwright/test").Page, body: object) {
  await page.route(`**/api/v1/clinics/${CLINIC_ID}/schedule*`, (r) =>
    r.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(body) }));
  await page.route(`**/api/v1/clinics/${CLINIC_ID}/settings`, (r) =>
    r.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify({ default_slot_size_minutes: 30, allow_multiple_bookings_per_slot: true, max_bookings_per_slot: 4, appointment_request_expiry_minutes: null, post_confirmation_hook_delay_minutes: 0, reminders_enabled: false, whatsapp_enabled: false, google_calendar_enabled: false, scheduling_workflow: "doctor_approval", allow_staff_approval: false, allow_staff_manage_availability: false }) }));
}

test("calendar renders doctor-coloured events; 2h spans ~4× a 30-min; parallel side-by-side", async ({ page }) => {
  await installAuth(page, { me: meWithRole("owner") });
  await stub(page, SCHED);
  await gotoAuthed(page, "/today", { ready: page.getByTestId("today-grid") });
  await expect(page.getByTestId("appt-a1")).toBeVisible();
  const a1 = await page.getByTestId("appt-a1").boundingBox();   // 2h
  const a2 = await page.getByTestId("appt-a2").boundingBox();   // 30m
  expect(a1!.height).toBeGreaterThan(a2!.height * 3);
  // a2 (Dr. Sayali) and a3 (Dr. Mehta) overlap 10:30–11:00 → side-by-side (different x)
  const a3 = await page.getByTestId("appt-a3").boundingBox();
  expect(Math.abs(a2!.x - a3!.x)).toBeGreaterThan(20);
  // doctor name shown in card
  await expect(page.getByTestId("appt-a1")).toContainText("Dr. Sayali");
});

test("expired pending NOT shown; live pending shown; now-line today only", async ({ page }) => {
  await installAuth(page, { me: meWithRole("owner") });
  await stub(page, SCHED);
  await gotoAuthed(page, "/today", { ready: page.getByTestId("today-grid") });
  await expect(page.getByTestId("req-r1")).toBeVisible();
  await expect(page.getByTestId("req-rexp")).toHaveCount(0);
  await expect(page.locator(".fc-timegrid-now-indicator-line")).toBeVisible(); // today
});

test("tap appointment → /patients; tap request → /requests", async ({ page }) => {
  await installAuth(page, { me: meWithRole("owner") });
  await stub(page, SCHED);
  await gotoAuthed(page, "/today", { ready: page.getByTestId("today-grid") });
  await page.getByTestId("appt-a1").click();
  await expect(page).toHaveURL(/\/patients$/);
  await page.goBack();
  await page.getByTestId("req-r1").click();
  await expect(page).toHaveURL(/\/requests$/);
});
```

- [ ] **Step 2: Run to verify it fails**

Run: `npm run test:e2e -- today-grid`
Expected: FAIL (DayCalendar/FullCalendar not present yet).

- [ ] **Step 3: Create `<DayCalendar>`**

Create `src/features/today/day-calendar.tsx`:

```typescript
"use client";

import { useRouter } from "next/navigation";
import { useTranslation } from "react-i18next";
import FullCalendar from "@fullcalendar/react";
import timeGridPlugin from "@fullcalendar/timegrid";

import { Badge } from "@/components/ui/badge";
import { useClinicSettings } from "@/features/clinic/hooks";
import { doctorColorVar } from "@/features/today/doctor-colors";
import type { Schedule } from "@/features/today/api";

function addMinutes(iso: string, mins: number) {
  const d = new Date(iso);
  d.setMinutes(d.getMinutes() + mins);
  return d.toISOString();
}

export function DayCalendar({
  schedule,
  date,
  clinicId,
  doctorIds,
}: {
  schedule: Schedule;
  date: string;
  clinicId: string;
  doctorIds?: string[];
}) {
  const { t } = useTranslation();
  const router = useRouter();
  const settings = useClinicSettings(clinicId);
  const defaultLen = settings.data?.default_slot_size_minutes ?? 30;
  const inFilter = (id: string) => !doctorIds || doctorIds.length === 0 || doctorIds.includes(id);
  const docName = new Map(schedule.doctors.map((d) => [d.id, d.name]));

  const events = [
    ...schedule.appointments
      .filter((a) => inFilter(a.doctor_id))
      .map((a) => ({
        id: a.id,
        start: a.start_datetime,
        end: a.end_datetime,
        extendedProps: {
          kind: "appt",
          patient: a.patient_name,
          complaint: a.chief_complaint,
          doctorId: a.doctor_id,
          doctorName: docName.get(a.doctor_id) ?? "",
          status: a.status,
        },
      })),
    ...schedule.requests
      .filter((r) => r.status === "pending" && !r.expired && inFilter(r.doctor_id))
      .map((r) => ({
        id: r.id,
        start: r.start_datetime,
        end: addMinutes(r.start_datetime, defaultLen),
        extendedProps: {
          kind: "req",
          patient: r.patient_name,
          complaint: r.chief_complaint,
          doctorId: r.doctor_id,
          doctorName: r.doctor_name,
          status: r.status,
        },
      })),
  ];

  return (
    <div className="today-cal rounded-xl border border-border bg-card p-1" data-testid="today-grid">
      <FullCalendar
        key={date}
        plugins={[timeGridPlugin]}
        initialView="timeGridDay"
        initialDate={date}
        headerToolbar={false}
        dayHeaders={false}
        allDaySlot={false}
        nowIndicator
        slotMinTime={schedule.working_window.start}
        slotMaxTime={schedule.working_window.end}
        slotDuration="00:30:00"
        slotLabelInterval="00:30:00"
        expandRows
        height="auto"
        eventOverlap
        events={events}
        eventClick={(info) => {
          info.jsEvent.preventDefault();
          router.push((info.event.extendedProps as { kind: string }).kind === "appt" ? "/patients" : "/requests");
        }}
        eventContent={(arg) => {
          const p = arg.event.extendedProps as {
            kind: string; patient: string; complaint: string | null; doctorId: string; doctorName: string; status: string;
          };
          const dc = doctorColorVar(p.doctorId, schedule.doctors);
          const isReq = p.kind === "req";
          return (
            <div
              data-testid={`${isReq ? "req" : "appt"}-${arg.event.id}`}
              className="flex h-full flex-col overflow-hidden rounded-lg border border-l-4 border-border px-2 py-1"
              style={{
                borderLeftColor: dc,
                background: `color-mix(in srgb, ${dc} 12%, transparent)`,
                ...(isReq ? { borderStyle: "dashed" } : {}),
              }}
            >
              <span className="block truncate text-xs font-semibold text-foreground">{p.patient}</span>
              {p.complaint ? (
                <span className="block truncate text-[10px] text-muted-foreground">{p.complaint}</span>
              ) : null}
              <div className="mt-auto flex items-center justify-between gap-1 pt-0.5">
                <span className="inline-flex min-w-0 items-center gap-1 text-[9.5px] font-semibold text-foreground">
                  <span className="size-2 shrink-0 rounded-full" style={{ background: dc }} aria-hidden />
                  <span className="truncate">{p.doctorName}</span>
                </span>
                <Badge variant={isReq ? "warning" : "success"} className="shrink-0 px-1.5 py-0 text-[9px]">
                  {t(`requests.status.${p.status}`)}
                </Badge>
              </div>
            </div>
          );
        }}
      />
    </div>
  );
}
```

- [ ] **Step 4: Theme FullCalendar with our tokens (`globals.css`)**

Append a scoped block (after the existing layers; this themes the lib, not a per-page one-off):

```css
/* ── Today's Schedule calendar — FullCalendar themed to design tokens ── */
.today-cal .fc {
  --fc-border-color: var(--border);
  --fc-page-bg-color: var(--card);
  --fc-neutral-bg-color: var(--card);
  --fc-now-indicator-color: var(--info);
  --fc-today-bg-color: transparent;
  font-family: inherit;
}
.today-cal .fc .fc-timegrid-slot { height: 2.75rem; }              /* 44px slot → ≥44px touch target */
.today-cal .fc .fc-timegrid-slot-label, .today-cal .fc .fc-timegrid-axis-cushion { color: var(--muted-foreground); font-size: 10px; }
.today-cal .fc .fc-event, .today-cal .fc .fc-timegrid-event { background: transparent; border: none; box-shadow: none; }
.today-cal .fc .fc-timegrid-event .fc-event-main { padding: 0; color: inherit; }
.today-cal .fc-theme-standard td, .today-cal .fc-theme-standard th { border-color: var(--border); }
.today-cal .fc .fc-timegrid-now-indicator-line { border-color: var(--info); }
```

- [ ] **Step 5: Wire into the page; delete the old grid**

In `src/app/today/page.tsx`: replace the import `import { DayGrid } from "@/features/today/day-grid";` with `import { DayCalendar } from "@/features/today/day-calendar";`, and replace the desktop block:

```typescript
              <div className="hidden lg:block">
                <DayCalendar schedule={q.data} date={date} clinicId={clinicId} doctorIds={selected} />
              </div>
```

(Leave the `<DayTimeline …>` mobile block for Task 4.) Then delete the file:

```bash
git rm src/features/today/day-grid.tsx
```

- [ ] **Step 6: Run e2e + typecheck + lint**

Run: `npm run test:e2e -- today-grid && npx tsc --noEmit && npx eslint src/features/today/day-calendar.tsx src/app/today/page.tsx`
Expected: all three `today-grid` tests PASS; tsc + eslint clean.

- [ ] **Step 7: Commit**

```bash
git add src/features/today/day-calendar.tsx src/app/globals.css src/app/today/page.tsx tests/e2e/today-grid.spec.ts
git rm src/features/today/day-grid.tsx
git commit -m "feat(today): FullCalendar timeGrid day view with diary-card events (replaces hand-rolled grid)"
```

---

### Task 4: `<DayAgenda>` mobile — dot+name + parallel marker + doctor colours

**Files:**
- Create: `src/features/today/day-agenda.tsx` (evolves `day-timeline.tsx`)
- Modify: `src/app/today/page.tsx` (use `<DayAgenda>` in the `lg:hidden` block)
- Delete: `src/features/today/day-timeline.tsx`
- Modify/Replace: `tests/e2e/today-mobile.spec.ts`

**Interfaces:**
- Consumes: `Schedule`, `doctorColorVar` (Task 1).
- Produces: `<DayAgenda schedule doctorIds />` with `data-testid="today-timeline"`, rows `tl-appt-{id}` / `tl-req-{id}`, and a parallel marker `data-testid="today-parallel-{HHMM}"`.

- [ ] **Step 1: Write/replace the failing e2e**

Replace `tests/e2e/today-mobile.spec.ts`:

```typescript
import { test, expect } from "@playwright/test";
import { CLINIC_ID, installAuth, meWithRole, gotoAuthed } from "./_auth";

test.use({ viewport: { width: 375, height: 740 } });

function todayAt(hhmm: string) {
  const d = new Date();
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}T${hhmm}:00`;
}
const SCHED = {
  date: todayAt("00:00").slice(0, 10),
  working_window: { start: "09:00:00", end: "14:00:00" },
  doctors: [{ id: "d1", name: "Dr. Sayali", specialty: null, windows: [] }, { id: "d2", name: "Dr. Mehta", specialty: null, windows: [] }],
  appointments: [
    { id: "a2", doctor_id: "d1", patient_id: "p2", patient_name: "ABC", start_datetime: todayAt("11:00"), end_datetime: todayAt("11:30"), status: "confirmed", chief_complaint: "Bleeding gums" },
    { id: "a3", doctor_id: "d2", patient_id: "p3", patient_name: "Neha", start_datetime: todayAt("11:00"), end_datetime: todayAt("11:30"), status: "confirmed", chief_complaint: "Checkup" },
    { id: "a1", doctor_id: "d1", patient_id: "p1", patient_name: "Vinod", start_datetime: todayAt("10:00"), end_datetime: todayAt("10:30"), status: "confirmed", chief_complaint: "Follow up" },
  ],
  requests: [],
};
async function stub(page: import("@playwright/test").Page) {
  await page.route(`**/api/v1/clinics/${CLINIC_ID}/schedule*`, (r) =>
    r.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(SCHED) }));
}

test("mobile shows the agenda (not the calendar), colour-coded, with a parallel marker", async ({ page }) => {
  await installAuth(page, { me: meWithRole("owner") });
  await stub(page);
  await gotoAuthed(page, "/today", { ready: page.getByTestId("today-page") });
  await expect(page.getByTestId("today-timeline")).toBeVisible();
  await expect(page.getByTestId("today-grid")).toBeHidden();
  await expect(page.getByTestId("tl-appt-a1")).toContainText("Vinod");
  await expect(page.getByTestId("tl-appt-a1")).toContainText("Dr. Sayali");
  await expect(page.getByTestId("today-parallel-1100")).toBeVisible(); // 11:00 a2 + a3 parallel
});
```

- [ ] **Step 2: Run to verify it fails**

Run: `npm run test:e2e -- today-mobile`
Expected: FAIL (no `today-parallel-*`, no DayAgenda).

- [ ] **Step 3: Create `<DayAgenda>`**

Create `src/features/today/day-agenda.tsx`:

```typescript
"use client";

import Link from "next/link";
import { useTranslation } from "react-i18next";

import { Badge } from "@/components/ui/badge";
import { doctorColorVar } from "@/features/today/doctor-colors";
import type { Schedule } from "@/features/today/api";

export function DayAgenda({ schedule, doctorIds }: { schedule: Schedule; doctorIds?: string[] }) {
  const { t, i18n } = useTranslation();
  const inFilter = (id: string) => !doctorIds || doctorIds.length === 0 || doctorIds.includes(id);
  const fmt = (iso: string) => new Date(iso).toLocaleTimeString(i18n.language, { hour: "numeric", minute: "2-digit" });
  const docName = new Map(schedule.doctors.map((d) => [d.id, d.name]));

  type Row = { kind: "appt" | "req"; id: string; start: string; name: string; doctorId: string; status: string };
  const rows: Row[] = [
    ...schedule.appointments.filter((a) => inFilter(a.doctor_id)).map((a) => ({ kind: "appt" as const, id: a.id, start: a.start_datetime, name: a.patient_name, doctorId: a.doctor_id, status: a.status })),
    ...schedule.requests.filter((r) => r.status === "pending" && !r.expired && inFilter(r.doctor_id)).map((r) => ({ kind: "req" as const, id: r.id, start: r.start_datetime, name: r.patient_name, doctorId: r.doctor_id, status: r.status })),
  ].sort((x, y) => x.start.localeCompare(y.start));

  // group consecutive same-start rows so parallel appts get a marker
  const groups: Row[][] = [];
  for (const row of rows) {
    const last = groups[groups.length - 1];
    if (last && last[0].start === row.start) last.push(row);
    else groups.push([row]);
  }
  const hhmm = (iso: string) => { const d = new Date(iso); return `${String(d.getHours()).padStart(2, "0")}${String(d.getMinutes()).padStart(2, "0")}`; };

  function rowEl(row: Row) {
    const dc = doctorColorVar(row.doctorId, schedule.doctors);
    return (
      <Link
        key={row.id}
        href={row.kind === "appt" ? "/patients" : "/requests"}
        data-testid={`tl-${row.kind}-${row.id}`}
        className="flex items-center gap-3 rounded-xl border border-l-4 border-border bg-card px-3.5 py-2.5"
        style={{ borderLeftColor: dc }}
      >
        <span className="w-[64px] shrink-0 text-[13px] font-semibold text-foreground">{fmt(row.start)}</span>
        <span className="min-w-0 flex-1">
          <span className="block truncate text-[13.5px] font-semibold text-foreground">{row.name}</span>
          <span className="mt-0.5 inline-flex min-w-0 items-center gap-1 text-xs font-medium text-foreground">
            <span className="size-2 shrink-0 rounded-full" style={{ background: dc }} aria-hidden />
            <span className="truncate">{docName.get(row.doctorId) ?? ""}</span>
          </span>
        </span>
        <Badge variant={row.kind === "req" ? "warning" : "success"}>{t(`requests.status.${row.status}`)}</Badge>
      </Link>
    );
  }

  return (
    <div className="space-y-2" data-testid="today-timeline">
      {groups.map((g) =>
        g.length > 1 ? (
          <div key={`p-${g[0].start}`} className="space-y-2">
            <div
              data-testid={`today-parallel-${hhmm(g[0].start)}`}
              className="flex items-center gap-2 px-1 pt-1 text-[10px] font-bold uppercase tracking-wide text-muted-foreground"
            >
              <span className="h-px flex-none w-3.5 bg-border" />
              {fmt(g[0].start)} · {t("today.parallel", { count: g.length })}
            </div>
            {g.map(rowEl)}
          </div>
        ) : (
          rowEl(g[0])
        ),
      )}
    </div>
  );
}
```

- [ ] **Step 4: i18n key + wire-in; delete old timeline**

Add to `src/i18n/locales/en.json` `today` block: `"parallel": "{{count}} in parallel",` and to `hi.json`: `"parallel": "{{count}} समानांतर",`.
In `page.tsx`, swap the import + the mobile block:

```typescript
import { DayAgenda } from "@/features/today/day-agenda";
// …
              <div className="lg:hidden">
                <DayAgenda schedule={q.data} doctorIds={selected} />
              </div>
```

Delete: `git rm src/features/today/day-timeline.tsx`.

- [ ] **Step 5: Run e2e + typecheck + lint**

Run: `npm run test:e2e -- today-mobile && npx tsc --noEmit && npx eslint src/features/today/day-agenda.tsx src/app/today/page.tsx`
Expected: PASS; clean.

- [ ] **Step 6: Commit**

```bash
git add src/features/today/day-agenda.tsx src/app/today/page.tsx src/i18n/locales/en.json src/i18n/locales/hi.json tests/e2e/today-mobile.spec.ts
git rm src/features/today/day-timeline.tsx
git commit -m "feat(today): colour-coded mobile agenda with dot+name + parallel marker"
```

---

### Task 5: `<DoctorLegend>` + wire-in, visual-fidelity gate, docs, cleanup

**Files:**
- Create: `src/features/today/doctor-legend.tsx`
- Modify: `src/app/today/page.tsx` (render `<DoctorLegend>` above the calendar/agenda)
- Create: `tests/e2e/today-visual.spec.ts` (screenshot capture, light/dark × desktop/mobile)
- Modify: `src/i18n/locales/en.json` + `hi.json` (`today.legend` aria, if used)

**Interfaces:**
- Consumes: `Schedule`, `doctorColorVar`.
- Produces: `<DoctorLegend doctors={DoctorColumn[]} />` with `data-testid="today-legend"`, chips `data-testid="legend-{id}"` = ● dot (doctor colour) + name.

- [ ] **Step 1: Write the failing e2e (legend visible)**

Append to (or create) `tests/e2e/today-grid.spec.ts` a test — or add to a new file:

```typescript
test("legend shows a coloured chip per active doctor", async ({ page }) => {
  await installAuth(page, { me: meWithRole("owner") });
  await stub(page, SCHED);
  await gotoAuthed(page, "/today", { ready: page.getByTestId("today-page") });
  await expect(page.getByTestId("today-legend")).toBeVisible();
  await expect(page.getByTestId("legend-d1")).toContainText("Dr. Sayali");
  await expect(page.getByTestId("legend-d2")).toContainText("Dr. Mehta");
});
```

- [ ] **Step 2: Run to verify it fails**

Run: `npm run test:e2e -- today-grid`
Expected: the legend test FAILS.

- [ ] **Step 3: Create `<DoctorLegend>`**

Create `src/features/today/doctor-legend.tsx`:

```typescript
"use client";

import { doctorColorVar } from "@/features/today/doctor-colors";
import type { DoctorColumn } from "@/features/today/api";

export function DoctorLegend({ doctors }: { doctors: DoctorColumn[] }) {
  if (doctors.length === 0) return null;
  return (
    <div
      data-testid="today-legend"
      className="mb-3 flex flex-wrap items-center gap-x-4 gap-y-2 rounded-xl border border-border bg-card px-3 py-2"
    >
      {doctors.map((d) => (
        <span key={d.id} data-testid={`legend-${d.id}`} className="inline-flex items-center gap-1.5 text-xs text-foreground">
          <span className="size-2.5 shrink-0 rounded-full" style={{ background: doctorColorVar(d.id, doctors) }} aria-hidden />
          {d.name}
        </span>
      ))}
    </div>
  );
}
```

- [ ] **Step 4: Wire into the page**

In `page.tsx`, import `DoctorLegend` and render it just before the responsive grid/agenda block, when data is present:

```typescript
          {q.data && q.data.doctors.length > 0 && (q.data.appointments.length > 0 || q.data.requests.length > 0) && (
            <DoctorLegend doctors={q.data.doctors} />
          )}
```

- [ ] **Step 5: Visual-fidelity gate — capture screenshots (light/dark × desktop/mobile)**

Create `tests/e2e/today-visual.spec.ts` (captures PNGs for human review against the mockup; not an assertion baseline):

```typescript
import { test } from "@playwright/test";
import { CLINIC_ID, installAuth, meWithRole, gotoAuthed } from "./_auth";

function todayAt(hhmm: string) {
  const d = new Date();
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}T${hhmm}:00`;
}
const SCHED = {
  date: todayAt("00:00").slice(0, 10),
  working_window: { start: "09:00:00", end: "14:00:00" },
  doctors: [
    { id: "d1", name: "Dr. Sayali", specialty: null, windows: [] },
    { id: "d2", name: "Dr. Mehta", specialty: null, windows: [] },
    { id: "d3", name: "Dr. Iyer", specialty: null, windows: [] },
  ],
  appointments: [
    { id: "a1", doctor_id: "d1", patient_id: "p1", patient_name: "Vinod Kambli", start_datetime: todayAt("10:00"), end_datetime: todayAt("12:00"), status: "confirmed", chief_complaint: "Follow up" },
    { id: "a2", doctor_id: "d1", patient_id: "p2", patient_name: "ABC", start_datetime: todayAt("11:00"), end_datetime: todayAt("11:45"), status: "confirmed", chief_complaint: "Bleeding gums" },
    { id: "a3", doctor_id: "d3", patient_id: "p3", patient_name: "Tara N.", start_datetime: todayAt("11:00"), end_datetime: todayAt("11:30"), status: "confirmed", chief_complaint: "Consult" },
  ],
  requests: [
    { id: "r1", doctor_id: "d2", patient_id: "p4", patient_name: "Neha Sharma", doctor_name: "Dr. Mehta", start_datetime: todayAt("11:00"), status: "pending", expired: false, chief_complaint: "Checkup" },
  ],
};
async function stub(page: import("@playwright/test").Page) {
  await page.route(`**/api/v1/clinics/${CLINIC_ID}/schedule*`, (r) =>
    r.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(SCHED) }));
}
const DIR = "test-results/today-visual";
for (const theme of ["light", "dark"] as const) {
  for (const [label, vp] of [["desktop", { width: 1280, height: 900 }], ["mobile", { width: 375, height: 800 }]] as const) {
    test(`screenshot ${theme} ${label}`, async ({ page }) => {
      await page.emulateMedia({ colorScheme: theme });
      await page.setViewportSize(vp);
      await installAuth(page, { me: meWithRole("owner") });
      await stub(page);
      // force theme class (next-themes persists via localStorage key "theme")
      await page.addInitScript((th) => window.localStorage.setItem("theme", th), theme);
      await gotoAuthed(page, "/today", { ready: page.getByTestId("today-page") });
      await page.waitForTimeout(400);
      await page.screenshot({ path: `${DIR}/${theme}-${label}.png`, fullPage: true });
    });
  }
}
```

- [ ] **Step 6: Run everything; capture the screenshots**

Run: `npm run test:e2e -- today-` then `npx tsc --noEmit` then `npx eslint src/features/today/`
Expected: all `today-*` specs pass; the 4 screenshots exist under `dentist-registry-frontend/test-results/today-visual/`. **In your report, list the 4 screenshot paths so the controller can eyeball them against the mockup** (`.superpowers/brainstorm/61922-1782536711/content/day-diary-lightdark.html`). Also run the FULL suite `npm run test:e2e` (note only the pre-existing `patients.spec` #40/#78 + my-schedule blocked-slot failures, unrelated).

- [ ] **Step 7: Docs + commit**

Update the FE `README.md` (Data/architecture section) + add a one-line FullCalendar (MIT) entry. Then:

```bash
git add src/features/today/doctor-legend.tsx src/app/today/page.tsx tests/e2e/today-visual.spec.ts tests/e2e/today-grid.spec.ts src/i18n/locales/en.json src/i18n/locales/hi.json README.md
git commit -m "feat(today): doctor legend + visual-fidelity screenshot gate"
```

---

## Self-Review (against the spec)

**Spec coverage:** §2.1 doctor=colour + legend → Tasks 1,5. §2.2/§2.3 FullCalendar timeGrid day + overlap + now-line → Task 3. §3a dep vet → Task 2. §2.4 event card (patient·complaint·●doctor·badge, tint, dashed req) → Task 3 `eventContent` (mirrors mockup). §2.5 confirmed+non-expired pending; cancelled→strip → Tasks 3/4 filters (kept from current). §2.6 mobile agenda + parallel marker → Task 4. §2.7 light+dark (tokens flip; FC themed) → Tasks 1,3 + visual gate Task 5. §2.8 doctor palette tokens → Task 1. §2.9 keep endpoint/nav/stepper/filter/cancelled/tap-through/empty → page.tsx unchanged except component swaps + legend. §2.10 remove hand-rolled grid → Task 3 (`git rm` day-grid) + Task 4 (day-timeline). §7 a11y (colour+name, ≥44px slot, AA) → Tasks 1/3/5. §8 tests + visual → Tasks 3/4/5.

**Placeholder scan:** none — complete code per step. The visual gate is human-eyeballed (no flaky pixel baseline) — deliberate, with paths reported.

**Type/name consistency:** `doctorColorVar`/`doctorColorIndex` defined Task 1, used Tasks 3/4/5. `DayCalendar({schedule,date,clinicId,doctorIds})`, `DayAgenda({schedule,doctorIds})`, `DoctorLegend({doctors})` consistent with page wiring. Testids consistent: `today-grid`, `appt-{id}`/`req-{id}`, `today-timeline`, `tl-appt-{id}`/`tl-req-{id}`, `today-parallel-{HHMM}`, `today-legend`, `legend-{id}`, and the FullCalendar `.fc-timegrid-now-indicator-line` for the now-line.

---

## Release note (post-merge)
**Frontend-only**, BE untouched, **no migration**. Ship FE per `release-playbook.md`; feature → **minor** (FE `v1.6.0 → v1.7.0`). Supersedes the live hand-rolled day-grid. Confirm version at release.
