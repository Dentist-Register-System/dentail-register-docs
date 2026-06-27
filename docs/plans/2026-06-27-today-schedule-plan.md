# Today's Schedule Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A clinic-wide "Today's Schedule" view (owner+assistant) — a doctor-column, time-proportional day grid on desktop with a merged-timeline fallback on mobile — fed by one new read endpoint.

**Architecture:** New BE read endpoint `GET /clinics/{id}/schedule?date=` aggregates active doctors (+ their availability for the date), confirmed appointments, and all requests, with a derived working-window. FE adds a role-gated `/today` route whose page holds `date` + doctor-filter state, fetches once via `useTodaySchedule`, and renders `<DayGrid>` (lg+) or `<DayTimeline>` (mobile). No migration.

**Tech Stack:** FastAPI + SQLAlchemy 2.x + pytest; Next.js App Router, React, TanStack Query, react-i18next, Tailwind v4 semantic tokens, Playwright e2e (mocked).

**Spec:** `docs/specs/2026-06-27-today-schedule-design.md`.

## Global Constraints

- **Access = owner + assistant** — gate the nav item, the page (defense-in-depth guard), and the endpoint (`require_role(MemberRole.owner, MemberRole.assistant)`). Non-owner doctors must NOT see it (nav absent, route guarded, API 403).
- **i18n-first (Rule §16):** every new string in BOTH `src/i18n/locales/en.json` and `hi.json`; counts/dates interpolated; no hardcoded literals.
- **Design system (Rule §17.0):** semantic tokens only (`bg-success/…`, `border-l-warning`, `bg-card`, `text-foreground`, `text-muted-foreground`, `bg-primary-container`, `text-on-primary-container`, …); no per-page CSS; compose `components/ui/*`. Reuse the `request-row` status-colour language (pending→warning/amber, confirmed→success/green, rejected→destructive/red).
- **No migration** — endpoint reuses existing models only.
- **Touch targets ≥44px (Rule §17.4):** grid uses `ROW_H = 44` px per 30-min slot so a 30-min block is ≥44px tall.
- **Ports:** dev FE `3000` / BE `8000` / Postgres `5433`. Never `3001`/`8001`/`5434`.
- **TDD:** BE = `uv run pytest` (Postgres 5433). FE = `npm run test:e2e` (Playwright auto-starts dev server on 3000; backend + Supabase mocked). Failing test first.
- **No new dependencies.** Naive datetimes (existing convention).
- Route `/today`; nav key `today`; label **"Today"**; icon `today`.

---

### Task 1: Backend — `GET /clinics/{id}/schedule?date=` aggregation endpoint

**Files:**
- Modify: `app/modules/scheduling/schemas.py` (add the Schedule schemas)
- Modify: `app/modules/scheduling/service.py` (add `get_day_schedule`)
- Modify: `app/modules/scheduling/router.py` (add the route + imports)
- Test: `tests/scheduling/test_day_schedule.py` (create)

**Interfaces:**
- Produces: `GET /api/v1/clinics/{clinic_id}/schedule?date=YYYY-MM-DD` → `ScheduleRead { date, working_window {start,end}, doctors:[{id,name,specialty,windows:[{start_time,end_time}]}], appointments:[{id,doctor_id,patient_id,patient_name,start_datetime,end_datetime,status,chief_complaint}], requests:[{id,doctor_id,patient_id,patient_name,doctor_name,start_datetime,status,expired,chief_complaint}] }`. Owner+assistant → 200; non-owner doctor → 403.

- [ ] **Step 1: Write the failing test**

Create `tests/scheduling/test_day_schedule.py`:

```python
import uuid as _uuid
from tests.conftest import make_clinic

OWNER = "11111111-1111-1111-1111-111111111111"
ASST = "33333333-3333-3333-3333-333333333333"
DOCU = "22222222-2222-2222-2222-222222222222"
MON = "2026-06-22"  # a Monday → weekday()==0
MON_9 = f"{MON}T09:00:00"


def _clinic_with_confirmed_appt(owner):
    clinic = make_clinic(owner, name="Sched")
    owner.patch(f"/api/v1/clinics/{clinic}/settings", json={"scheduling_workflow": "doctor_approval"})
    doc = owner.post(
        f"/api/v1/clinics/{clinic}/doctors", json={"name": "Dr. A", "phone": "+91 90000 00001"}
    ).json()["doctor"]["id"]
    owner.post(
        f"/api/v1/clinics/{clinic}/doctors/{doc}/availability",
        json={"kind": "recurring", "day_of_week": 0, "start_time": "09:00", "end_time": "12:00"},
    )
    pat = owner.post(
        f"/api/v1/clinics/{clinic}/patients",
        json={"name": "Asha", "phone": "+91 99000 00001", "age": 30, "acknowledge_duplicates": True},
    ).json()["id"]
    rid = owner.post(
        f"/api/v1/clinics/{clinic}/doctors/{doc}/appointment-requests",
        json={"patient_id": pat, "start_datetime": MON_9},
    ).json()["id"]
    assert owner.post(f"/api/v1/clinics/{clinic}/appointment-requests/{rid}/approve").status_code == 200
    return clinic, doc


def test_schedule_returns_day_sections(auth_client):
    owner, _ = auth_client(sub=OWNER)
    clinic, doc = _clinic_with_confirmed_appt(owner)
    r = owner.get(f"/api/v1/clinics/{clinic}/schedule?date={MON}")
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["date"] == MON
    assert body["working_window"]["start"] == "09:00:00"
    assert any(d["id"] == doc and d["windows"] for d in body["doctors"])
    assert len(body["appointments"]) == 1
    assert body["appointments"][0]["doctor_id"] == doc
    assert body["appointments"][0]["patient_name"] == "Asha"


def test_schedule_excludes_other_days(auth_client):
    owner, _ = auth_client(sub=OWNER)
    clinic, _ = _clinic_with_confirmed_appt(owner)
    r = owner.get(f"/api/v1/clinics/{clinic}/schedule?date=2026-06-23")  # Tuesday
    assert r.status_code == 200
    assert r.json()["appointments"] == []


def test_schedule_assistant_allowed_doctor_forbidden(auth_client):
    owner, _ = auth_client(sub=OWNER)
    clinic, _ = _clinic_with_confirmed_appt(owner)
    # assistant joins
    at = owner.post(f"/api/v1/clinics/{clinic}/invites", json={"role": "assistant"}).json()["token"]
    asst, _ = auth_client(sub=ASST)
    asst.post("/api/v1/clinics/join", json={"token": at})
    assert asst.get(f"/api/v1/clinics/{clinic}/schedule?date={MON}").status_code == 200
    # non-owner doctor joins
    dt_ = owner.post(f"/api/v1/clinics/{clinic}/invites", json={"role": "doctor"}).json()["token"]
    docu, _ = auth_client(sub=DOCU)
    docu.post("/api/v1/clinics/join", json={"token": dt_})
    assert docu.get(f"/api/v1/clinics/{clinic}/schedule?date={MON}").status_code == 403
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd dentist-registry-backend && uv run pytest tests/scheduling/test_day_schedule.py -q`
Expected: FAIL (404/route missing).

- [ ] **Step 3: Add the schemas**

In `app/modules/scheduling/schemas.py`, append:

```python
class WorkingWindow(BaseModel):
    start: dt.time
    end: dt.time


class DayWindow(BaseModel):
    start_time: dt.time
    end_time: dt.time


class DoctorColumn(BaseModel):
    id: uuid.UUID
    name: str
    specialty: str | None
    windows: list[DayWindow]


class ScheduleAppt(BaseModel):
    id: uuid.UUID
    doctor_id: uuid.UUID
    patient_id: uuid.UUID
    patient_name: str
    start_datetime: dt.datetime
    end_datetime: dt.datetime
    status: str
    chief_complaint: str | None


class ScheduleReq(BaseModel):
    id: uuid.UUID
    doctor_id: uuid.UUID
    patient_id: uuid.UUID
    patient_name: str
    doctor_name: str
    start_datetime: dt.datetime
    status: str
    expired: bool
    chief_complaint: str | None


class ScheduleRead(BaseModel):
    date: dt.date
    working_window: WorkingWindow
    doctors: list[DoctorColumn]
    appointments: list[ScheduleAppt]
    requests: list[ScheduleReq]
```

(`uuid`, `dt`, `BaseModel` are already imported in this file.)

- [ ] **Step 4: Add the service aggregation**

In `app/modules/scheduling/service.py`, add:

```python
def get_day_schedule(db: Session, clinic_id: uuid.UUID, target_date: dt.date) -> dict:
    from app.modules.doctors.models import Doctor, DoctorStatus  # noqa: PLC0415
    from app.modules.patients.models import Patient  # noqa: PLC0415
    from app.modules.scheduling.models import (  # noqa: PLC0415
        Appointment,
        AppointmentRequest,
        AvailabilityWindow,
    )

    def _expired(r: AppointmentRequest) -> bool:
        return (
            r.status == "pending"
            and r.expires_at is not None
            and dt.datetime.now() > r.expires_at
        )

    dow = target_date.weekday()
    start_dt = dt.datetime.combine(target_date, dt.time.min)
    end_dt = dt.datetime.combine(target_date, dt.time.max)

    doctors = list(
        db.execute(
            select(Doctor)
            .where(Doctor.clinic_id == clinic_id, Doctor.status == DoctorStatus.active)
            .order_by(Doctor.name)
        ).scalars()
    )
    all_windows = list(
        db.execute(
            select(AvailabilityWindow).where(
                AvailabilityWindow.clinic_id == clinic_id,
                AvailabilityWindow.status == "active",
            )
        ).scalars()
    )

    def day_windows(doc_id: uuid.UUID) -> list[AvailabilityWindow]:
        return [
            w
            for w in all_windows
            if w.doctor_id == doc_id
            and (
                (w.kind == "recurring" and w.day_of_week == dow)
                or (w.kind == "one_off" and w.specific_date == target_date)
            )
        ]

    doctor_cols = [
        {
            "id": d.id,
            "name": d.name,
            "specialty": d.specialty,
            "windows": [
                {"start_time": w.start_time, "end_time": w.end_time} for w in day_windows(d.id)
            ],
        }
        for d in doctors
    ]

    appt_rows = db.execute(
        select(Appointment, Patient.name.label("pn"))
        .join(Patient, Patient.id == Appointment.patient_id)
        .where(
            Appointment.clinic_id == clinic_id,
            Appointment.status == "confirmed",
            Appointment.start_datetime >= start_dt,
            Appointment.start_datetime <= end_dt,
        )
        .order_by(Appointment.start_datetime)
    ).all()
    appointments = [
        {
            "id": a.id,
            "doctor_id": a.doctor_id,
            "patient_id": a.patient_id,
            "patient_name": pn,
            "start_datetime": a.start_datetime,
            "end_datetime": a.end_datetime,
            "status": a.status,
            "chief_complaint": a.chief_complaint,
        }
        for a, pn in appt_rows
    ]

    req_rows = db.execute(
        select(AppointmentRequest, Patient.name.label("pn"), Doctor.name.label("dn"))
        .join(Patient, Patient.id == AppointmentRequest.patient_id)
        .join(Doctor, Doctor.id == AppointmentRequest.doctor_id)
        .where(
            AppointmentRequest.clinic_id == clinic_id,
            AppointmentRequest.start_datetime >= start_dt,
            AppointmentRequest.start_datetime <= end_dt,
        )
        .order_by(AppointmentRequest.start_datetime)
    ).all()
    requests = [
        {
            "id": r.id,
            "doctor_id": r.doctor_id,
            "patient_id": r.patient_id,
            "patient_name": pn,
            "doctor_name": dn,
            "start_datetime": r.start_datetime,
            "status": r.status,
            "expired": _expired(r),
            "chief_complaint": r.chief_complaint,
        }
        for r, pn, dn in req_rows
    ]

    wins = [w for d in doctors for w in day_windows(d.id)]
    if wins:
        ws = min(w.start_time for w in wins)
        we = max(w.end_time for w in wins)
    else:
        times = [a["start_datetime"] for a in appointments] + [
            r["start_datetime"] for r in requests
        ]
        if times:
            ws = min(t.time() for t in times)
            we = max((t + dt.timedelta(minutes=30)).time() for t in times)
        else:
            ws, we = dt.time(9, 0), dt.time(18, 0)

    return {
        "date": target_date,
        "working_window": {"start": ws, "end": we},
        "doctors": doctor_cols,
        "appointments": appointments,
        "requests": requests,
    }
```

- [ ] **Step 5: Add the route**

In `app/modules/scheduling/router.py`: extend the imports —

```python
from fastapi import APIRouter, Depends, Query, status
from app.modules.members.deps import CurrentMembership, require_role
from app.modules.members.models import MemberRole
from app.modules.scheduling.schemas import ScheduleRead
```

(merge with existing imports; `AppointmentRead`/`RequestListPage` etc. stay). Then add, near the other routes:

```python
_can_view_schedule = require_role(MemberRole.owner, MemberRole.assistant)


@router.get("/{clinic_id}/schedule", response_model=ScheduleRead)
def get_schedule(
    clinic_id: uuid.UUID,
    db: DbSession,
    date: dt.date = Query(...),
    membership=Depends(_can_view_schedule),
):
    return service.get_day_schedule(db, clinic_id, date)
```

- [ ] **Step 6: Run the new tests + full suite + lint**

Run: `uv run pytest tests/scheduling/test_day_schedule.py -q && uv run pytest -q && uv run ruff check app/modules/scheduling`
Expected: new tests PASS; full suite green; ruff clean.

- [ ] **Step 7: Commit**

```bash
git add app/modules/scheduling/schemas.py app/modules/scheduling/service.py app/modules/scheduling/router.py tests/scheduling/test_day_schedule.py
git commit -m "feat(scheduling): clinic-wide GET /schedule?date= day aggregation (owner+assistant)"
```

---

### Task 2: Frontend — nav item, `/today` route, data hook (substrate)

**Files:**
- Modify: `src/components/shell/destinations.ts` (add `today`)
- Modify: `src/components/shell/app-shell.tsx` (gate `today` to owner+assistant)
- Create: `src/features/today/api.ts` (types + `fetchSchedule`)
- Create: `src/features/today/hooks.ts` (`useTodaySchedule`)
- Modify: `src/lib/query-keys.ts` (add `qk.schedule`)
- Create: `src/app/today/page.tsx`
- Modify: `src/i18n/locales/en.json` + `hi.json` (`nav.today`, `today.title`, `today.empty`, `today.notAvailable`)
- Test: `tests/e2e/today-access.spec.ts` (create)

**Interfaces:**
- Produces: types `Schedule`, `ScheduleAppt`, `ScheduleReq`, `DoctorColumn`, `WorkingWindow` (in `src/features/today/api.ts`); `useTodaySchedule(clinicId, date)`; `qk.schedule(clinicId, date)`; route `/today` with `data-testid="today-page"`; nav item `data-testid="nav-today"`.

- [ ] **Step 1: Write the failing e2e test**

Create `tests/e2e/today-access.spec.ts`:

```typescript
import { test, expect } from "@playwright/test";
import { CLINIC_ID, installAuth, meWithRole, gotoAuthed } from "./_auth";

const EMPTY = {
  date: "2026-06-22",
  working_window: { start: "09:00:00", end: "18:00:00" },
  doctors: [],
  appointments: [],
  requests: [],
};
async function stubSchedule(page: import("@playwright/test").Page, body: object = EMPTY) {
  await page.route(`**/api/v1/clinics/${CLINIC_ID}/schedule*`, (r) =>
    r.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(body) }),
  );
}

for (const role of ["owner", "assistant"] as const) {
  test(`${role} sees Today nav + /today renders`, async ({ page }) => {
    await installAuth(page, { me: meWithRole(role) });
    await stubSchedule(page);
    await gotoAuthed(page, "/today", { ready: page.getByTestId("today-page") });
    await expect(page.getByTestId("nav-today")).toBeVisible();
  });
}

test("non-owner doctor does NOT see Today nav, and /today is blocked", async ({ page }) => {
  await installAuth(page, { me: meWithRole("doctor") });
  await stubSchedule(page);
  await gotoAuthed(page, "/", { ready: page.getByTestId("signout-desktop") });
  await expect(page.getByTestId("nav-today")).toHaveCount(0);
  await page.goto("/today");
  await expect(page.getByTestId("today-not-available")).toBeVisible();
  await expect(page.getByTestId("today-grid")).toHaveCount(0);
});
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd dentist-registry-frontend && npm run test:e2e -- today-access`
Expected: FAIL (route + nav don't exist).

- [ ] **Step 3: Add the nav destination**

In `src/components/shell/destinations.ts`, insert after the `clinic-schedules` entry:

```typescript
  {
    key: "today",
    labelKey: "nav.today",
    icon: "today",
    href: "/today",
  },
```

- [ ] **Step 4: Gate `today` in the shell**

In `src/components/shell/app-shell.tsx`, in the `visibleDestinations` filter, add a line before `return true;`:

```typescript
  if (d.key === "today") return role === "owner" || role === "assistant";
```

- [ ] **Step 5: Query key + api + hook**

In `src/lib/query-keys.ts`, add to the `qk` object:

```typescript
  schedule: (clinicId: string, date: string) => ["schedule", clinicId, date] as const,
```

Create `src/features/today/api.ts`:

```typescript
import { apiFetch } from "@/lib/api-client";

export type WorkingWindow = { start: string; end: string };
export type DoctorColumn = {
  id: string;
  name: string;
  specialty: string | null;
  windows: { start_time: string; end_time: string }[];
};
export type ScheduleAppt = {
  id: string;
  doctor_id: string;
  patient_id: string;
  patient_name: string;
  start_datetime: string;
  end_datetime: string;
  status: string;
  chief_complaint: string | null;
};
export type ScheduleReq = {
  id: string;
  doctor_id: string;
  patient_id: string;
  patient_name: string;
  doctor_name: string;
  start_datetime: string;
  status: string;
  expired: boolean;
  chief_complaint: string | null;
};
export type Schedule = {
  date: string;
  working_window: WorkingWindow;
  doctors: DoctorColumn[];
  appointments: ScheduleAppt[];
  requests: ScheduleReq[];
};

export const fetchSchedule = (clinicId: string, date: string) =>
  apiFetch<Schedule>(`/api/v1/clinics/${clinicId}/schedule?date=${date}`);
```

Create `src/features/today/hooks.ts`:

```typescript
import { useQuery } from "@tanstack/react-query";
import { qk } from "@/lib/query-keys";
import { fetchSchedule } from "@/features/today/api";

export function useTodaySchedule(clinicId: string, date: string) {
  return useQuery({
    queryKey: qk.schedule(clinicId, date),
    queryFn: () => fetchSchedule(clinicId, date),
    enabled: !!clinicId && !!date,
  });
}
```

- [ ] **Step 6: Create the page**

Create `src/app/today/page.tsx`:

```typescript
"use client";

import { useState } from "react";
import { useTranslation } from "react-i18next";

import { AuthGate } from "@/components/auth-gate";
import { AppShell } from "@/components/shell/app-shell";
import { PageContainer } from "@/components/layout/page-container";
import { PageHeader } from "@/components/layout/page-header";
import { useMe } from "@/features/clinic/hooks";
import { useTodaySchedule } from "@/features/today/hooks";

function isoDate(d: Date) {
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
}

function TodayShell() {
  const { t } = useTranslation();
  const me = useMe();
  const membership = me.data?.memberships[0];
  const clinicId = membership?.clinic_id ?? "";
  const role = membership?.role ?? "";
  const [date] = useState(() => isoDate(new Date()));
  const q = useTodaySchedule(clinicId, date);

  if (role !== "owner" && role !== "assistant") {
    return (
      <AppShell clinicName={membership?.clinic_name}>
        <PageContainer>
          <p className="text-sm text-muted-foreground" data-testid="today-not-available">
            {t("today.notAvailable")}
          </p>
        </PageContainer>
      </AppShell>
    );
  }

  return (
    <AppShell clinicName={membership?.clinic_name}>
      <PageContainer>
        <div data-testid="today-page">
          <PageHeader title={t("today.title")} />
          {q.isPending ? (
            <p className="text-sm text-muted-foreground">{t("common.loading")}</p>
          ) : (q.data && q.data.appointments.length === 0 && q.data.requests.length === 0) ? (
            <p className="text-sm text-muted-foreground" data-testid="today-empty">{t("today.empty")}</p>
          ) : null}
        </div>
      </PageContainer>
    </AppShell>
  );
}

export default function TodayPage() {
  return (
    <AuthGate>
      <TodayShell />
    </AuthGate>
  );
}
```

- [ ] **Step 7: i18n (en + hi)**

In `src/i18n/locales/en.json`, add `"today": "Today"` to the `nav` object, and a top-level block:

```json
  "today": {
    "title": "Today's Schedule",
    "empty": "Nothing scheduled for this day.",
    "notAvailable": "This view isn't available for your role."
  },
```

In `hi.json`, mirror with Hindi (flag for i18n-owner review): `nav.today` = `"आज"`, and:

```json
  "today": {
    "title": "आज का शेड्यूल",
    "empty": "इस दिन के लिए कुछ भी निर्धारित नहीं है।",
    "notAvailable": "यह दृश्य आपकी भूमिका के लिए उपलब्ध नहीं है।"
  },
```

- [ ] **Step 8: Run e2e + typecheck + lint**

Run: `npm run test:e2e -- today-access && npx tsc --noEmit && npx eslint src/app/today/page.tsx src/features/today/api.ts src/features/today/hooks.ts src/components/shell/destinations.ts src/components/shell/app-shell.tsx`
Expected: tests PASS; tsc + eslint clean.

- [ ] **Step 9: Commit**

```bash
git add src/components/shell/destinations.ts src/components/shell/app-shell.tsx src/lib/query-keys.ts src/features/today/ src/app/today/page.tsx src/i18n/locales/en.json src/i18n/locales/hi.json tests/e2e/today-access.spec.ts
git commit -m "feat(today): nav item + /today route + schedule data hook (owner+assistant)"
```

---

### Task 3: Frontend — `<DayGrid>` proportional day grid

**Files:**
- Create: `src/features/today/day-grid.tsx`
- Modify: `src/app/today/page.tsx` (render `<DayGrid>` for owner/assistant)
- Modify: `src/i18n/locales/en.json` + `hi.json` (`today.now`, `today.duration.h`, `today.duration.m`)
- Test: `tests/e2e/today-grid.spec.ts` (create)

**Interfaces:**
- Consumes: `Schedule` from `@/features/today/api`; `useTodaySchedule`.
- Produces: `<DayGrid schedule={Schedule} isToday={boolean} />`; testids `today-grid`, `appt-{id}` (appointment block), `req-{id}` (request block), `today-now-line`.

- [ ] **Step 1: Write the failing e2e test**

Create `tests/e2e/today-grid.spec.ts`:

```typescript
import { test, expect } from "@playwright/test";
import { CLINIC_ID, installAuth, meWithRole, gotoAuthed } from "./_auth";

function todayAt(hhmm: string) {
  const d = new Date();
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}T${hhmm}:00`;
}
const SCHED = {
  date: todayAt("00:00").slice(0, 10),
  working_window: { start: "00:00:00", end: "23:30:00" }, // wide → now is always inside
  doctors: [{ id: "d1", name: "Dr. A", specialty: "Ortho", windows: [] }],
  appointments: [
    { id: "a1", doctor_id: "d1", patient_id: "p1", patient_name: "Amit", start_datetime: todayAt("09:00"), end_datetime: todayAt("11:00"), status: "confirmed", chief_complaint: null },
    { id: "a2", doctor_id: "d1", patient_id: "p2", patient_name: "Priya", start_datetime: todayAt("11:00"), end_datetime: todayAt("11:30"), status: "confirmed", chief_complaint: null },
  ],
  requests: [
    { id: "r1", doctor_id: "d1", patient_id: "p3", patient_name: "Neha", doctor_name: "Dr. A", start_datetime: todayAt("12:00"), status: "pending", expired: false, chief_complaint: null },
  ],
};
async function stub(page: import("@playwright/test").Page, body: object) {
  await page.route(`**/api/v1/clinics/${CLINIC_ID}/schedule*`, (r) =>
    r.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(body) }),
  );
}

test("grid renders proportional blocks + now line for today", async ({ page }) => {
  await installAuth(page, { me: meWithRole("owner") });
  await stub(page, SCHED);
  await gotoAuthed(page, "/today", { ready: page.getByTestId("today-grid") });
  const a1 = await page.getByTestId("appt-a1").boundingBox();
  const a2 = await page.getByTestId("appt-a2").boundingBox();
  expect(a1!.height).toBeGreaterThan(a2!.height * 3); // 2h ≈ 4× 30-min
  await expect(page.getByTestId("req-r1")).toBeVisible(); // amber pending block
  await expect(page.getByTestId("today-now-line")).toBeVisible();
});

test("tap appointment → /patients, tap request → /requests", async ({ page }) => {
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
Expected: FAIL (`today-grid` doesn't exist).

- [ ] **Step 3: Create `<DayGrid>`**

Create `src/features/today/day-grid.tsx`:

```typescript
"use client";

import Link from "next/link";
import { useTranslation } from "react-i18next";

import { useClinicSettings } from "@/features/clinic/hooks";
import type { Schedule, ScheduleAppt, ScheduleReq } from "@/features/today/api";

const ROW_H = 44; // px per 30-min slot (also satisfies ≥44px touch target)
const SLOT = 30; // minutes

function hhmmssToMin(s: string) {
  const [h, m] = s.split(":").map(Number);
  return h * 60 + m;
}
function minOfDay(iso: string) {
  const d = new Date(iso);
  return d.getHours() * 60 + d.getMinutes();
}

export function DayGrid({
  schedule,
  isToday,
  clinicId,
}: {
  schedule: Schedule;
  isToday: boolean;
  clinicId: string;
}) {
  const { t } = useTranslation();
  const settings = useClinicSettings(clinicId);
  const defaultLen = settings.data?.default_slot_size_minutes ?? 30;

  const winStart = hhmmssToMin(schedule.working_window.start);
  const winEnd = hhmmssToMin(schedule.working_window.end);
  const rows = Math.max(1, Math.ceil((winEnd - winStart) / SLOT));
  const gridH = rows * ROW_H;

  const labels: number[] = [];
  for (let m = winStart; m <= winEnd; m += SLOT) labels.push(m);

  const now = new Date();
  const nowMin = now.getHours() * 60 + now.getMinutes();
  const showNow = isToday && nowMin >= winStart && nowMin <= winEnd;

  function top(min: number) {
    return ((min - winStart) / SLOT) * ROW_H;
  }
  function apptBox(a: ScheduleAppt) {
    const s = minOfDay(a.start_datetime);
    const e = minOfDay(a.end_datetime);
    return { top: top(s), height: Math.max(ROW_H, ((e - s) / SLOT) * ROW_H) };
  }
  function reqBox(r: ScheduleReq) {
    const s = minOfDay(r.start_datetime);
    return { top: top(s), height: Math.max(ROW_H, (defaultLen / SLOT) * ROW_H) };
  }
  const fmt = (iso: string) =>
    new Date(iso).toLocaleTimeString(undefined, { hour: "numeric", minute: "2-digit" });

  return (
    <div className="overflow-x-auto rounded-xl border border-border bg-card" data-testid="today-grid">
      <div className="flex min-w-max">
        {/* time gutter */}
        <div className="sticky left-0 z-10 w-14 shrink-0 bg-card">
          <div className="h-10 border-b border-border" />
          <div className="relative" style={{ height: gridH }}>
            {labels.map((m) => (
              <div
                key={m}
                className="absolute right-1 -translate-y-2 text-[10px] text-muted-foreground"
                style={{ top: top(m) }}
              >
                {String(Math.floor(m / 60)).padStart(2, "0")}:{String(m % 60).padStart(2, "0")}
              </div>
            ))}
          </div>
        </div>

        {/* doctor columns */}
        {schedule.doctors.map((doc) => (
          <div key={doc.id} className="w-44 shrink-0 border-l border-border">
            <div className="flex h-10 items-center gap-2 border-b border-border bg-muted/30 px-2">
              <span className="truncate text-xs font-semibold text-foreground">{doc.name}</span>
            </div>
            <div
              className="relative"
              style={{
                height: gridH,
                backgroundImage:
                  "repeating-linear-gradient(to bottom, transparent 0, transparent calc(var(--rh) - 1px), var(--border) calc(var(--rh) - 1px), var(--border) var(--rh)))".replace(
                    /var\(--rh\)/g,
                    `${ROW_H}px`,
                  ),
              }}
            >
              {schedule.appointments
                .filter((a) => a.doctor_id === doc.id)
                .map((a) => {
                  const b = apptBox(a);
                  return (
                    <Link
                      key={a.id}
                      href="/patients"
                      data-testid={`appt-${a.id}`}
                      className="absolute inset-x-1 overflow-hidden rounded-lg border border-l-4 border-border border-l-success bg-success/10 px-2 py-1"
                      style={{ top: b.top + 1, height: b.height - 2 }}
                    >
                      <span className="block truncate text-xs font-semibold text-foreground">{a.patient_name}</span>
                      <span className="block truncate text-[10px] text-muted-foreground">
                        {fmt(a.start_datetime)}–{fmt(a.end_datetime)}
                      </span>
                    </Link>
                  );
                })}
              {schedule.requests
                .filter((r) => r.doctor_id === doc.id && r.status === "pending")
                .map((r) => {
                  const b = reqBox(r);
                  return (
                    <Link
                      key={r.id}
                      href="/requests"
                      data-testid={`req-${r.id}`}
                      className="absolute inset-x-1 overflow-hidden rounded-lg border border-l-4 border-border border-l-warning bg-warning/10 px-2 py-1"
                      style={{ top: b.top + 1, height: b.height - 2 }}
                    >
                      <span className="block truncate text-xs font-semibold text-foreground">{r.patient_name}</span>
                      <span className="block truncate text-[10px] text-muted-foreground">
                        {fmt(r.start_datetime)} · {t(`requests.status.${r.status}`)}
                      </span>
                    </Link>
                  );
                })}
            </div>
          </div>
        ))}
      </div>

      {showNow && (
        <div
          data-testid="today-now-line"
          className="pointer-events-none absolute left-14 right-0 z-20 h-0.5 bg-info"
          style={{ top: 40 + top(nowMin) }}
        />
      )}
    </div>
  );
}
```

> The now-line uses absolute positioning relative to the grid; the outer grid container needs `relative`. Add `relative` to the `today-grid` container's className (`"relative overflow-x-auto …"`).

- [ ] **Step 4: Render it in the page**

In `src/app/today/page.tsx`, import and render the grid in the owner/assistant branch (replace the loading/empty-only body). Add:

```typescript
import { DayGrid } from "@/features/today/day-grid";
```

In the body, after the empty-state `<p>`, when data is present and non-empty:

```typescript
          {q.data && (q.data.appointments.length > 0 || q.data.requests.length > 0) && (
            <DayGrid schedule={q.data} isToday={q.data.date === date} clinicId={clinicId} />
          )}
```

- [ ] **Step 5: i18n (en + hi)**

Add to the `today` block in `en.json`:

```json
    "now": "now",
    "duration": { "h": "{{count}}h", "m": "{{count}}m" },
```

and Hindi equivalents in `hi.json` (`now` → `"अभी"`, durations same format).

- [ ] **Step 6: Run e2e + typecheck + lint**

Run: `npm run test:e2e -- today-grid && npx tsc --noEmit && npx eslint src/features/today/day-grid.tsx src/app/today/page.tsx`
Expected: both grid tests PASS; tsc + eslint clean.

- [ ] **Step 7: Commit**

```bash
git add src/features/today/day-grid.tsx src/app/today/page.tsx src/i18n/locales/en.json src/i18n/locales/hi.json tests/e2e/today-grid.spec.ts
git commit -m "feat(today): proportional doctor-column day grid + now line + tap-through"
```

---

### Task 4: Frontend — day stepper, doctor-filter pills, cancelled strip

**Files:**
- Create: `src/features/today/today-header.tsx` (stepper + filter pills + cancelled strip)
- Modify: `src/app/today/page.tsx` (lift `date` + `selectedDoctorIds` state, render header, pass filter to grid)
- Modify: `src/features/today/day-grid.tsx` (accept `doctorIds?: string[]` to filter columns)
- Modify: `src/i18n/locales/en.json` + `hi.json` (`today.todayPill`, `today.allDoctors`, `today.notCancelled`)
- Test: `tests/e2e/today-header.spec.ts` (create)

**Interfaces:**
- Consumes: `Schedule`.
- Produces: `<TodayHeader>` with testids `today-prev`, `today-next`, `today-reset`, `today-date-title`, `today-doc-pill-{id}`, `today-cancelled-strip`; `DayGrid` gains optional `doctorIds` prop (when set, only those doctor columns render).

- [ ] **Step 1: Write the failing e2e test**

Create `tests/e2e/today-header.spec.ts`:

```typescript
import { test, expect } from "@playwright/test";
import { CLINIC_ID, installAuth, meWithRole, gotoAuthed } from "./_auth";

function dayISO(offset: number) {
  const d = new Date();
  d.setDate(d.getDate() + offset);
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
}
function schedFor(dateISO: string) {
  return {
    date: dateISO,
    working_window: { start: "09:00:00", end: "17:00:00" },
    doctors: [
      { id: "d1", name: "Dr. A", specialty: null, windows: [] },
      { id: "d2", name: "Dr. B", specialty: null, windows: [] },
    ],
    appointments: [
      { id: `a-${dateISO}`, doctor_id: "d1", patient_id: "p1", patient_name: "Amit", start_datetime: `${dateISO}T10:00:00`, end_datetime: `${dateISO}T10:30:00`, status: "confirmed", chief_complaint: null },
    ],
    requests: [
      { id: "rc", doctor_id: "d2", patient_id: "p2", patient_name: "Sara", doctor_name: "Dr. B", start_datetime: `${dateISO}T11:00:00`, status: "cancelled", expired: false, chief_complaint: null },
    ],
  };
}
async function stubByDate(page: import("@playwright/test").Page) {
  await page.route(`**/api/v1/clinics/${CLINIC_ID}/schedule*`, (r) => {
    const url = new URL(r.request().url());
    const date = url.searchParams.get("date")!;
    r.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(schedFor(date)) });
  });
}

test("next/prev/today stepper refetches by date", async ({ page }) => {
  await installAuth(page, { me: meWithRole("owner") });
  await stubByDate(page);
  await gotoAuthed(page, "/today", { ready: page.getByTestId("today-grid") });
  await expect(page.getByTestId(`appt-a-${dayISO(0)}`)).toBeVisible();
  await page.getByTestId("today-next").click();
  await expect(page.getByTestId(`appt-a-${dayISO(1)}`)).toBeVisible();
  await page.getByTestId("today-reset").click();
  await expect(page.getByTestId(`appt-a-${dayISO(0)}`)).toBeVisible();
});

test("doctor filter narrows columns; cancelled strip shows", async ({ page }) => {
  await installAuth(page, { me: meWithRole("owner") });
  await stubByDate(page);
  await gotoAuthed(page, "/today", { ready: page.getByTestId("today-grid") });
  await expect(page.getByTestId("today-cancelled-strip")).toBeVisible(); // 1 cancelled req
  await page.getByTestId("today-doc-pill-d1").click(); // focus only Dr. A
  await expect(page.getByTestId(`appt-a-${dayISO(0)}`)).toBeVisible();
});
```

- [ ] **Step 2: Run to verify it fails**

Run: `npm run test:e2e -- today-header`
Expected: FAIL (header testids don't exist).

- [ ] **Step 3: Create `<TodayHeader>`**

Create `src/features/today/today-header.tsx`:

```typescript
"use client";

import { useState } from "react";
import { useTranslation } from "react-i18next";

import { Icon } from "@/components/ui/icon";
import type { Schedule } from "@/features/today/api";

export function TodayHeader({
  schedule,
  date,
  isToday,
  onPrev,
  onNext,
  onToday,
  selected,
  onToggleDoctor,
}: {
  schedule: Schedule | undefined;
  date: string;
  isToday: boolean;
  onPrev: () => void;
  onNext: () => void;
  onToday: () => void;
  selected: string[]; // empty = all
  onToggleDoctor: (id: string) => void;
}) {
  const { t, i18n } = useTranslation();
  const [openCancelled, setOpenCancelled] = useState(false);
  const title = new Date(`${date}T00:00:00`).toLocaleDateString(i18n.language, {
    weekday: "short",
    day: "numeric",
    month: "short",
  });
  const cancelled = (schedule?.requests ?? []).filter(
    (r) => r.status === "rejected" || r.status === "cancelled" || r.expired,
  );
  const docs = schedule?.doctors ?? [];

  return (
    <div className="mb-4 space-y-3">
      <div className="flex items-center gap-2">
        <button type="button" onClick={onPrev} data-testid="today-prev" aria-label={t("common.previous")}
          className="flex size-8 items-center justify-center rounded-lg border border-border text-muted-foreground hover:bg-muted">
          <Icon name="chevron_left" size={18} aria-hidden />
        </button>
        <span className="text-base font-bold text-foreground" data-testid="today-date-title">{title}</span>
        {isToday && (
          <span className="rounded-full bg-info/15 px-2 py-0.5 text-[10px] font-bold uppercase tracking-wide text-info">
            {t("today.todayPill")}
          </span>
        )}
        <button type="button" onClick={onNext} data-testid="today-next" aria-label={t("common.next")}
          className="flex size-8 items-center justify-center rounded-lg border border-border text-muted-foreground hover:bg-muted">
          <Icon name="chevron_right" size={18} aria-hidden />
        </button>
        {!isToday && (
          <button type="button" onClick={onToday} data-testid="today-reset"
            className="ml-1 rounded-full border border-border px-2.5 py-0.5 text-xs font-medium text-muted-foreground hover:bg-muted">
            {t("today.todayPill")}
          </button>
        )}
        {cancelled.length > 0 && (
          <button type="button" onClick={() => setOpenCancelled((v) => !v)} data-testid="today-cancelled-strip"
            className="ml-auto flex items-center gap-1.5 rounded-lg border border-border bg-card px-2.5 py-1 text-xs text-muted-foreground hover:bg-muted">
            <span className="size-1.5 rounded-full bg-destructive" aria-hidden />
            {t("today.notCancelled", { count: cancelled.length })}
            <Icon name="chevron_right" size={14} aria-hidden />
          </button>
        )}
      </div>

      {openCancelled && cancelled.length > 0 && (
        <ul className="rounded-lg border border-border bg-card divide-y divide-border" data-testid="today-cancelled-list">
          {cancelled.map((r) => (
            <li key={r.id} className="flex items-center justify-between px-3 py-2 text-xs">
              <span className="font-medium text-foreground">{r.patient_name}</span>
              <span className="text-muted-foreground">{r.doctor_name} · {t(`requests.status.${r.status}`)}</span>
            </li>
          ))}
        </ul>
      )}

      {docs.length > 1 && (
        <div className="flex flex-wrap items-center gap-2">
          <button type="button" onClick={() => selected.length && selected.forEach(onToggleDoctor)}
            className={`rounded-full px-3 py-1 text-xs ${selected.length === 0 ? "bg-primary-container text-on-primary-container font-semibold" : "border border-border text-muted-foreground"}`}>
            {t("today.allDoctors", { count: docs.length })}
          </button>
          {docs.map((d) => (
            <button key={d.id} type="button" onClick={() => onToggleDoctor(d.id)} data-testid={`today-doc-pill-${d.id}`}
              className={`rounded-full px-3 py-1 text-xs ${selected.includes(d.id) ? "bg-primary-container text-on-primary-container font-semibold" : "border border-border text-muted-foreground"}`}>
              {d.name}
            </button>
          ))}
        </div>
      )}
    </div>
  );
}
```

- [ ] **Step 4: Lift state into the page + filter the grid**

In `src/app/today/page.tsx`: change `date` to mutable state and add doctor-filter state; render `<TodayHeader>` and pass `doctorIds` to `<DayGrid>`:

```typescript
  const [date, setDate] = useState(() => isoDate(new Date()));
  const [selected, setSelected] = useState<string[]>([]);
  const todayStr = isoDate(new Date());
  function step(delta: number) {
    const d = new Date(`${date}T00:00:00`);
    d.setDate(d.getDate() + delta);
    setDate(isoDate(d));
  }
  const toggleDoctor = (id: string) =>
    setSelected((s) => (s.includes(id) ? s.filter((x) => x !== id) : [...s, id]));
```

Render (owner/assistant branch):

```typescript
        <TodayHeader
          schedule={q.data}
          date={date}
          isToday={date === todayStr}
          onPrev={() => step(-1)}
          onNext={() => step(1)}
          onToday={() => setDate(todayStr)}
          selected={selected}
          onToggleDoctor={toggleDoctor}
        />
        {/* …grid… */}
            <DayGrid schedule={q.data} isToday={date === todayStr} clinicId={clinicId} doctorIds={selected} />
```

(Import `TodayHeader`.) Replace `<PageHeader title={t("today.title")} />` with the `<TodayHeader>` (keep `today.title` as the document/section intent — the date title now lives in the header).

In `src/features/today/day-grid.tsx`, accept and apply the filter:

```typescript
export function DayGrid({ schedule, isToday, clinicId, doctorIds }: {
  schedule: Schedule; isToday: boolean; clinicId: string; doctorIds?: string[];
}) {
  // …
  const cols = doctorIds && doctorIds.length > 0
    ? schedule.doctors.filter((d) => doctorIds.includes(d.id))
    : schedule.doctors;
  // replace `schedule.doctors.map((doc) =>` with `cols.map((doc) =>`
```

- [ ] **Step 5: i18n (en + hi)**

Add to the `today` block in `en.json`:

```json
    "todayPill": "Today",
    "allDoctors": "All ({{count}})",
    "notCancelled": "{{count}} not on the schedule",
```

Hindi in `hi.json`: `"todayPill": "आज"`, `"allDoctors": "सभी ({{count}})"`, `"notCancelled": "{{count}} शेड्यूल में नहीं"`. (Confirm `common.previous`/`common.next` exist; if not, add `"previous": "Previous day"` / `"next": "Next day"` to `common` in both.)

- [ ] **Step 6: Run e2e + typecheck + lint**

Run: `npm run test:e2e -- today-header && npx tsc --noEmit && npx eslint src/features/today/today-header.tsx src/features/today/day-grid.tsx src/app/today/page.tsx`
Expected: both header tests PASS; tsc + eslint clean.

- [ ] **Step 7: Commit**

```bash
git add src/features/today/today-header.tsx src/features/today/day-grid.tsx src/app/today/page.tsx src/i18n/locales/en.json src/i18n/locales/hi.json tests/e2e/today-header.spec.ts
git commit -m "feat(today): day stepper + doctor-filter pills + cancelled strip"
```

---

### Task 5: Frontend — `<DayTimeline>` mobile fallback + responsive switch

**Files:**
- Create: `src/features/today/day-timeline.tsx`
- Modify: `src/app/today/page.tsx` (render grid at `lg+`, timeline below `lg`)
- Test: `tests/e2e/today-mobile.spec.ts` (create)

**Interfaces:**
- Consumes: `Schedule`.
- Produces: `<DayTimeline schedule clinicId doctorIds />` with testid `today-timeline`, `tl-appt-{id}`, `tl-req-{id}`.

- [ ] **Step 1: Write the failing e2e test**

Create `tests/e2e/today-mobile.spec.ts`:

```typescript
import { test, expect } from "@playwright/test";
import { CLINIC_ID, installAuth, meWithRole, gotoAuthed } from "./_auth";

test.use({ viewport: { width: 375, height: 740 } }); // phone

function todayAt(hhmm: string) {
  const d = new Date();
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}T${hhmm}:00`;
}
const SCHED = {
  date: todayAt("00:00").slice(0, 10),
  working_window: { start: "09:00:00", end: "17:00:00" },
  doctors: [{ id: "d1", name: "Dr. A", specialty: null, windows: [] }],
  appointments: [{ id: "a1", doctor_id: "d1", patient_id: "p1", patient_name: "Amit", start_datetime: todayAt("10:00"), end_datetime: todayAt("10:30"), status: "confirmed", chief_complaint: null }],
  requests: [],
};

test("mobile shows the timeline, not the grid", async ({ page }) => {
  await installAuth(page, { me: meWithRole("owner") });
  await page.route(`**/api/v1/clinics/${CLINIC_ID}/schedule*`, (r) =>
    r.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(SCHED) }),
  );
  await gotoAuthed(page, "/today", { ready: page.getByTestId("today-page") });
  await expect(page.getByTestId("today-timeline")).toBeVisible();
  await expect(page.getByTestId("today-grid")).toBeHidden();
  await expect(page.getByTestId("tl-appt-a1")).toContainText("Amit");
});
```

- [ ] **Step 2: Run to verify it fails**

Run: `npm run test:e2e -- today-mobile`
Expected: FAIL (`today-timeline` missing; grid not hidden).

- [ ] **Step 3: Create `<DayTimeline>`**

Create `src/features/today/day-timeline.tsx`:

```typescript
"use client";

import Link from "next/link";
import { useTranslation } from "react-i18next";

import { Badge } from "@/components/ui/badge";
import type { Schedule } from "@/features/today/api";

export function DayTimeline({
  schedule,
  doctorIds,
}: {
  schedule: Schedule;
  doctorIds?: string[];
}) {
  const { t, i18n } = useTranslation();
  const inFilter = (docId: string) => !doctorIds || doctorIds.length === 0 || doctorIds.includes(docId);
  const fmt = (iso: string) =>
    new Date(iso).toLocaleTimeString(i18n.language, { hour: "numeric", minute: "2-digit" });

  type Row =
    | { kind: "appt"; id: string; start: string; name: string; doctor_id: string; end: string }
    | { kind: "req"; id: string; start: string; name: string; doctor_id: string; status: string };

  const docName = new Map(schedule.doctors.map((d) => [d.id, d.name]));
  const rows: Row[] = [
    ...schedule.appointments
      .filter((a) => inFilter(a.doctor_id))
      .map((a) => ({ kind: "appt" as const, id: a.id, start: a.start_datetime, name: a.patient_name, doctor_id: a.doctor_id, end: a.end_datetime })),
    ...schedule.requests
      .filter((r) => r.status === "pending" && inFilter(r.doctor_id))
      .map((r) => ({ kind: "req" as const, id: r.id, start: r.start_datetime, name: r.patient_name, doctor_id: r.doctor_id, status: r.status })),
  ].sort((x, y) => x.start.localeCompare(y.start));

  return (
    <div className="space-y-2" data-testid="today-timeline">
      {rows.map((row) =>
        row.kind === "appt" ? (
          <Link key={row.id} href="/patients" data-testid={`tl-appt-${row.id}`}
            className="flex items-center gap-3 rounded-xl border border-l-4 border-border border-l-success bg-success/5 px-3.5 py-2.5">
            <span className="w-[78px] shrink-0 text-[13px] font-semibold text-foreground">{fmt(row.start)}</span>
            <span className="min-w-0 flex-1">
              <span className="block truncate text-[13.5px] font-semibold text-foreground">{row.name}</span>
              <span className="block truncate text-xs text-muted-foreground">{docName.get(row.doctor_id) ?? ""}</span>
            </span>
            <Badge variant="success">{t("requests.status.confirmed")}</Badge>
          </Link>
        ) : (
          <Link key={row.id} href="/requests" data-testid={`tl-req-${row.id}`}
            className="flex items-center gap-3 rounded-xl border border-l-4 border-border border-l-warning bg-warning/5 px-3.5 py-2.5">
            <span className="w-[78px] shrink-0 text-[13px] font-semibold text-foreground">{fmt(row.start)}</span>
            <span className="min-w-0 flex-1">
              <span className="block truncate text-[13.5px] font-semibold text-foreground">{row.name}</span>
              <span className="block truncate text-xs text-muted-foreground">{docName.get(row.doctor_id) ?? ""}</span>
            </span>
            <Badge variant="warning">{t(`requests.status.${row.status}`)}</Badge>
          </Link>
        ),
      )}
    </div>
  );
}
```

- [ ] **Step 4: Responsive switch in the page**

In `src/app/today/page.tsx`, render both, gated by Tailwind breakpoints (grid hidden below `lg`, timeline hidden at `lg+`). Replace the single `<DayGrid …>` render with:

```typescript
            <>
              <div className="hidden lg:block">
                <DayGrid schedule={q.data} isToday={date === todayStr} clinicId={clinicId} doctorIds={selected} />
              </div>
              <div className="lg:hidden">
                <DayTimeline schedule={q.data} doctorIds={selected} />
              </div>
            </>
```

(Import `DayTimeline`.) Both consume the same `q.data`; CSS shows exactly one per viewport.

- [ ] **Step 5: Full e2e sweep + typecheck + lint**

Run: `npm run test:e2e -- today- && npx tsc --noEmit && npx eslint src/features/today/ src/app/today/page.tsx`
Then the whole suite once: `npm run test:e2e`
Expected: all `today-*` specs PASS; full suite green except the pre-existing `patients.spec` (#40/#78) failures (unrelated — do not block).

- [ ] **Step 6: Commit**

```bash
git add src/features/today/day-timeline.tsx src/app/today/page.tsx tests/e2e/today-mobile.spec.ts
git commit -m "feat(today): mobile timeline fallback + responsive grid/timeline switch"
```

---

## Self-Review (against the spec)

**Spec coverage:** §2.1 access owner+assistant → Tasks 1 (endpoint) + 2 (nav/page gate). §2.2/§4.4 proportional grid → Task 3. §2.3 slot-length (start→end sizing) → Task 3 `apptBox`. §2.4 filter pills + horizontal scroll → Task 4 + the grid's `overflow-x-auto`/`min-w-max`/sticky gutter. §2.5 mobile timeline → Task 5. §2.6 continuous 30-min axis + working window → Task 1 (`working_window`) + Task 3 (rows). §2.7 now line (today only) → Task 3 (`showNow`). §2.8 cancelled strip → Task 4. §2.9 day stepper → Task 4. §2.10 tap-through → Tasks 3/5 (Links to /patients, /requests). §5 endpoint → Task 1. §6 matrix → Tasks 1/2. §7 i18n → every FE task adds en+hi. §8 UX/neg → access spec (Task 2), proportional + now (Task 3). §9 tests → each task's TDD.

**Placeholder scan:** none — every step has concrete code/commands. Hindi strings provided and flagged for i18n-owner review (not placeholders). Two judgment notes are explicit: confirm `common.previous/next` exist (Task 4 Step 5); the now-line needs `relative` on the grid container (Task 3 Step 3 note).

**Type/name consistency:** `Schedule`/`ScheduleAppt`/`ScheduleReq`/`DoctorColumn`/`WorkingWindow` defined in Task 2 `api.ts`, consumed unchanged in Tasks 3/4/5. `useTodaySchedule`, `qk.schedule`, `DayGrid({schedule,isToday,clinicId,doctorIds})`, `DayTimeline({schedule,doctorIds})`, `TodayHeader({…})` consistent across tasks. Testids consistent between components and specs (`today-grid`, `appt-{id}`, `req-{id}`, `today-now-line`, `today-next/prev/reset`, `today-doc-pill-{id}`, `today-cancelled-strip`, `today-timeline`, `tl-appt-{id}`).

---

## Release note (post-merge, not implementation)

Ship **backend → frontend**, manual, per `docs/ops/release-playbook.md`. Feature → **minor** (BE + FE). **No migration.** Confirm versions with the user at release time.
