# Requests Page Redesign Implementation Plan (#89)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Redesign Requests into enriched, status-colour-coded, server-paginated carded rows (tabs-with-counts + Filters + search), and add a `gender` field across the patient surface.

**Architecture:** Backend — add nullable `gender` to patient (T1); rewrite the requests list to enriched + paginated + searchable `{items,total}` + a counts endpoint (T2). Frontend — gender in patient forms/detail (T3); requests data layer + pure status helper (T4); the redesigned list/toolbar/rows (T5); Filters popover + pagination + actions (T6). Server-driven; `refetchOnWindowFocus` + invalidate-on-mutation for multi-device freshness.

**Tech Stack:** FastAPI / SQLAlchemy 2.x / Alembic / pytest; Next.js App Router / TanStack Query / RHF+Zod / react-i18next / Tailwind v4 tokens.

## Global Constraints
- **Backend:** sync SQLAlchemy; UUID PKs; uniform error envelope; in-transaction audit; cross-module reads go through the other module's service (a read-only JOIN on `patient_beta`/`doctor_beta` inside a scheduling query is acceptable; do NOT mutate or import their models' internals beyond columns for the join). `uv run ruff check .` MUST pass. `make test` on local PG :5433. **Migrations controller-only:** implementer writes the Alembic file + validates `alembic upgrade head` + `make test` locally; the **controller** applies via Supabase MCP.
- **Enum:** `gender ∈ ('male','female','other')` nullable. Request `status ∈ ('pending','approved','rejected','cancelled')`.
- **Frontend:** Rule 17.0 — semantic tokens ONLY (no raw colours / palette utils), compose `components/ui/*`, no per-page CSS, no new tokens; inline `var(--token)` allowed. i18n: every new string a `t()` key in BOTH `src/i18n/locales/en.json` + `hi.json` (parity gate `tests/e2e/i18n.spec.ts`). Both themes; mobile-first; WCAG AA (status by chip text + colour, not colour alone). Match Patients/Settings conventions (Card/CardSeparator, type scale, body-portaled ⋮ menu from `patients-table.tsx`). CI = `tsc --noEmit` + `npm run build`; run `i18n.spec.ts` + touched e2e locally. Stale iCloud `* [0-9].ts*` files break tsc → delete + re-run.
- **Status tokens:** pending→`warning`, approved→`success`, rejected→`destructive`, cancelled→`muted`.
- **Mockup:** `Mockups/requests_mockup_final.png` — match within the design system.
- Commit trailer `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`; stage SPECIFIC paths (never `git add -A`; never `.superpowers/`); don't touch `.env`/`.env.local`.
- **Merge policy:** backend PR may squash-merge after green review (controller applies migration to Supabase); **frontend PR opens then STOPS** for the user's test. Never merge red.

---

## Task 1: Backend — patient `gender` field

**Files:** Create `alembic/versions/00NN_patient_gender.py` (NN = next after current head — run `ls alembic/versions/ | tail -1` to find it; revise that head). Modify `app/modules/patients/models.py`, `app/modules/patients/schemas.py`, `app/modules/patients/service.py`. Test `tests/patients/`.

**Interfaces produced:** `Patient.gender: str | None`; `gender` on `PatientCreate`/`PatientUpdate`/`PatientRead`.

- [ ] **Step 1: Migration.** Create the file (revises the current head, table `patient_beta`):
```python
from alembic import op
import sqlalchemy as sa
revision = "00NN"; down_revision = "<current_head>"; branch_labels = None; depends_on = None
def upgrade() -> None:
    op.add_column("patient_beta", sa.Column("gender", sa.String(length=10), nullable=True))
    op.create_check_constraint("ck_patient_gender", "patient_beta", "gender IN ('male','female','other')")
def downgrade() -> None:
    op.drop_constraint("ck_patient_gender", "patient_beta", type_="check")
    op.drop_column("patient_beta", "gender")
```
(The CHECK permits NULL automatically.)

- [ ] **Step 2: Model.** In `patients/models.py` add to `Patient`: `gender: Mapped[str | None] = mapped_column(String(10), nullable=True)` (ensure `String` imported).

- [ ] **Step 3: Schemas.** In `patients/schemas.py`: add `gender: str | None = None` to `PatientCreate` and `PatientUpdate`; add `gender: str | None` to `PatientRead`. Add a shared validator on Create+Update:
```python
from pydantic import field_validator
@field_validator("gender")
@classmethod
def _validate_gender(cls, v: str | None) -> str | None:
    if v is not None and v not in ("male", "female", "other"):
        raise ValueError("gender must be 'male', 'female', or 'other'.")
    return v
```

- [ ] **Step 4: Service.** In `patients/service.py` `create_patient`, add `gender=data.gender` to the `Patient(...)` construction. In `update_patient`, ensure `gender` is included in the updatable fields (it likely uses `data.model_dump(exclude_unset=True)` — if so, no change needed; otherwise add `gender` to the field list). Confirm `gender` round-trips.

- [ ] **Step 5: Tests.** `tests/patients/test_gender.py`: create with gender → persisted + in read; create without gender → null; update sets gender; invalid gender → 422. (Mirror existing patients-test fixtures.)

- [ ] **Step 6: Validate.** `docker compose up -d && uv run alembic upgrade head && uv run ruff check . && make test` — green. **Step 7: Commit** specific paths → `feat(patients): nullable gender field (#89)`.

---

## Task 2: Backend — enriched, paginated, searchable requests list + counts

**Files:** Modify `app/modules/scheduling/schemas.py` (RequestListItem + new `RequestListPage`, `RequestCounts`), `app/modules/scheduling/booking.py` (`list_requests`, `count_by_status`), `app/modules/scheduling/router.py` (list endpoint params + response, counts endpoint). Test `tests/scheduling/test_requests_list.py`.

**Interfaces produced:** `GET .../appointment-requests?status=&q=&doctor_id=&date_from=&date_to=&limit=&offset=` → `RequestListPage { items: list[RequestListItem], total: int }`; `GET .../appointment-requests/counts` → `RequestCounts { all, pending, approved, rejected, cancelled }`. `RequestListItem` gains `patient_name, patient_age, patient_gender, patient_phone, doctor_name, created_at, updated_at`.

- [ ] **Step 1: Failing tests** in `tests/scheduling/test_requests_list.py` (reuse `tests/scheduling/test_booking.py` fixtures to create clinic + doctor + patient(s) + requests in various statuses; set `scheduling_workflow="doctor_approval"` so pending requests exist):
```python
def test_list_returns_enriched_fields(...):
    # item has patient_name, patient_age, patient_gender, patient_phone, doctor_name, created_at, updated_at, status
def test_list_status_filter(...):
def test_list_search_matches_name_phone_doctor_complaint(...):  # q= each
def test_list_doctor_and_date_filters(...):
def test_list_pagination_total_and_slice(...):  # limit/offset + total stable
def test_counts_endpoint(...):  # {all,pending,approved,rejected,cancelled} correct
```

- [ ] **Step 2: Run → fail.**

- [ ] **Step 3: Schemas.** In `scheduling/schemas.py` extend `RequestListItem`:
```python
class RequestListItem(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: uuid.UUID
    patient_id: uuid.UUID
    doctor_id: uuid.UUID
    patient_name: str
    patient_age: int | None
    patient_gender: str | None
    patient_phone: str | None
    doctor_name: str
    start_datetime: dt.datetime
    status: str
    chief_complaint: str | None
    expires_at: dt.datetime
    expired: bool = False
    created_at: dt.datetime
    updated_at: dt.datetime

class RequestListPage(BaseModel):
    items: list[RequestListItem]
    total: int

class RequestCounts(BaseModel):
    all: int
    pending: int
    approved: int
    rejected: int
    cancelled: int
```

- [ ] **Step 4: Service `list_requests`.** Rewrite to join + filter + search + paginate and return `(items, total)`. Build a base query joining the patient + doctor rows:
```python
from app.modules.patients.models import Patient
from app.modules.doctors.models import Doctor
from sqlalchemy import or_, func, select

def list_requests(
    db, *, clinic_id, doctor_id=None, status=None, q=None,
    date_from=None, date_to=None, limit=5, offset=0,
):
    base = (
        select(AppointmentRequest, Patient, Doctor)
        .join(Patient, Patient.id == AppointmentRequest.patient_id)
        .join(Doctor, Doctor.id == AppointmentRequest.doctor_id)
        .where(AppointmentRequest.clinic_id == clinic_id)
    )
    if doctor_id is not None:
        base = base.where(AppointmentRequest.doctor_id == doctor_id)
    if status:
        base = base.where(AppointmentRequest.status == status)
    if date_from is not None:
        base = base.where(AppointmentRequest.start_datetime >= date_from)
    if date_to is not None:
        base = base.where(AppointmentRequest.start_datetime < date_to)  # caller passes end-exclusive (next day)
    if q:
        like = f"%{q}%"
        base = base.where(or_(
            Patient.name.ilike(like), Patient.phone.ilike(like),
            Doctor.name.ilike(like), AppointmentRequest.chief_complaint.ilike(like),
        ))
    total = db.execute(select(func.count()).select_from(base.subquery())).scalar_one()
    rows = db.execute(
        base.order_by(AppointmentRequest.created_at.desc()).limit(limit).offset(offset)
    ).all()
    items = [
        {
            "id": r.id, "patient_id": r.patient_id, "doctor_id": r.doctor_id,
            "patient_name": p.name, "patient_age": p.age, "patient_gender": p.gender, "patient_phone": p.phone,
            "doctor_name": d.name,
            "start_datetime": r.start_datetime, "status": r.status,
            "chief_complaint": r.chief_complaint, "expires_at": r.expires_at, "expired": is_expired(r),
            "created_at": r.created_at, "updated_at": r.updated_at,
        }
        for (r, p, d) in rows
    ]
    return items, total

def count_by_status(db, *, clinic_id) -> dict:
    rows = db.execute(
        select(AppointmentRequest.status, func.count())
        .where(AppointmentRequest.clinic_id == clinic_id)
        .group_by(AppointmentRequest.status)
    ).all()
    by = {s: 0 for s in ("pending", "approved", "rejected", "cancelled")}
    for status_val, n in rows:
        if status_val in by:
            by[status_val] = n
    by_all = sum(by.values())
    return {"all": by_all, **by}
```
(Joining read-only on `Patient`/`Doctor` tables within scheduling's query is the boundary-respecting choice for an enriched read; we import only the model classes for the join, no service mutation.)

- [ ] **Step 5: Router.** Update the list endpoint + add counts:
```python
@router.get("/{clinic_id}/appointment-requests", response_model=RequestListPage)
def list_requests(
    clinic_id: uuid.UUID, db: DbSession, membership: CurrentMembership,
    doctor_id: uuid.UUID | None = None, status: str | None = None, q: str | None = None,
    date_from: dt.date | None = None, date_to: dt.date | None = None,
    limit: int = 5, offset: int = 0,
):
    # date_to is inclusive of that day → pass end-exclusive next-day midnight to the service
    df = dt.datetime.combine(date_from, dt.time.min) if date_from else None
    dto = dt.datetime.combine(date_to + dt.timedelta(days=1), dt.time.min) if date_to else None
    items, total = booking.list_requests(
        db, clinic_id=clinic_id, doctor_id=doctor_id, status=status, q=q,
        date_from=df, date_to=dto, limit=min(limit, 100), offset=offset,
    )
    return RequestListPage(items=items, total=total)

@router.get("/{clinic_id}/appointment-requests/counts", response_model=RequestCounts)
def request_counts(clinic_id: uuid.UUID, db: DbSession, membership: CurrentMembership):
    return RequestCounts(**booking.count_by_status(db, clinic_id=clinic_id))
```
(Import `RequestListPage`, `RequestCounts`, `dt`. Place the `/counts` route so it doesn't collide with the `{request_id}` routes — counts is a fixed segment, fine. Keep the existing `pending-count` endpoint as-is for the nav badge, or repoint it later — do not remove in this task.)

- [ ] **Step 6: Run → pass; ruff clean. Step 7: Commit** specific paths → `feat(scheduling): enriched paginated requests list + counts (#89)`.

> Backend PR (Tasks 1+2): open + review + controller applies the gender migration to Supabase via MCP + verify CI green → may squash-merge.

---

## Task 3: Frontend — patient gender (forms + detail)

**Files:** Modify `src/features/patients/api.ts` (Patient type + create/update payloads), `src/features/patients/add-patient-form.tsx`, the patient EDIT surface (find it: grep `useUpdatePatient` — likely in `patients-table.tsx` and/or `patient-detail.tsx`), `src/features/patients/patient-detail.tsx` (Personal Info), `src/i18n/locales/en.json`+`hi.json`.

- [ ] **Step 1: Types.** In `patients/api.ts`: add `gender: "male" | "female" | "other" | null` to `Patient`; add optional `gender` to the create + update payload types.
- [ ] **Step 2: i18n (en+hi).** Add `patients.gender` ("Gender"/"लिंग") and `patients.genderOption.{male,female,other}` ("Male/Female/Other" + Hindi). Parity.
- [ ] **Step 3: Add Patient form.** In `add-patient-form.tsx`: add `gender` to `_addPatientSchemaStatic` + `addPatientSchema` (`z.enum(["male","female","other"]).or(z.literal(""))` — empty allowed), to `defaultValues` (`gender: ""`), to `ResolvedValues` + `resolveValues` (`...(raw.gender ? { gender: raw.gender } : {})`). Add a `FormField` for `gender` (after age) rendering a select/segmented control of the three options + an "optional" hint, `data-testid="patient-gender-input"`. (Use a `components/ui` select if one exists; else a native `<select>` styled with tokens, or a small segmented control like the workflow radios — keep tokens-only.)
- [ ] **Step 4: Edit Patient.** Wherever patient edit is implemented (the `useUpdatePatient` form), add the same gender control + include `gender` in the update payload, seeded from the patient's current value.
- [ ] **Step 5: Patient detail.** In `patient-detail.tsx` Personal Information grid, add a **Gender** field (label `patients.gender`, value = `genderOption.{value}` or "—"), placed with Age.
- [ ] **Step 6: Verify + commit.** `npx tsc --noEmit && npm run build && npx playwright test tests/e2e/i18n.spec.ts`. Commit specific paths → `feat(patients): gender in add/edit forms + detail (#89)`.

---

## Task 4: Frontend — requests data layer + status helper

**Files:** Modify `src/features/scheduling/api.ts` (types + list params + counts), `src/features/scheduling/hooks.ts` (useRequests rewrite + useRequestCounts + refetchOnWindowFocus); Create `src/features/scheduling/request-status.ts` + `tests/e2e/request-status.spec.ts`.

- [ ] **Step 1: Failing unit test** `tests/e2e/request-status.spec.ts` for a pure helper:
```ts
// statusToken(status) -> "warning"|"success"|"destructive"|"muted"
// isNew(status, createdAtISO, nowMs) -> true only when status==="pending" && created within 24h
// decisionLabelKey(status) -> "requests.requestedOn"|"requests.approvedOn"|"requests.rejectedOn"|"requests.cancelledOn"
```
Cover each status + a >24h pending (not new) + a recent pending (new) + a recent approved (not new).
- [ ] **Step 2: Implement** `request-status.ts` with those three pure functions (token map; `isNew` uses `Date.parse`; `decisionLabelKey` maps status→key, default requestedOn).
- [ ] **Step 3: Types + api.** In `api.ts`: extend `RequestListItem` with `patient_name: string; patient_age: number|null; patient_gender: string|null; patient_phone: string|null; doctor_name: string; created_at: string; updated_at: string;`. Add `RequestListPage = { items: RequestListItem[]; total: number }` and `RequestCounts = { all; pending; approved; rejected; cancelled: number }`. Rewrite `listRequests(clinicId, params)` to accept `{ status?, q?, doctor_id?, date_from?, date_to?, limit?, offset? }`, build the query string, and return `RequestListPage`. Add `fetchRequestCounts(clinicId) => apiFetch<RequestCounts>(`${reqBase}/counts`)`.
- [ ] **Step 4: Hooks.** Rewrite `useRequests(clinicId, params)` (query key includes ALL params) returning `RequestListPage`, with `refetchOnWindowFocus: true`. Add `useRequestCounts(clinicId)` (`["request-counts", clinicId]`, `refetchOnWindowFocus: true`). In `useRequestAction.onSuccess`, also invalidate `["request-counts", clinicId]`.
- [ ] **Step 5: Verify + commit.** `npx tsc --noEmit && npm run build && npx playwright test tests/e2e/request-status.spec.ts tests/e2e/i18n.spec.ts`. Commit → `feat(scheduling): requests data layer (paginated+counts) + status helper (#89)`.

---

## Task 5: Frontend — requests list, rows, toolbar (tabs/counts/search)

**Files:** Rewrite `src/app/requests/page.tsx`; Create `src/features/scheduling/requests-list.tsx`, `src/features/scheduling/request-row.tsx`; delete `src/features/scheduling/requests-queue.tsx`. Modify i18n.

> Match `Mockups/requests_mockup_final.png`. Reuse Patients/Settings conventions + `avatarTint`/`initials` from `patients-logic.ts` (or status-tint per `statusToken`).

- [ ] **Step 1: Page + state.** `requests/page.tsx` keeps the auth/me gating + computes `canDecide` (linked doctor) / `canCoordinate` (owner/PM/assistant) + `approvalMode` (from `useClinic` `scheduling_workflow !== "direct_booking"`); renders `<RequestsList clinicId canDecide={canDecide && approvalMode} canCoordinate={...} />`. `RequestsList` holds toolbar state: `tab` (all/pending/approved/rejected/cancelled), `q` (debounced ~300ms), filter state (doctorId, dateFrom, dateTo), `page`+`perPage` (default 5). It calls `useRequests(clinicId, { status: tab==="all"?undefined:tab, q, doctor_id, date_from, date_to, limit: perPage, offset: (page-1)*perPage })` + `useRequestCounts`.
- [ ] **Step 2: Header + tabs.** PageHeader "Requests" + subtitle. Status tabs All/Pending/Approved/Rejected/Cancelled, each a pill showing the label + a count badge from `useRequestCounts` (`all/pending/...`); active pill styled like Settings/Patients active sub-nav; `data-testid={`tab-${key}`}`. Switching a tab resets `page` to 1.
- [ ] **Step 3: Search.** A search `Input` (search icon, `data-testid="requests-search"`) bound to local state, debounced into `q`; resets page to 1 on change.
- [ ] **Step 4: Row card.** `request-row.tsx` renders one enriched row as a status-tinted card (background `bg-{token}/8` or a left accent; token from `statusToken(status)`): avatar (initials, status-tinted) · **name** + `isNew` "New" badge · `{age} yrs • {gender}` (omit gender if null) · phone w/ `call` icon · **Doctor** label+name · **Chief Complaint** label+text · **Requested Date & Time** (calendar+clock icons, from `start_datetime`) · status **chip** (`statusToken` colour + `requests.status.{status}`) + a muted `{t(decisionLabelKey(status))} {ts}` line (ts = `updated_at` for decided, `created_at` for pending). Action slot is a prop (filled in T6). `data-testid={`request-${id}`}`.
- [ ] **Step 5: List + empty/loading.** `requests-list.tsx` maps `items` → `RequestRow`; loading + empty states (calm centered empty per tab/search). Toolbar (tabs, search, a Filters button placeholder wired in T6) above the list.
- [ ] **Step 6: i18n (en+hi)** for: `requests.title`, `requests.subtitle`, `requests.tab.{all,pending,approved,rejected,cancelled}`, `requests.searchPlaceholder`, `requests.doctorLabel`, `requests.requestedDateTime`, `requests.requestedOn/approvedOn/rejectedOn/cancelledOn`, `requests.newBadge`, plus reuse existing `requests.status.*`/`requests.chiefComplaint?`/`requests.empty`. Parity.
- [ ] **Step 7: Verify + commit.** `tsc + build + i18n`. Commit → `feat(requests): redesigned list + rows + tabs/search (#89)`.

---

## Task 6: Frontend — Filters popover, pagination, row actions

**Files:** Modify `requests-list.tsx`, `request-row.tsx`; Create `src/features/scheduling/requests-filters.tsx`; i18n.

- [ ] **Step 1: Row actions.** In `request-row.tsx`, fill the action slot: **Approve** (filled) + **Reject** (outlined) when `canDecide && status==="pending" && !expired` (calls the same `useRequestAction` approve/reject + success card as before, with patient name + when in details); a **⋮** overflow menu (body-portaled, reusing the pattern in `patients-table.tsx`) on every row → **Cancel** (when `canCoordinate && status==="pending"`), **Resend** (when `canCoordinate && status==="pending" && expired`). testids `approve-${id}`/`reject-${id}`/`cancel-${id}`/`resend-${id}`/`request-menu-${id}`.
- [ ] **Step 2: Filters popover.** `requests-filters.tsx`: a "Filters" button (`funnel`/`filter_list` icon, `data-testid="requests-filters"`) opening a popover with a **Doctor** select (from `useDoctors(clinicId)` — confirm the hook name) and **From/To** date inputs (`<input type="date">` styled with tokens). "Apply"/"Clear" update the list's filter state (reset page to 1). Show an active-filter indicator (dot/count) on the button when filters are set.
- [ ] **Step 3: Pagination footer.** In `requests-list.tsx`: "Showing {from}–{to} of {total}" + Prev/Next + numbered page chips (compute from `total`/`perPage`) + a "{n} per page" select (5/10/20, default 5). All drive `page`/`perPage`; clamp page within range. testids `requests-prev`/`requests-next`/`requests-page-{n}`/`requests-perpage`.
- [ ] **Step 4: i18n (en+hi)** for filters (`requests.filters`, `requests.filterDoctor`, `requests.filterFrom`, `requests.filterTo`, `requests.apply`, `requests.clear`) + pagination (`requests.showing` with `{{from}}/{{to}}/{{total}}`, `requests.perPage`) + reuse `requests.approve/reject/cancel/resend`. Parity.
- [ ] **Step 5: Verify + commit.** `tsc + build + i18n` + `npx playwright test tests/e2e/request-status.spec.ts`. Commit → `feat(requests): filters popover + pagination + row actions (#89)`.

> After Task 6: opus whole-branch review → fix Critical/Important → render the page → **open the frontend PR and STOP for the user's test** (no auto-merge).

---

## Self-Review (plan vs spec)
- Patient gender (migration + schemas + service + forms + detail + card): T1, T3, T5(row). ✅ (spec §3/§4a/§5a)
- Enriched + paginated + searchable list + counts (server-side): T2, T4. ✅ (§4b)
- Redesigned rows (name/age/gender/phone, doctor, complaint, date/time, status chip + timestamp, New badge): T5. ✅ (§5b)
- Status colour mapping via tokens: T4 helper + T5. ✅
- Tabs-with-counts + Filters popover + search + pagination: T5, T6. ✅
- Approve/Reject gated (canDecide + direct-mode) + ⋮ menu (cancel/resend): T6. ✅
- Multi-device freshness (refetchOnWindowFocus + invalidate): T4. ✅
- Rule 17.0 + i18n parity + both themes + tests + merge policy: Global Constraints + per-task. ✅
- Type consistency: `RequestListItem`/`RequestListPage`/`RequestCounts` fields identical BE↔FE; `statusToken` values match the token set; `{items,total}` shape consistent. ✅
- Placeholder scan: backend full code; FE tasks give exact files/props/testids/i18n + reference mockup + existing patterns. (`00NN`/`<current_head>` in T1 are explicit lookups, not placeholders.) ✅
