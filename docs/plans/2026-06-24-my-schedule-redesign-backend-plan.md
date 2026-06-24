# My Schedule Redesign — Backend Plan (#129)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Add ONE transactional endpoint that atomically replaces a doctor's **usual-week** (recurring) availability, so the My Schedule "Confirm & save" applies the whole week at once without a half-applied state.

**Architecture:** A new service `replace_weekly_windows` that, in a single transaction, soft-removes the doctor's active recurring windows and inserts the submitted set; surfaced as `PUT …/availability/weekly`. Reuses existing authz + models. **No schema/model change.**

**Tech Stack:** FastAPI, SQLAlchemy 2.x (sync), Pydantic v2, pytest. Postgres :5433 (dev). Spec: `docs/specs/2026-06-24-my-schedule-redesign-design.md` §6.

## Global Constraints
- **No DB migration / no new columns.** Reuses `availability_window` (`kind=recurring`).
- Day-of-week convention **0 = Monday … 6 = Sunday**; `end_time > start_time`; multiple windows per day allowed (split shifts).
- Authz reuses the availability rule (owner any · doctor own · assistant iff `allow_staff_manage_availability`) — the existing `authorize_manage_availability`.
- Routers thin; service holds logic; transaction wraps remove+insert. `uv run ruff check .` + `make test` green before each commit. Never the test-suite ports (5434/8001/3001).

---

### Task 1: `replace_weekly_windows` service (transactional)

**Files:**
- Modify: `app/modules/scheduling/service.py`
- Test: `tests/scheduling/test_replace_weekly.py` (new)

**Interfaces:**
- Produces: `replace_weekly_windows(db, *, clinic_id, doctor_id, actor_user_id, windows: list[WeeklyWindowIn]) -> list[AvailabilityWindow]` where `WeeklyWindowIn = {day_of_week:int, start_time:time, end_time:time}`. Atomically soft-removes existing `status='active'` recurring windows for the doctor and inserts the new set; returns the active recurring windows.

- [ ] **Step 1: Write the failing test**

```python
# tests/scheduling/test_replace_weekly.py
import datetime as dt
from app.modules.scheduling import service

def _w(dow, s, e):
    return {"day_of_week": dow, "start_time": dt.time.fromisoformat(s), "end_time": dt.time.fromisoformat(e)}

def test_replace_swaps_the_whole_week(db, clinic, doctor, owner_user):
    # seed Mon 09-12
    service.replace_weekly_windows(db, clinic_id=clinic.id, doctor_id=doctor.id,
        actor_user_id=owner_user.id, windows=[_w(0, "09:00", "12:00")])
    # replace with Mon/Wed/Fri 10-13 + Tue/Thu 17-20
    out = service.replace_weekly_windows(db, clinic_id=clinic.id, doctor_id=doctor.id,
        actor_user_id=owner_user.id,
        windows=[_w(0,"10:00","13:00"), _w(2,"10:00","13:00"), _w(4,"10:00","13:00"),
                 _w(1,"17:00","20:00"), _w(3,"17:00","20:00")])
    active = [w for w in out if w.status == "active" and w.kind == "recurring"]
    assert len(active) == 5
    assert {w.day_of_week for w in active} == {0, 1, 2, 3, 4}
    # the original Mon 09-12 is gone (soft-removed)
    assert all(not (w.day_of_week == 0 and w.start_time == dt.time(9, 0)) for w in active)

def test_replace_with_empty_clears_week(db, clinic, doctor, owner_user):
    service.replace_weekly_windows(db, clinic_id=clinic.id, doctor_id=doctor.id,
        actor_user_id=owner_user.id, windows=[_w(0,"09:00","12:00")])
    out = service.replace_weekly_windows(db, clinic_id=clinic.id, doctor_id=doctor.id,
        actor_user_id=owner_user.id, windows=[])
    assert [w for w in out if w.status == "active" and w.kind == "recurring"] == []

def test_replace_rejects_bad_range(db, clinic, doctor, owner_user):
    import pytest
    from app.core.errors import ValidationError
    with pytest.raises(ValidationError):
        service.replace_weekly_windows(db, clinic_id=clinic.id, doctor_id=doctor.id,
            actor_user_id=owner_user.id, windows=[_w(0,"12:00","09:00")])
```

- [ ] **Step 2: Run test to verify it fails**

Run: `uv run pytest tests/scheduling/test_replace_weekly.py -v`
Expected: FAIL — `AttributeError: ... has no attribute 'replace_weekly_windows'`.

- [ ] **Step 3: Implement the service**

```python
# app/modules/scheduling/service.py  (append; reuse existing imports/models)
def replace_weekly_windows(db, *, clinic_id, doctor_id, actor_user_id, windows):
    get_doctor(db, clinic_id, doctor_id)  # 404 if not in clinic
    # validate
    for w in windows:
        if not (0 <= w["day_of_week"] <= 6):
            raise ValidationError("day_of_week must be 0..6.")
        if w["end_time"] <= w["start_time"]:
            raise ValidationError("end_time must be after start_time.")
    # soft-remove current active recurring windows
    existing = [w for w in list_windows(db, clinic_id, doctor_id) if w.kind == "recurring"]
    for w in existing:
        w.status = "removed"
    # insert new
    for w in windows:
        db.add(AvailabilityWindow(
            clinic_id=clinic_id, doctor_id=doctor_id, kind="recurring",
            day_of_week=w["day_of_week"], specific_date=None,
            start_time=w["start_time"], end_time=w["end_time"],
            status="active", created_by=actor_user_id,
        ))
    db.commit()
    return list_windows(db, clinic_id, doctor_id)
```

> NOTE: confirm `list_windows` returns active windows (or filter `status=='active'`), the `AvailabilityWindow` field names, and that `get_doctor`/`ValidationError` import paths match this module. Wrap remove+insert in the request's transaction (single `db.commit()` as shown).

- [ ] **Step 4: Run tests**

Run: `uv run pytest tests/scheduling/test_replace_weekly.py -v`
Expected: PASS.

- [ ] **Step 5: Lint + commit**

```bash
uv run ruff check .
git add app/modules/scheduling/service.py tests/scheduling/test_replace_weekly.py
git commit -m "feat(scheduling): transactional replace_weekly_windows (#129)"
```

---

### Task 2: `PUT …/availability/weekly` endpoint + authz

**Files:**
- Modify: `app/modules/scheduling/router.py`
- Modify: `app/modules/scheduling/schemas.py`
- Test: `tests/scheduling/test_weekly_endpoint.py` (new)

**Interfaces:**
- Consumes: `replace_weekly_windows` (Task 1); `authorize_manage_availability`; `CurrentMembership`, `DbSession`, `get_settings`.
- Produces: `PUT /api/v1/clinics/{clinic_id}/doctors/{doctor_id}/availability/weekly` body `WeeklyAvailabilityReplace { windows: [{day_of_week:int, start_time:str, end_time:str}] }` → `list[AvailabilityWindowRead]`.

- [ ] **Step 1: Write the failing test**

```python
# tests/scheduling/test_weekly_endpoint.py
def test_owner_replaces_week(client, clinic, doctor, owner_auth_headers):
    body = {"windows": [
        {"day_of_week": 0, "start_time": "10:00", "end_time": "13:00"},
        {"day_of_week": 1, "start_time": "17:00", "end_time": "20:00"}]}
    r = client.put(f"/api/v1/clinics/{clinic.id}/doctors/{doctor.id}/availability/weekly",
                   json=body, headers=owner_auth_headers)
    assert r.status_code == 200
    rows = [w for w in r.json() if w["kind"] == "recurring" and w["status"] == "active"]
    assert {w["day_of_week"] for w in rows} == {0, 1}

def test_assistant_blocked_when_setting_off(client, clinic, doctor, assistant_auth_headers):
    # allow_staff_manage_availability defaults False
    r = client.put(f"/api/v1/clinics/{clinic.id}/doctors/{doctor.id}/availability/weekly",
                   json={"windows": []}, headers=assistant_auth_headers)
    assert r.status_code == 403
```

- [ ] **Step 2: Run test to verify it fails**

Run: `uv run pytest tests/scheduling/test_weekly_endpoint.py -v`
Expected: FAIL — 404/405 (route missing).

- [ ] **Step 3: Add the schema + route**

```python
# app/modules/scheduling/schemas.py  (append)
import datetime as dt
from pydantic import BaseModel

class WeeklyWindowItem(BaseModel):
    day_of_week: int
    start_time: dt.time
    end_time: dt.time

class WeeklyAvailabilityReplace(BaseModel):
    windows: list[WeeklyWindowItem]
```

```python
# app/modules/scheduling/router.py  (add)
@router.put("/{clinic_id}/doctors/{doctor_id}/availability/weekly",
            response_model=list[AvailabilityWindowRead])
def replace_weekly(clinic_id: uuid.UUID, doctor_id: uuid.UUID, body: WeeklyAvailabilityReplace,
                   db: DbSession, membership: CurrentMembership):
    settings = get_settings(db, clinic_id)
    authorize_manage_availability(db, clinic_id=clinic_id, doctor_id=doctor_id,
                                  membership=membership, settings=settings)
    return service.replace_weekly_windows(
        db, clinic_id=clinic_id, doctor_id=doctor_id, actor_user_id=membership.user_id,
        windows=[w.model_dump() for w in body.windows])
```

> NOTE: match the existing availability router's import style and `AvailabilityWindowRead` schema name; confirm `authorize_manage_availability`'s exact signature (it loads/receives `settings` — pass as the existing availability POST route does).

- [ ] **Step 4: Run tests + full suite**

Run: `uv run pytest tests/scheduling -v && make test`
Expected: PASS.

- [ ] **Step 5: Lint + commit**

```bash
uv run ruff check .
git add app/modules/scheduling/router.py app/modules/scheduling/schemas.py tests/scheduling/test_weekly_endpoint.py
git commit -m "feat(api): PUT availability/weekly atomic replace (#129)"
```

---

## Self-Review (plan vs spec §6)
- Transactional atomic apply of the usual week → Tasks 1–2. ✅
- No model change; reuses windows/authz → Global Constraints. ✅
- Authz reuse (owner/doctor/assistant-gated) → Task 2. ✅
- One-off days + time off keep their existing create/delete endpoints (no change here) — consumed by the FE plan. ✅
- Placeholder scan: concrete code/tests; signature-verify NOTEs flag the two spots to confirm, not placeholders. ✅

## README
Update `dentist-registry-backend/README.md` (mention the weekly-replace endpoint) in the PR that lands it.
