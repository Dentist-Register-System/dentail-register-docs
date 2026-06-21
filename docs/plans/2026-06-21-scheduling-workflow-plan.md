# Scheduling Workflow (Direct Booking vs Doctor Approval) Implementation Plan (#87)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a clinic-level `scheduling_workflow` setting (`direct_booking` default | `doctor_approval`); in direct mode a booking auto-confirms instead of creating a pending approval request.

**Architecture:** Backend — column on `clinic_settings_beta` + schemas + `create_clinic` writes it + `create_request` auto-confirms (reusing an extracted `_materialize_appointment` helper). Frontend — settings api/hook + types (T3), Settings → Scheduling pane + sub-nav (T4), clinic-setup wizard step (T5), requests-queue gating + booking copy (T6). Notifications stay stubbed (hooks unchanged).

**Tech Stack:** FastAPI / SQLAlchemy 2.x / Alembic / pytest (backend); Next.js App Router / TanStack Query / react-i18next / Tailwind v4 tokens (frontend).

## Global Constraints
- **Backend:** sync SQLAlchemy; UUID PKs; uniform error envelope; in-transaction audit via `record_audit`; cross-module calls go through the other module's `service` (never models). `uv run ruff check .` MUST pass (CI runs it). `make test` against local PG :5433. **Migrations are controller-only:** the implementer writes the Alembic migration file + model + schemas and validates with `alembic upgrade head` + `make test` locally; the **controller** applies it to Supabase via the MCP `apply_migration` (never run alembic against Supabase).
- **Enum values (exact):** `scheduling_workflow ∈ ('direct_booking','doctor_approval')`, default `'direct_booking'`. `Appointment.source` new value `'direct_booking'` (existing `'request_approval'`).
- **Frontend:** Rule 17.0 — semantic tokens only (no raw colours / palette utils), compose `components/ui/*`, no per-page CSS, no new tokens; inline `var(--token)` allowed. i18n: every new string a `t()` key in BOTH `src/i18n/locales/en.json` and `hi.json` (parity gate `tests/e2e/i18n.spec.ts`). Match the Profile/Clinic pane conventions (`Card`→`CardHeader`(CardTitle+muted subtitle)→`CardSeparator`→`CardContent`; outlined `size="sm"` actions; labels `text-sm text-muted-foreground`, values `font-medium`). Both themes; mobile-first; WCAG AA. CI = `npx tsc --noEmit` + `npm run build`; also run `tests/e2e/i18n.spec.ts` + any touched e2e locally. Stale iCloud `* 2.ts*` files break tsc → delete + re-run.
- **Mockup:** the Settings → Scheduling screen the user provided (radio cards "Direct Booking" pre-selected / "Doctor Approval", each with description + "Recommended for" bullets, info note, Save Changes). Match it within the design system.
- Commit trailer `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`; stage SPECIFIC paths (never `git add -A`; never stage `.superpowers/`); don't touch `.env`/`.env.local`.
- **Merge policy:** backend PR may squash-merge after green review; **frontend PR opens then STOPS** for the user's test (merge only on explicit say-so). Never merge red — verify `gh-personal pr checks` green first.

---

## Task 1: Backend — `scheduling_workflow` column, schemas, create-clinic wiring

**Files (`dentist-registry-backend`):**
- Create: `alembic/versions/0012_scheduling_workflow.py`
- Modify: `app/modules/clinics/models.py` (ClinicSettings), `app/modules/clinics/schemas.py` (ClinicSettingsRead/Update, ClinicCreate, ClinicRead), `app/modules/clinics/service.py` (create_clinic)
- Test: `tests/clinics/` (add a settings/workflow test file or extend existing)

**Interfaces produced:** `ClinicSettings.scheduling_workflow: str`; `ClinicSettingsRead.scheduling_workflow`, `ClinicSettingsUpdate.scheduling_workflow: str | None`, `ClinicCreate.scheduling_workflow: str` (default `"direct_booking"`), `ClinicRead.scheduling_workflow: str`.

- [ ] **Step 1: Migration.** Create `alembic/versions/0012_scheduling_workflow.py` (revises `0011`). Table is `clinic_settings_beta`:
```python
"""scheduling_workflow on clinic_settings

Revision ID: 0012
Revises: 0011
"""
from alembic import op
import sqlalchemy as sa

revision = "0012"
down_revision = "0011"
branch_labels = None
depends_on = None

def upgrade() -> None:
    op.add_column(
        "clinic_settings_beta",
        sa.Column("scheduling_workflow", sa.String(length=20), nullable=False, server_default="direct_booking"),
    )
    op.create_check_constraint(
        "ck_clinic_settings_scheduling_workflow",
        "clinic_settings_beta",
        "scheduling_workflow IN ('direct_booking','doctor_approval')",
    )

def downgrade() -> None:
    op.drop_constraint("ck_clinic_settings_scheduling_workflow", "clinic_settings_beta", type_="check")
    op.drop_column("clinic_settings_beta", "scheduling_workflow")
```
(Confirm `0011` is the current head: `ls alembic/versions/ | tail`. If the head differs, set `down_revision` to the actual head.)

- [ ] **Step 2: Model.** In `app/modules/clinics/models.py`, add to `ClinicSettings` (after `google_calendar_enabled`):
```python
    scheduling_workflow: Mapped[str] = mapped_column(String(20), default="direct_booking")
```
(Confirm `String` is imported in that file; it is used elsewhere — if not, add to the SQLAlchemy import.)

- [ ] **Step 3: Schemas.** In `app/modules/clinics/schemas.py`:
  - Add to `ClinicSettingsRead`: `scheduling_workflow: str`
  - Add to `ClinicSettingsUpdate`: `scheduling_workflow: str | None = None` plus a validator:
```python
    @field_validator("scheduling_workflow")
    @classmethod
    def validate_scheduling_workflow(cls, v: str | None) -> str | None:
        if v is not None and v not in ("direct_booking", "doctor_approval"):
            raise ValueError("scheduling_workflow must be 'direct_booking' or 'doctor_approval'.")
        return v
```
  - Add to `ClinicCreate`: `scheduling_workflow: str = Field(default="direct_booking")` plus the same validator (non-optional variant: reject values outside the two).
  - Add to `ClinicRead`: `scheduling_workflow: str` — and make it populate from the settings row (see Step 4 note).

- [ ] **Step 4: create_clinic writes the setting + ClinicRead exposes it.** In `app/modules/clinics/service.py` `create_clinic`, change the settings creation line:
```python
    db.add(ClinicSettings(clinic_id=clinic.id, scheduling_workflow=data.scheduling_workflow))
```
For `ClinicRead.scheduling_workflow`: the router returns `ClinicRead.model_validate(clinic)`, but `scheduling_workflow` lives on `ClinicSettings`, not `Clinic`. Resolve by having the clinic-read path attach it. Inspect `app/modules/clinics/router.py` `get_clinic`/read endpoint: after loading the clinic, fetch `get_settings(db, clinic_id)` and build the response with `scheduling_workflow=settings.scheduling_workflow` (e.g. `ClinicRead(**clinic_as_dict, scheduling_workflow=settings.scheduling_workflow)` or set the attr before `model_validate`). Keep it in the service/router layer (no model change). Pick the approach that fits the existing read code; the requirement is `GET /clinics/{id}` returns `scheduling_workflow` for any member.

- [ ] **Step 5: Tests.** Add `tests/clinics/test_scheduling_workflow.py`:
```python
def test_create_clinic_defaults_direct_booking(auth_client):
    # POST /clinics without scheduling_workflow -> settings.scheduling_workflow == "direct_booking"
    ...
def test_create_clinic_with_doctor_approval(auth_client):
    # POST /clinics with scheduling_workflow="doctor_approval" -> persisted
    ...
def test_get_settings_includes_workflow_and_patch_toggles(auth_client):
    # GET /clinics/{id}/settings shows scheduling_workflow; PATCH to "doctor_approval" persists
    ...
def test_get_clinic_exposes_workflow(auth_client):
    # GET /clinics/{id} returns scheduling_workflow
    ...
def test_patch_settings_rejects_bad_workflow(auth_client):
    # PATCH scheduling_workflow="nope" -> 422/validation error
    ...
```
(Mirror fixtures from existing `tests/clinics/` tests for auth + clinic creation.)

- [ ] **Step 6: Validate.** `cd dentist-registry-backend && docker compose up -d && uv run alembic upgrade head && uv run ruff check . && make test` — all green. (Controller applies the migration to Supabase via MCP separately.)

- [ ] **Step 7: Commit.** `git add alembic/versions/0012_scheduling_workflow.py app/modules/clinics/models.py app/modules/clinics/schemas.py app/modules/clinics/service.py app/modules/clinics/router.py tests/clinics/test_scheduling_workflow.py` → `feat(clinics): scheduling_workflow setting (default direct_booking) (#87)`.

---

## Task 2: Backend — direct-booking auto-confirm in `create_request`

**Files (`dentist-registry-backend`):**
- Modify: `app/modules/scheduling/booking.py`
- Test: `tests/scheduling/test_booking.py` (extend) or new `tests/scheduling/test_direct_booking.py`

**Interfaces:** Consumes `ClinicSettings.scheduling_workflow` (Task 1). Produces: in direct mode `create_request` returns an `AppointmentRequest` whose `status == "approved"` and `created_appointment_id` is set; a confirmed `Appointment` with `source="direct_booking"` exists.

- [ ] **Step 1: Failing test.** In `tests/scheduling/test_direct_booking.py` (reuse `tests/scheduling/test_booking.py` fixtures for clinic + doctor + availability + patient):
```python
def test_direct_booking_auto_confirms(auth_client, ...):
    # clinic settings scheduling_workflow="direct_booking" (default)
    # POST appointment-requests -> response.status == "approved", created_appointment_id set
    # and an Appointment exists with status "confirmed", source "direct_booking"
    ...
def test_doctor_approval_still_pending(auth_client, ...):
    # set scheduling_workflow="doctor_approval"; booking -> status "pending", no appointment yet;
    # then approve -> confirmed (regression)
    ...
def test_direct_booking_respects_capacity(auth_client, ...):
    # capacity 1: first direct booking confirms; second on same slot -> slot_full
    ...
```

- [ ] **Step 2: Run → fail** (`make test`).

- [ ] **Step 3: Extract `_materialize_appointment`.** In `booking.py`, refactor the appointment-creation block out of `approve_request` into a reusable helper (slot already locked by caller; req already validated):
```python
def _materialize_appointment(
    db: Session,
    *,
    clinic_id: uuid.UUID,
    req: AppointmentRequest,
    slot: Slot,
    actor_user_id: uuid.UUID,
    source: str,
) -> Appointment:
    appt = Appointment(
        clinic_id=clinic_id,
        patient_id=req.patient_id,
        doctor_id=req.doctor_id,
        slot_id=req.slot_id,
        start_datetime=req.start_datetime,
        end_datetime=slot.end_datetime,
        status="confirmed",
        source=source,
        request_id=req.id,
        requested_by=req.requested_by,
        approved_by=actor_user_id,
        chief_complaint=req.chief_complaint,
        notes=req.notes,
    )
    db.add(appt)
    db.flush()
    req.status = "approved"
    req.created_appointment_id = appt.id
    record_audit(
        db, action="appointment.created", entity_type="appointment", entity_id=appt.id,
        clinic_id=clinic_id, actor_user_id=actor_user_id, new={"request_id": str(req.id), "source": source},
    )
    return appt
```
Then make `approve_request` use it: replace its inline `Appointment(...)` + `db.add` + `req.status/created_appointment_id` + the `appointment.created` audit with `appt = _materialize_appointment(db, clinic_id=clinic_id, req=req, slot=slot, actor_user_id=actor_user_id, source="request_approval")` (keep the existing `appointment_request.approved` audit + the pre-checks + `db.commit(); db.refresh(appt); return appt`).

- [ ] **Step 4: Branch in `create_request`.** After `db.flush()` of the new `req` (and BEFORE the final `record_audit`/`commit`, or right after the create audit), add the direct-booking branch. `reserve_slot` already locked the slot and returned it as `slot`; reuse it:
```python
    if settings.scheduling_workflow == "direct_booking":
        appt = _materialize_appointment(
            db, clinic_id=clinic_id, req=req, slot=slot,
            actor_user_id=actor_user_id, source="direct_booking",
        )
        record_audit(
            db, action="appointment_request.auto_approved",
            entity_type="appointment_request", entity_id=req.id,
            clinic_id=clinic_id, actor_user_id=actor_user_id,
            new={"appointment_id": str(appt.id)},
        )
    db.commit()
    db.refresh(req)
    return req
```
(`settings` is already loaded in `create_request`. The capacity check in `reserve_slot` counted this pending request as a consumer; materializing then converts it to a confirmed appointment on the same slot — net capacity unchanged, so no extra capacity check is needed here. The existing `appointment_request.created` audit stays.)

- [ ] **Step 5: Run → pass** (`make test`). Confirm `test_booking.py` (existing) still passes — those tests use the default clinic settings; if they assumed `pending` after booking, they may now see `approved` under the default `direct_booking`. **If so, that is expected** — update those assertions to set `scheduling_workflow="doctor_approval"` in their fixture (so they keep testing the approval loop), OR assert the new direct-mode outcome, whichever matches each test's intent. Do not weaken capacity/concurrency assertions.

- [ ] **Step 6: ruff + commit.** `uv run ruff check .` clean. `git add app/modules/scheduling/booking.py tests/scheduling/test_direct_booking.py tests/scheduling/test_booking.py` → `feat(scheduling): direct-booking auto-confirm in create_request (#87)`.

> Backend PR (Tasks 1+2): open + review + **controller applies migration 0012 to Supabase via MCP**, verify CI green, then may squash-merge.

---

## Task 3: Frontend — settings api/hook + types

**Files (`dentist-registry-frontend`):**
- Modify: `src/features/clinic/api.ts` (Clinic type + createClinic payload + new settings api), `src/features/clinic/hooks.ts` (settings hooks), `src/features/scheduling/api.ts` (AppointmentRequest type fields if missing)

**Interfaces produced:** `ClinicSettings` type + `getClinicSettings(clinicId)` + `updateClinicSettings(clinicId, payload)`; `useClinicSettings(clinicId)` + `useUpdateClinicSettings(clinicId)` (query key `["clinic-settings", clinicId]`); `Clinic.scheduling_workflow: "direct_booking" | "doctor_approval"`; createClinic payload accepts `scheduling_workflow?`.

- [ ] **Step 1: Types + api.** In `src/features/clinic/api.ts`:
  - Add `scheduling_workflow: "direct_booking" | "doctor_approval"` to the `Clinic` type.
  - Add `scheduling_workflow?: "direct_booking" | "doctor_approval"` to the createClinic payload type.
  - Add:
```typescript
export type ClinicSettings = {
  allow_multiple_bookings_per_slot: boolean;
  max_bookings_per_slot: number;
  default_slot_size_minutes: number;
  appointment_request_expiry_minutes: number;
  post_confirmation_hook_delay_minutes: number;
  reminders_enabled: boolean;
  whatsapp_enabled: boolean;
  google_calendar_enabled: boolean;
  scheduling_workflow: "direct_booking" | "doctor_approval";
};
export const getClinicSettings = (clinicId: string) =>
  apiFetch<ClinicSettings>("/api/v1/clinics/" + clinicId + "/settings");
export const updateClinicSettings = (
  clinicId: string,
  payload: Partial<ClinicSettings>,
) =>
  apiFetch<ClinicSettings>("/api/v1/clinics/" + clinicId + "/settings", {
    method: "PATCH",
    body: JSON.stringify(payload),
  });
```
  (Match the existing `apiFetch` call style in this file.)

- [ ] **Step 2: Hooks.** In `src/features/clinic/hooks.ts`:
```typescript
export function useClinicSettings(clinicId: string) {
  return useQuery({
    queryKey: ["clinic-settings", clinicId],
    queryFn: () => getClinicSettings(clinicId),
    enabled: !!clinicId,
  });
}
export function useUpdateClinicSettings(clinicId: string) {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (payload: Partial<ClinicSettings>) => updateClinicSettings(clinicId, payload),
    onSuccess: () => { void qc.invalidateQueries({ queryKey: ["clinic-settings", clinicId] }); },
  });
}
```
  (Import `getClinicSettings`/`updateClinicSettings`/`ClinicSettings` from `./api`.)

- [ ] **Step 3: Request type.** In `src/features/scheduling/api.ts`, ensure the `AppointmentRequest` type (the create response) includes `status: string` and `created_appointment_id: string | null` (add if missing) so the dialog can detect auto-confirmation.

- [ ] **Step 4: Verify + commit.** `npx tsc --noEmit && npm run build`. `git add src/features/clinic/api.ts src/features/clinic/hooks.ts src/features/scheduling/api.ts` → `feat(clinic): clinic-settings api/hook + scheduling_workflow types (#87)`.

---

## Task 4: Frontend — Settings → Scheduling pane + sub-nav

**Files:**
- Create: `src/features/settings/scheduling-pane.tsx`
- Modify: `src/features/settings/settings-shell.tsx` (add "scheduling" section), `src/i18n/locales/en.json` + `hi.json`

**Interfaces:** Consumes `useClinicSettings`/`useUpdateClinicSettings` (Task 3), `useSuccess`.

- [ ] **Step 1: Sub-nav.** In `settings-shell.tsx`: extend `type Section = "profile" | "clinic" | "scheduling"`; add `{ key: "scheduling", labelKey: "settings.nav.scheduling", icon: "event_available" }` to `items`; render `<SchedulingPane clinicId={clinicId} canManage={canManageClinic} />` when `section === "scheduling"`.

- [ ] **Step 2: i18n (en + hi parity).** Add under `settings.nav`: `"scheduling": "Scheduling"` (hi: `"शेड्यूलिंग"`). Add a `settings.scheduling` block + a `scheduling.workflow` block with: pane title "Scheduling" + subtitle "Manage how appointments are created and approved in your clinic"; card title "Scheduling Workflow" + "Choose how appointments are confirmed in your clinic"; `directBooking.title`="Direct Booking", `directBooking.desc`="Appointments are immediately confirmed.", `doctorApproval.title`="Doctor Approval", `doctorApproval.desc`="Appointments require doctor approval before confirmation."; `recommendedFor`="Recommended for:"; bullet arrays as individual keys (`directBooking.r1`="Solo practices", `directBooking.r2`="Clinics where doctors manage their own schedules"; `doctorApproval.r1`="Clinics with assistants", `doctorApproval.r2`="Multi-doctor clinics", `doctorApproval.r3`="Visiting consultants"); `note`="You can change this setting at any time. It will apply to all future appointments."; `save`="Save Changes". Mirror ALL in `hi.json` (parity). Reuse `common.loading`, `apiErrors.default`.

- [ ] **Step 3: The pane.** Create `scheduling-pane.tsx` matching the mockup + Profile-pane conventions. Structure:
  - `<div className="space-y-5" data-testid="settings-scheduling">`. Header block (title + subtitle) like the Clinic pane header.
  - A `Card`: `CardHeader` (icon `event` in a `bg-primary-container` rounded square + `CardTitle` "Scheduling Workflow" + muted subtitle) → `CardSeparator` → `CardContent`.
  - Local state seeded from `useClinicSettings`: `const [choice, setChoice] = useState<Workflow>()` initialized once data loads (guard for `isPending`).
  - Two **radio cards** (buttons with `role="radio"`/`aria-checked`, full-width, left radio dot + icon + title + description + "Recommended for" bullet list). Selected card: `border-primary bg-primary-container/30`; unselected: `border-border`. testids `workflow-option-direct_booking` / `workflow-option-doctor_approval`. Disabled (not clickable) when `!canManage`.
  - Info note row (icon `info` + the `note` text) in a soft `bg-muted/50` rounded box.
  - **Save Changes** `Button` (right-aligned), `data-testid="scheduling-save"`, disabled when `!canManage` or `choice === settings.scheduling_workflow` or mutation pending; on click `useUpdateClinicSettings.mutate({ scheduling_workflow: choice })` → on success show a success card (`titleKey` e.g. `settings.scheduling.saved`, add that i18n key too) .
  - Semantic tokens only; both themes; mobile-first (cards stack). Read-only (radios non-interactive, no Save) when `!canManage`.

- [ ] **Step 4: Verify + commit.** `npx tsc --noEmit && npm run build && npx playwright test tests/e2e/i18n.spec.ts`. `git add src/features/settings/scheduling-pane.tsx src/features/settings/settings-shell.tsx src/i18n/locales/en.json src/i18n/locales/hi.json` → `feat(settings): Scheduling Workflow pane + sub-nav (#87)`.

---

## Task 5: Frontend — clinic-setup wizard step

**Files:**
- Modify: `src/features/auth/onboarding.tsx`, `src/i18n/locales/en.json` + `hi.json`

**Interfaces:** Consumes the createClinic payload `scheduling_workflow` (Task 3).

- [ ] **Step 1: Form field.** In `onboarding.tsx`, add `scheduling_workflow` to `_createSchemaStatic` (`z.enum(["direct_booking","doctor_approval"])`) and to the form `defaultValues` (`scheduling_workflow: "direct_booking"`). In `onSubmit`, add `payload.scheduling_workflow = values.scheduling_workflow;`.

- [ ] **Step 2: Wizard step.** Add a `WizardStep<CreateValues>` (place it sensibly, e.g. after the address/contact steps, before the final review): `key: "scheduling"`, `labelKey: "clinicWizard.steps.scheduling"`, `questionKey: "clinicWizard.q.scheduling"`, `fields: ["scheduling_workflow"]`, `isComplete: (v) => !!v.scheduling_workflow`. `content`: a `FormField` for `scheduling_workflow` rendering the same two radio cards as Task 4 (Direct Booking pre-selected) — reuse the same i18n option keys — plus a helper line: `t("clinicWizard.schedulingHelp")` = "Don't worry — you can change this anytime in Settings → Scheduling." (Consider extracting a small shared `WorkflowOptions` component used by both this step and the Scheduling pane to avoid duplication; if extracted, put it in `src/features/scheduling/` or `src/features/settings/` and import in both. DRY but only if clean.)

- [ ] **Step 3: i18n (en + hi).** Add `clinicWizard.steps.scheduling`="Scheduling", `clinicWizard.q.scheduling`="How should appointments be confirmed?", `clinicWizard.schedulingHelp`="Don't worry — you can change this anytime in Settings → Scheduling." (+ Hindi). Reuse the `scheduling.workflow.*` option keys from Task 4.

- [ ] **Step 4: Verify + commit.** `npx tsc --noEmit && npm run build && npx playwright test tests/e2e/i18n.spec.ts`; also run `npx playwright test tests/e2e/auth.spec.ts` (onboarding flow touched) — confirm it passes or update the create-clinic flow assertions to advance through the new step. `git add src/features/auth/onboarding.tsx src/i18n/locales/en.json src/i18n/locales/hi.json` (+ the shared component if extracted) → `feat(onboarding): scheduling workflow step in clinic setup (#87)`.

---

## Task 6: Frontend — requests-queue gating + booking confirmation copy

**Files:**
- Modify: `src/app/requests/page.tsx` (pass approval-mode gate), `src/features/scheduling/requests-queue.tsx` (only if needed), `src/features/scheduling/request-dialog.tsx`, `src/i18n/locales/en.json` + `hi.json`

**Interfaces:** Consumes `Clinic.scheduling_workflow` (Task 3) via `useClinic`; `AppointmentRequest.status`/`created_appointment_id` (Task 3).

- [ ] **Step 1: Hide Approve/Reject in direct mode.** In `src/app/requests/page.tsx`, read the clinic: `const clinic = useClinic(clinicId);` and compute `const approvalMode = clinic.data?.scheduling_workflow !== "direct_booking";`. Pass `canDecide={canDecide && approvalMode}` to `<RequestsQueue>` (it already gates Approve/Reject on `canDecide`). `canCoordinate` (Cancel/Resend) is unchanged. (No change needed inside `requests-queue.tsx` if it already gates the decide buttons on the `canDecide` prop — verify; if it reads canDecide differently, adjust there instead.)

- [ ] **Step 2: Booking confirmation copy.** In `request-dialog.tsx`, capture the mutation result and branch the success card. Change `onSuccess: () =>` to `onSuccess: (res) =>` and:
```typescript
        onSuccess: (res) => {
          setOpen(false); setPatientId(""); setQ(""); setComplaint(""); setNotes("");
          const confirmed = res.status === "approved" || res.created_appointment_id != null;
          success({
            titleKey: confirmed ? "success.appointmentConfirmed" : "success.requestSent",
            details: [
              { labelKey: "success.label.patient", value: patientName },
              { labelKey: "success.label.when", value: label },
            ],
          });
          setPatientName("");
        },
```
  Add `success.appointmentConfirmed`="Appointment confirmed" (hi: appropriate) to both locales if not already present (it may exist from the approval flow — reuse if so; do NOT duplicate the key).

- [ ] **Step 3: Verify + commit.** `npx tsc --noEmit && npm run build && npx playwright test tests/e2e/i18n.spec.ts`. `git add src/app/requests/page.tsx src/features/scheduling/request-dialog.tsx src/i18n/locales/en.json src/i18n/locales/hi.json` (+ requests-queue.tsx if touched) → `feat(scheduling): hide approve in direct mode + confirmed booking copy (#87)`.

> Frontend PR (Tasks 3–6): open + opus whole-branch review + render the wizard step + Scheduling page → then STOP for the user's test (no auto-merge).

---

## Self-Review (plan vs spec)
- **scheduling_workflow column + default direct_booking + schemas + ClinicRead exposure:** Task 1. ✅ (§3)
- **Auto-confirm in create_request reusing _materialize_appointment; doctor-approval untouched:** Task 2. ✅ (§4)
- **FE settings api/hook + types:** Task 3. ✅ (§5)
- **Settings → Scheduling pane (mockup) + 3rd sub-nav:** Task 4. ✅ (§5b)
- **Clinic-setup wizard step + "change later" helper:** Task 5. ✅ (§5a)
- **Requests: Approve/Reject hidden in direct mode (Cancel kept); confirmed booking copy:** Task 6. ✅ (§5c)
- **Notifications deferred (no sending):** no task touches WhatsApp/calendar. ✅ (§8)
- **Rule 17.0 + i18n parity + both themes + ruff + migration-via-MCP + merge policy:** Global Constraints + per-task verify. ✅ (§7)
- **Type consistency:** `scheduling_workflow` enum strings identical across BE (CHECK/validator) + FE (`"direct_booking"|"doctor_approval"`); `_materialize_appointment(source=...)` used by both approve + direct paths; `["clinic-settings", clinicId]` key consistent. ✅
- **Placeholder scan:** backend steps carry full code; FE composition tasks give exact files/props/testids/i18n keys + reference the mockup (UI-composition pattern). ✅
