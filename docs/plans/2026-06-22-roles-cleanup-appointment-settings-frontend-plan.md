# Role Cleanup + Appointment Settings — Frontend Implementation Plan (#97)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove `practice_manager` from the frontend, add the **Settings → Appointment Settings** pane (Staff Approval toggle + configurable/"Never" expiry, gray-out under Direct Booking), gate Approve/Reject per the new permission model, and add a count-aware confirm when switching to Direct Booking.

**Architecture:** Frontend slice of #91. Spec: `docs/specs/2026-06-22-roles-cleanup-appointment-settings-design.md`. Depends on the backend slice (#96) being merged first — it provides `allow_staff_approval` + nullable `appointment_request_expiry_minutes` on `GET/PATCH /clinics/{id}/settings` (now member-readable). Compose `components/ui/*`, semantic tokens only (Rule 17.0), both themes, mobile-first, WCAG AA.

**Tech Stack:** Next.js App Router (client components), TanStack Query, react-i18next (en/hi parity gated), Tailwind v4 semantic tokens, Material Symbols. CI = `tsc --noEmit` + `npm run build`.

## Global Constraints

- New role set: `owner`, `doctor`, `assistant`. Remove every `practice_manager` reference (8 component spots + en/hi role labels).
- Role predicates: manage doctors / clinic-schedules nav → `owner || assistant`; clinic settings / invites → `owner`; coordinator (cancel/resend) → `owner || assistant`.
- Approve/Reject visible per row when: `role === "owner" || myDoctorId === row.doctor_id || (role === "assistant" && allowStaffApproval)` — AND pending AND not expired.
- `allow_staff_approval` default OFF. Expiry select options: **30 / 60 / 120 (Default) / 240 / 480 minutes / Never** (Never = `null`).
- Under `scheduling_workflow === "direct_booking"`, the expiry control is **disabled + locked note** shown; the Staff Approval toggle stays enabled (with its info note).
- Switching to Direct Booking with pending requests > 0 shows a count-aware confirm before PATCH.
- Only "Appointment Settings" is added to the settings sub-nav (Profile · Clinic · Scheduling · Appointment Settings). The existing Scheduling pane stays.
- i18n: every new string in BOTH `en.json` and `hi.json` (parity gated by `tests/e2e/i18n.spec.ts`). Never hardcode colours; compose `components/ui/*`.
- Quality gate per task: `npx tsc --noEmit` clean + `npm run build` succeeds. Frontend PR held for user test.

---

### Task 1: ClinicSettings API type

**Files:**
- Modify: `src/features/clinic/api.ts:79-90` (the `ClinicSettings` type)

**Interfaces:**
- Produces: `ClinicSettings.allow_staff_approval: boolean`; `ClinicSettings.appointment_request_expiry_minutes: number | null`.

- [ ] **Step 1: Update the type**

In `src/features/clinic/api.ts`, the `ClinicSettings` type — change the expiry field and add the toggle:
```typescript
export type ClinicSettings = {
  allow_multiple_bookings_per_slot: boolean;
  max_bookings_per_slot: number;
  default_slot_size_minutes: number;
  appointment_request_expiry_minutes: number | null;
  post_confirmation_hook_delay_minutes: number;
  reminders_enabled: boolean;
  whatsapp_enabled: boolean;
  google_calendar_enabled: boolean;
  scheduling_workflow: "direct_booking" | "doctor_approval";
  allow_staff_approval: boolean;
};
```

- [ ] **Step 2: Type-check + commit**

```bash
npx tsc --noEmit
git add src/features/clinic/api.ts
git commit -m "feat(settings): ClinicSettings type adds allow_staff_approval + nullable expiry (#97)"
```

---

### Task 2: Remove practice_manager across the frontend

**Files:**
- Modify: `src/app/settings/page.tsx:27`, `src/app/requests/page.tsx:21`, `src/app/clinic-schedules/page.tsx:20`, `src/app/doctors/[id]/page.tsx:27`, `src/components/shell/app-shell.tsx:35`, `src/features/patients/patient-detail.tsx:935`
- Modify: `src/i18n/locales/en.json` (lines ~163, ~498 — `practice_manager` keys), `src/i18n/locales/hi.json` (line ~163)

**Interfaces:**
- Consumes: nothing.
- Produces: role predicates aligned to the new model.

- [ ] **Step 1: Update each role predicate**

`src/app/settings/page.tsx:27` (clinic management = owner only):
```typescript
  const canManageClinic = role === "owner";
```
`src/app/clinic-schedules/page.tsx:20` (manage availability = owner + assistant):
```typescript
  const canManage = role === "owner" || role === "assistant";
```
`src/app/doctors/[id]/page.tsx:25-28` (edit doctor = owner/assistant, or the doctor editing their own):
```typescript
  const canEdit =
    role === "owner" ||
    role === "assistant" ||
    (role === "doctor" && doctor.data?.linked_user_id === me.data?.user_id);
```
`src/components/shell/app-shell.tsx:35` (clinic-schedules nav = owner + assistant):
```typescript
  const canClinicSchedules = role === "owner" || role === "assistant";
```
`src/app/requests/page.tsx:21` and `src/features/patients/patient-detail.tsx:935` (coordinator = owner + assistant):
```typescript
  const canCoordinate = role === "owner" || role === "assistant";
```

- [ ] **Step 2: Remove the locale role labels**

In `src/i18n/locales/en.json`, delete the `"practice_manager": "Practice Manager"` line from BOTH the `status.role` block (~163) and the top-level `roles` block (~498). In `src/i18n/locales/hi.json`, delete the `"practice_manager": "प्रैक्टिस मैनेजर"` line from the `status.role` block (~163). (If `hi.json` has a `roles` block with the key, remove it there too — keep en/hi parity.)

- [ ] **Step 3: Verify no references remain**

Run: `grep -rn "practice_manager" src/`
Expected: no output.

- [ ] **Step 4: Type-check, parity, commit**

```bash
npx tsc --noEmit
npm run test:e2e -- i18n.spec.ts   # en/hi parity (or: npx playwright test tests/e2e/i18n.spec.ts)
git add src/app src/components src/features/patients/patient-detail.tsx src/i18n/locales
git commit -m "feat(roles): remove practice_manager from frontend predicates + locales (#97)"
```

---

### Task 3: `canDecide` pure helper + unit test

**Files:**
- Modify: `src/features/scheduling/request-status.ts` (add `canDecide`)
- Test: `tests/e2e/request-status.spec.ts` (add cases)

**Interfaces:**
- Produces: `canDecide(row: { status: string; doctor_id: string }, ctx: DecideContext): boolean` and `type DecideContext = { role: string; myDoctorId: string | null; allowStaffApproval: boolean }`.

- [ ] **Step 1: Write the failing test**

Append to `tests/e2e/request-status.spec.ts`:
```typescript
import { canDecide } from "@/features/scheduling/request-status";

const row = (doctor_id: string) => ({ status: "pending", doctor_id });

test("owner can always decide", () => {
  expect(canDecide(row("d1"), { role: "owner", myDoctorId: null, allowStaffApproval: false })).toBe(true);
});
test("assigned doctor can decide own", () => {
  expect(canDecide(row("d1"), { role: "doctor", myDoctorId: "d1", allowStaffApproval: false })).toBe(true);
});
test("other doctor cannot decide even with toggle on", () => {
  expect(canDecide(row("d1"), { role: "doctor", myDoctorId: "d2", allowStaffApproval: true })).toBe(false);
});
test("assistant decides only when toggle on", () => {
  expect(canDecide(row("d1"), { role: "assistant", myDoctorId: null, allowStaffApproval: false })).toBe(false);
  expect(canDecide(row("d1"), { role: "assistant", myDoctorId: null, allowStaffApproval: true })).toBe(true);
});
```
(Match the existing test runner style in that file — if it uses Vitest `describe/it`, mirror it; the assertions are the same.)

- [ ] **Step 2: Run to verify failure**

Run: `npx vitest run tests/e2e/request-status.spec.ts` (or the project's unit-test command for that file)
Expected: FAIL — `canDecide` not exported.

- [ ] **Step 3: Add the helper**

Append to `src/features/scheduling/request-status.ts`:
```typescript
export type DecideContext = {
  role: string;
  myDoctorId: string | null;
  allowStaffApproval: boolean;
};

/**
 * Whether the current user may approve/reject this request, per #91:
 * owner always; the assigned doctor for their own request; an assistant only
 * when the clinic allows staff approval. Other doctors never.
 * (Pending/expired gating is applied separately by the row.)
 */
export function canDecide(
  row: { status: string; doctor_id: string },
  ctx: DecideContext,
): boolean {
  if (ctx.role === "owner") return true;
  if (ctx.myDoctorId != null && ctx.myDoctorId === row.doctor_id) return true;
  if (ctx.role === "assistant" && ctx.allowStaffApproval) return true;
  return false;
}
```

- [ ] **Step 4: Run the test**

Run: `npx vitest run tests/e2e/request-status.spec.ts`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/features/scheduling/request-status.ts tests/e2e/request-status.spec.ts
git commit -m "feat(scheduling): canDecide per-row permission helper (#97)"
```

---

### Task 4: Per-row decide gating on the Requests page

**Files:**
- Modify: `src/features/scheduling/requests-list.tsx:126-132` (props), `:326-332` (per-row `canDecide`)
- Modify: `src/app/requests/page.tsx` (read settings, pass context)

**Interfaces:**
- Consumes: `canDecide` + `DecideContext` (Task 3), `ClinicSettings.allow_staff_approval` (Task 1), `useClinicSettings` (existing), `useMe` (existing).
- Produces: `RequestsList` props `{ clinicId, role, myDoctorId, allowStaffApproval, canCoordinate }`.

- [ ] **Step 1: Update `RequestsList` props + per-row computation**

`src/features/scheduling/requests-list.tsx` — replace the `RequestsListProps` interface (126-130) and signature (132):
```typescript
interface RequestsListProps {
  clinicId: string;
  role: string;
  myDoctorId: string | null;
  allowStaffApproval: boolean;
  canCoordinate: boolean;
}

export function RequestsList({
  clinicId,
  role,
  myDoctorId,
  allowStaffApproval,
  canCoordinate,
}: RequestsListProps) {
```
Add the import at the top of the file:
```typescript
import { canDecide } from "@/features/scheduling/request-status";
```
At the row map (around line 326-332), compute `canDecide` per row:
```typescript
            <RequestRow
              key={row.id}
              request={row}
              clinicId={clinicId}
              canDecide={canDecide(row, { role, myDoctorId, allowStaffApproval })}
              canCoordinate={canCoordinate}
            />
```

- [ ] **Step 2: Update the Requests page to supply context**

`src/app/requests/page.tsx` — replace the `RequestsShell` body so it reads settings and passes the context:
```typescript
import { useClinicSettings, useMe } from "@/features/clinic/hooks";
// ...
function RequestsShell() {
  const me = useMe();
  const membership = me.data?.memberships[0];
  const clinicId = membership?.clinic_id ?? "";
  const role = membership?.role ?? "";
  const settings = useClinicSettings(clinicId);
  const allowStaffApproval = settings.data?.allow_staff_approval ?? false;

  // Approve/Reject visibility is computed per row (see canDecide). Coordinator
  // (cancel/resend) = owner or assistant.
  const canCoordinate = role === "owner" || role === "assistant";

  return (
    <AppShell clinicName={membership?.clinic_name}>
      <PageContainer width="wide">
        {clinicId && (
          <RequestsList
            clinicId={clinicId}
            role={role}
            myDoctorId={me.data?.doctor_id ?? null}
            allowStaffApproval={allowStaffApproval}
            canCoordinate={canCoordinate}
          />
        )}
      </PageContainer>
    </AppShell>
  );
}
```
(Remove the now-unused `canDecide` const and the stale comment block referencing it.)

- [ ] **Step 3: Type-check + build**

Run: `npx tsc --noEmit && npm run build`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add src/features/scheduling/requests-list.tsx src/app/requests/page.tsx
git commit -m "feat(requests): per-row Approve/Reject gating from settings (#97)"
```

---

### Task 5: Per-row decide gating on the patient page

**Files:**
- Modify: `src/features/patients/patient-detail.tsx` — `OverviewTabProps`/`AppointmentsTabProps` (593-598, 792-796), the two `<RequestRow>` sites (815-820, and the Overview compact/rows), and the parent that computes context (934-935, 1063-1073)

**Interfaces:**
- Consumes: `canDecide` (Task 3), `useClinicSettings` (existing).
- Produces: tabs receive `role`, `myDoctorId`, `allowStaffApproval` instead of a single `canDecide`.

- [ ] **Step 1: Replace the parent's `canDecide` with context + settings read**

In `src/features/patients/patient-detail.tsx`, near line 930-935 (where `me` is read), add the settings read and the context, and drop the coarse `canDecide`:
```typescript
  const settings = useClinicSettings(clinicId);
  const decideCtx = {
    role,
    myDoctorId: me.data?.doctor_id ?? null,
    allowStaffApproval: settings.data?.allow_staff_approval ?? false,
  };
  const canCoordinate = role === "owner" || role === "assistant";
```
(`useClinicSettings` is exported from `@/features/clinic/hooks`; add it to the existing import from that module if not already present.)

- [ ] **Step 2: Thread context into the tabs**

Update `OverviewTabProps` and `AppointmentsTabProps` (593-594, 792-793) to replace `canDecide: boolean;` with:
```typescript
  role: string;
  myDoctorId: string | null;
  allowStaffApproval: boolean;
```
Update both function signatures (598, 796) to destructure `role, myDoctorId, allowStaffApproval` instead of `canDecide`, and update the two render sites (1063-1073) to pass `role={decideCtx.role} myDoctorId={decideCtx.myDoctorId} allowStaffApproval={decideCtx.allowStaffApproval}` instead of `canDecide={canDecide}`.

- [ ] **Step 3: Compute `canDecide` at each `<RequestRow>` inside the tabs**

Add `import { canDecide } from "@/features/scheduling/request-status";` at the top. At each `<RequestRow ... />` (the AppointmentsTab list around 815-820, and any Overview rich-row that renders `<RequestRow>`), replace `canDecide={canDecide}` with:
```typescript
                canDecide={canDecide(row, { role, myDoctorId, allowStaffApproval })}
```
(Use the row variable in scope — it is the per-item object with `status` and `doctor_id`. The Overview compact rows that are NOT `<RequestRow>` need no change — they render no actions.)

- [ ] **Step 4: Type-check + build**

Run: `npx tsc --noEmit && npm run build`
Expected: PASS (no remaining reference to a `canDecide` boolean prop).

- [ ] **Step 5: Commit**

```bash
git add src/features/patients/patient-detail.tsx
git commit -m "feat(patients): per-row Approve/Reject gating from settings (#97)"
```

---

### Task 6: Appointment Settings pane (Switch + expiry select + gray-out) + nav

**Files:**
- Create: `src/components/ui/switch.tsx`
- Create: `src/features/settings/appointment-settings-pane.tsx`
- Modify: `src/features/settings/settings-shell.tsx:12,17-21,73-81` (add nav item + route the pane)
- Modify: `src/i18n/locales/en.json` + `src/i18n/locales/hi.json` (new `settings.nav.appointment` + `settings.appointment.*`)

**Interfaces:**
- Consumes: `useClinicSettings`/`useUpdateClinicSettings` (existing), `useSuccess` (existing), `ClinicSettings` type (Task 1).
- Produces: `<AppointmentSettingsPane clinicId canManage />`; `<Switch checked onCheckedChange disabled />`.

- [ ] **Step 1: Create the Switch primitive**

```tsx
// src/components/ui/switch.tsx
"use client";

type SwitchProps = {
  checked: boolean;
  onCheckedChange: (checked: boolean) => void;
  disabled?: boolean;
  id?: string;
  "data-testid"?: string;
  "aria-label"?: string;
};

export function Switch({
  checked,
  onCheckedChange,
  disabled = false,
  id,
  ...rest
}: SwitchProps) {
  return (
    <button
      type="button"
      role="switch"
      id={id}
      aria-checked={checked}
      disabled={disabled}
      onClick={() => onCheckedChange(!checked)}
      data-testid={rest["data-testid"]}
      aria-label={rest["aria-label"]}
      className={`relative inline-flex h-6 w-11 shrink-0 items-center rounded-full transition-colors outline-none focus-visible:ring-3 focus-visible:ring-ring/50 disabled:cursor-not-allowed disabled:opacity-50 ${
        checked ? "bg-primary" : "bg-muted"
      }`}
    >
      <span
        className={`inline-block size-5 transform rounded-full bg-background shadow transition-transform ${
          checked ? "translate-x-5" : "translate-x-0.5"
        }`}
      />
    </button>
  );
}
```

- [ ] **Step 2: Create the Appointment Settings pane**

```tsx
// src/features/settings/appointment-settings-pane.tsx
"use client";

import { useEffect, useState } from "react";
import { useTranslation } from "react-i18next";

import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardSeparator, CardTitle } from "@/components/ui/card";
import { Icon } from "@/components/ui/icon";
import { Switch } from "@/components/ui/switch";
import { useSuccess } from "@/components/success/use-success";
import { useClinicSettings, useUpdateClinicSettings } from "@/features/clinic/hooks";

// Expiry option values; `null` = Never. 120 is the default.
const EXPIRY_OPTIONS: (number | null)[] = [30, 60, 120, 240, 480, null];

export function AppointmentSettingsPane({
  clinicId,
  canManage,
}: {
  clinicId: string;
  canManage: boolean;
}) {
  const { t } = useTranslation();
  const settings = useClinicSettings(clinicId);
  const updateSettings = useUpdateClinicSettings(clinicId);
  const success = useSuccess();

  const [allowStaff, setAllowStaff] = useState<boolean | undefined>(undefined);
  const [expiry, setExpiry] = useState<number | null | undefined>(undefined);

  useEffect(() => {
    if (settings.data && allowStaff === undefined) {
      setAllowStaff(settings.data.allow_staff_approval);
      setExpiry(settings.data.appointment_request_expiry_minutes);
    }
  }, [settings.data, allowStaff]);

  if (settings.isPending || allowStaff === undefined) {
    return (
      <Card>
        <CardContent className="py-6">
          <p className="text-sm text-muted-foreground">{t("common.loading")}</p>
        </CardContent>
      </Card>
    );
  }

  const isDirect = settings.data?.scheduling_workflow === "direct_booking";
  const isDirty =
    allowStaff !== settings.data?.allow_staff_approval ||
    expiry !== settings.data?.appointment_request_expiry_minutes;
  const isSaveDisabled = !canManage || !isDirty || updateSettings.isPending;

  function handleSave() {
    updateSettings.mutate(
      {
        allow_staff_approval: allowStaff,
        appointment_request_expiry_minutes: expiry,
      },
      { onSuccess: () => success({ titleKey: "settings.appointment.saved" }) },
    );
  }

  function expiryLabel(v: number | null): string {
    if (v === null) return t("settings.appointment.expiry.never");
    if (v === 120) return t("settings.appointment.expiry.minutesDefault", { count: 120 });
    return t("settings.appointment.expiry.minutes", { count: v });
  }

  return (
    <div className="space-y-5" data-testid="settings-appointment">
      <div>
        <h2 className="text-lg font-semibold text-foreground">{t("settings.appointment.title")}</h2>
        <p className="text-sm text-muted-foreground">{t("settings.appointment.subtitle")}</p>
      </div>

      {/* Staff Approval */}
      <Card>
        <CardHeader>
          <CardTitle>{t("settings.appointment.staff.title")}</CardTitle>
          <p className="text-sm text-muted-foreground">{t("settings.appointment.staff.subtitle")}</p>
        </CardHeader>
        <CardSeparator />
        <CardContent className="space-y-4 pt-4">
          <div className="flex items-start justify-between gap-4">
            <div>
              <p className="text-sm font-medium text-foreground">{t("settings.appointment.staff.row")}</p>
              <p className="text-sm text-muted-foreground">{t("settings.appointment.staff.rowDesc")}</p>
            </div>
            <Switch
              checked={allowStaff}
              onCheckedChange={setAllowStaff}
              disabled={!canManage}
              data-testid="allow-staff-approval-toggle"
              aria-label={t("settings.appointment.staff.row")}
            />
          </div>
          <div className="flex items-start gap-2 rounded-lg bg-primary-container/30 px-4 py-3">
            <Icon name="info" size={16} className="mt-0.5 shrink-0 text-on-primary-container" aria-hidden />
            <p className="text-sm text-on-primary-container">{t("settings.appointment.staff.info")}</p>
          </div>
        </CardContent>
      </Card>

      {/* Request Expiry */}
      <Card>
        <CardHeader>
          <CardTitle>{t("settings.appointment.expiry.title")}</CardTitle>
          <p className="text-sm text-muted-foreground">{t("settings.appointment.expiry.subtitle")}</p>
        </CardHeader>
        <CardSeparator />
        <CardContent className="space-y-4 pt-4">
          <div className="flex items-start justify-between gap-4">
            <div>
              <p className="text-sm font-medium text-foreground">{t("settings.appointment.expiry.row")}</p>
              <p className="text-sm text-muted-foreground">{t("settings.appointment.expiry.rowDesc")}</p>
            </div>
            <select
              data-testid="request-expiry-select"
              value={expiry === null ? "never" : String(expiry)}
              disabled={!canManage || isDirect}
              onChange={(e) =>
                setExpiry(e.target.value === "never" ? null : Number(e.target.value))
              }
              className="flex h-10 w-56 rounded-lg border border-border bg-background px-3 py-2 text-sm text-foreground transition-colors outline-none focus-visible:border-ring focus-visible:ring-3 focus-visible:ring-ring/50 disabled:cursor-not-allowed disabled:opacity-50"
            >
              {EXPIRY_OPTIONS.map((v) => (
                <option key={v === null ? "never" : v} value={v === null ? "never" : String(v)}>
                  {expiryLabel(v)}
                </option>
              ))}
            </select>
          </div>
          <div className="flex items-start gap-2 rounded-lg bg-primary-container/30 px-4 py-3">
            <Icon name="info" size={16} className="mt-0.5 shrink-0 text-on-primary-container" aria-hidden />
            <p className="text-sm text-on-primary-container">{t("settings.appointment.expiry.neverInfo")}</p>
          </div>
          {isDirect && (
            <div
              className="flex items-start gap-2 rounded-lg border border-border px-4 py-3"
              data-testid="expiry-direct-locked"
            >
              <Icon name="event_busy" size={18} className="mt-0.5 shrink-0 text-muted-foreground" aria-hidden />
              <div className="flex-1">
                <p className="text-sm font-medium text-foreground">{t("settings.appointment.expiry.directNoteTitle")}</p>
                <p className="text-sm text-muted-foreground">{t("settings.appointment.expiry.directNote")}</p>
              </div>
              <Icon name="lock" size={16} className="mt-0.5 shrink-0 text-muted-foreground" aria-hidden />
            </div>
          )}
        </CardContent>
      </Card>

      {/* Save bar */}
      <div className="flex items-center justify-between gap-4 rounded-lg bg-muted/50 px-4 py-3">
        <div className="flex items-start gap-2">
          <Icon name="info" size={16} className="mt-0.5 shrink-0 text-muted-foreground" aria-hidden />
          <p className="text-sm text-muted-foreground">{t("settings.appointment.saveNote")}</p>
        </div>
        {canManage && (
          <Button onClick={handleSave} disabled={isSaveDisabled} data-testid="appointment-settings-save">
            {t("settings.appointment.save")}
          </Button>
        )}
      </div>

      {updateSettings.isError && (
        <p className="text-right text-sm text-destructive">{t("apiErrors.default")}</p>
      )}
    </div>
  );
}
```

- [ ] **Step 3: Add the pane to the settings sub-nav**

`src/features/settings/settings-shell.tsx` — import the pane, extend the `Section` union and `items`, and route it:
```typescript
import { AppointmentSettingsPane } from "@/features/settings/appointment-settings-pane";
// ...
type Section = "profile" | "clinic" | "scheduling" | "appointment";
// ...
  const items: { key: Section; labelKey: string; icon: string }[] = [
    { key: "profile", labelKey: "settings.nav.profile", icon: "person" },
    { key: "clinic", labelKey: "settings.nav.clinic", icon: "domain" },
    { key: "scheduling", labelKey: "settings.nav.scheduling", icon: "event_available" },
    { key: "appointment", labelKey: "settings.nav.appointment", icon: "event_note" },
  ];
```
Replace the pane render block (73-81) so the new section renders:
```tsx
          {section === "profile" ? (
            <ProfilePane clinicId={clinicId} />
          ) : section === "clinic" ? (
            <ClinicPane clinicId={clinicId} canManage={canManageClinic} />
          ) : section === "scheduling" ? (
            <SchedulingPane clinicId={clinicId} canManage={canManageClinic} />
          ) : (
            <AppointmentSettingsPane clinicId={clinicId} canManage={canManageClinic} />
          )}
```

- [ ] **Step 4: Add i18n keys (en + hi)**

In `src/i18n/locales/en.json`, under `settings.nav` add `"appointment": "Appointment Settings"`, and add a `settings.appointment` block:
```json
"appointment": {
  "title": "Appointment Settings",
  "subtitle": "Configure appointment approval preferences and request expiry settings.",
  "saved": "Appointment settings saved",
  "save": "Save Changes",
  "saveNote": "These settings apply to all future appointment requests. Existing requests will follow the previous configuration.",
  "staff": {
    "title": "Staff Approval",
    "subtitle": "Manage whether other staff members can approve or reject appointment requests.",
    "row": "Allow other staff to approve appointments",
    "rowDesc": "When enabled, assistants and other staff members can approve or reject appointments assigned to doctors.",
    "info": "This applies only to multi-booking workflow (clinics with assistants or multiple staff). In Direct Booking (solo clinic), appointments are automatically approved."
  },
  "expiry": {
    "title": "Request Expiry",
    "subtitle": "Set how long appointment requests remain pending for approval.",
    "row": "Request expiry duration",
    "rowDesc": "Choose how long a request remains pending before it expires.",
    "minutes": "{{count}} minutes",
    "minutesDefault": "{{count}} minutes (Default)",
    "never": "Never",
    "neverInfo": "If set to Never, requests will not expire and will remain pending until manually approved or rejected.",
    "directNoteTitle": "Note for Direct Booking (Solo Clinic)",
    "directNote": "When Direct Booking workflow is selected, appointment requests are automatically approved and this setting is disabled."
  }
}
```
Mirror the same keys in `src/i18n/locales/hi.json` with Hindi translations (keep structure identical for parity).

- [ ] **Step 5: Type-check, build, parity**

Run: `npx tsc --noEmit && npm run build && npx playwright test tests/e2e/i18n.spec.ts`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add src/components/ui/switch.tsx src/features/settings/appointment-settings-pane.tsx src/features/settings/settings-shell.tsx src/i18n/locales
git commit -m "feat(settings): Appointment Settings pane (staff approval + expiry, gray-out) (#97)"
```

---

### Task 7: Auto-approve confirm when switching to Direct Booking

**Files:**
- Modify: `src/features/settings/scheduling-pane.tsx`
- Modify: `src/i18n/locales/en.json` + `hi.json` (confirm-dialog keys)

**Interfaces:**
- Consumes: `useRequestCounts` (`src/features/scheduling/hooks.ts:77`), `Dialog` (`@/components/ui/dialog`), existing `useUpdateClinicSettings`.

- [ ] **Step 1: Add a confirm gate before switching to Direct Booking**

In `src/features/settings/scheduling-pane.tsx`, import the counts hook and a dialog, add confirm state, and gate the save:
```typescript
import { useRequestCounts } from "@/features/scheduling/hooks";
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter } from "@/components/ui/dialog";
// ...
  const counts = useRequestCounts(clinicId);
  const [confirmOpen, setConfirmOpen] = useState(false);
  const pendingCount = counts.data?.pending ?? 0;

  function performSave() {
    if (!choice) return;
    updateSettings.mutate(
      { scheduling_workflow: choice },
      { onSuccess: () => success({ titleKey: "settings.scheduling.saved" }) },
    );
  }

  function handleSave() {
    if (!choice) return;
    const switchingToDirect = choice === "direct_booking" && savedWorkflow !== "direct_booking";
    if (switchingToDirect && pendingCount > 0) {
      setConfirmOpen(true);
      return;
    }
    performSave();
  }
```
(`savedWorkflow` is already defined at line 40. Replace the existing `handleSave` body with the above; keep the existing button wiring to `handleSave`.)

- [ ] **Step 2: Render the confirm dialog**

Add before the closing `</div>` of the component:
```tsx
      <Dialog open={confirmOpen} onOpenChange={setConfirmOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>{t("scheduling.workflow.autoApprove.title")}</DialogTitle>
          </DialogHeader>
          <p className="text-sm text-muted-foreground">
            {t("scheduling.workflow.autoApprove.body", { count: pendingCount })}
          </p>
          <DialogFooter>
            <Button variant="outline" onClick={() => setConfirmOpen(false)}>
              {t("common.cancel")}
            </Button>
            <Button
              data-testid="auto-approve-confirm"
              onClick={() => {
                setConfirmOpen(false);
                performSave();
              }}
            >
              {t("scheduling.workflow.autoApprove.confirm")}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
```
(Verify the exact `Dialog`/`DialogFooter`/`Button variant` prop names against `src/components/ui/dialog.tsx` and `button.tsx`; adjust to the real exports if they differ — e.g. if the project uses `ConfirmDialog`, use that. If `common.cancel` is missing, add it to both locales.)

- [ ] **Step 3: Add i18n keys (en + hi)**

In both locale files, under `scheduling.workflow` add:
```json
"autoApprove": {
  "title": "Switch to Direct Booking?",
  "body": "{{count}} pending request(s) will be automatically approved and confirmed.",
  "confirm": "Switch and approve"
}
```
(Hindi equivalents in `hi.json`.)

- [ ] **Step 4: Type-check, build, parity**

Run: `npx tsc --noEmit && npm run build && npx playwright test tests/e2e/i18n.spec.ts`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/features/settings/scheduling-pane.tsx src/i18n/locales
git commit -m "feat(scheduling): count-aware confirm on switch to Direct Booking (#97)"
```

---

### Task 8: Final verification

**Files:** none.

- [ ] **Step 1: Full type-check + build + parity**

Run: `npx tsc --noEmit && npm run build && npx playwright test tests/e2e/i18n.spec.ts tests/e2e/request-status.spec.ts`
Expected: ALL PASS. Fix any iCloud duplicate files (`* 2.ts*`) that break tsc by deleting them.

- [ ] **Step 2: Manual self-check against the mockup**

Confirm visually (dev server) that the Appointment Settings pane matches `Mockups/Appointment_settings_mockup.png`: two cards (Staff Approval, Request Expiry), the toggle on the right, the expiry select reading "120 minutes (Default)", the two info callouts, the locked Direct-Booking note when the clinic is in Direct Booking, and the bottom save bar. Both light and dark themes.

- [ ] **Step 3: Commit any fixups**

```bash
git add -A
git commit -m "chore(settings): final tsc/build/i18n green for #97"
```

---

## Self-Review (plan vs spec)

- **Spec §5a role removal (8 spots + locales)** → Task 2. ✅
- **Spec §5b Appointment Settings pane (mockup, gray-out, lock note)** → Task 6 (incl. Switch + select + nav). ✅
- **Spec §5c per-row decide gating** → Task 3 (helper) + Task 4 (requests) + Task 5 (patient). ✅
- **Spec §5d auto-approve confirm** → Task 7. ✅
- **Spec §5e API/types** → Task 1. ✅
- **Spec §5f i18n en/hi** → Tasks 2/6/7 each add to both; Task 8 parity gate. ✅
- **Type consistency:** `canDecide(row, ctx)` + `DecideContext` defined in Task 3, consumed in Tasks 4/5; `ClinicSettings.allow_staff_approval` (Task 1) consumed in Tasks 4/5/6; `Switch` created + used in Task 6. ✅
- **Dependency on backend (#96):** stated in Architecture — settings GET must be member-readable and expose `allow_staff_approval` before Tasks 4/5/6 work end-to-end. ✅
- **Placeholder scan:** verification asides ("verify exact Dialog export names", "if common.cancel is missing") are concrete checks against named files, not TBDs; expiry options + all copy are concrete. ✅
- **Rule 17.0:** semantic tokens only; composes `components/ui/*`; new `Switch` is a tokened primitive. ✅
```

---

## REVISION (2026-06-22): Tasks 6 & 7 superseded by the merged Scheduling pane
Design changed after render review (see spec §11). **Task 6 and Task 7 are replaced by a single task**: rewrite `src/features/settings/scheduling-pane.tsx` to host three cards (Scheduling Workflow → Staff Approval → Request Expiry) with contextual disable + compact lock notes under Direct Booking, a single Save that persists all three fields, and the auto-approve-on-switch confirm — plus a new `src/components/ui/switch.tsx` primitive and i18n. **No separate `appointment-settings-pane.tsx`, no settings-shell nav change.** Visual source of truth: the approved render at `/tmp/appt-settings-render/index.html`. Task 8 (tsc + build + i18n parity) stands as the final verify.
