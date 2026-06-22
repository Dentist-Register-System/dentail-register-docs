# User Settings — Backend Implementation Plan (#100)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Persist per-user preferences (theme + language) with a `user_preferences_beta` table, expose them on `GET /me`, and add `PATCH /api/v1/me/preferences`.

**Architecture:** Backend slice of the User Settings feature. New `app/modules/preferences/` module (model/schemas/service). The HTTP endpoints live in the existing **auth router** (which already hosts `/me` and `/me/profile`) — this keeps the import direction one-way (`auth → preferences`) and avoids an auth↔preferences cycle. Preferences are lazily created with defaults on first read/update (no backfill).

**Tech Stack:** FastAPI, SQLAlchemy 2.x (sync), Pydantic v2, Alembic, pytest on Postgres host port 5433.

## Global Constraints
- Table `user_preferences_beta`, 1:1 with `app_user_beta` (unique `user_id`). `theme ∈ {light,dark,system}` default `system`; `language ∈ {en,hi}` default `en`. CHECK constraints on both.
- Lazy default creation — existing users get `system`/`en` with no backfill (zero behavior change).
- Preferences are self-scoped: any authenticated user reads/updates only their OWN row (keyed off `auth.sub` → user). No clinic/role gating.
- Audit `user_preferences.updated` in-transaction (clinic_id omitted — not clinic-scoped).
- Module discipline: `core ← preferences`; auth router composes preferences.service. Never import auth from preferences.
- Quality gate per task: `uv run ruff check .` clean + `make test` green. Local PG :5433 only; never point Alembic/DB at Supabase.

---

### Task 1: Migration 0016 + UserPreferences model + module registration

**Files:**
- Create: `app/modules/preferences/__init__.py` (empty), `app/modules/preferences/models.py`
- Create: `alembic/versions/0016_user_preferences.py`
- Modify: `app/db/base.py` (register the model)
- Test: `tests/preferences/__init__.py` (empty), `tests/preferences/test_model.py`

**Interfaces:**
- Produces: `UserPreferences` (`app/modules/preferences/models.py`) with `id`, `user_id` (unique FK → app_user_beta.id), `theme: Mapped[str]` (default "system"), `language: Mapped[str]` (default "en"), `created_at`, `updated_at`.

- [ ] **Step 1: Write the failing test**

```python
# tests/preferences/test_model.py
import uuid as _uuid

from app.modules.auth.models import AppUser
from app.modules.preferences.models import UserPreferences


def test_user_preferences_defaults(db_session):
    user = AppUser(auth_user_id=_uuid.uuid4(), name="P")
    db_session.add(user)
    db_session.flush()
    pref = UserPreferences(user_id=user.id)
    db_session.add(pref)
    db_session.flush()
    db_session.refresh(pref)
    assert pref.theme == "system"
    assert pref.language == "en"
```

- [ ] **Step 2: Run to verify it fails**

Run: `uv run pytest tests/preferences/test_model.py -v`
Expected: FAIL — module `app.modules.preferences.models` does not exist.

- [ ] **Step 3: Create the model**

```python
# app/modules/preferences/models.py
import uuid
from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, String, func
from sqlalchemy.orm import Mapped, mapped_column

from app.core.base import Base


class UserPreferences(Base):
    __tablename__ = "user_preferences_beta"

    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("app_user_beta.id"), unique=True, index=True
    )
    theme: Mapped[str] = mapped_column(String(10), default="system")
    language: Mapped[str] = mapped_column(String(10), default="en")
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.clock_timestamp()
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.clock_timestamp(),
        onupdate=func.clock_timestamp(),
    )
```
Create empty `app/modules/preferences/__init__.py` and `tests/preferences/__init__.py`.

- [ ] **Step 4: Write the migration**

```python
# alembic/versions/0016_user_preferences.py
"""user_preferences_beta (per-user theme + language)

Revision ID: 0016
Revises: 0015
"""
from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "0016"
down_revision: str | None = "0015"
branch_labels: Sequence[str] | None = None
depends_on: Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "user_preferences_beta",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("theme", sa.String(length=10), nullable=False, server_default="system"),
        sa.Column("language", sa.String(length=10), nullable=False, server_default="en"),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.clock_timestamp(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.clock_timestamp(), nullable=False),
        sa.ForeignKeyConstraint(["user_id"], ["app_user_beta.id"], name=op.f("fk_user_preferences_beta_user_id_app_user_beta")),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_user_preferences_beta")),
        sa.UniqueConstraint("user_id", name=op.f("uq_user_preferences_beta_user_id")),
    )
    op.create_check_constraint("ck_user_preferences_theme", "user_preferences_beta", "theme IN ('light','dark','system')")
    op.create_check_constraint("ck_user_preferences_language", "user_preferences_beta", "language IN ('en','hi')")


def downgrade() -> None:
    op.drop_constraint("ck_user_preferences_language", "user_preferences_beta", type_="check")
    op.drop_constraint("ck_user_preferences_theme", "user_preferences_beta", type_="check")
    op.drop_table("user_preferences_beta")
```

- [ ] **Step 5: Register the model in `app/db/base.py`**

Add after the patients import:
```python
from app.modules.preferences.models import UserPreferences  # noqa: F401
```

- [ ] **Step 6: Run the test (schema fixture applies 0016)**

Run: `uv run pytest tests/preferences/test_model.py -v`
Expected: PASS. (`tests/conftest.py` runs `alembic upgrade head`, applying 0016 to the test DB.)

- [ ] **Step 7: Lint + commit**

```bash
uv run ruff check .
git add app/modules/preferences app/db/base.py alembic/versions/0016_user_preferences.py tests/preferences
git commit -m "feat(preferences): user_preferences_beta table + model (#100)"
```

---

### Task 2: Schemas + service (get-or-create + update + audit)

**Files:**
- Create: `app/modules/preferences/schemas.py`, `app/modules/preferences/service.py`
- Test: `tests/preferences/test_service.py`

**Interfaces:**
- Consumes: `UserPreferences` (Task 1), `record_audit` (`app/modules/audit/service`).
- Produces: `PreferencesRead`, `PreferencesUpdate`; `get_or_create_preferences(db, user_id: uuid.UUID) -> UserPreferences`; `update_preferences(db, user_id: uuid.UUID, data: PreferencesUpdate) -> UserPreferences`.

- [ ] **Step 1: Write the failing test**

```python
# tests/preferences/test_service.py
import uuid as _uuid

import pytest
from pydantic import ValidationError

from app.modules.auth.models import AppUser
from app.modules.preferences.schemas import PreferencesUpdate
from app.modules.preferences.service import get_or_create_preferences, update_preferences


def _user(db):
    u = AppUser(auth_user_id=_uuid.uuid4(), name="P")
    db.add(u); db.flush()
    return u


def test_get_or_create_returns_defaults_then_same_row(db_session):
    u = _user(db_session)
    p1 = get_or_create_preferences(db_session, u.id)
    assert (p1.theme, p1.language) == ("system", "en")
    p2 = get_or_create_preferences(db_session, u.id)
    assert p2.id == p1.id  # not duplicated


def test_update_partial_leaves_other_field(db_session):
    u = _user(db_session)
    get_or_create_preferences(db_session, u.id)
    p = update_preferences(db_session, u.id, PreferencesUpdate(theme="dark"))
    assert p.theme == "dark" and p.language == "en"
    p = update_preferences(db_session, u.id, PreferencesUpdate(language="hi"))
    assert p.theme == "dark" and p.language == "hi"


def test_update_creates_row_if_missing(db_session):
    u = _user(db_session)
    p = update_preferences(db_session, u.id, PreferencesUpdate(theme="light"))
    assert p.theme == "light" and p.language == "en"


def test_invalid_values_rejected_by_schema():
    with pytest.raises(ValidationError):
        PreferencesUpdate(theme="purple")
    with pytest.raises(ValidationError):
        PreferencesUpdate(language="fr")
```

- [ ] **Step 2: Run to verify it fails**

Run: `uv run pytest tests/preferences/test_service.py -v`
Expected: FAIL — schemas/service not defined.

- [ ] **Step 3: Write the schemas**

```python
# app/modules/preferences/schemas.py
from pydantic import BaseModel, ConfigDict, field_validator

_VALID_THEMES = ("light", "dark", "system")
_VALID_LANGUAGES = ("en", "hi")


class PreferencesRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    theme: str
    language: str


class PreferencesUpdate(BaseModel):
    theme: str | None = None
    language: str | None = None

    @field_validator("theme")
    @classmethod
    def _validate_theme(cls, v: str | None) -> str | None:
        if v is not None and v not in _VALID_THEMES:
            raise ValueError("theme must be one of light, dark, system.")
        return v

    @field_validator("language")
    @classmethod
    def _validate_language(cls, v: str | None) -> str | None:
        if v is not None and v not in _VALID_LANGUAGES:
            raise ValueError("language must be one of en, hi.")
        return v
```

- [ ] **Step 4: Write the service**

```python
# app/modules/preferences/service.py
import uuid

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.modules.audit.service import record_audit
from app.modules.preferences.models import UserPreferences
from app.modules.preferences.schemas import PreferencesUpdate


def get_or_create_preferences(db: Session, user_id: uuid.UUID) -> UserPreferences:
    pref = db.execute(
        select(UserPreferences).where(UserPreferences.user_id == user_id)
    ).scalar_one_or_none()
    if pref is None:
        pref = UserPreferences(user_id=user_id)
        db.add(pref)
        db.commit()
        db.refresh(pref)
    return pref


def update_preferences(
    db: Session, user_id: uuid.UUID, data: PreferencesUpdate
) -> UserPreferences:
    pref = get_or_create_preferences(db, user_id)
    changes = data.model_dump(exclude_unset=True, exclude_none=True)
    previous = {k: getattr(pref, k) for k in changes}
    for k, v in changes.items():
        setattr(pref, k, v)
    db.flush()
    record_audit(
        db,
        action="user_preferences.updated",
        entity_type="user_preferences",
        entity_id=pref.id,
        actor_user_id=user_id,
        previous=previous,
        new=changes,
    )
    db.commit()
    db.refresh(pref)
    return pref
```

- [ ] **Step 5: Run the test**

Run: `uv run pytest tests/preferences/test_service.py -v`
Expected: PASS.

- [ ] **Step 6: Lint + commit**

```bash
uv run ruff check .
git add app/modules/preferences tests/preferences/test_service.py
git commit -m "feat(preferences): schemas + get-or-create/update service (#100)"
```

---

### Task 3: Expose on `/me` + `PATCH /me/preferences`

**Files:**
- Modify: `app/modules/auth/schemas.py` (add `preferences` to `MeRead`)
- Modify: `app/modules/auth/router.py` (populate `preferences` in `/me`; add `PATCH /me/preferences`)
- Test: `tests/preferences/test_api.py`

**Interfaces:**
- Consumes: `get_or_create_preferences`, `update_preferences`, `PreferencesRead`, `PreferencesUpdate` (Task 2); `get_user_by_auth_id` (auth.service), `CurrentAuth`, `DbSession`.
- Produces: `MeRead.preferences: PreferencesRead | None`; endpoint `PATCH /api/v1/me/preferences → PreferencesRead`.

- [ ] **Step 1: Write the failing test**

```python
# tests/preferences/test_api.py
from tests.conftest import make_clinic

OWNER = "11111111-1111-1111-1111-111111111111"


def test_me_includes_default_preferences(auth_client):
    c, _ = auth_client(sub=OWNER)
    make_clinic(c, name="C")  # ensures an AppUser exists
    body = c.get("/api/v1/me").json()
    assert body["preferences"] == {"theme": "system", "language": "en"}


def test_patch_preferences_persists_and_roundtrips(auth_client):
    c, _ = auth_client(sub=OWNER)
    make_clinic(c, name="C")
    r = c.patch("/api/v1/me/preferences", json={"theme": "dark"})
    assert r.status_code == 200 and r.json() == {"theme": "dark", "language": "en"}
    assert c.get("/api/v1/me").json()["preferences"]["theme"] == "dark"
    r = c.patch("/api/v1/me/preferences", json={"language": "hi"})
    assert r.json() == {"theme": "dark", "language": "hi"}


def test_patch_invalid_theme_422(auth_client):
    c, _ = auth_client(sub=OWNER)
    make_clinic(c, name="C")
    assert c.patch("/api/v1/me/preferences", json={"theme": "neon"}).status_code == 422


def test_preferences_are_per_user(auth_client):
    a, _ = auth_client(sub=OWNER)
    make_clinic(a, name="A")
    a.patch("/api/v1/me/preferences", json={"theme": "dark"})
    b, _ = auth_client(sub="22222222-2222-2222-2222-222222222222")
    make_clinic(b, name="B")
    assert b.get("/api/v1/me").json()["preferences"]["theme"] == "system"  # unaffected
```

- [ ] **Step 2: Run to verify it fails**

Run: `uv run pytest tests/preferences/test_api.py -v`
Expected: FAIL — `preferences` not in `/me`; PATCH route 404/405.

- [ ] **Step 3: Add `preferences` to `MeRead`**

`app/modules/auth/schemas.py` — add the import + field:
```python
from app.modules.preferences.schemas import PreferencesRead
```
In `MeRead`, add:
```python
    preferences: PreferencesRead | None = None
```

- [ ] **Step 4: Populate `preferences` in `/me` and add the PATCH endpoint**

`app/modules/auth/router.py` — add imports:
```python
from app.modules.preferences.schemas import PreferencesRead, PreferencesUpdate
from app.modules.preferences.service import get_or_create_preferences, update_preferences
```
In `me(...)`, when `user` is not None, build the prefs read before returning and include it in the `MeRead(...)` (the `user is None` branch keeps `preferences=None`):
```python
    prefs = get_or_create_preferences(db, user.id)
    return MeRead(
        user_id=user.id, email=user.email, phone=user.phone,
        needs_onboarding=len(memberships) == 0, memberships=memberships,
        doctor_id=doctor_id, name=user.name, joined_at=user.created_at,
        preferences=PreferencesRead.model_validate(prefs),
    )
```
Add the endpoint at the end of the file:
```python
@router.patch("/me/preferences", response_model=PreferencesRead)
def update_my_preferences(
    data: PreferencesUpdate, auth: CurrentAuth, db: DbSession
) -> PreferencesRead:
    user = get_user_by_auth_id(db, uuid.UUID(auth.sub))
    if user is None:
        raise NotFoundError("User not found.")
    pref = update_preferences(db, user.id, data)
    return PreferencesRead.model_validate(pref)
```

- [ ] **Step 5: Run the tests**

Run: `uv run pytest tests/preferences/test_api.py -v`
Expected: PASS.

- [ ] **Step 6: Full suite + lint**

Run: `uv run ruff check . && make test`
Expected: all green (no regression to existing `/me` tests — `preferences` is additive).

- [ ] **Step 7: Commit**

```bash
git add app/modules/auth tests/preferences/test_api.py
git commit -m "feat(auth): expose preferences on /me + PATCH /me/preferences (#100)"
```

---

## Self-Review (plan vs spec)
- **Spec §3 table/migration** → Task 1 (0016, model, CHECKs, unique user_id). ✅
- **Spec §4 module + service (get-or-create, update, audit)** → Task 1 (module) + Task 2 (service/schemas). ✅
- **Spec §4 /me preferences + PATCH /me/preferences (self)** → Task 3. ✅
- **Spec §4 lazy default creation, no backfill** → `get_or_create_preferences` (Task 2), used by both /me and PATCH. ✅
- **Spec §4 validators (theme/language)** → Task 2 schemas + Task 3 invalid-422 test. ✅
- **Spec §4 tests** → Tasks 1-3 each add tests; Task 3 Step 6 full suite. ✅
- **Type consistency:** `get_or_create_preferences`/`update_preferences` signatures defined Task 2, consumed Task 3; `PreferencesRead`/`PreferencesUpdate` defined Task 2, used Task 3; `UserPreferences` Task 1 → Task 2. ✅
- **Module direction:** endpoints in auth router (auth → preferences), no preferences→auth import. ✅
- **Placeholder scan:** concrete code/paths/commands; no TBD. ✅
