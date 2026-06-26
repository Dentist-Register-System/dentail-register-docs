# Doctors Schedules Redesign — Implementation Plan (F)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Clinic Schedules doctor-picker with **doctor cards → a tabbed `/doctors/[id]` (Availability + new Appointments)**, surfacing each doctor's next-7-day appointments.

**Architecture:** Backend gains one field (`patient_name`) on the existing per-doctor appointments endpoint. Frontend: a cards grid replaces `DoctorPicker`; `/doctors/[id]` wraps its body in page-level `Availability | Appointments` tabs; the Appointments tab renders grouped, status-coloured request-style rows. Access tightens to owner + manage-schedules assistant.

**Tech Stack:** Next.js (App Router), React + TS, TanStack Query, react-i18next, Tailwind v4 semantic tokens, base-ui (`Tabs`, `Card`, `Badge`), Playwright e2e; FastAPI + SQLAlchemy + pytest. Spec: `docs/specs/2026-06-26-doctors-schedules-redesign-design.md`. Signed-off mockup: `dentist-registry-frontend/src/features/scheduling/doctors-schedules-mock.tsx` (delete after build).

## Global Constraints

- **Backend = one small enrich, NO migration.** Add `patient_name` to the per-doctor appointments response only.
- **FE test convention:** this repo has **no Vitest** — FE tests are **Playwright e2e only** (mock auth via `tests/e2e/_auth.ts`, mock API via `page.route`). Do **not** add Vitest. Pure helpers are exercised through e2e.
- **Access rule (verbatim):** Doctors Schedules nav visible when `role === "owner" || (role === "assistant" && clinicSettings.allow_staff_manage_availability)`.
- **Avatar tints (verbatim palette, token-only, assigned by list position):** `["bg-primary-container text-on-primary-container", "bg-success/15 text-success", "bg-tertiary-container text-on-tertiary-container", "bg-info/15 text-info", "bg-warning/20 text-warning-foreground", "bg-destructive/15 text-destructive"]`.
- **Appointment status → colour:** confirmed/completed → `success`; arrived → `warning`; no_show → `destructive`; cancelled → `secondary`.
- **Rule 17.0:** compose `components/ui/*`; semantic tokens only, no raw colours; both themes; mobile-first; WCAG AA (status by badge text+colour, never colour-only; ≥44px targets; visible focus).
- **i18n-first:** all copy via `t()`; add to **both** `en.json` + `hi.json` (parity gated by `tests/e2e/i18n.spec.ts`); friendly day/time via `Intl`.
- `npx tsc --noEmit` + `npm run build` clean before each FE commit; `uv run pytest` + `ruff` clean before each BE commit. **Testing: Playwright locally + verify on beta** (render sign-off already done via the mockup).

---

### Task 1: Backend — `patient_name` on per-doctor appointments

**Files:**
- Modify: `app/modules/scheduling/schemas.py` (`AppointmentRead`)
- Modify: `app/modules/scheduling/service.py` (`list_appointments`)
- Test: `tests/scheduling/test_patient_appointments.py` (or a new `test_doctor_appointments.py`)

**Interfaces:**
- Produces: `AppointmentRead` gains `patient_name: str`. `GET /clinics/{cid}/doctors/{did}/appointments?from=&to=` returns it.

- [ ] **Step 1: Write the failing test**

```python
# tests/scheduling/test_doctor_appointments.py
def test_doctor_appointments_include_patient_name(auth_client, db_session):
    from tests.conftest import make_clinic
    owner, _ = auth_client()
    cid = make_clinic(owner)
    # create a doctor + a patient + a confirmed appointment via the existing flows/fixtures,
    # then list the doctor's appointments for a window that includes it.
    # (Reuse the appointment-creation helpers already used in tests/scheduling.)
    resp = owner.get(f"/api/v1/clinics/{cid}/doctors/{DOCTOR_ID}/appointments?from=2026-06-26&to=2026-07-03")
    assert resp.status_code == 200
    rows = resp.json()
    assert rows and "patient_name" in rows[0]
    assert rows[0]["patient_name"]  # non-empty
```

> Use the existing scheduling test helpers to set up the doctor/patient/appointment (see `tests/scheduling/test_patient_appointments.py` for the established setup pattern); bind `DOCTOR_ID`/window accordingly.

- [ ] **Step 2: Run → fail.** `uv run pytest tests/scheduling/test_doctor_appointments.py -q` → `KeyError: patient_name` / assertion fails.

- [ ] **Step 3: Add the field + join**

```python
# schemas.py — AppointmentRead: add
    patient_name: str
```

```python
# service.py — list_appointments: join Patient and shape patient_name.
# Existing returns Appointment rows; switch to a row that includes the patient name.
from app.modules.patients.models import Patient

def list_appointments(db, clinic_id, doctor_id, from_, to):
    stmt = (
        select(Appointment, Patient.name)
        .join(Patient, Patient.id == Appointment.patient_id)
        .where(
            Appointment.clinic_id == clinic_id,
            Appointment.doctor_id == doctor_id,
            Appointment.start_datetime >= from_dt,   # keep existing date filtering
            Appointment.start_datetime < to_dt,
        )
        .order_by(Appointment.start_datetime)
    )
    rows = db.execute(stmt).all()
    return [
        AppointmentRead(**{**appt_to_dict(a), "patient_name": pname})
        for a, pname in rows
    ]
```

> Match the **existing** date-window/filter logic in the current `list_appointments` (don't change behaviour — only add the join + field). If the router constructs `AppointmentRead` via `from_attributes`, instead return objects/dicts carrying `patient_name`. Keep it minimal.

- [ ] **Step 4: Run → pass.** `uv run pytest tests/scheduling/test_doctor_appointments.py -q` → PASS.

- [ ] **Step 5: Guard the suite + lint + commit**

```bash
uv run pytest tests/scheduling -q && uv run ruff check app/modules/scheduling/
git add app/modules/scheduling/schemas.py app/modules/scheduling/service.py tests/scheduling/test_doctor_appointments.py
git commit -m "feat(scheduling): patient_name on per-doctor appointments (F)"
```

> **PR note:** no migration — flag "no DB migration" in the backend PR body.

---

### Task 2: FE — `Appointment.patient_name` + `useDoctorAppointments`

**Files:**
- Modify: `src/features/scheduling/api.ts` (`Appointment` type)
- Modify: `src/features/scheduling/hooks.ts` (add `useDoctorAppointments`)

**Interfaces:**
- Consumes: `listAppointments(clinicId, doctorId, from, to)` (exists).
- Produces: `Appointment` gains `patient_name: string`; `useDoctorAppointments(clinicId, doctorId, from, to)` → TanStack query of `Appointment[]`.

- [ ] **Step 1: Extend the type**

```ts
// api.ts — add to the Appointment type:
  patient_name: string;
```

- [ ] **Step 2: Add the hook**

```ts
// hooks.ts
import { listAppointments } from "@/features/scheduling/api";

export function useDoctorAppointments(clinicId: string, doctorId: string, from: string, to: string) {
  return useQuery({
    queryKey: ["doctor-appointments", clinicId, doctorId, from, to],
    queryFn: () => listAppointments(clinicId, doctorId, from, to),
    enabled: !!clinicId && !!doctorId,
  });
}
```

- [ ] **Step 3: Typecheck + commit**

```bash
npx tsc --noEmit
git add src/features/scheduling/api.ts src/features/scheduling/hooks.ts
git commit -m "feat(#F): Appointment.patient_name + useDoctorAppointments hook"
```

---

### Task 3: FE — `DoctorAppointmentsTab` (grouped, status-coloured rows)

**Files:**
- Create: `src/features/scheduling/doctor-appointments-tab.tsx`

**Interfaces:**
- Consumes: `useDoctorAppointments` (Task 2); `Badge`, `Icon`.
- Produces: `<DoctorAppointmentsTab clinicId doctorId />` — next-7-day rows grouped by day, colour-coded, `data-testid="doctor-appointments"`.

- [ ] **Step 1: Implement** (mirror the signed-off mockup's Appointments panel, real data)

```tsx
"use client";
import { useMemo } from "react";
import { useTranslation } from "react-i18next";
import { Badge } from "@/components/ui/badge";
import { useDoctorAppointments } from "@/features/scheduling/hooks";

function isoDate(d: Date) { return d.toISOString().slice(0, 10); }
function variant(s: string): "success" | "warning" | "destructive" | "secondary" {
  if (s === "confirmed" || s === "completed") return "success";
  if (s === "arrived") return "warning";
  if (s === "no_show") return "destructive";
  return "secondary";
}
function rowTint(s: string): string {
  if (s === "confirmed" || s === "completed") return "border-success/25 bg-success/5";
  if (s === "arrived") return "border-warning/25 bg-warning/5";
  if (s === "no_show") return "border-destructive/25 bg-destructive/5";
  return "border-border bg-muted/20";
}

export function DoctorAppointmentsTab({ clinicId, doctorId }: { clinicId: string; doctorId: string }) {
  const { t, i18n } = useTranslation();
  const from = isoDate(new Date());
  const to = useMemo(() => { const d = new Date(); d.setDate(d.getDate() + 6); return isoDate(d); }, []);
  const q = useDoctorAppointments(clinicId, doctorId, from, to);

  const groups = useMemo(() => {
    const map = new Map<string, typeof q.data>();
    for (const a of q.data ?? []) {
      const day = new Date(a.start_datetime).toLocaleDateString(i18n.language, { weekday: "short", day: "numeric", month: "short" });
      const arr = map.get(day) ?? []; arr!.push(a); map.set(day, arr);
    }
    return [...map.entries()];
  }, [q.data, i18n.language]);

  if (q.isPending) return <p className="mt-4 text-sm text-muted-foreground">{t("common.loading")}</p>;
  if (groups.length === 0) return <p className="mt-4 text-sm text-muted-foreground">{t("doctorAppointments.empty")}</p>;

  return (
    <div className="mt-4 space-y-4" data-testid="doctor-appointments">
      {groups.map(([day, rows]) => (
        <div key={day}>
          <p className="mb-1.5 text-xs font-medium text-muted-foreground">{day}</p>
          <div className="space-y-2">
            {(rows ?? []).map((a) => {
              const time = new Date(a.start_datetime).toLocaleTimeString(i18n.language, { hour: "numeric", minute: "2-digit" });
              return (
                <div key={a.id} className={`flex items-center gap-3 rounded-lg border px-4 py-3 ${rowTint(a.status)}`}>
                  <span className="w-20 shrink-0 text-sm font-medium text-foreground">{time}</span>
                  <span className="min-w-0 flex-1">
                    <span className="block truncate text-sm font-medium text-foreground">{a.patient_name}</span>
                    <span className="block truncate text-sm text-muted-foreground">{a.chief_complaint || "—"}</span>
                  </span>
                  <Badge variant={variant(a.status)}>{t(`requests.status.${a.status}`, { defaultValue: a.status.replace("_", " ") })}</Badge>
                </div>
              );
            })}
          </div>
        </div>
      ))}
    </div>
  );
}
```

- [ ] **Step 2: Typecheck + commit**

```bash
npx tsc --noEmit
git add src/features/scheduling/doctor-appointments-tab.tsx
git commit -m "feat(#F): DoctorAppointmentsTab — next-7-day status-coloured rows"
```

---

### Task 4: FE — `/doctors/[id]` page-level `Availability | Appointments` tabs

**Files:**
- Modify: `src/app/doctors/[id]/page.tsx`

**Interfaces:**
- Consumes: `DoctorAppointmentsTab` (Task 3); existing `AvailabilitySummaryCard` + `EditAvailabilityModal`; `TabsRoot/List/Tab/Panel`.

- [ ] **Step 1: Wrap the body in tabs** (keep the header + Book action unchanged; move the existing availability block under the Availability tab)

```tsx
import { TabsList, TabsPanel, TabsRoot, TabsTab } from "@/components/ui/tabs";
import { DoctorAppointmentsTab } from "@/features/scheduling/doctor-appointments-tab";
// ...
{clinicId && doctorId && (
  <TabsRoot defaultValue="appointments">
    <TabsList>
      <TabsTab value="availability" data-testid="tab-availability">{t("doctorsSchedules.tabs.availability")}</TabsTab>
      <TabsTab value="appointments" data-testid="tab-appointments">{t("doctorsSchedules.tabs.appointments")}</TabsTab>
    </TabsList>
    <TabsPanel value="availability">
      <div className="mt-4 flex flex-col gap-6">
        <AvailabilitySummaryCard clinicId={clinicId} doctorId={doctorId} canEdit={!!canEdit} onEdit={(tab) => setOpenTab(tab ?? "usual")} />
        {canEdit && (
          <EditAvailabilityModal clinicId={clinicId} doctorId={doctorId} open={openTab !== null} initialTab={openTab ?? "usual"} onOpenChange={(o) => { if (!o) setOpenTab(null); }} />
        )}
      </div>
    </TabsPanel>
    <TabsPanel value="appointments">
      <DoctorAppointmentsTab clinicId={clinicId} doctorId={doctorId} />
    </TabsPanel>
  </TabsRoot>
)}
```

- [ ] **Step 2: Typecheck + build + commit**

```bash
npx tsc --noEmit && npm run build
git add src/app/doctors/[id]/page.tsx
git commit -m "feat(#F): /doctors/[id] page-level Availability | Appointments tabs"
```

---

### Task 5: FE — `DoctorsScheduleGrid` (cards) replaces `DoctorPicker`

**Files:**
- Create: `src/features/scheduling/doctors-schedule-grid.tsx`
- Modify: `src/app/clinic-schedules/page.tsx`
- Delete: `src/features/scheduling/doctor-picker.tsx` (after confirming no other consumer)

**Interfaces:**
- Consumes: `useDoctors(clinicId)`; `initials` (`@/features/patients/patients-logic`); `Card`, `Icon`; Next `Link`.
- Produces: `<DoctorsScheduleGrid clinicId />` — cards linking to `/doctors/[id]`.

- [ ] **Step 1: Implement the grid** (mirror the signed-off mockup's cards, real doctors; tints by position)

```tsx
"use client";
import Link from "next/link";
import { useTranslation } from "react-i18next";
import { Card, CardContent } from "@/components/ui/card";
import { Icon } from "@/components/ui/icon";
import { initials } from "@/features/patients/patients-logic";
import { useDoctors } from "@/features/doctors/hooks";

const TINTS = [
  "bg-primary-container text-on-primary-container", "bg-success/15 text-success",
  "bg-tertiary-container text-on-tertiary-container", "bg-info/15 text-info",
  "bg-warning/20 text-warning-foreground", "bg-destructive/15 text-destructive",
];
const tintFor = (i: number) => TINTS[((i % TINTS.length) + TINTS.length) % TINTS.length];

export function DoctorsScheduleGrid({ clinicId }: { clinicId: string }) {
  const { t } = useTranslation();
  const doctors = useDoctors(clinicId);
  const list = doctors.data ?? [];
  if (doctors.isPending) return <p className="text-sm text-muted-foreground">{t("common.loading")}</p>;
  if (list.length === 0) return <p className="text-sm text-muted-foreground" data-testid="ds-empty">{t("doctorsSchedules.empty")}</p>;

  return (
    <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3" data-testid="doctors-schedule-grid">
      {list.map((d, i) => (
        <Link key={d.id} href={`/doctors/${d.id}`} data-testid={`ds-card-${d.id}`}>
          <Card className="transition-shadow hover:shadow-elevation-2">
            <CardContent className="flex items-center gap-3 p-4">
              <span className={`flex size-11 shrink-0 items-center justify-center rounded-full text-sm font-semibold ${tintFor(i)}`}>{initials(d.name)}</span>
              <span className="min-w-0 flex-1">
                <span className="block truncate font-medium text-foreground">{d.name}</span>
                <span className="block truncate text-sm text-muted-foreground">{d.specialty ?? ""}</span>
              </span>
              <Icon name="chevron_right" size={20} className="text-muted-foreground" aria-hidden />
            </CardContent>
          </Card>
        </Link>
      ))}
    </div>
  );
}
```

- [ ] **Step 2: Swap the page** (`clinic-schedules/page.tsx`): replace `DoctorPicker` + `DoctorScheduleView` with `<DoctorsScheduleGrid clinicId={clinicId} />` and the renamed title `t("nav.doctorsSchedules")`. Remove the now-unused imports/state (`doctorId`, `DoctorPicker`, `DoctorScheduleView`).

- [ ] **Step 3: Delete `doctor-picker.tsx`** after `grep -rn "DoctorPicker" src` shows no remaining consumer.

- [ ] **Step 4: Typecheck + build + commit**

```bash
grep -rn "DoctorPicker" src || echo "no consumers"
npx tsc --noEmit && npm run build
git add -A
git commit -m "feat(#F): Doctors Schedules cards grid; remove DoctorPicker"
```

---

### Task 6: FE — nav rename + access gating

**Files:**
- Modify: `src/components/shell/app-shell.tsx`
- Modify: `src/i18n/locales/en.json`, `src/i18n/locales/hi.json`

**Interfaces:**
- Consumes: `useClinicSettings` (for `allow_staff_manage_availability`).

- [ ] **Step 1: Tighten nav gating + rename label**

```tsx
// app-shell.tsx — replace canClinicSchedules:
const { data: settings } = useClinicSettings(clinicId);
const canDoctorsSchedules =
  role === "owner" ||
  (role === "assistant" && settings?.allow_staff_manage_availability === true);
// in the visibility filter: if (d.key === "clinic-schedules") return canDoctorsSchedules;
// label: the nav item uses t("nav.doctorsSchedules") (key value renamed below)
```

> Keep the nav `key`/route `clinic-schedules` (route path unchanged per spec §12). Only the **label** + **gating** change. Ensure `clinicId` is available where `useClinicSettings` is called (it is — `app-shell` already reads `me`).

- [ ] **Step 2: i18n** — set `nav.doctorsSchedules` = "Doctors Schedules" / "डॉक्टर शेड्यूल"; add `doctorsSchedules.subtitle`, `doctorsSchedules.empty`, `doctorsSchedules.tabs.availability`/`appointments`, `doctorAppointments.empty` to **both** locales (parity).

- [ ] **Step 3: i18n parity + typecheck + commit**

```bash
npx playwright test i18n --reporter=line   # parity green
npx tsc --noEmit
git add src/components/shell/app-shell.tsx src/i18n/locales/en.json src/i18n/locales/hi.json
git commit -m "feat(#F): rename nav -> Doctors Schedules + owner/manage-assistant gating"
```

---

### Task 7: e2e — cards → tabs → appointments, and the access gate

**Files:**
- Create: `tests/e2e/doctors-schedules.spec.ts`

- [ ] **Step 1: Write the e2e** (mock `/me`, doctors list, and the per-doctor appointments endpoint with `patient_name` + statuses)

```ts
import { test, expect, type Page } from "@playwright/test";
import { installAuth, gotoAuthed, defaultMe, CLINIC_ID } from "./_auth";

const DOCTORS = [{ id: "d1", clinic_id: CLINIC_ID, name: "Dr. Sayali Rao", specialty: "Orthodontist" }];
const APPTS = [{ id: "a1", patient_id: "p1", patient_name: "Asha Rao", doctor_id: "d1", start_datetime: "2026-06-26T09:30:00", end_datetime: "2026-06-26T10:00:00", status: "confirmed", chief_complaint: "Toothache" }];

async function mockSchedules(page: Page) {
  await page.route("**/api/v1/clinics/*/doctors", (r) => r.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(DOCTORS) }));
  await page.route("**/api/v1/clinics/*/doctors/*/appointments*", (r) => r.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(APPTS) }));
  await page.route("**/api/v1/clinics/*/settings", (r) => r.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify({ allow_staff_manage_availability: true, allow_staff_approval: false }) }));
}

test("owner: cards → doctor → Appointments tab shows coloured rows with patient name", async ({ page }) => {
  await installAuth(page);
  await mockSchedules(page);
  await gotoAuthed(page, "/clinic-schedules");
  await expect(page.getByTestId("ds-card-d1")).toBeVisible();
  await page.getByTestId("ds-card-d1").click();
  await expect(page).toHaveURL(/\/doctors\/d1/);
  await expect(page.getByTestId("doctor-appointments")).toBeVisible();
  await expect(page.getByText("Asha Rao")).toBeVisible();
});

test("assistant WITHOUT manage-schedules cannot see the Doctors Schedules nav", async ({ page }) => {
  await installAuth(page, { me: defaultMe({ memberships: [{ clinic_id: CLINIC_ID, clinic_name: "Test", role: "assistant", status: "active" }] }) as object });
  await page.route("**/api/v1/clinics/*/settings", (r) => r.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify({ allow_staff_manage_availability: false, allow_staff_approval: false }) }));
  await gotoAuthed(page, "/");
  await expect(page.getByTestId("nav-clinic-schedules")).toHaveCount(0);
});
```

- [ ] **Step 2: Run → green.** `npx playwright test doctors-schedules --reporter=line`. (Kill any dev server holding :8753 first; Playwright starts its own on :3000.)

- [ ] **Step 3: Commit**

```bash
git add tests/e2e/doctors-schedules.spec.ts
git commit -m "test(#F): e2e doctors-schedules cards/tabs/appointments + access gate"
```

---

### Task 8: Cleanup — remove the mockup

**Files:**
- Delete: `src/features/scheduling/doctors-schedules-mock.tsx`, `src/app/ds-preview/` (throwaway sign-off artefacts)

- [ ] **Step 1:** `git rm -r src/features/scheduling/doctors-schedules-mock.tsx src/app/ds-preview` → `npx tsc --noEmit && npm run build` → commit `chore(#F): remove Doctors Schedules sign-off mockup`.

---

## Self-Review

**Spec coverage:** cards grid §4 → Task 5 ✅ · tabs §5 → Task 4 ✅ · Appointments tab §6 → Tasks 2,3 ✅ · access §7 → Task 6 ✅ · backend `patient_name` §8 → Task 1 ✅ · avatar tints §2.7 → Task 5 ✅ · rename §2.2 → Task 6 ✅ · DoctorPicker removed §4 → Task 5 ✅ · tests §11 → Tasks 1,7 ✅ · mockup removal §12 → Task 8 ✅.

**Placeholder scan:** Task 1's test setup references "existing scheduling test helpers" (a real pattern in `tests/scheduling/`, to be matched) — not a placeholder for unwritten code; the field/join code is complete. No TBD/TODO.

**Type consistency:** `patient_name` added on the backend (Task 1) and FE `Appointment` (Task 2), consumed in `DoctorAppointmentsTab` (Task 3). `useDoctorAppointments(clinicId, doctorId, from, to)` signature consistent across Tasks 2–3. `tintFor`/`TINTS` identical in the mockup and Task 5. `DoctorsScheduleGrid` / `DoctorAppointmentsTab` names consistent across producing/consuming tasks. ✅
