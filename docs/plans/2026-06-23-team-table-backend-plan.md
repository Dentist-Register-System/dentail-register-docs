# Team Table (#106) — Backend Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add dedicated paginated + filterable + sortable list endpoints for doctors and assistants (`…/page`), powering the server-side Team table, without changing the existing full-list endpoints.

**Architecture:** Mirror the Requests list (`booking.list_requests` → `(items, total)`, `RequestListPage`). Add `list_doctors_page` / `list_assistants_page` service fns returning `(rows, total)`, `DoctorListPage`/`AssistantListPage` schemas, and `GET /clinics/{id}/doctors/page` / `…/assistants/page` routes. No DB migration. The existing `GET …/doctors` and `…/assistants` (full list) stay untouched so dropdowns/overview keep working.

**Tech Stack:** FastAPI, SQLAlchemy 2.x sync, Pydantic v2, pytest on Postgres :5433.

## Global Constraints
- Spec: `docs/specs/2026-06-23-team-table-design.md`. Backend half of #106.
- **No DB migration.** Reuse existing models/statuses.
- Sort whitelist: `name | joined | status` (default `joined`); order `asc | desc` (default `desc`). Invalid → 422.
- Pagination: `page` ≥ 1 (default 1); `page_size` 1–100 (default 10). `total` = count BEFORE limit/offset.
- `q` ILIKE: doctors over `name`,`email`,`specialty`; assistants over `name`,`email`,`title`.
- Role/specialty filter param: doctors `specialty` (ILIKE), assistants `role` (ILIKE on `title`).
- Read access = `CurrentMembership` (any active member), matching the existing list endpoints. No new write endpoints (⋯ actions reuse existing PATCH/DELETE).
- Module boundary discipline; absolute imports; `uv run ruff check .` clean; `make test` green.
- `joined` sort maps to the `created_at` column (when the member record was created).

## File Structure
- Modify: `app/modules/doctors/schemas.py` — add `DoctorListPage`.
- Modify: `app/modules/doctors/service.py` — add `list_doctors_page` + shared sort helper.
- Modify: `app/modules/doctors/router.py` — add `GET /{clinic_id}/doctors/page`.
- Modify: `app/modules/assistants/schemas.py` — add `AssistantListPage`.
- Modify: `app/modules/assistants/service.py` — add `list_assistants_page`.
- Modify: `app/modules/assistants/router.py` — add `GET /{clinic_id}/assistants/page`.
- Create: `app/modules/doctors/_sorting.py`? No — keep the tiny sort map inline per service (DRY across two modules isn't worth a shared core module; the map differs by model). Each service defines its own `_SORT_COLUMNS`.
- Tests: `tests/doctors/test_doctors_page.py`, `tests/assistants/test_assistants_page.py`.

---

### Task 1: Doctors paginated endpoint

**Files:**
- Modify: `app/modules/doctors/schemas.py`
- Modify: `app/modules/doctors/service.py`
- Modify: `app/modules/doctors/router.py`
- Test: `tests/doctors/test_doctors_page.py`

**Interfaces:**
- Produces:
  - `DoctorListPage { items: list[DoctorRead], total: int }`.
  - `service.list_doctors_page(db, *, clinic_id, q=None, status=None, specialty=None, sort="joined", order="desc", page=1, page_size=10) -> tuple[list[Doctor], int]`.
  - Route `GET /clinics/{clinic_id}/doctors/page` → `DoctorListPage`.

- [ ] **Step 1: Write failing tests** (`tests/doctors/test_doctors_page.py`)

```python
def _seed(owner, cid, n):
    for i in range(n):
        owner.post(f"/api/v1/clinics/{cid}/doctors",
                   json={"name": f"Dr {i:02d}", "email": f"d{i}@x.com", "specialty": "Ortho" if i % 2 else "Endo"})


def test_page_returns_items_and_total(auth_client):
    from tests.conftest import make_clinic
    owner, _ = auth_client(sub="cccc0000-0000-0000-0000-000000000001")
    cid = make_clinic(owner)
    _seed(owner, cid, 12)
    r = owner.get(f"/api/v1/clinics/{cid}/doctors/page?page=1&page_size=10")
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["total"] == 12
    assert len(body["items"]) == 10
    # page 2
    r2 = owner.get(f"/api/v1/clinics/{cid}/doctors/page?page=2&page_size=10")
    assert len(r2.json()["items"]) == 2


def test_page_q_filter(auth_client):
    from tests.conftest import make_clinic
    owner, _ = auth_client(sub="cccc0000-0000-0000-0000-000000000002")
    cid = make_clinic(owner)
    owner.post(f"/api/v1/clinics/{cid}/doctors", json={"name": "Asha Rao", "email": "asha@x.com"})
    owner.post(f"/api/v1/clinics/{cid}/doctors", json={"name": "Bob Lee", "email": "bob@x.com"})
    body = owner.get(f"/api/v1/clinics/{cid}/doctors/page?q=asha").json()
    assert body["total"] == 1 and body["items"][0]["name"] == "Asha Rao"


def test_page_specialty_and_status_filter(auth_client):
    from tests.conftest import make_clinic
    owner, _ = auth_client(sub="cccc0000-0000-0000-0000-000000000003")
    cid = make_clinic(owner)
    _seed(owner, cid, 4)  # specialties alternate Endo/Ortho
    body = owner.get(f"/api/v1/clinics/{cid}/doctors/page?specialty=ortho").json()
    assert body["total"] == 2
    # all seeded are status 'invited'
    assert owner.get(f"/api/v1/clinics/{cid}/doctors/page?status=invited").json()["total"] == 4
    assert owner.get(f"/api/v1/clinics/{cid}/doctors/page?status=active").json()["total"] == 0


def test_page_sort_name_asc(auth_client):
    from tests.conftest import make_clinic
    owner, _ = auth_client(sub="cccc0000-0000-0000-0000-000000000004")
    cid = make_clinic(owner)
    owner.post(f"/api/v1/clinics/{cid}/doctors", json={"name": "Zara", "email": "z@x.com"})
    owner.post(f"/api/v1/clinics/{cid}/doctors", json={"name": "Adam", "email": "a@x.com"})
    items = owner.get(f"/api/v1/clinics/{cid}/doctors/page?sort=name&order=asc").json()["items"]
    assert [i["name"] for i in items] == ["Adam", "Zara"]


def test_page_invalid_sort_422(auth_client):
    from tests.conftest import make_clinic
    owner, _ = auth_client(sub="cccc0000-0000-0000-0000-000000000005")
    cid = make_clinic(owner)
    assert owner.get(f"/api/v1/clinics/{cid}/doctors/page?sort=ssn").status_code == 422


def test_page_clinic_scoped(auth_client):
    from tests.conftest import make_clinic
    owner, _ = auth_client(sub="cccc0000-0000-0000-0000-000000000006")
    cid1 = make_clinic(owner, name="C1")
    owner.post(f"/api/v1/clinics/{cid1}/doctors", json={"name": "Mine", "email": "m@x.com"})
    other, _ = auth_client(sub="cccc0000-0000-0000-0000-000000000007")
    cid2 = make_clinic(other, name="C2")
    assert other.get(f"/api/v1/clinics/{cid2}/doctors/page").json()["total"] == 0
```

- [ ] **Step 2: Run, verify fail.** `uv run pytest tests/doctors/test_doctors_page.py -v` → 404 (route missing).

- [ ] **Step 3: Add `DoctorListPage` schema** (`app/modules/doctors/schemas.py`)

```python
class DoctorListPage(BaseModel):
    items: list[DoctorRead]
    total: int
```

- [ ] **Step 4: Add `list_doctors_page` to `service.py`**

```python
from sqlalchemy import func, or_
from app.core.errors import DomainError

_DOCTOR_SORT_COLUMNS = {"name": Doctor.name, "joined": Doctor.created_at, "status": Doctor.status}
_VALID_ORDERS = ("asc", "desc")


def list_doctors_page(
    db: Session,
    *,
    clinic_id: uuid.UUID,
    q: str | None = None,
    status: DoctorStatus | None = None,
    specialty: str | None = None,
    sort: str = "joined",
    order: str = "desc",
    page: int = 1,
    page_size: int = 10,
) -> tuple[list[Doctor], int]:
    if sort not in _DOCTOR_SORT_COLUMNS or order not in _VALID_ORDERS:
        raise DomainError("Invalid sort/order.")  # 400 → but we validate at route for 422; see route note
    base = select(Doctor).where(Doctor.clinic_id == clinic_id)
    if status is not None:
        base = base.where(Doctor.status == status)
    if specialty:
        base = base.where(Doctor.specialty.ilike(f"%{specialty}%"))
    if q:
        like = f"%{q}%"
        base = base.where(or_(Doctor.name.ilike(like), Doctor.email.ilike(like), Doctor.specialty.ilike(like)))
    total = db.execute(select(func.count()).select_from(base.subquery())).scalar_one()
    col = _DOCTOR_SORT_COLUMNS[sort]
    ordered = base.order_by(col.asc() if order == "asc" else col.desc())
    rows = list(db.execute(ordered.limit(page_size).offset((page - 1) * page_size)).scalars().all())
    return rows, total
```

- [ ] **Step 5: Add the route** (`app/modules/doctors/router.py`). Validate sort/order/page/page_size with FastAPI `Query` so bad input is a clean 422 (do NOT rely on the service's DomainError for that):

```python
from typing import Literal
from fastapi import Query
from app.modules.doctors.schemas import DoctorListPage

@router.get("/{clinic_id}/doctors/page", response_model=DoctorListPage)
def list_doctors_page(
    clinic_id: uuid.UUID,
    db: DbSession,
    membership: CurrentMembership,
    q: str | None = None,
    status: DoctorStatus | None = None,
    specialty: str | None = None,
    sort: Literal["name", "joined", "status"] = "joined",
    order: Literal["asc", "desc"] = "desc",
    page: int = Query(1, ge=1),
    page_size: int = Query(10, ge=1, le=100),
) -> DoctorListPage:
    items, total = service.list_doctors_page(
        db, clinic_id=clinic_id, q=q, status=status, specialty=specialty,
        sort=sort, order=order, page=page, page_size=page_size,
    )
    return DoctorListPage(items=[DoctorRead.model_validate(d) for d in items], total=total)
```

> The `Literal[...]` query types make FastAPI return 422 for invalid `sort`/`order` automatically (satisfies `test_page_invalid_sort_422`). The service's own guard is defense-in-depth.

- [ ] **Step 6: Run, verify PASS.** `uv run pytest tests/doctors/test_doctors_page.py -v` (6 pass) + `uv run ruff check .`.

- [ ] **Step 7: Commit**

```bash
git add app/modules/doctors tests/doctors/test_doctors_page.py
git commit -m "feat(doctors): paginated/filterable/sortable /doctors/page endpoint (#106)"
```

---

### Task 2: Assistants paginated endpoint

**Files:**
- Modify: `app/modules/assistants/schemas.py`, `app/modules/assistants/service.py`, `app/modules/assistants/router.py`
- Test: `tests/assistants/test_assistants_page.py`

**Interfaces:**
- Produces: `AssistantListPage { items: list[AssistantRead], total: int }`; `service.list_assistants_page(db, *, clinic_id, q=None, status=None, role=None, sort="joined", order="desc", page=1, page_size=10) -> tuple[list[Assistant], int]`; route `GET /clinics/{clinic_id}/assistants/page`.
- Note the role filter param is named `role` and filters `Assistant.title` (ILIKE); `q` covers `name`/`email`/`title`.

- [ ] **Step 1: Write failing tests** (`tests/assistants/test_assistants_page.py`) — mirror Task 1's tests against `/assistants/page`, seeding via `POST …/assistants` with `{name,email,title}` (title alternating e.g. "Receptionist"/"Coordinator"). Include: items+total+page2; `q`; `role` filter (ILIKE title) + `status`; `sort=name&order=asc`; invalid sort → 422; clinic-scoped.

```python
def _seed(owner, cid, n):
    for i in range(n):
        owner.post(f"/api/v1/clinics/{cid}/assistants",
                   json={"name": f"A {i:02d}", "email": f"a{i}@x.com",
                         "title": "Receptionist" if i % 2 else "Coordinator"})

def test_page_role_filter(auth_client):
    from tests.conftest import make_clinic
    owner, _ = auth_client(sub="dddd0000-0000-0000-0000-0000000000a1")
    cid = make_clinic(owner)
    _seed(owner, cid, 4)
    assert owner.get(f"/api/v1/clinics/{cid}/assistants/page?role=recept").json()["total"] == 2
```

(Add the items+total, q, status, sort, invalid-422, clinic-scoped tests mirroring Task 1 with distinct sub UUIDs.)

- [ ] **Step 2: Run, verify fail.**

- [ ] **Step 3: `AssistantListPage` schema:**

```python
class AssistantListPage(BaseModel):
    items: list[AssistantRead]
    total: int
```

- [ ] **Step 4: `list_assistants_page` in `service.py`** — identical structure to `list_doctors_page` but:

```python
_ASSISTANT_SORT_COLUMNS = {"name": Assistant.name, "joined": Assistant.created_at, "status": Assistant.status}
_VALID_ORDERS = ("asc", "desc")

def list_assistants_page(db, *, clinic_id, q=None, status=None, role=None,
                         sort="joined", order="desc", page=1, page_size=10):
    if sort not in _ASSISTANT_SORT_COLUMNS or order not in _VALID_ORDERS:
        raise DomainError("Invalid sort/order.")
    base = select(Assistant).where(Assistant.clinic_id == clinic_id)
    if status is not None:
        base = base.where(Assistant.status == status)
    if role:
        base = base.where(Assistant.title.ilike(f"%{role}%"))
    if q:
        like = f"%{q}%"
        base = base.where(or_(Assistant.name.ilike(like), Assistant.email.ilike(like), Assistant.title.ilike(like)))
    total = db.execute(select(func.count()).select_from(base.subquery())).scalar_one()
    col = _ASSISTANT_SORT_COLUMNS[sort]
    ordered = base.order_by(col.asc() if order == "asc" else col.desc())
    rows = list(db.execute(ordered.limit(page_size).offset((page - 1) * page_size)).scalars().all())
    return rows, total
```

(Add imports `from sqlalchemy import func, or_`, `from app.core.errors import DomainError`.)

- [ ] **Step 5: Route** (`app/modules/assistants/router.py`) — mirror Task 1's, with `role: str | None = None`, `status: AssistantStatus | None`, `Literal` sort/order, `Query(ge=...)` page/page_size, returning `AssistantListPage`.

- [ ] **Step 6: Run, verify PASS** + ruff clean. `uv run pytest tests/assistants/test_assistants_page.py -v`.

- [ ] **Step 7: Commit**

```bash
git add app/modules/assistants tests/assistants/test_assistants_page.py
git commit -m "feat(assistants): paginated/filterable/sortable /assistants/page endpoint (#106)"
```

---

## Self-Review (against the spec)
- §4 doctors `/page` (q over name/email/specialty, status, specialty filter, sort name/joined/status, order, page/page_size, total-before-limit): Task 1. ✅
- §4 assistants `/page` (q over name/email/title, role=title filter): Task 2. ✅
- §4 invalid sort/order → 422 (Literal query types): Tasks 1–2. ✅
- §4 existing full-list endpoints unchanged (no edits to `list_doctors`/`list_assistants` or their routes): confirmed — only additive. ✅
- §4 no migration; ⋯ actions reuse existing PATCH/DELETE (no new write endpoints): confirmed. ✅
- §4 read = CurrentMembership: both routes use it. ✅
- Type consistency: `DoctorListPage`/`AssistantListPage` `{items,total}`; service returns `(rows, total)`; route maps rows via `…Read.model_validate`. Consistent across both tasks. ✅
- Placeholder scan: concrete params, schemas, SQL, tests; no TBD. ✅
