# Owner-Doctor Self-Profile + Schedule Nav Split (Slice 1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a clinic member create their own active doctor profile (no invite) so an owner becomes an owner-doctor who appears in doctor lists, is bookable, and can approve their own requests; and split scheduling into **My Schedule** (own, no picker) vs **Clinic Schedules** (admin, M3 doctor picker).

**Architecture:** Backend adds a self doctor-profile endpoint (`POST …/doctors/me`), exposes `me.doctor_id`, and fixes approve/reject authz to key off the *linked* doctor rather than `membership.role`. Frontend restructures the single "Schedule" destination into role/profile-aware **My Schedule** + **Clinic Schedules** built on a shared `DoctorScheduleView`, adds an M3 `DoctorPicker` (replacing the native dropdown) + a self doctor-profile dialog + a dismissable "create your profile" banner, and converts the day-of-week `<select>` to the existing M3 Segmented control.

**Tech Stack:** Backend — FastAPI, SQLAlchemy 2.x, Pydantic v2, pytest (Postgres :5433). Frontend — Next.js App Router (client components), TanStack Query, react-i18next, Tailwind v4 semantic tokens, Playwright (i18n + pure-logic; tsc + build are the CI gates).

**Spec:** `docs/specs/2026-06-20-owner-doctor-self-profile-nav-split-design.md` (issue #49).

## Global Constraints

- **No new migration expected** — `doctor_beta` already has `linked_user_id`/`status`/`name`/`phone`/`email`/`specialty`. (If, against expectation, a column is needed, follow the offline-SQL → MCP `apply_migration` controller process; implementers validate via `make test` only and NEVER run `make migrate`/alembic against Supabase.)
- **Core model:** doctor-ness = a `doctor_beta` row with `linked_user_id == user`, independent of `clinic_member.role`. A self doctor-profile is `status='active'`, `linked_user_id=caller`, **no `clinic_invite`**, and does NOT change the caller's `clinic_member.role`. **One self-profile per user per clinic** → 409 `conflict`.
- **Authz:** approve/reject allowed iff `get_doctor(clinic, request.doctor_id).linked_user_id == membership.user_id` (drop the `role == doctor` requirement). Self doctor-profile: any **active member** may create **their own**. Reads unchanged.
- **Nav visibility:** My Schedule iff `me.doctor_id`; Clinic Schedules iff role ∈ {owner, practice_manager, assistant}. Replaces the existing single "schedule" destination.
- **No traditional dropdowns** for non-trivial selection — the doctor picker is an M3 search/modal picker; day-of-week uses the existing M3 `SegmentedButton`. (Permanent rule.)
- `_beta` suffix; uniform error envelope + stable codes (`conflict`, `forbidden`, `validation_error`); audit in-transaction; permissive-OSS only; **no new dependencies**.
- **Frontend Rule 17.0:** semantic tokens only (no raw colours / `bg-white` / `text-gray-*`), compose `components/ui/*` + `components/layout/*`, no per-page CSS, both themes, mobile-first, a11y. **i18n-first:** every user-facing string via `t()`, in BOTH `en.json` + `hi.json` (parity enforced by `tests/e2e/i18n.spec.ts`).
- **Next.js caveat (`AGENTS.md`):** breaking changes; client components; `useParams()` for route params; consult `node_modules/next/dist/docs/` if surprised.
- Backend repo `dentist-registry-backend`; frontend `dentist-registry-frontend`. Commit trailer `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`. Feature branch → PR.

---

## File Structure

**Backend**
- Modify: `app/modules/doctors/schemas.py` (`DoctorSelfCreate`), `service.py` (`create_self_doctor`, `get_my_doctor`), `router.py` (`POST …/doctors/me`).
- Modify: `app/modules/scheduling/booking.py` (`authorize_decide`).
- Modify: `app/modules/auth/router.py` + `schemas.py` (`me.doctor_id`).
- Test: `tests/doctors/test_self_profile.py`, `tests/scheduling/test_approval.py` (extend), `tests/auth/test_me.py` (extend or new).

**Frontend**
- Modify: `src/features/doctors/api.ts` (`createSelfDoctor`), `src/features/doctors/hooks.ts` (`useCreateSelfDoctor`), `src/features/clinic/api.ts` (`Me.doctor_id`).
- Modify: `src/components/shell/destinations.ts` (replace `schedule`), `src/components/shell/app-shell.tsx` (role/profile nav filtering).
- Create: `src/features/scheduling/doctor-picker.tsx`, `src/features/scheduling/doctor-schedule-view.tsx`, `src/features/doctors/doctor-profile-dialog.tsx`, `src/features/doctors/create-profile-banner.tsx`.
- Modify: `src/features/scheduling/slot-viewer.tsx` (`bookable` prop), `src/features/scheduling/availability-editor.tsx` (Segmented day-of-week).
- Create: `src/app/my-schedule/page.tsx`, `src/app/clinic-schedules/page.tsx`. Delete: `src/app/schedule/page.tsx`.
- Modify: `src/app/page.tsx` (banner), `src/i18n/locales/en.json` + `hi.json`.

**Docs** (`dentail-register-docs`)
- Modify: `PRD/PRD_v3_1_Founder_Edition.md`, `Entities/01-clinic.md`, `Entities/03-user.md`, `Entities/04-doctor.md`, plus a Golden Rules / design-system note.

---

## Task 1: Backend — self doctor-profile (`POST …/doctors/me`)

**Files:** Modify `app/modules/doctors/schemas.py`, `service.py`, `router.py`; Test `tests/doctors/test_self_profile.py`.

**Interfaces:**
- Consumes: `Doctor`/`DoctorStatus` models, `DoctorRead`, `record_audit`, `ConflictError`, `CurrentMembership`.
- Produces: `DoctorSelfCreate`; `create_self_doctor(db, *, clinic_id, user_id, data) -> Doctor`; `get_my_doctor(db, clinic_id, user_id) -> Doctor | None`; `POST /clinics/{clinic_id}/doctors/me`.

- [ ] **Step 1: Write failing tests**

Create `tests/doctors/test_self_profile.py`:

```python
from tests.conftest import make_clinic

OWNER = "11111111-1111-1111-1111-111111111111"


def test_owner_creates_own_doctor_profile(auth_client):
    c, _ = auth_client(sub=OWNER)
    clinic = make_clinic(c, name="C")
    r = c.post(f"/api/v1/clinics/{clinic}/doctors/me",
               json={"name": "Dr. Sayali", "phone": "+91 90000 00000", "specialty": "Dentist"})
    assert r.status_code == 201, r.text
    body = r.json()
    assert body["status"] == "active"
    assert body["linked_user_id"] is not None
    # appears in the doctor list
    docs = c.get(f"/api/v1/clinics/{clinic}/doctors").json()
    assert any(d["id"] == body["id"] for d in docs)


def test_second_self_profile_conflicts(auth_client):
    c, _ = auth_client(sub=OWNER)
    clinic = make_clinic(c, name="C")
    payload = {"name": "Dr. A", "phone": "+91 90000 00000"}
    assert c.post(f"/api/v1/clinics/{clinic}/doctors/me", json=payload).status_code == 201
    r2 = c.post(f"/api/v1/clinics/{clinic}/doctors/me", json=payload)
    assert r2.status_code == 409
    assert r2.json()["error"]["code"] == "conflict"


def test_self_profile_requires_membership(auth_client):
    c, _ = auth_client(sub=OWNER)
    clinic = make_clinic(c, name="C")
    outsider, _ = auth_client(sub="44444444-4444-4444-4444-444444444444")
    assert outsider.post(f"/api/v1/clinics/{clinic}/doctors/me",
                         json={"name": "X", "phone": "+91 90000 00000"}).status_code == 403
```

- [ ] **Step 2: Run → fail** (`.venv/bin/pytest tests/doctors/test_self_profile.py -v`).

- [ ] **Step 3: Schema** — add to `app/modules/doctors/schemas.py`:

```python
class DoctorSelfCreate(BaseModel):
    name: str = Field(min_length=1, max_length=200)
    phone: str = Field(min_length=1, max_length=32)
    specialty: str | None = Field(default=None, max_length=200)
```
(Add `Field` to the pydantic import: `from pydantic import BaseModel, ConfigDict, Field`.)

- [ ] **Step 4: Service** — add to `app/modules/doctors/service.py` (import `ConflictError` from `app.core.errors`, and `DoctorSelfCreate` from schemas):

```python
def get_my_doctor(db: Session, clinic_id: uuid.UUID, user_id: uuid.UUID) -> Doctor | None:
    return db.execute(
        select(Doctor).where(
            Doctor.clinic_id == clinic_id, Doctor.linked_user_id == user_id
        )
    ).scalar_one_or_none()


def create_self_doctor(
    db: Session, *, clinic_id: uuid.UUID, user_id: uuid.UUID, data: DoctorSelfCreate
) -> Doctor:
    existing = get_my_doctor(db, clinic_id, user_id)
    if existing is not None:
        raise ConflictError("You already have a doctor profile in this clinic.")
    doctor = Doctor(
        clinic_id=clinic_id,
        linked_user_id=user_id,
        name=data.name,
        phone=data.phone,
        specialty=data.specialty,
        status=DoctorStatus.active,
        created_by=user_id,
    )
    db.add(doctor)
    db.flush()
    record_audit(
        db, action="doctor.created", entity_type="doctor", entity_id=doctor.id,
        clinic_id=clinic_id, actor_user_id=user_id,
        new={"name": doctor.name, "specialty": doctor.specialty, "self_profile": True},
    )
    db.commit()
    db.refresh(doctor)
    return doctor
```
(Confirm `DoctorStatus.active` exists — the enum has `invited`/`active` per SP2. If the active value name differs, use the actual member.)

- [ ] **Step 5: Route** — add to `app/modules/doctors/router.py` (import `DoctorSelfCreate`, `CurrentMembership`):

```python
@router.post(
    "/{clinic_id}/doctors/me",
    response_model=DoctorRead,
    status_code=status.HTTP_201_CREATED,
)
def create_self_doctor(
    clinic_id: uuid.UUID,
    data: DoctorSelfCreate,
    db: DbSession,
    membership: CurrentMembership,
):
    return service.create_self_doctor(
        db, clinic_id=clinic_id, user_id=membership.user_id, data=data
    )
```
> Route ordering: declare `/{clinic_id}/doctors/me` — `me` is a literal and the existing `GET /{clinic_id}/doctors/{doctor_id}` types `doctor_id` as `uuid.UUID`, so `me` cannot be captured by it. The POST method + literal segment is unambiguous.

- [ ] **Step 6: Run tests + full suite + lint** — `.venv/bin/pytest tests/doctors/test_self_profile.py -v && make test && make lint` → pass.

- [ ] **Step 7: Commit**
```bash
git add app/modules/doctors/ tests/doctors/test_self_profile.py
git commit -m "feat(doctors): self doctor-profile endpoint (active, linked, no invite)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: Backend — `/me.doctor_id` + approve/reject authz fix

**Files:** Modify `app/modules/auth/schemas.py`, `app/modules/auth/router.py`, `app/modules/scheduling/booking.py`; Test `tests/auth/test_me.py` (new), `tests/scheduling/test_approval.py` (extend).

**Interfaces:**
- Consumes: `doctors.service.get_my_doctor` (Task 1).
- Produces: `MeRead.doctor_id`; updated `authorize_decide`.

- [ ] **Step 1: Failing tests**

Create `tests/auth/test_me.py`:
```python
from tests.conftest import make_clinic

OWNER = "11111111-1111-1111-1111-111111111111"


def test_me_doctor_id_null_then_set(auth_client):
    c, _ = auth_client(sub=OWNER)
    clinic = make_clinic(c, name="C")
    assert c.get("/api/v1/me").json()["doctor_id"] is None
    did = c.post(f"/api/v1/clinics/{clinic}/doctors/me",
                 json={"name": "Dr. A", "phone": "+91 90000 00000"}).json()["id"]
    assert c.get("/api/v1/me").json()["doctor_id"] == did
```

Append to `tests/scheduling/test_approval.py` (owner-doctor can approve their own request via HTTP):
```python
def test_owner_doctor_approves_own_request(auth_client):
    c, _ = auth_client(sub=OWNER)
    clinic = make_clinic(c, name="C")
    doc = c.post(f"/api/v1/clinics/{clinic}/doctors/me",
                 json={"name": "Dr. A", "phone": "+91 90000 00000"}).json()["id"]
    pat = c.post(f"/api/v1/clinics/{clinic}/patients",
                 json={"name": "P", "phone": "+91 98888 00000", "age": 30}).json()["id"]
    c.post(f"/api/v1/clinics/{clinic}/doctors/{doc}/availability",
           json={"kind": "recurring", "day_of_week": 0, "start_time": "09:00", "end_time": "10:00"})
    rid = c.post(f"/api/v1/clinics/{clinic}/doctors/{doc}/appointment-requests",
                 json={"patient_id": pat, "start_datetime": "2026-06-22T09:00:00"}).json()["id"]
    # owner (membership role=owner) is linked to this doctor -> may approve
    assert c.post(f"/api/v1/clinics/{clinic}/appointment-requests/{rid}/approve").status_code == 200
```

- [ ] **Step 2: Run → fail.**

- [ ] **Step 3: `MeRead.doctor_id`** — in `app/modules/auth/schemas.py` add to `MeRead`:
```python
    doctor_id: uuid.UUID | None = None
```

- [ ] **Step 4: Populate it in `/me`** — in `app/modules/auth/router.py`, import `from app.modules.doctors.service import get_my_doctor`, and compute the linked doctor for the first active clinic:
```python
    doctor_id = None
    if memberships:
        my_doctor = get_my_doctor(db, memberships[0].clinic_id, user.id)
        doctor_id = my_doctor.id if my_doctor else None
    return MeRead(
        user_id=user.id, email=user.email, phone=user.phone,
        needs_onboarding=len(memberships) == 0, memberships=memberships,
        doctor_id=doctor_id,
    )
```
(`memberships[0].clinic_id` — `MembershipRead.clinic_id` is a UUID; correct. Import is auth→doctors which respects the inward dependency rule, same as the existing auth→clinics import.)

- [ ] **Step 5: Authz fix** — in `app/modules/scheduling/booking.py`, change `authorize_decide`:
```python
def authorize_decide(
    db: Session, *, clinic_id: uuid.UUID, request: AppointmentRequest, membership: ClinicMember
) -> None:
    """Only the doctor LINKED to the request's doctor may approve/reject (any member role)."""
    doctor = get_doctor(db, clinic_id, request.doctor_id)
    if doctor.linked_user_id != membership.user_id:
        raise ForbiddenError("Only the assigned doctor may approve or reject this request.")
```
(Removes the `membership.role == MemberRole.doctor` condition. `MemberRole` may now be unused in this file — remove the import if so to keep lint clean.)

- [ ] **Step 6: Run tests + full suite + lint** → pass. (The existing `test_owner_cannot_approve` from SP3.2 expected a 403 because the owner was NOT linked to the doctor; it remains valid — that owner has no linked doctor. Confirm it still passes; if that test created a doctor via the invite path and asserted owner-403, it still holds since the owner isn't linked.)

- [ ] **Step 7: Commit**
```bash
git add app/modules/auth/ app/modules/scheduling/booking.py tests/auth/test_me.py tests/scheduling/test_approval.py
git commit -m "feat(auth/scheduling): /me.doctor_id + approve-reject by linked doctor

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

> No Supabase migration in this slice (no schema change).

---

## Task 3: Frontend — self-profile api/hook + `Me.doctor_id`

**Files:** Modify `src/features/doctors/api.ts`, `src/features/doctors/hooks.ts`, `src/features/clinic/api.ts`.

- [ ] **Step 1: API + Me type** — in `src/features/doctors/api.ts` add:
```typescript
export const createSelfDoctor = (
  clinicId: string,
  payload: { name: string; phone: string; specialty?: string },
) => apiFetch<Doctor>(`/api/v1/clinics/${clinicId}/doctors/me`, {
  method: "POST",
  body: JSON.stringify(payload),
});
```
In `src/features/clinic/api.ts`, add `doctor_id` to the `Me` type:
```typescript
export type Me = {
  user_id: string | null;
  email: string | null;
  phone: string | null;
  doctor_id: string | null;
  needs_onboarding: boolean;
  memberships: Membership[];
};
```

- [ ] **Step 2: Hook** — in `src/features/doctors/hooks.ts` add (match the file's existing imports):
```typescript
export function useCreateSelfDoctor(clinicId: string) {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (p: Parameters<typeof createSelfDoctor>[1]) => createSelfDoctor(clinicId, p),
    onSuccess: () => {
      void qc.invalidateQueries({ queryKey: ["me"] });
      void qc.invalidateQueries({ queryKey: ["doctors", clinicId] });
    },
  });
}
```
(Import `createSelfDoctor` from `@/features/doctors/api`; ensure `useMutation`/`useQueryClient` are imported — add if missing.)

- [ ] **Step 3: tsc + commit**
```bash
cd dentist-registry-frontend && npx tsc --noEmit
git add src/features/doctors/api.ts src/features/doctors/hooks.ts src/features/clinic/api.ts
git commit -m "feat(doctors): self-profile api/hook + Me.doctor_id type

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: Frontend — i18n keys + nav destinations + role-aware filtering

**Files:** Modify `src/i18n/locales/en.json`, `hi.json`, `src/components/shell/destinations.ts`, `src/components/shell/app-shell.tsx`.

- [ ] **Step 1: Destinations** — in `src/components/shell/destinations.ts`, REPLACE the single `schedule` entry with two, keeping order Home → My Schedule → Clinic Schedules → Requests → Doctors → …:
```typescript
  {
    key: "my-schedule",
    labelKey: "nav.mySchedule",
    icon: "event_available",
    href: "/my-schedule",
  },
  {
    key: "clinic-schedules",
    labelKey: "nav.clinicSchedules",
    icon: "calendar_month",
    href: "/clinic-schedules",
  },
```

- [ ] **Step 2: Role/profile-aware filtering** — in `src/components/shell/app-shell.tsx`, the component already has `me` and `clinicId`. Compute visibility and filter BOTH `destinations.map(...)` sites. Add near the top of the component body:
```tsx
  const role = me.data?.memberships[0]?.role ?? "";
  const hasDoctorProfile = !!me.data?.doctor_id;
  const canClinicSchedules = role === "owner" || role === "practice_manager" || role === "assistant";
  const visibleDestinations = destinations.filter((d) => {
    if (d.key === "my-schedule") return hasDoctorProfile;
    if (d.key === "clinic-schedules") return canClinicSchedules;
    return true;
  });
```
Then change BOTH `destinations.map((dest) => {` occurrences to `visibleDestinations.map((dest) => {`.

- [ ] **Step 3: i18n (en)** — in `nav` add `"mySchedule": "My Schedule"`, `"clinicSchedules": "Clinic Schedules"` (remove the old `"schedule"` key). Add a `doctorProfile` block + `daysShort`:
```json
  "doctorProfile": {
    "bannerQuestion": "Are you a practicing doctor?",
    "bannerBody": "Create your doctor profile to start scheduling.",
    "bannerCta": "Set up profile",
    "dismiss": "Dismiss",
    "createTitle": "Create your doctor profile",
    "nameLabel": "Your name",
    "namePlaceholder": "Dr. Sayali Joshi",
    "phoneLabel": "Your phone",
    "specialtyLabel": "Specialty",
    "submit": "Create profile",
    "exists": "You already have a doctor profile.",
    "pickDoctor": "Choose a doctor",
    "change": "Change",
    "viewing": "Viewing"
  },
```
Add `daysShort` to the existing `scheduling` block:
```json
    "daysShort": { "0": "Mon", "1": "Tue", "2": "Wed", "3": "Thu", "4": "Fri", "5": "Sat", "6": "Sun" },
```

- [ ] **Step 4: i18n (hi)** — mirror with Hindi values; remove old `nav.schedule`:
`nav.mySchedule` = `"मेरा शेड्यूल"`, `nav.clinicSchedules` = `"क्लिनिक शेड्यूल"`. `doctorProfile`:
```json
  "doctorProfile": {
    "bannerQuestion": "क्या आप एक प्रैक्टिसिंग डॉक्टर हैं?",
    "bannerBody": "शेड्यूलिंग शुरू करने के लिए अपनी डॉक्टर प्रोफ़ाइल बनाएँ।",
    "bannerCta": "प्रोफ़ाइल बनाएँ",
    "dismiss": "खारिज करें",
    "createTitle": "अपनी डॉक्टर प्रोफ़ाइल बनाएँ",
    "nameLabel": "आपका नाम",
    "namePlaceholder": "डॉ. सयाली जोशी",
    "phoneLabel": "आपका फ़ोन",
    "specialtyLabel": "विशेषज्ञता",
    "submit": "प्रोफ़ाइल बनाएँ",
    "exists": "आपके पास पहले से डॉक्टर प्रोफ़ाइल है।",
    "pickDoctor": "डॉक्टर चुनें",
    "change": "बदलें",
    "viewing": "देख रहे हैं"
  },
```
`scheduling.daysShort` = `{ "0": "सोम", "1": "मंगल", "2": "बुध", "3": "गुरु", "4": "शुक्र", "5": "शनि", "6": "रवि" }`.

> Removing `nav.schedule` from both files keeps parity. Grep the codebase for `nav.schedule` first and ensure no component still references it (the old `/schedule` page is deleted in Task 6; if any reference remains at this point it's the destinations entry you just replaced).

- [ ] **Step 5: Verify** — `npx playwright test tests/e2e/i18n.spec.ts` (or node parity) + `npx tsc --noEmit` + `npm run build`. (Build will still include the old `/schedule` until Task 6; that's fine — nav no longer links to it.)

- [ ] **Step 6: Commit**
```bash
git add src/i18n/locales/ src/components/shell/destinations.ts src/components/shell/app-shell.tsx
git commit -m "feat(nav): My Schedule / Clinic Schedules destinations + role-aware filtering + i18n

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: Frontend — DoctorPicker + DoctorScheduleView (+ SlotViewer bookable prop)

**Files:** Create `src/features/scheduling/doctor-picker.tsx`, `src/features/scheduling/doctor-schedule-view.tsx`; Modify `src/features/scheduling/slot-viewer.tsx`.

**Interfaces:**
- Consumes: `useDoctors` (`@/features/doctors/hooks`), `AvailabilityEditor`, `SlotViewer`.
- Produces: `DoctorPicker({clinicId, value, onChange})`; `DoctorScheduleView({clinicId, doctorId, canManage, bookable})`; `SlotViewer` gains `bookable?: boolean` (default true).

- [ ] **Step 1: SlotViewer `bookable` prop** — in `src/features/scheduling/slot-viewer.tsx`, add `bookable` to the props (default `true`); when `bookable === false`, render available slots as a non-interactive chip (same look as the full chip but showing the time) instead of `<RequestDialog>`. Keep occupancy display. (Minimal change: gate the `<RequestDialog>` branch on `bookable`.)

- [ ] **Step 2: DoctorPicker** — create `src/features/scheduling/doctor-picker.tsx` (M3 modal/search picker — NOT a `<select>`):
```tsx
"use client";

import { useState } from "react";
import { useTranslation } from "react-i18next";

import { buttonVariants } from "@/components/ui/button";
import { DialogPopup, DialogRoot, DialogTitle, DialogTrigger } from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { useDoctors } from "@/features/doctors/hooks";

interface DoctorPickerProps {
  clinicId: string;
  value: string;
  onChange: (doctorId: string) => void;
}

export function DoctorPicker({ clinicId, value, onChange }: DoctorPickerProps) {
  const { t } = useTranslation();
  const [open, setOpen] = useState(false);
  const [q, setQ] = useState("");
  const doctors = useDoctors(clinicId);
  const selected = (doctors.data ?? []).find((d) => d.id === value);
  const filtered = (doctors.data ?? []).filter((d) =>
    d.name.toLowerCase().includes(q.toLowerCase()),
  );

  return (
    <DialogRoot open={open} onOpenChange={setOpen}>
      <div className="flex items-center gap-2">
        <span className="text-sm text-muted-foreground">
          {t("doctorProfile.viewing")}:{" "}
          <span className="font-medium text-foreground" data-testid="picker-current">
            {selected ? selected.name : t("doctorProfile.pickDoctor")}
          </span>
        </span>
        <DialogTrigger className={buttonVariants({ variant: "outlined", size: "sm" })} data-testid="doctor-picker-change">
          {t("doctorProfile.change")}
        </DialogTrigger>
      </div>
      <DialogPopup>
        <DialogTitle>{t("doctorProfile.pickDoctor")}</DialogTitle>
        <Input value={q} onChange={(e) => setQ(e.target.value)} placeholder={t("doctorProfile.pickDoctor")} className="mt-3" data-testid="doctor-picker-search" />
        <ul className="mt-2 max-h-72 overflow-auto">
          {filtered.map((d) => (
            <li key={d.id}>
              <button
                type="button"
                onClick={() => { onChange(d.id); setOpen(false); setQ(""); }}
                className={`w-full rounded-lg px-3 py-2 text-left text-sm ${d.id === value ? "bg-primary-container text-on-primary-container" : "hover:bg-muted/50 text-foreground"}`}
                data-testid={`doctor-opt-${d.id}`}
              >
                {d.name}{d.specialty ? ` · ${d.specialty}` : ""}
              </button>
            </li>
          ))}
        </ul>
      </DialogPopup>
    </DialogRoot>
  );
}
```

- [ ] **Step 3: DoctorScheduleView** — create `src/features/scheduling/doctor-schedule-view.tsx`:
```tsx
"use client";

import { AvailabilityEditor } from "@/features/scheduling/availability-editor";
import { SlotViewer } from "@/features/scheduling/slot-viewer";

interface DoctorScheduleViewProps {
  clinicId: string;
  doctorId: string;
  canManage: boolean;
  bookable: boolean;
}

export function DoctorScheduleView({ clinicId, doctorId, canManage, bookable }: DoctorScheduleViewProps) {
  return (
    <div className="space-y-6">
      <AvailabilityEditor clinicId={clinicId} doctorId={doctorId} canEdit={canManage} />
      <SlotViewer clinicId={clinicId} doctorId={doctorId} bookable={bookable} />
    </div>
  );
}
```

- [ ] **Step 4: tsc + build + commit**
```bash
npx tsc --noEmit && npm run build
git add src/features/scheduling/doctor-picker.tsx src/features/scheduling/doctor-schedule-view.tsx src/features/scheduling/slot-viewer.tsx
git commit -m "feat(scheduling): M3 DoctorPicker + shared DoctorScheduleView + SlotViewer bookable flag

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 6: Frontend — My Schedule + Clinic Schedules routes (replace /schedule)

**Files:** Create `src/app/my-schedule/page.tsx`, `src/app/clinic-schedules/page.tsx`; Delete `src/app/schedule/page.tsx`.

- [ ] **Step 1: My Schedule** — create `src/app/my-schedule/page.tsx`:
```tsx
"use client";

import { useTranslation } from "react-i18next";

import { AuthGate } from "@/components/auth-gate";
import { AppShell } from "@/components/shell/app-shell";
import { PageContainer } from "@/components/layout/page-container";
import { PageHeader } from "@/components/layout/page-header";
import { useMe } from "@/features/clinic/hooks";
import { DoctorScheduleView } from "@/features/scheduling/doctor-schedule-view";

function MyScheduleShell() {
  const { t } = useTranslation();
  const me = useMe();
  const membership = me.data?.memberships[0];
  const clinicId = membership?.clinic_id ?? "";
  const doctorId = me.data?.doctor_id ?? "";

  return (
    <AppShell clinicName={membership?.clinic_name}>
      <PageContainer>
        <PageHeader title={t("nav.mySchedule")} />
        {clinicId && doctorId ? (
          <DoctorScheduleView clinicId={clinicId} doctorId={doctorId} canManage bookable={false} />
        ) : (
          <p className="text-sm text-muted-foreground" data-testid="no-doctor-profile">
            {t("doctorProfile.bannerBody")}
          </p>
        )}
      </PageContainer>
    </AppShell>
  );
}

export default function MySchedulePage() {
  return (
    <AuthGate>
      <MyScheduleShell />
    </AuthGate>
  );
}
```

- [ ] **Step 2: Clinic Schedules** — create `src/app/clinic-schedules/page.tsx` (M3 picker → schedule view; manage iff owner/PM; bookable):
```tsx
"use client";

import { useState } from "react";
import { useTranslation } from "react-i18next";

import { AuthGate } from "@/components/auth-gate";
import { AppShell } from "@/components/shell/app-shell";
import { PageContainer } from "@/components/layout/page-container";
import { PageHeader } from "@/components/layout/page-header";
import { useMe } from "@/features/clinic/hooks";
import { DoctorPicker } from "@/features/scheduling/doctor-picker";
import { DoctorScheduleView } from "@/features/scheduling/doctor-schedule-view";

function ClinicSchedulesShell() {
  const { t } = useTranslation();
  const me = useMe();
  const membership = me.data?.memberships[0];
  const clinicId = membership?.clinic_id ?? "";
  const role = membership?.role ?? "";
  const canManage = role === "owner" || role === "practice_manager";
  const [doctorId, setDoctorId] = useState("");

  return (
    <AppShell clinicName={membership?.clinic_name}>
      <PageContainer>
        <PageHeader title={t("nav.clinicSchedules")} />
        {clinicId && (
          <div className="space-y-4">
            <DoctorPicker clinicId={clinicId} value={doctorId} onChange={setDoctorId} />
            {doctorId && (
              <DoctorScheduleView clinicId={clinicId} doctorId={doctorId} canManage={canManage} bookable />
            )}
          </div>
        )}
      </PageContainer>
    </AppShell>
  );
}

export default function ClinicSchedulesPage() {
  return (
    <AuthGate>
      <ClinicSchedulesShell />
    </AuthGate>
  );
}
```

- [ ] **Step 3: Delete the old route** — `git rm src/app/schedule/page.tsx`.

- [ ] **Step 4: tsc + build** — `npx tsc --noEmit && npm run build` → clean (`/my-schedule` + `/clinic-schedules` compile; `/schedule` gone; no dangling imports).

- [ ] **Step 5: Commit**
```bash
git add src/app/my-schedule/ src/app/clinic-schedules/ src/app/schedule/
git commit -m "feat(scheduling): My Schedule + Clinic Schedules routes (replace /schedule)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 7: Frontend — doctor-profile dialog + create-profile banner

**Files:** Create `src/features/doctors/doctor-profile-dialog.tsx`, `src/features/doctors/create-profile-banner.tsx`; Modify `src/app/page.tsx`.

**Interfaces:** Consumes `useCreateSelfDoctor` (Task 3), `useMe`.

- [ ] **Step 1: Profile dialog** — create `src/features/doctors/doctor-profile-dialog.tsx`:
```tsx
"use client";

import { useState } from "react";
import { useTranslation } from "react-i18next";

import { Button, buttonVariants } from "@/components/ui/button";
import { DialogClose, DialogPopup, DialogRoot, DialogTitle, DialogTrigger } from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { ApiError } from "@/lib/api-client";
import { useCreateSelfDoctor } from "@/features/doctors/hooks";

interface DoctorProfileDialogProps {
  clinicId: string;
  triggerClassName?: string;
  triggerLabel: string;
}

export function DoctorProfileDialog({ clinicId, triggerClassName, triggerLabel }: DoctorProfileDialogProps) {
  const { t } = useTranslation();
  const [open, setOpen] = useState(false);
  const [name, setName] = useState("");
  const [phone, setPhone] = useState("");
  const [specialty, setSpecialty] = useState("");
  const create = useCreateSelfDoctor(clinicId);

  function submit() {
    create.mutate(
      { name, phone, specialty: specialty || undefined },
      { onSuccess: () => { setOpen(false); setName(""); setPhone(""); setSpecialty(""); } },
    );
  }
  const exists = create.error instanceof ApiError && create.error.code === "conflict";

  return (
    <DialogRoot open={open} onOpenChange={(o) => { setOpen(o); if (!o) create.reset(); }}>
      <DialogTrigger className={triggerClassName ?? buttonVariants({ variant: "filled", size: "sm" })} data-testid="open-doctor-profile">
        {triggerLabel}
      </DialogTrigger>
      <DialogPopup>
        <DialogTitle>{t("doctorProfile.createTitle")}</DialogTitle>
        <div className="mt-4 space-y-3" data-testid="doctor-profile-form">
          <div>
            <label className="text-sm text-muted-foreground">{t("doctorProfile.nameLabel")}</label>
            <Input value={name} onChange={(e) => setName(e.target.value)} placeholder={t("doctorProfile.namePlaceholder")} data-testid="profile-name" className="mt-1" />
          </div>
          <div>
            <label className="text-sm text-muted-foreground">{t("doctorProfile.phoneLabel")}</label>
            <Input value={phone} onChange={(e) => setPhone(e.target.value)} placeholder={t("clinic.phonePlaceholder")} data-testid="profile-phone" className="mt-1" />
          </div>
          <div>
            <label className="text-sm text-muted-foreground">{t("doctorProfile.specialtyLabel")}</label>
            <Input value={specialty} onChange={(e) => setSpecialty(e.target.value)} data-testid="profile-specialty" className="mt-1" />
          </div>
          {exists && <p className="text-sm text-destructive" data-testid="profile-exists">{t("doctorProfile.exists")}</p>}
          {create.isError && !exists && <p className="text-sm text-destructive">{t("apiErrors.default")}</p>}
          <div className="flex justify-end gap-2">
            <DialogClose className={buttonVariants({ variant: "ghost", size: "sm" })}>{t("common.cancel")}</DialogClose>
            <Button onClick={submit} disabled={!name || !phone || create.isPending} data-testid="submit-doctor-profile">{t("doctorProfile.submit")}</Button>
          </div>
        </div>
      </DialogPopup>
    </DialogRoot>
  );
}
```

- [ ] **Step 2: Banner** — create `src/features/doctors/create-profile-banner.tsx`:
```tsx
"use client";

import { useState } from "react";
import { useTranslation } from "react-i18next";

import { Icon } from "@/components/ui/icon";
import { DoctorProfileDialog } from "@/features/doctors/doctor-profile-dialog";

export function CreateProfileBanner({ clinicId }: { clinicId: string }) {
  const { t } = useTranslation();
  const [dismissed, setDismissed] = useState(false);
  if (dismissed) return null;

  return (
    <div
      className="flex items-start justify-between gap-3 rounded-lg border border-warning bg-warning/10 px-4 py-3"
      data-testid="create-profile-banner"
      role="status"
    >
      <div className="flex items-start gap-2">
        <Icon name="info" size={20} className="text-warning" aria-hidden />
        <div>
          <p className="text-sm font-medium text-foreground">{t("doctorProfile.bannerQuestion")}</p>
          <p className="text-sm text-muted-foreground">{t("doctorProfile.bannerBody")}</p>
          <div className="mt-2">
            <DoctorProfileDialog clinicId={clinicId} triggerLabel={t("doctorProfile.bannerCta")} />
          </div>
        </div>
      </div>
      <button onClick={() => setDismissed(true)} className="text-muted-foreground hover:text-foreground" aria-label={t("doctorProfile.dismiss")} data-testid="dismiss-banner">
        <Icon name="close" size={18} />
      </button>
    </div>
  );
}
```
> Confirm `border-warning` / `bg-warning` / `text-warning` semantic tokens exist in `globals.css` (the design system defines `--warning`/`bg-warning` per the SP inventory). If the exact utility differs, use the project's warning token.

- [ ] **Step 3: Wire banner into Home** — in `src/app/page.tsx`, inside `<section data-testid="clinic-shell">` (top, before the summary card), render the banner when the member has no doctor profile:
```tsx
import { CreateProfileBanner } from "@/features/doctors/create-profile-banner";
// ...
{clinicId && me.data && !me.data.doctor_id && <CreateProfileBanner clinicId={clinicId} />}
```
(`me` is already available in `HomeShell` via `useMe()`; `clinicId` is already derived.)

- [ ] **Step 4: tsc + build + commit**
```bash
npx tsc --noEmit && npm run build
git add src/features/doctors/doctor-profile-dialog.tsx src/features/doctors/create-profile-banner.tsx src/app/page.tsx
git commit -m "feat(doctors): self doctor-profile dialog + dismissable create-profile banner

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 8: Frontend — day-of-week Segmented (no dropdown)

**Files:** Modify `src/features/scheduling/availability-editor.tsx`.

- [ ] **Step 1: Replace the day `<select>`** — in `availability-editor.tsx`, replace the recurring-window day-of-week native `<select>` (state `dow`/`setDow`) with the existing M3 `SegmentedButton`:
```tsx
import { SegmentedButton } from "@/components/ui/segmented";
// ...
<SegmentedButton
  ariaLabel={t("scheduling.dayLabel")}
  options={[0, 1, 2, 3, 4, 5, 6].map((n) => ({ value: String(n), label: t(`scheduling.daysShort.${n}`) }))}
  value={dow}
  onChange={setDow}
  data-testid="recurring-day"
/>
```
(Keep `dow`/`setDow` state; the create-window call still passes `day_of_week: Number(dow)`. `SegmentedButton`'s props are `options/value/onChange/ariaLabel` per `components/ui/segmented.tsx`. If `SegmentedButton` doesn't forward `data-testid`, wrap it in a `<div data-testid="recurring-day">`.)

- [ ] **Step 2: tsc + build + commit**
```bash
npx tsc --noEmit && npm run build
git add src/features/scheduling/availability-editor.tsx
git commit -m "feat(scheduling): day-of-week as M3 segmented control (no dropdown)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 9: Docs — PRD / Entities / Workflows / Golden Rules (docs repo)

**Files (in `dentail-register-docs`):** `PRD/PRD_v3_1_Founder_Edition.md`, `Entities/01-clinic.md`, `Entities/03-user.md`, `Entities/04-doctor.md`, a Golden Rules / design-system note.

- [ ] **Step 1: PRD** — in the clinic/roles/scheduling area, document: owner-doctor is the default happy path; the clinic creator creates their **own doctor profile** (separate, self-service, no invite, not derived from clinic data); **My Schedule** (own) vs **Clinic Schedules** (admin) are separate navigable concepts.

- [ ] **Step 2: Entities** — `01-clinic.md`: note clinic data is distinct from owner/doctor data. `03-user.md`: a user may be linked to a doctor profile; roles (Owner/Doctor/Assistant) are **not mutually exclusive**; doctor-ness = a linked `doctor_beta` row. `04-doctor.md`: a doctor profile may be **self-created (active, no invite)** by the linked user, in addition to the invite-based path; `linked_user_id` is the doctor↔user link.

- [ ] **Step 3: Permanent rules** — add to the Golden Rules + design-system notes: **"Owner-doctor is the default happy path."**, **"My Schedule and Clinic Schedules are separate navigable concepts."**, and the UI rule **"Prefer M3 searchable / bottom-sheet / command-style selection over dropdowns; dropdowns only for 2–4 trivial options."**

- [ ] **Step 4: Commit** (docs repo)
```bash
git add PRD/ Entities/ Rules/ 2>/dev/null
git commit -m "docs: owner-doctor default + My/Clinic Schedules + no-dropdowns rule (#49)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Final Verification (before PRs)
- [ ] Backend: `make test && make lint` → green.
- [ ] Frontend: `npx tsc --noEmit && npm run build` → clean; `npx playwright test tests/e2e/i18n.spec.ts` (or node parity) → pass.
- [ ] PRs: backend `Part of #49`; frontend `Closes #49`; docs change can ride the docs PR or a small docs PR. Board #49 → In Review → Completed.
- [ ] No Supabase migration (no schema change).

## Self-Review (against the spec)
- **§3.1 self doctor-profile (active, linked, no invite, one-per-user 409, member-only):** Task 1. ✅
- **§3.2 `/me.doctor_id`:** Task 2. ✅
- **§3.3 authz fix (approve/reject by linked doctor):** Task 2. ✅
- **§4.1 profile form + entry points:** Task 7 (dialog + banner). ✅
- **§4.2 dismissable warning banner (no doctor_id):** Task 7. ✅
- **§4.3 nav split (My/Clinic Schedules, role/profile-aware, shared DoctorScheduleView, replaces /schedule):** Tasks 4–6. ✅
- **§4.4 M3 DoctorPicker (no dropdown) + day-of-week segmented:** Tasks 5, 8. ✅
- **§5 docs + permanent rules:** Task 9. ✅
- **§6 testing:** backend Tasks 1–2; frontend tsc/build/i18n + the behaviors above.
- **Placeholder scan:** "confirm X exists" notes (DoctorStatus.active value, warning token, Segmented data-testid forwarding) are symbol/asset checks, not placeholders; resolve inline. ✅
- **Type consistency:** `create_self_doctor(db,*,clinic_id,user_id,data)` / `get_my_doctor(db,clinic_id,user_id)` consistent across Tasks 1–2; FE `createSelfDoctor(clinicId,payload)` / `useCreateSelfDoctor(clinicId)` / `Me.doctor_id` / `DoctorScheduleView({clinicId,doctorId,canManage,bookable})` / `DoctorPicker({clinicId,value,onChange})` consistent across Tasks 3–7. ✅
- **Clinic creation unchanged:** confirmed — no task touches `create_clinic`. ✅
