# Home / Needs-Attention — Backend Plan (#62)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Add a role-aware `GET /clinics/{id}/home-summary` (clinic-wide appointment aggregation + counts + role-scoped needs-attention signals) and `is_complete` on `PatientRead`.

**Architecture:** A shared patient-completeness helper feeds both `PatientRead.is_complete` (consumed by #59's badge) and a clinic incomplete-count. A clinic-wide appointment aggregation (new — appointments were per-doctor only) feeds today's-schedule/counts/upcoming. The home-summary service branches on the caller's role + `scheduling_workflow` and returns only role-relevant data.

**Tech Stack:** FastAPI, SQLAlchemy 2.x, Pydantic v2, pytest. PG :5433. Spec: `docs/specs/2026-06-24-home-needs-attention-design.md` §6.

## Global Constraints
- **No migration** (reads only). Reuses Appointment/AppointmentRequest/Patient/ClinicSettings/Doctor models.
- Day/time clinic-local (IST). Weekday 0=Mon. Routers thin; logic in services; `CurrentMembership` auth (cross-clinic 403).
- Stable codes in payloads (needs-attention `type` strings; never display English). `uv run ruff check .` + `make test` green per commit. Never ports 5434/8001/3001.
- **Completeness rule (single source of truth):** complete = `name AND phone AND (age OR date_of_birth) AND gender`.

---

### Task 1: Patient completeness — `is_complete` on `PatientRead` + clinic count

**Files:** Modify `app/modules/patients/schemas.py`, `app/modules/patients/service.py`; Test `tests/patients/test_completeness.py`.

**Interfaces:**
- Produces: `service.patient_missing_fields(p) -> list[str]`, `service.is_patient_complete(p) -> bool`, `service.count_incomplete_patients(db, clinic_id) -> int`; `PatientRead.is_complete: bool` (+ `missing_fields: list[str]`).

- [ ] **Step 1: Write the failing test**

```python
# tests/patients/test_completeness.py
from app.modules.patients import service

def test_complete_vs_incomplete(db, clinic, make_patient):
    full = make_patient(name="Riya", phone="+919800000000", age=30, gender="female")
    thin = make_patient(name="Walk In", phone="+919811111111", age=None, gender=None)
    assert service.is_patient_complete(full) is True
    assert service.is_patient_complete(thin) is False
    assert set(service.patient_missing_fields(thin)) == {"age", "gender"}
    assert service.count_incomplete_patients(db, clinic.id) >= 1
```

- [ ] **Step 2: Run → fail.** `uv run pytest tests/patients/test_completeness.py -v`

- [ ] **Step 3: Implement**

```python
# app/modules/patients/service.py  (append)
def patient_missing_fields(p) -> list[str]:
    missing = []
    if not getattr(p, "name", None): missing.append("name")
    if not getattr(p, "phone", None): missing.append("phone")
    if getattr(p, "age", None) is None and not getattr(p, "date_of_birth", None): missing.append("age")
    if not getattr(p, "gender", None): missing.append("gender")
    return missing

def is_patient_complete(p) -> bool:
    return not patient_missing_fields(p)

def count_incomplete_patients(db, clinic_id) -> int:
    return sum(1 for p in list_all_patients(db, clinic_id) if not is_patient_complete(p))
```

```python
# app/modules/patients/schemas.py  — PatientRead: add computed fields
from pydantic import computed_field
# inside PatientRead (model_config from_attributes=True):
    @computed_field
    @property
    def is_complete(self) -> bool:
        from app.modules.patients.service import is_patient_complete
        return is_patient_complete(self)
    @computed_field
    @property
    def missing_fields(self) -> list[str]:
        from app.modules.patients.service import patient_missing_fields
        return patient_missing_fields(self)
```

> NOTE: confirm `PatientRead` exposes `name/phone/age|date_of_birth/gender`; confirm a `list_all_patients`/equivalent exists (else add a simple `select(Patient).where(clinic_id==...)`). Avoid circular import (local import inside the property, as shown).

- [ ] **Step 4: Run → pass. Step 5: Commit** `feat(patients): is_complete + incomplete count (#62, #59)`.

---

### Task 2: Clinic-wide appointment aggregation

**Files:** Modify `app/modules/scheduling/service.py`; Test `tests/scheduling/test_clinic_appointments.py`.

**Interfaces:**
- Produces: `list_clinic_appointments(db, clinic_id, date_from, date_to) -> list[Appointment]` (all clinic doctors, within [from,to], ordered by start). `count_appointments(db, clinic_id, date_from, date_to, status=None) -> int`.

- [ ] **Step 1: Write the failing test**

```python
# tests/scheduling/test_clinic_appointments.py
import datetime as dt
from app.modules.scheduling import service

def test_clinic_wide_today(db, clinic, two_doctors_with_appointments_today):
    today = dt.date.today()
    appts = service.list_clinic_appointments(db, clinic.id, today, today)
    assert len(appts) >= 2  # across both doctors
    assert service.count_appointments(db, clinic.id, today, today) == len(appts)
```

- [ ] **Step 2–4:** Implement a `select(Appointment).where(Appointment.clinic_id == clinic_id, start in [from,to])` (join doctor for clinic scope if `clinic_id` not on Appointment — verify) ordered by `start_datetime`; `count_appointments` adds an optional `status` filter (e.g. `"completed"`). > NOTE: confirm Appointment has `clinic_id` or join via `doctor_id`→`doctor_beta.clinic_id`.

- [ ] **Step 5: Commit** `feat(scheduling): clinic-wide appointment aggregation (#62)`.

---

### Task 3: `GET /home-summary` (role-aware) + schema

**Files:** Create `app/modules/home/__init__.py`, `app/modules/home/router.py`, `app/modules/home/schemas.py`, `app/modules/home/service.py`; Modify `app/main.py` (mount router) + `app/db/base.py` if needed; Test `tests/home/test_home_summary.py`.

**Interfaces:**
- Consumes: `count_incomplete_patients` (T1), `list_clinic_appointments`/`count_appointments` (T2), `request_counts`, `get_settings`, `list_windows`, clinic profile fields, `get_my_doctor`.
- Produces: `GET /api/v1/clinics/{clinic_id}/home-summary -> HomeSummaryRead`.

```python
# app/modules/home/schemas.py
class NeedsAttentionItem(BaseModel): type: str; count: int | None = None; link: str
class TodayAppt(BaseModel): start_time: str; patient_name: str; type: str | None; doctor_name: str; doctor_id: uuid.UUID
class UpcomingDay(BaseModel): date: str; count: int; doctor_initials: list[str]
class HomeCounts(BaseModel): appointments_today: int; completed_today: int; pending_requests: int | None = None; patients_this_week: int | None = None
class HomeSummaryRead(BaseModel):
    date: str; counts: HomeCounts
    today_appointments: list[TodayAppt]; upcoming: list[UpcomingDay]
    needs_attention: list[NeedsAttentionItem]
```

- [ ] **Step 1: Write the failing test**

```python
# tests/home/test_home_summary.py
def test_owner_sees_clinic_wide(client, clinic, owner_auth_headers, seed_home_data):
    r = client.get(f"/api/v1/clinics/{clinic.id}/home-summary", headers=owner_auth_headers)
    assert r.status_code == 200
    b = r.json()
    types = {n["type"] for n in b["needs_attention"]}
    assert "patients_missing_details" in types or b["counts"]["appointments_today"] >= 0

def test_doctor_excludes_patient_and_profile_rows(client, clinic, doctor_auth_headers, seed_home_data):
    b = client.get(f"/api/v1/clinics/{clinic.id}/home-summary", headers=doctor_auth_headers).json()
    types = {n["type"] for n in b["needs_attention"]}
    assert "patients_missing_details" not in types
    assert "clinic_profile_incomplete" not in types

def test_direct_mode_no_pending(client, clinic_direct, owner_auth_headers):
    b = client.get(f"/api/v1/clinics/{clinic_direct.id}/home-summary", headers=owner_auth_headers).json()
    assert b["counts"].get("pending_requests") in (None, 0)
    assert all(n["type"] != "requests_awaiting_approval" for n in b["needs_attention"])
```

- [ ] **Step 2–4:** Implement `service.home_summary(db, *, clinic_id, membership)`:
  - Resolve role, `settings = get_settings`, doctor count; for a non-owner doctor resolve their `doctor_id`.
  - **today_appointments/upcoming/counts:** owner/assistant → `list_clinic_appointments` clinic-wide; doctor → filter to own `doctor_id`. `completed_today` via `count_appointments(status="completed")`. `pending_requests` from `request_counts` **only if** `scheduling_workflow=="doctor_approval"`. `patients_this_week` (created last 7 days) **only** for owner/assistant.
  - **needs_attention** per §3 matrix: `requests_awaiting_approval` (approval mode; doctor→own assigned count); `patients_missing_details` (owner/assistant → `count_incomplete_patients`); `clinic_profile_incomplete` (owner → clinic missing key fields); `no_availability` (doctor → `list_windows` recurring empty). Each with a stable `type` + `link`.
  - Mount router at `/api/v1`. Tests green + `make test`.

- [ ] **Step 5: Commit** `feat(home): role-aware home-summary endpoint (#62)`.

---

## Self-Review (vs spec §6)
- `is_complete` shared w/ #59 (T1); clinic-wide aggregation (T2); role-aware home-summary + role-scoped needs-attention + mode-gated pending (T3). ✅ No migration. Placeholder scan: concrete code/tests; verify-NOTEs on patient fields + Appointment clinic scope. ✅

## README
Update `dentist-registry-backend/README.md` (home-summary endpoint) in the landing PR.
