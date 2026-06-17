# Auth + Clinic Workspace Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the multi-tenant identity + authorization foundation: Supabase-Auth login (phone-OTP / email-pw) validated by FastAPI via JWKS, self-serve clinic creation vs role-specific invite joining, clinic-boundary + role enforcement, and a minimal append-only audit trail.

**Architecture:** Frontend authenticates with Supabase Auth (supabase-js) and sends the Supabase JWT as a Bearer token. FastAPI verifies the JWT against the project's JWKS (ES256), maps the auth identity to an `app_user`, resolves the `clinic_member` (role) for the clinic in the route, and is the authoritative tenant/role gate. Data lives in Supabase Postgres; automated tests run against a local Postgres test DB with mocked JWTs.

**Tech Stack:** Backend — FastAPI, SQLAlchemy 2.x (sync), Alembic, Pydantic, `pyjwt[crypto]` (ES256 JWKS verification). Frontend — Next.js (App Router), `@supabase/supabase-js`, TanStack Query, React Hook Form, Zod, shadcn/ui, Playwright.

**Spec:** `docs/specs/2026-06-17-auth-clinic-workspace-design.md` (approved, merged).

## Global Constraints

Every task implicitly includes these (from the spec + the skeleton it builds on):

- **Repos / dirs:** backend = `~/Documents/register_workspace/dentist-registry-backend`; frontend = `~/Documents/register_workspace/dentist-registry-frontend`. Both on `main` with the merged skeleton.
- **Git:** never push to `main`; feature branch → PR → review → merge via `gh-personal` (`github-personal`, email `rohan2jos@gmail.com`).
- **Backend layout:** feature-first modules under `app/modules/<domain>/` (`router.py`, `schemas.py`, `models.py`, `service.py`). Dependency direction: `core/ ← auth ← members ← {clinics, invites, audit-consumers} ← main`. Cross-module use goes through a module's public deps/service, never sideways into its internals. `app/db/base.py` is the only model aggregator. Routers stay thin. No circular imports (string-based SQLAlchemy relationships).
- **DB conventions:** UUID PKs; tz-aware timestamps (`server_default=func.clock_timestamp()` for creation instants); `MetaData` naming convention from the skeleton.
- **`_beta` table naming** during implementation (Golden Rule 4.5): `clinic_beta`, `clinic_settings_beta`, `app_user_beta`, `clinic_member_beta`, `clinic_invite_beta`, `audit_event_beta`.
- **`app_user_beta.auth_user_id`** is a plain **UUID (unique), NOT a DB FK** to `auth.users` — so the local test DB (no `auth` schema) works and we don't couple to Supabase's managed schema. Identity trust comes from the verified JWT `sub`.
- **JWT:** verify ES256 via JWKS at `<supabase_url>/auth/v1/.well-known/jwks.json`; validate `iss = <supabase_url>/auth/v1`, `aud = "authenticated"`, `exp`, and require `sub`. Backend needs **no** Supabase API key.
- **Tests:** pytest against the local Postgres `register_test` DB (port 5433), schema built by **running migrations**; **mock all Supabase Auth** (test ES256 keypair + fake JWKS), never call real Supabase (Golden Rule 10.3). Pristine output. Uniform error envelope from the skeleton.
- **RLS** enabled on every new `public` table; no `anon`/`authenticated` grants (tables stay off the Data API). FastAPI connects via `DATABASE_URL` (privileged).
- **Audit:** every mutating action writes an `audit_event_beta` row in the SAME transaction; append-only (no update/delete).
- **Roles:** `owner, practice_manager, doctor, assistant`. Owner = self-serve creator only. Invite carries the role to grant.
- **Permissive-OSS deps only** (`pyjwt`, `@supabase/supabase-js` are MIT). No secrets committed.

---

# Phase A — Backend (`dentist-registry-backend`)

> Branch: `git switch -c sp1-auth-backend` in the backend repo before Task A1.

### Task A1: Foundation — Supabase config, JWT deps, remove ping slice

**Files:**
- Modify: `app/core/config.py` (Supabase settings), `pyproject.toml` (add `pyjwt[crypto]`)
- Delete: `app/modules/ping/` (whole dir), `tests/ping/` (whole dir)
- Modify: `app/main.py` (remove ping router import + mount), `app/db/base.py` (remove ping model import)
- Modify: `.env.example` (add SUPABASE_URL)
- Test: `tests/test_config.py`

**Interfaces:**
- Produces: `settings.supabase_url`, `settings.supabase_jwt_audience`, and properties `settings.supabase_issuer`, `settings.supabase_jwks_url`.

- [ ] **Step 1: Add the dependency and Supabase settings**

In `pyproject.toml` `dependencies`, add `"pyjwt[crypto]>=2.9"`. Then `uv sync`.

In `app/core/config.py`, add to `Settings`:
```python
    supabase_url: str = "https://wxwasnshmnttiixvzeod.supabase.co"
    supabase_jwt_audience: str = "authenticated"

    @property
    def supabase_issuer(self) -> str:
        return f"{self.supabase_url}/auth/v1"

    @property
    def supabase_jwks_url(self) -> str:
        return f"{self.supabase_url}/auth/v1/.well-known/jwks.json"
```
Add `SUPABASE_URL=https://wxwasnshmnttiixvzeod.supabase.co` to `.env.example`.

- [ ] **Step 2: Remove the throwaway ping slice**

```bash
git rm -r app/modules/ping tests/ping
```
In `app/main.py` remove the `from app.modules.ping.router import router as ping_router` line and the `app.include_router(ping_router, prefix="/api/v1")` line. In `app/db/base.py` remove `from app.modules.ping.models import PingBeta`.

- [ ] **Step 3: Write the failing config test**

`tests/test_config.py`:
```python
from app.core.config import settings


def test_supabase_issuer_and_jwks_derived_from_url() -> None:
    assert settings.supabase_issuer == f"{settings.supabase_url}/auth/v1"
    assert settings.supabase_jwks_url.endswith("/auth/v1/.well-known/jwks.json")
    assert settings.supabase_jwt_audience == "authenticated"
```

- [ ] **Step 4: Run tests**

Run: `make test`
Expected: `test_config` passes; `test_health` still passes; no ping tests remain; pristine output.

- [ ] **Step 5: Lint and commit**

```bash
uv run ruff check .
git add -A
git commit -m "feat: add Supabase auth config and pyjwt; remove ping slice"
```

---

### Task A2: JWT verification + `current_auth` dependency

**Files:**
- Create: `app/modules/auth/__init__.py`, `app/modules/auth/jwks.py`, `app/modules/auth/tokens.py`, `app/modules/auth/deps.py`
- Test: `tests/auth/__init__.py`, `tests/auth/conftest.py` (test keypair + token factory + fake JWKS), `tests/auth/test_tokens.py`

**Interfaces:**
- Produces: `AuthIdentity(sub: str, email: str | None, phone: str | None)`; `verify_token(token, jwk_client, *, issuer, audience) -> AuthIdentity` (raises `InvalidToken`); `get_current_auth` FastAPI dependency + `CurrentAuth` annotated type; `AuthError(DomainError)` (status 401, code `unauthorized`).

- [ ] **Step 1: Write the test fixtures (ES256 keypair, token factory, fake JWKS)**

`tests/auth/__init__.py`: empty. `tests/auth/conftest.py`:
```python
import datetime as dt
import uuid

import jwt
import pytest
from cryptography.hazmat.primitives.asymmetric import ec

from app.core.config import settings


@pytest.fixture(scope="session")
def ec_keypair():
    private_key = ec.generate_private_key(ec.SECP256R1())
    return private_key


@pytest.fixture
def make_token(ec_keypair):
    def _make(**overrides) -> str:
        now = dt.datetime.now(tz=dt.timezone.utc)
        claims = {
            "sub": str(uuid.uuid4()),
            "aud": settings.supabase_jwt_audience,
            "iss": settings.supabase_issuer,
            "exp": int((now + dt.timedelta(hours=1)).timestamp()),
            "email": "user@example.com",
            "phone": "",
        }
        claims.update(overrides)
        return jwt.encode(claims, ec_keypair, algorithm="ES256")
    return _make


@pytest.fixture
def fake_jwk_client(ec_keypair):
    public_key = ec_keypair.public_key()

    class _Key:
        key = public_key

    class _Client:
        def get_signing_key_from_jwt(self, token: str):
            return _Key()

    return _Client()
```

- [ ] **Step 2: Write the failing token tests**

`tests/auth/test_tokens.py`:
```python
import datetime as dt

import pytest

from app.core.config import settings
from app.modules.auth.tokens import AuthIdentity, InvalidToken, verify_token


def _verify(token, client):
    return verify_token(
        token, client, issuer=settings.supabase_issuer,
        audience=settings.supabase_jwt_audience,
    )


def test_verify_valid_token(make_token, fake_jwk_client) -> None:
    token = make_token(sub="abc", email="a@b.com")
    identity = _verify(token, fake_jwk_client)
    assert isinstance(identity, AuthIdentity)
    assert identity.sub == "abc"
    assert identity.email == "a@b.com"


def test_verify_rejects_expired(make_token, fake_jwk_client) -> None:
    past = int((dt.datetime.now(tz=dt.timezone.utc) - dt.timedelta(hours=1)).timestamp())
    with pytest.raises(InvalidToken):
        _verify(make_token(exp=past), fake_jwk_client)


def test_verify_rejects_wrong_issuer(make_token, fake_jwk_client) -> None:
    with pytest.raises(InvalidToken):
        _verify(make_token(iss="https://evil.example/auth/v1"), fake_jwk_client)


def test_verify_rejects_wrong_audience(make_token, fake_jwk_client) -> None:
    with pytest.raises(InvalidToken):
        _verify(make_token(aud="anon"), fake_jwk_client)
```

Run: `make test` → these FAIL (`app.modules.auth.tokens` missing).

- [ ] **Step 3: Implement tokens + jwks**

`app/modules/auth/jwks.py`:
```python
from jwt import PyJWKClient

from app.core.config import settings

_jwk_client: PyJWKClient | None = None


def get_jwk_client() -> PyJWKClient:
    global _jwk_client
    if _jwk_client is None:
        _jwk_client = PyJWKClient(settings.supabase_jwks_url, cache_keys=True)
    return _jwk_client
```

`app/modules/auth/tokens.py`:
```python
from dataclasses import dataclass

import jwt
from jwt import PyJWKClient


@dataclass(frozen=True)
class AuthIdentity:
    sub: str
    email: str | None
    phone: str | None


class InvalidToken(Exception):
    """Raised when a Supabase JWT fails verification."""


def verify_token(
    token: str, jwk_client: PyJWKClient, *, issuer: str, audience: str
) -> AuthIdentity:
    try:
        signing_key = jwk_client.get_signing_key_from_jwt(token)
        claims = jwt.decode(
            token,
            signing_key.key,
            algorithms=["ES256"],
            audience=audience,
            issuer=issuer,
            options={"require": ["exp", "sub", "aud", "iss"]},
        )
    except Exception as exc:  # PyJWT raises many subclasses; normalize them
        raise InvalidToken(str(exc)) from exc
    return AuthIdentity(
        sub=claims["sub"],
        email=claims.get("email") or None,
        phone=claims.get("phone") or None,
    )
```

Run: `make test` → token tests PASS.

- [ ] **Step 4: Add the `current_auth` dependency**

`app/modules/auth/deps.py`:
```python
from typing import Annotated

from fastapi import Depends, Header

from app.core.config import settings
from app.core.errors import DomainError
from app.modules.auth.jwks import get_jwk_client
from app.modules.auth.tokens import AuthIdentity, InvalidToken, verify_token


class AuthError(DomainError):
    status_code = 401
    code = "unauthorized"


def get_current_auth(
    authorization: Annotated[str | None, Header()] = None,
) -> AuthIdentity:
    if not authorization or not authorization.lower().startswith("bearer "):
        raise AuthError("Missing or malformed Authorization header.")
    token = authorization.split(" ", 1)[1].strip()
    try:
        return verify_token(
            token,
            get_jwk_client(),
            issuer=settings.supabase_issuer,
            audience=settings.supabase_jwt_audience,
        )
    except InvalidToken as exc:
        raise AuthError("Invalid authentication token.") from exc


CurrentAuth = Annotated[AuthIdentity, Depends(get_current_auth)]
```

- [ ] **Step 5: Run, lint, commit**

Run: `make test` (all green, pristine) and `uv run ruff check .`
```bash
git add -A
git commit -m "feat: add Supabase JWT (ES256/JWKS) verification and current_auth dependency"
```

---

### Task A3: SP1 data model + migration + audit helper

**Files:**
- Create: `app/modules/auth/models.py` (`AppUser`), `app/modules/clinics/__init__.py` + `models.py` (`Clinic`, `ClinicSettings`), `app/modules/members/__init__.py` + `models.py` (`ClinicMember`), `app/modules/invites/__init__.py` + `models.py` (`ClinicInvite`), `app/modules/audit/__init__.py` + `models.py` (`AuditEvent`) + `service.py` (`record_audit`)
- Modify: `app/db/base.py` (import all new models)
- Create: `alembic/versions/0002_auth_clinic_workspace.py`
- Test: `tests/auth/test_models.py`

**Interfaces:**
- Produces ORM models (all `*_beta` tables): `AppUser(id, auth_user_id: uuid unique, name, phone, email, status, created_at)`; `Clinic(id, name, phone, whatsapp_number, operating_hours, address, status, created_at, created_by)`; `ClinicSettings(id, clinic_id unique, allow_multiple_bookings_per_slot, max_bookings_per_slot, default_slot_size_minutes, appointment_request_expiry_minutes, post_confirmation_hook_delay_minutes, reminders_enabled, whatsapp_enabled, google_calendar_enabled, created_at, updated_at)`; `ClinicMember(id, clinic_id, user_id, role, status, created_at, created_by)` unique(clinic_id, user_id); `ClinicInvite(id, clinic_id, role, token unique, created_by, status, expires_at, accepted_by, accepted_at, invited_contact, created_at)`; `AuditEvent(id, clinic_id, actor_user_id, action, entity_type, entity_id, previous_value, new_value, reason, created_at)`. Enums: `MemberRole`, `MemberStatus`, `UserStatus`, `ClinicStatus`, `InviteStatus`. Helper `record_audit(db, *, clinic_id, actor_user_id, action, entity_type, entity_id, previous=None, new=None, reason=None) -> AuditEvent`.

- [ ] **Step 1: Define enums + models**

`app/modules/auth/models.py`:
```python
import enum
import uuid
from datetime import datetime

from sqlalchemy import DateTime, String, func
from sqlalchemy import Enum as SAEnum
from sqlalchemy.orm import Mapped, mapped_column

from app.core.base import Base


class UserStatus(str, enum.Enum):
    invited = "invited"
    active = "active"
    inactive = "inactive"


class AppUser(Base):
    __tablename__ = "app_user_beta"

    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid.uuid4)
    auth_user_id: Mapped[uuid.UUID] = mapped_column(unique=True, index=True)
    name: Mapped[str | None] = mapped_column(String(200), nullable=True)
    phone: Mapped[str | None] = mapped_column(String(32), nullable=True)
    email: Mapped[str | None] = mapped_column(String(320), nullable=True)
    status: Mapped[UserStatus] = mapped_column(
        SAEnum(UserStatus, name="user_status"), default=UserStatus.active
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.clock_timestamp()
    )
```

`app/modules/clinics/models.py`:
```python
import enum
import uuid
from datetime import datetime

from sqlalchemy import Boolean, DateTime, ForeignKey, Integer, String, func
from sqlalchemy import Enum as SAEnum
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column

from app.core.base import Base


class ClinicStatus(str, enum.Enum):
    active = "active"
    inactive = "inactive"


class Clinic(Base):
    __tablename__ = "clinic_beta"

    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid.uuid4)
    name: Mapped[str] = mapped_column(String(200))
    phone: Mapped[str | None] = mapped_column(String(32), nullable=True)
    whatsapp_number: Mapped[str | None] = mapped_column(String(32), nullable=True)
    operating_hours: Mapped[dict | None] = mapped_column(JSONB, nullable=True)
    address: Mapped[str | None] = mapped_column(String(500), nullable=True)
    status: Mapped[ClinicStatus] = mapped_column(
        SAEnum(ClinicStatus, name="clinic_status"), default=ClinicStatus.active
    )
    created_by: Mapped[uuid.UUID | None] = mapped_column(nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.clock_timestamp()
    )


class ClinicSettings(Base):
    __tablename__ = "clinic_settings_beta"

    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid.uuid4)
    clinic_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("clinic_beta.id"), unique=True
    )
    allow_multiple_bookings_per_slot: Mapped[bool] = mapped_column(Boolean, default=False)
    max_bookings_per_slot: Mapped[int] = mapped_column(Integer, default=3)
    default_slot_size_minutes: Mapped[int] = mapped_column(Integer, default=30)
    appointment_request_expiry_minutes: Mapped[int] = mapped_column(Integer, default=120)
    post_confirmation_hook_delay_minutes: Mapped[int] = mapped_column(Integer, default=5)
    reminders_enabled: Mapped[bool] = mapped_column(Boolean, default=True)
    whatsapp_enabled: Mapped[bool] = mapped_column(Boolean, default=False)
    google_calendar_enabled: Mapped[bool] = mapped_column(Boolean, default=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.clock_timestamp()
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.clock_timestamp()
    )
```

`app/modules/members/models.py`:
```python
import enum
import uuid
from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, UniqueConstraint, func
from sqlalchemy import Enum as SAEnum
from sqlalchemy.orm import Mapped, mapped_column

from app.core.base import Base


class MemberRole(str, enum.Enum):
    owner = "owner"
    practice_manager = "practice_manager"
    doctor = "doctor"
    assistant = "assistant"


class MemberStatus(str, enum.Enum):
    active = "active"
    inactive = "inactive"


class ClinicMember(Base):
    __tablename__ = "clinic_member_beta"
    __table_args__ = (UniqueConstraint("clinic_id", "user_id", name="uq_member_clinic_user"),)

    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid.uuid4)
    clinic_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("clinic_beta.id"), index=True)
    user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("app_user_beta.id"), index=True)
    role: Mapped[MemberRole] = mapped_column(SAEnum(MemberRole, name="member_role"))
    status: Mapped[MemberStatus] = mapped_column(
        SAEnum(MemberStatus, name="member_status"), default=MemberStatus.active
    )
    created_by: Mapped[uuid.UUID | None] = mapped_column(nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.clock_timestamp()
    )
```

`app/modules/invites/models.py`:
```python
import enum
import uuid
from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, String, func
from sqlalchemy import Enum as SAEnum
from sqlalchemy.orm import Mapped, mapped_column

from app.core.base import Base
from app.modules.members.models import MemberRole


class InviteStatus(str, enum.Enum):
    pending = "pending"
    accepted = "accepted"
    revoked = "revoked"
    expired = "expired"


class ClinicInvite(Base):
    __tablename__ = "clinic_invite_beta"

    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid.uuid4)
    clinic_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("clinic_beta.id"), index=True)
    role: Mapped[MemberRole] = mapped_column(SAEnum(MemberRole, name="member_role"))
    token: Mapped[str] = mapped_column(String(64), unique=True, index=True)
    created_by: Mapped[uuid.UUID] = mapped_column(ForeignKey("app_user_beta.id"))
    status: Mapped[InviteStatus] = mapped_column(
        SAEnum(InviteStatus, name="invite_status"), default=InviteStatus.pending
    )
    invited_contact: Mapped[str | None] = mapped_column(String(320), nullable=True)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    accepted_by: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("app_user_beta.id"), nullable=True
    )
    accepted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.clock_timestamp()
    )
```
> Note: `MemberRole` is imported (not redefined) so the `member_role` enum type is shared. In the migration, create the enum type once and reference it with `create_type=False` on later columns (see Step 3).

`app/modules/audit/models.py`:
```python
import uuid
from datetime import datetime

from sqlalchemy import DateTime, String, func
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column

from app.core.base import Base


class AuditEvent(Base):
    __tablename__ = "audit_event_beta"

    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid.uuid4)
    clinic_id: Mapped[uuid.UUID | None] = mapped_column(nullable=True, index=True)
    actor_user_id: Mapped[uuid.UUID | None] = mapped_column(nullable=True)
    action: Mapped[str] = mapped_column(String(100))
    entity_type: Mapped[str] = mapped_column(String(100))
    entity_id: Mapped[uuid.UUID] = mapped_column()
    previous_value: Mapped[dict | None] = mapped_column(JSONB, nullable=True)
    new_value: Mapped[dict | None] = mapped_column(JSONB, nullable=True)
    reason: Mapped[str | None] = mapped_column(String(500), nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.clock_timestamp()
    )
```

- [ ] **Step 2: Audit helper + register models**

`app/modules/audit/service.py`:
```python
import uuid

from sqlalchemy.orm import Session

from app.modules.audit.models import AuditEvent


def record_audit(
    db: Session,
    *,
    action: str,
    entity_type: str,
    entity_id: uuid.UUID,
    clinic_id: uuid.UUID | None = None,
    actor_user_id: uuid.UUID | None = None,
    previous: dict | None = None,
    new: dict | None = None,
    reason: str | None = None,
) -> AuditEvent:
    event = AuditEvent(
        clinic_id=clinic_id,
        actor_user_id=actor_user_id,
        action=action,
        entity_type=entity_type,
        entity_id=entity_id,
        previous_value=previous,
        new_value=new,
        reason=reason,
    )
    db.add(event)
    db.flush()  # same transaction as the caller; caller commits
    return event
```
`app/modules/{auth,clinics,members,invites,audit}/__init__.py`: empty. Update `app/db/base.py`:
```python
from app.core.base import Base  # noqa: F401
from app.modules.auth.models import AppUser  # noqa: F401
from app.modules.clinics.models import Clinic, ClinicSettings  # noqa: F401
from app.modules.members.models import ClinicMember  # noqa: F401
from app.modules.invites.models import ClinicInvite  # noqa: F401
from app.modules.audit.models import AuditEvent  # noqa: F401
```

- [ ] **Step 3: Create the migration**

Generate the skeleton with Alembic, then hand-edit to the model above:
```bash
uv run alembic revision -m "auth clinic workspace" --rev-id 0002
```
Fill `alembic/versions/0002_auth_clinic_workspace.py` `upgrade()` to create the enum types **once** (`user_status`, `clinic_status`, `member_role`, `member_status`, `invite_status`) and the six tables with the exact columns/constraints above (UUID PKs named `pk_<table>`, the unique constraints `uq_member_clinic_user`, `clinic_settings_beta.clinic_id` unique, `clinic_invite_beta.token` unique, `app_user_beta.auth_user_id` unique). For columns reusing `member_role`, pass `postgresql.ENUM(..., name="member_role", create_type=False)` so the type is created once. `downgrade()` drops the tables then the enum types.

(Use `uv run alembic revision --autogenerate --rev-id 0002 -m "auth clinic workspace"` first to get a correct draft from the models, then verify it matches — autogenerate handles the enum-create-once and constraint naming for you. Review before committing.)

- [ ] **Step 4: Apply + write the model test**

Run: `make migrate` → creates all six tables.

`tests/auth/test_models.py`:
```python
import uuid

from app.modules.audit.service import record_audit
from app.modules.auth.models import AppUser
from app.modules.clinics.models import Clinic


def test_app_user_persists(db_session) -> None:
    user = AppUser(auth_user_id=uuid.uuid4(), name="Priya", email="p@c.com")
    db_session.add(user)
    db_session.flush()
    db_session.refresh(user)
    assert user.id is not None
    assert user.status.value == "active"


def test_record_audit_writes_event(db_session) -> None:
    clinic = Clinic(name="Test Clinic")
    db_session.add(clinic)
    db_session.flush()
    event = record_audit(
        db_session, action="clinic.created", entity_type="clinic",
        entity_id=clinic.id, clinic_id=clinic.id, new={"name": "Test Clinic"},
    )
    assert event.id is not None
    assert event.action == "clinic.created"
```

Run: `make test` → PASS (against the migration-built schema).

- [ ] **Step 5: Lint and commit**

```bash
uv run ruff check .
git add -A
git commit -m "feat: add clinic/user/member/invite/audit models, migration, and audit helper"
```

---

### Task A4: `current_user` dependency + `GET /me`

**Files:**
- Create: `app/modules/auth/schemas.py`, `app/modules/auth/service.py`, `app/modules/auth/router.py`
- Modify: `app/modules/auth/deps.py` (add `get_current_user`), `app/main.py` (mount auth router under `/api/v1`)
- Test: `tests/auth/test_me.py`

**Interfaces:**
- Consumes: `CurrentAuth`, `DbSession`, `AppUser`, `ClinicMember`.
- Produces: `get_or_none_user(db, auth_user_id) -> AppUser | None`; `ensure_user(db, identity) -> AppUser` (creates the `app_user` if absent, from the identity); `get_current_user` dependency → `AppUser` (raises 401 if no JWT); `CurrentUser` type. `GET /api/v1/me` → `{ user, memberships: [{clinic_id, clinic_name, role, status}], needs_onboarding: bool }`.

- [ ] **Step 1: Write the failing `/me` tests**

`tests/auth/test_me.py` (uses an `auth_client` fixture defined in Step 2 that injects a verified identity):
```python
def test_me_new_user_needs_onboarding(auth_client) -> None:
    client, _ = auth_client()
    resp = client.get("/api/v1/me")
    assert resp.status_code == 200
    body = resp.json()
    assert body["needs_onboarding"] is True
    assert body["memberships"] == []


def test_me_requires_auth(client) -> None:
    resp = client.get("/api/v1/me")
    assert resp.status_code == 401
    assert resp.json()["error"]["code"] == "unauthorized"
```

- [ ] **Step 2: Add an `auth_client` fixture that overrides `get_current_auth`**

Append to `tests/auth/conftest.py`:
```python
import uuid as _uuid

from fastapi.testclient import TestClient

from app.main import create_app
from app.modules.auth.deps import get_current_auth
from app.modules.auth.tokens import AuthIdentity


@pytest.fixture
def auth_client(db_session):
    def _factory(sub: str | None = None, email: str | None = "user@example.com",
                 phone: str | None = None):
        identity = AuthIdentity(sub=sub or str(_uuid.uuid4()), email=email, phone=phone)
        app = create_app()
        from app.core.database import get_db

        def _override_db():
            yield db_session

        app.dependency_overrides[get_db] = _override_db
        app.dependency_overrides[get_current_auth] = lambda: identity
        return TestClient(app), identity

    return _factory
```
(This mocks Supabase — no real JWT/JWKS in tests, per Golden Rule 10.3.)

- [ ] **Step 3: Implement service, schemas, deps, router**

`app/modules/auth/service.py`:
```python
import uuid

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.modules.auth.models import AppUser
from app.modules.auth.tokens import AuthIdentity


def get_user_by_auth_id(db: Session, auth_user_id: uuid.UUID) -> AppUser | None:
    return db.execute(
        select(AppUser).where(AppUser.auth_user_id == auth_user_id)
    ).scalar_one_or_none()


def ensure_user(db: Session, identity: AuthIdentity) -> AppUser:
    auth_id = uuid.UUID(identity.sub)
    user = get_user_by_auth_id(db, auth_id)
    if user is None:
        user = AppUser(auth_user_id=auth_id, email=identity.email, phone=identity.phone)
        db.add(user)
        db.flush()
    return user
```

In `app/modules/auth/deps.py` add:
```python
from app.core.deps import DbSession
from app.modules.auth.models import AppUser
from app.modules.auth.service import get_user_by_auth_id
import uuid


def get_current_user(auth: CurrentAuth, db: DbSession) -> AppUser:
    user = get_user_by_auth_id(db, uuid.UUID(auth.sub))
    if user is None:
        raise AuthError("No account yet; onboarding required.")
    return user


CurrentUser = Annotated[AppUser, Depends(get_current_user)]
```
> The `/me` endpoint must NOT use `get_current_user` (a brand-new user has no `app_user` yet); it uses `CurrentAuth` + a lookup so it can report `needs_onboarding`.

`app/modules/auth/schemas.py`:
```python
import uuid

from pydantic import BaseModel


class MembershipRead(BaseModel):
    clinic_id: uuid.UUID
    clinic_name: str
    role: str
    status: str


class MeRead(BaseModel):
    user_id: uuid.UUID | None
    email: str | None
    phone: str | None
    needs_onboarding: bool
    memberships: list[MembershipRead]
```

`app/modules/auth/router.py`:
```python
import uuid

from fastapi import APIRouter
from sqlalchemy import select

from app.core.deps import DbSession
from app.modules.auth.deps import CurrentAuth
from app.modules.auth.schemas import MeRead, MembershipRead
from app.modules.auth.service import get_user_by_auth_id
from app.modules.clinics.models import Clinic
from app.modules.members.models import ClinicMember, MemberStatus

router = APIRouter(tags=["auth"])


@router.get("/me", response_model=MeRead)
def me(auth: CurrentAuth, db: DbSession) -> MeRead:
    user = get_user_by_auth_id(db, uuid.UUID(auth.sub))
    if user is None:
        return MeRead(
            user_id=None, email=auth.email, phone=auth.phone,
            needs_onboarding=True, memberships=[],
        )
    rows = db.execute(
        select(ClinicMember, Clinic)
        .join(Clinic, Clinic.id == ClinicMember.clinic_id)
        .where(ClinicMember.user_id == user.id, ClinicMember.status == MemberStatus.active)
    ).all()
    memberships = [
        MembershipRead(
            clinic_id=m.clinic_id, clinic_name=c.name,
            role=m.role.value, status=m.status.value,
        )
        for (m, c) in rows
    ]
    return MeRead(
        user_id=user.id, email=user.email, phone=user.phone,
        needs_onboarding=len(memberships) == 0, memberships=memberships,
    )
```
Mount in `app/main.py`: `app.include_router(auth_router, prefix="/api/v1")` (import `from app.modules.auth.router import router as auth_router`).

- [ ] **Step 4: Run, lint, commit**

Run: `make test` (green) · `uv run ruff check .`
```bash
git add -A
git commit -m "feat: add current_user dependency and GET /me with onboarding status"
```

---

### Task A5: Self-serve clinic creation (`POST /clinics`)

**Files:**
- Create: `app/modules/clinics/schemas.py`, `app/modules/clinics/service.py`, `app/modules/clinics/router.py`
- Modify: `app/main.py` (mount clinics router)
- Test: `tests/clinics/__init__.py`, `tests/clinics/test_create.py`

**Interfaces:**
- Consumes: `CurrentAuth`, `DbSession`, `ensure_user`, `record_audit`, models.
- Produces: `create_clinic(db, identity, data) -> Clinic` (atomically: ensure app_user → create `Clinic` + `ClinicSettings` defaults + `ClinicMember(role=owner, active)` + audit events; commits). `POST /api/v1/clinics {name, phone?, whatsapp_number?, address?}` → 201 `ClinicRead`.

- [ ] **Step 1: Write the failing test**

`tests/clinics/test_create.py`:
```python
from sqlalchemy import select

from app.modules.audit.models import AuditEvent
from app.modules.members.models import ClinicMember, MemberRole


def test_create_clinic_makes_owner_settings_and_audit(auth_client, db_session) -> None:
    client, identity = auth_client()
    resp = client.post("/api/v1/clinics", json={"name": "Bright Smiles", "phone": "+910000000000"})
    assert resp.status_code == 201
    clinic = resp.json()
    assert clinic["name"] == "Bright Smiles"

    members = db_session.execute(select(ClinicMember)).scalars().all()
    assert len(members) == 1
    assert members[0].role == MemberRole.owner

    actions = {e.action for e in db_session.execute(select(AuditEvent)).scalars().all()}
    assert "clinic.created" in actions
    assert "clinic_member.created" in actions


def test_create_clinic_requires_auth(client) -> None:
    assert client.post("/api/v1/clinics", json={"name": "X"}).status_code == 401
```

- [ ] **Step 2: Implement schemas, service, router**

`app/modules/clinics/schemas.py`:
```python
import uuid

from pydantic import BaseModel, ConfigDict, Field


class ClinicCreate(BaseModel):
    name: str = Field(min_length=1, max_length=200)
    phone: str | None = Field(default=None, max_length=32)
    whatsapp_number: str | None = Field(default=None, max_length=32)
    address: str | None = Field(default=None, max_length=500)


class ClinicRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    name: str
    phone: str | None
    status: str
```

`app/modules/clinics/service.py`:
```python
from sqlalchemy.orm import Session

from app.modules.audit.service import record_audit
from app.modules.auth.service import ensure_user
from app.modules.auth.tokens import AuthIdentity
from app.modules.clinics.models import Clinic, ClinicSettings
from app.modules.clinics.schemas import ClinicCreate
from app.modules.members.models import ClinicMember, MemberRole, MemberStatus


def create_clinic(db: Session, identity: AuthIdentity, data: ClinicCreate) -> Clinic:
    user = ensure_user(db, identity)
    clinic = Clinic(
        name=data.name, phone=data.phone,
        whatsapp_number=data.whatsapp_number, address=data.address,
        created_by=user.id,
    )
    db.add(clinic)
    db.flush()
    db.add(ClinicSettings(clinic_id=clinic.id))
    member = ClinicMember(
        clinic_id=clinic.id, user_id=user.id,
        role=MemberRole.owner, status=MemberStatus.active, created_by=user.id,
    )
    db.add(member)
    db.flush()
    record_audit(db, action="clinic.created", entity_type="clinic",
                 entity_id=clinic.id, clinic_id=clinic.id, actor_user_id=user.id,
                 new={"name": clinic.name})
    record_audit(db, action="clinic_member.created", entity_type="clinic_member",
                 entity_id=member.id, clinic_id=clinic.id, actor_user_id=user.id,
                 new={"role": "owner"})
    db.commit()
    db.refresh(clinic)
    return clinic
```

`app/modules/clinics/router.py`:
```python
from fastapi import APIRouter, status

from app.core.deps import DbSession
from app.modules.auth.deps import CurrentAuth
from app.modules.clinics import service
from app.modules.clinics.schemas import ClinicCreate, ClinicRead

router = APIRouter(prefix="/clinics", tags=["clinics"])


@router.post("", response_model=ClinicRead, status_code=status.HTTP_201_CREATED)
def create_clinic(data: ClinicCreate, auth: CurrentAuth, db: DbSession) -> ClinicRead:
    return service.create_clinic(db, auth, data)
```
Mount under `/api/v1` in `app/main.py`.

- [ ] **Step 3: Run, lint, commit**

Run: `make test` · `uv run ruff check .`
```bash
git add -A
git commit -m "feat: self-serve clinic creation (owner + settings + audit)"
```

---

### Task A6: Membership resolution + role guards + clinic read endpoints

**Files:**
- Create: `app/modules/members/deps.py`, `app/modules/members/schemas.py`, `app/modules/members/service.py`, `app/modules/members/router.py`
- Modify: `app/modules/clinics/router.py` (add `GET /clinics/{id}`), `app/main.py` (mount members router)
- Test: `tests/members/__init__.py`, `tests/members/test_authz.py`

**Interfaces:**
- Consumes: `CurrentUser`, `DbSession`, `ClinicMember`.
- Produces: `get_current_membership(clinic_id: UUID, user, db) -> ClinicMember` (raises 403 `forbidden` if the user has no active membership in that clinic — the clinic-boundary gate); `require_role(*roles: MemberRole)` → a dependency that asserts the membership role; `ForbiddenError(DomainError)` (403, `forbidden`). `GET /clinics/{clinic_id}` and `GET /clinics/{clinic_id}/members` (members only).

- [ ] **Step 1: Write the failing authz tests**

`tests/members/test_authz.py`:
```python
def _make_clinic(client, name="C"):
    return client.post("/api/v1/clinics", json={"name": name}).json()["id"]


def test_member_can_read_own_clinic(auth_client) -> None:
    client, _ = auth_client()
    cid = _make_clinic(client)
    assert client.get(f"/api/v1/clinics/{cid}").status_code == 200


def test_nonmember_cannot_read_other_clinic(auth_client) -> None:
    owner_client, _ = auth_client(sub="11111111-1111-1111-1111-111111111111")
    cid = _make_clinic(owner_client, "Owner's clinic")
    # A different authenticated user with no membership:
    other_client, _ = auth_client(sub="22222222-2222-2222-2222-222222222222")
    resp = other_client.get(f"/api/v1/clinics/{cid}")
    assert resp.status_code == 403
    assert resp.json()["error"]["code"] == "forbidden"
```
(Each `auth_client(sub=...)` shares the same `db_session`, so both see the same data; identities differ by `sub`.)

- [ ] **Step 2: Implement deps, service, schemas, router**

`app/modules/members/deps.py`:
```python
import uuid
from collections.abc import Callable
from typing import Annotated

from fastapi import Depends

from app.core.deps import DbSession
from app.core.errors import DomainError
from app.modules.auth.deps import CurrentUser
from app.modules.members.models import ClinicMember, MemberRole, MemberStatus
from sqlalchemy import select


class ForbiddenError(DomainError):
    status_code = 403
    code = "forbidden"


def get_current_membership(
    clinic_id: uuid.UUID, user: CurrentUser, db: DbSession
) -> ClinicMember:
    membership = db.execute(
        select(ClinicMember).where(
            ClinicMember.clinic_id == clinic_id,
            ClinicMember.user_id == user.id,
            ClinicMember.status == MemberStatus.active,
        )
    ).scalar_one_or_none()
    if membership is None:
        raise ForbiddenError("You are not a member of this clinic.")
    return membership


CurrentMembership = Annotated[ClinicMember, Depends(get_current_membership)]


def require_role(*roles: MemberRole) -> Callable[[ClinicMember], ClinicMember]:
    def _dep(membership: CurrentMembership) -> ClinicMember:
        if membership.role not in roles:
            raise ForbiddenError("Your role is not permitted to perform this action.")
        return membership

    return _dep
```

`app/modules/members/schemas.py`:
```python
import uuid

from pydantic import BaseModel, ConfigDict


class MemberRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    user_id: uuid.UUID
    role: str
    status: str
```

`app/modules/members/service.py`:
```python
import uuid

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.modules.members.models import ClinicMember


def list_members(db: Session, clinic_id: uuid.UUID) -> list[ClinicMember]:
    return list(
        db.execute(
            select(ClinicMember).where(ClinicMember.clinic_id == clinic_id)
        ).scalars().all()
    )
```

`app/modules/members/router.py`:
```python
import uuid

from fastapi import APIRouter

from app.core.deps import DbSession
from app.modules.members import service
from app.modules.members.deps import CurrentMembership
from app.modules.members.schemas import MemberRead

router = APIRouter(prefix="/clinics/{clinic_id}/members", tags=["members"])


@router.get("", response_model=list[MemberRead])
def list_members(clinic_id: uuid.UUID, membership: CurrentMembership, db: DbSession):
    # CurrentMembership enforces the caller belongs to {clinic_id}.
    return service.list_members(db, clinic_id)
```

Add to `app/modules/clinics/router.py`:
```python
import uuid

from app.modules.clinics.models import Clinic
from app.modules.members.deps import CurrentMembership


@router.get("/{clinic_id}", response_model=ClinicRead)
def get_clinic(clinic_id: uuid.UUID, membership: CurrentMembership, db: DbSession) -> ClinicRead:
    return db.get(Clinic, clinic_id)
```
Mount members router under `/api/v1`.

- [ ] **Step 3: Run, lint, commit**

Run: `make test` (authz isolation passes) · `uv run ruff check .`
```bash
git add -A
git commit -m "feat: membership resolution, role guards, clinic-boundary enforcement"
```

---

### Task A7: Invites — create / list / revoke / accept (single-use, atomic)

**Files:**
- Create: `app/modules/invites/schemas.py`, `app/modules/invites/service.py`, `app/modules/invites/router.py`
- Modify: `app/main.py` (mount invites router)
- Test: `tests/invites/__init__.py`, `tests/invites/test_invites.py`

**Interfaces:**
- Consumes: `CurrentAuth`, `CurrentMembership`, `require_role`, `ensure_user`, `record_audit`, models.
- Produces: `create_invite(db, clinic_id, role, created_by, ttl_hours=72) -> ClinicInvite`; `accept_invite(db, identity, token) -> ClinicMember` (atomic single-use; raises `InviteError` 400 for invalid/expired/revoked/used); `revoke_invite(db, clinic_id, invite_id) -> None`. Endpoints: `POST /clinics/{id}/invites {role}` (owner/practice_manager), `GET /clinics/{id}/invites`, `DELETE /clinics/{id}/invites/{invite_id}`, `POST /clinics/join {token}`.

- [ ] **Step 1: Write the failing tests**

`tests/invites/test_invites.py`:
```python
from sqlalchemy import select

from app.modules.invites.models import ClinicInvite, InviteStatus
from app.modules.members.models import ClinicMember, MemberRole


def _clinic(client):
    return client.post("/api/v1/clinics", json={"name": "C"}).json()["id"]


def test_invite_create_and_accept_grants_invite_role(auth_client, db_session) -> None:
    owner, _ = auth_client(sub="11111111-1111-1111-1111-111111111111")
    cid = _clinic(owner)
    inv = owner.post(f"/api/v1/clinics/{cid}/invites", json={"role": "doctor"})
    assert inv.status_code == 201
    token = inv.json()["token"]

    joiner, _ = auth_client(sub="22222222-2222-2222-2222-222222222222")
    resp = joiner.post("/api/v1/clinics/join", json={"token": token})
    assert resp.status_code == 200
    assert resp.json()["role"] == "doctor"

    # single-use: second redemption fails
    joiner2, _ = auth_client(sub="33333333-3333-3333-3333-333333333333")
    assert joiner2.post("/api/v1/clinics/join", json={"token": token}).status_code == 400


def test_accept_rejects_unknown_token(auth_client) -> None:
    joiner, _ = auth_client()
    assert joiner.post("/api/v1/clinics/join", json={"token": "nope"}).status_code == 400


def test_only_owner_or_pm_can_invite(auth_client) -> None:
    owner, _ = auth_client(sub="11111111-1111-1111-1111-111111111111")
    cid = _clinic(owner)
    token = owner.post(f"/api/v1/clinics/{cid}/invites", json={"role": "assistant"}).json()["token"]
    assistant, _ = auth_client(sub="44444444-4444-4444-4444-444444444444")
    assistant.post("/api/v1/clinics/join", json={"token": token})
    # assistant cannot create invites
    assert assistant.post(f"/api/v1/clinics/{cid}/invites", json={"role": "doctor"}).status_code == 403
```

- [ ] **Step 2: Implement service**

`app/modules/invites/service.py`:
```python
import datetime as dt
import secrets
import uuid

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.errors import DomainError
from app.modules.audit.service import record_audit
from app.modules.auth.service import ensure_user
from app.modules.auth.tokens import AuthIdentity
from app.modules.invites.models import ClinicInvite, InviteStatus
from app.modules.members.models import ClinicMember, MemberRole, MemberStatus


class InviteError(DomainError):
    status_code = 400
    code = "invalid_invite"


def create_invite(
    db: Session, *, clinic_id: uuid.UUID, role: MemberRole,
    created_by: uuid.UUID, ttl_hours: int = 72,
) -> ClinicInvite:
    expires_at = dt.datetime.now(tz=dt.timezone.utc) + dt.timedelta(hours=ttl_hours)
    invite = ClinicInvite(
        clinic_id=clinic_id, role=role, token=secrets.token_urlsafe(32),
        created_by=created_by, status=InviteStatus.pending, expires_at=expires_at,
    )
    db.add(invite)
    db.flush()
    record_audit(db, action="clinic_invite.created", entity_type="clinic_invite",
                 entity_id=invite.id, clinic_id=clinic_id, actor_user_id=created_by,
                 new={"role": role.value})
    db.commit()
    db.refresh(invite)
    return invite


def accept_invite(db: Session, identity: AuthIdentity, token: str) -> ClinicMember:
    invite = db.execute(
        select(ClinicInvite).where(ClinicInvite.token == token).with_for_update()
    ).scalar_one_or_none()
    if invite is None or invite.status != InviteStatus.pending:
        raise InviteError("Invite is invalid or already used.")
    if invite.expires_at < dt.datetime.now(tz=dt.timezone.utc):
        invite.status = InviteStatus.expired
        db.commit()
        raise InviteError("Invite has expired.")

    user = ensure_user(db, identity)
    member = ClinicMember(
        clinic_id=invite.clinic_id, user_id=user.id, role=invite.role,
        status=MemberStatus.active, created_by=invite.created_by,
    )
    db.add(member)
    invite.status = InviteStatus.accepted
    invite.accepted_by = user.id
    invite.accepted_at = dt.datetime.now(tz=dt.timezone.utc)
    db.flush()
    record_audit(db, action="clinic_member.created", entity_type="clinic_member",
                 entity_id=member.id, clinic_id=invite.clinic_id, actor_user_id=user.id,
                 new={"role": invite.role.value, "via": "invite"})
    record_audit(db, action="clinic_invite.accepted", entity_type="clinic_invite",
                 entity_id=invite.id, clinic_id=invite.clinic_id, actor_user_id=user.id)
    db.commit()
    db.refresh(member)
    return member


def list_invites(db: Session, clinic_id: uuid.UUID) -> list[ClinicInvite]:
    return list(db.execute(
        select(ClinicInvite).where(ClinicInvite.clinic_id == clinic_id)
    ).scalars().all())


def revoke_invite(db: Session, *, clinic_id: uuid.UUID, invite_id: uuid.UUID,
                  actor_user_id: uuid.UUID) -> None:
    invite = db.get(ClinicInvite, invite_id)
    if invite is None or invite.clinic_id != clinic_id:
        raise InviteError("Invite not found.")
    invite.status = InviteStatus.revoked
    record_audit(db, action="clinic_invite.revoked", entity_type="clinic_invite",
                 entity_id=invite.id, clinic_id=clinic_id, actor_user_id=actor_user_id)
    db.commit()
```
> `with_for_update()` row-locks the invite so two concurrent redemptions can't both succeed (single-use atomicity; needs Postgres — that's why tests run on Postgres, not SQLite).

- [ ] **Step 3: Implement schemas + router**

`app/modules/invites/schemas.py`:
```python
import datetime as dt
import uuid

from pydantic import BaseModel, ConfigDict

from app.modules.members.models import MemberRole


class InviteCreate(BaseModel):
    role: MemberRole


class InviteRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    role: str
    token: str
    status: str
    expires_at: dt.datetime


class JoinRequest(BaseModel):
    token: str


class JoinResult(BaseModel):
    clinic_id: uuid.UUID
    role: str
```

`app/modules/invites/router.py`:
```python
import uuid

from fastapi import APIRouter, Depends, status

from app.core.deps import DbSession
from app.modules.auth.deps import CurrentAuth
from app.modules.invites import service
from app.modules.invites.schemas import InviteCreate, InviteRead, JoinRequest, JoinResult
from app.modules.members.deps import CurrentMembership, require_role
from app.modules.members.models import MemberRole

router = APIRouter(prefix="/clinics", tags=["invites"])
_can_invite = require_role(MemberRole.owner, MemberRole.practice_manager)


@router.post("/{clinic_id}/invites", response_model=InviteRead,
             status_code=status.HTTP_201_CREATED)
def create_invite(clinic_id: uuid.UUID, data: InviteCreate, db: DbSession,
                  membership=Depends(_can_invite)) -> InviteRead:
    if data.role == MemberRole.owner:
        from app.modules.invites.service import InviteError
        raise InviteError("Cannot invite as owner.")
    return service.create_invite(db, clinic_id=clinic_id, role=data.role,
                                 created_by=membership.user_id)


@router.get("/{clinic_id}/invites", response_model=list[InviteRead])
def list_invites(clinic_id: uuid.UUID, db: DbSession,
                 membership=Depends(_can_invite)):
    return service.list_invites(db, clinic_id)


@router.delete("/{clinic_id}/invites/{invite_id}", status_code=status.HTTP_204_NO_CONTENT)
def revoke_invite(clinic_id: uuid.UUID, invite_id: uuid.UUID, db: DbSession,
                  membership=Depends(_can_invite)) -> None:
    service.revoke_invite(db, clinic_id=clinic_id, invite_id=invite_id,
                          actor_user_id=membership.user_id)


@router.post("/join", response_model=JoinResult)
def join(data: JoinRequest, auth: CurrentAuth, db: DbSession) -> JoinResult:
    member = service.accept_invite(db, auth, data.token)
    return JoinResult(clinic_id=member.clinic_id, role=member.role.value)
```
Mount under `/api/v1`. (Mount order doesn't matter; `/clinics/join` and `/clinics/{clinic_id}/invites` don't collide since `join` is a fixed segment — but ensure the `join` route is registered; FastAPI matches `/clinics/join` to the literal route, not `/{clinic_id}`. Verify in tests.)

- [ ] **Step 4: Run, lint, commit**

Run: `make test` (invite create/accept/single-use/expired/role-guard all pass) · `uv run ruff check .`
```bash
git add -A
git commit -m "feat: clinic invites (create/list/revoke) and invite-accept join (single-use, atomic)"
```

---

### Task A8: Member management + clinic settings

**Files:**
- Modify: `app/modules/members/{schemas,service,router}.py` (PATCH member), `app/modules/clinics/{schemas,service,router}.py` (settings GET/PATCH)
- Test: `tests/members/test_manage.py`, `tests/clinics/test_settings.py`

**Interfaces:**
- Produces: `PATCH /clinics/{id}/members/{member_id} {role?, status?}` (owner only) + audit `clinic_member.role_changed`/`status_changed`; `GET|PATCH /clinics/{id}/settings` (owner/practice_manager) + audit `clinic_settings.updated`. `update_member`, `get_settings`, `update_settings` services.

- [ ] **Step 1: Write failing tests**

`tests/clinics/test_settings.py`:
```python
def _clinic(client):
    return client.post("/api/v1/clinics", json={"name": "C"}).json()["id"]


def test_owner_can_read_and_update_settings(auth_client) -> None:
    owner, _ = auth_client()
    cid = _clinic(owner)
    assert owner.get(f"/api/v1/clinics/{cid}/settings").status_code == 200
    resp = owner.patch(f"/api/v1/clinics/{cid}/settings",
                       json={"allow_multiple_bookings_per_slot": True})
    assert resp.status_code == 200
    assert resp.json()["allow_multiple_bookings_per_slot"] is True


def test_doctor_cannot_update_settings(auth_client) -> None:
    owner, _ = auth_client(sub="11111111-1111-1111-1111-111111111111")
    cid = _clinic(owner)
    token = owner.post(f"/api/v1/clinics/{cid}/invites", json={"role": "doctor"}).json()["token"]
    doctor, _ = auth_client(sub="22222222-2222-2222-2222-222222222222")
    doctor.post("/api/v1/clinics/join", json={"token": token})
    assert doctor.patch(f"/api/v1/clinics/{cid}/settings",
                        json={"reminders_enabled": False}).status_code == 403
```

`tests/members/test_manage.py`:
```python
def _clinic(client):
    return client.post("/api/v1/clinics", json={"name": "C"}).json()["id"]


def test_owner_can_deactivate_member(auth_client, db_session) -> None:
    owner, _ = auth_client(sub="11111111-1111-1111-1111-111111111111")
    cid = _clinic(owner)
    token = owner.post(f"/api/v1/clinics/{cid}/invites", json={"role": "assistant"}).json()["token"]
    assistant, _ = auth_client(sub="22222222-2222-2222-2222-222222222222")
    assistant.post("/api/v1/clinics/join", json={"token": token})
    members = owner.get(f"/api/v1/clinics/{cid}/members").json()
    target = next(m for m in members if m["role"] == "assistant")
    resp = owner.patch(f"/api/v1/clinics/{cid}/members/{target['id']}",
                       json={"status": "inactive"})
    assert resp.status_code == 200
    assert resp.json()["status"] == "inactive"
```

- [ ] **Step 2: Implement settings (clinics module)**

Add to `app/modules/clinics/schemas.py`:
```python
class ClinicSettingsRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    allow_multiple_bookings_per_slot: bool
    max_bookings_per_slot: int
    default_slot_size_minutes: int
    appointment_request_expiry_minutes: int
    post_confirmation_hook_delay_minutes: int
    reminders_enabled: bool
    whatsapp_enabled: bool
    google_calendar_enabled: bool


class ClinicSettingsUpdate(BaseModel):
    allow_multiple_bookings_per_slot: bool | None = None
    max_bookings_per_slot: int | None = None
    default_slot_size_minutes: int | None = None
    appointment_request_expiry_minutes: int | None = None
    post_confirmation_hook_delay_minutes: int | None = None
    reminders_enabled: bool | None = None
    whatsapp_enabled: bool | None = None
    google_calendar_enabled: bool | None = None
```
Add to `app/modules/clinics/service.py`:
```python
import uuid

from sqlalchemy import select

from app.modules.clinics.models import ClinicSettings
from app.modules.clinics.schemas import ClinicSettingsUpdate


def get_settings(db: Session, clinic_id: uuid.UUID) -> ClinicSettings:
    return db.execute(
        select(ClinicSettings).where(ClinicSettings.clinic_id == clinic_id)
    ).scalar_one()


def update_settings(db: Session, clinic_id: uuid.UUID, data: ClinicSettingsUpdate,
                    actor_user_id: uuid.UUID) -> ClinicSettings:
    settings_row = get_settings(db, clinic_id)
    changes = data.model_dump(exclude_unset=True)
    previous = {k: getattr(settings_row, k) for k in changes}
    for k, v in changes.items():
        setattr(settings_row, k, v)
    db.flush()
    record_audit(db, action="clinic_settings.updated", entity_type="clinic_settings",
                 entity_id=settings_row.id, clinic_id=clinic_id,
                 actor_user_id=actor_user_id, previous=previous, new=changes)
    db.commit()
    db.refresh(settings_row)
    return settings_row
```
Add settings routes to `app/modules/clinics/router.py` guarded by `require_role(owner, practice_manager)`:
```python
from app.modules.clinics.schemas import ClinicSettingsRead, ClinicSettingsUpdate
from app.modules.members.deps import require_role
from app.modules.members.models import MemberRole
from fastapi import Depends

_settings_admin = require_role(MemberRole.owner, MemberRole.practice_manager)


@router.get("/{clinic_id}/settings", response_model=ClinicSettingsRead)
def get_settings(clinic_id: uuid.UUID, db: DbSession, membership=Depends(_settings_admin)):
    return service.get_settings(db, clinic_id)


@router.patch("/{clinic_id}/settings", response_model=ClinicSettingsRead)
def update_settings(clinic_id: uuid.UUID, data: ClinicSettingsUpdate, db: DbSession,
                    membership=Depends(_settings_admin)):
    return service.update_settings(db, clinic_id, data, membership.user_id)
```

- [ ] **Step 3: Implement member PATCH (members module, owner-only)**

Add to `app/modules/members/schemas.py`:
```python
from app.modules.members.models import MemberRole, MemberStatus


class MemberUpdate(BaseModel):
    role: MemberRole | None = None
    status: MemberStatus | None = None
```
Add to `app/modules/members/service.py`:
```python
from app.core.errors import DomainError
from app.modules.audit.service import record_audit
from app.modules.members.schemas import MemberUpdate


class MemberError(DomainError):
    status_code = 400
    code = "invalid_member_update"


def update_member(db: Session, clinic_id: uuid.UUID, member_id: uuid.UUID,
                  data: MemberUpdate, actor_user_id: uuid.UUID) -> ClinicMember:
    member = db.get(ClinicMember, member_id)
    if member is None or member.clinic_id != clinic_id:
        raise MemberError("Member not found.")
    changes = data.model_dump(exclude_unset=True)
    if "role" in changes:
        prev = member.role.value
        member.role = changes["role"]
        record_audit(db, action="clinic_member.role_changed", entity_type="clinic_member",
                     entity_id=member.id, clinic_id=clinic_id, actor_user_id=actor_user_id,
                     previous={"role": prev}, new={"role": member.role.value})
    if "status" in changes:
        prev = member.status.value
        member.status = changes["status"]
        record_audit(db, action="clinic_member.status_changed", entity_type="clinic_member",
                     entity_id=member.id, clinic_id=clinic_id, actor_user_id=actor_user_id,
                     previous={"status": prev}, new={"status": member.status.value})
    db.commit()
    db.refresh(member)
    return member
```
Add to `app/modules/members/router.py` (owner-only):
```python
from fastapi import Depends

from app.modules.members.deps import require_role
from app.modules.members.models import MemberRole
from app.modules.members.schemas import MemberUpdate

_owner_only = require_role(MemberRole.owner)


@router.patch("/{member_id}", response_model=MemberRead)
def update_member(clinic_id: uuid.UUID, member_id: uuid.UUID, data: MemberUpdate,
                  db: DbSession, membership=Depends(_owner_only)) -> MemberRead:
    return service.update_member(db, clinic_id, member_id, data, membership.user_id)
```

- [ ] **Step 4: Run, lint, commit**

Run: `make test` · `uv run ruff check .`
```bash
git add -A
git commit -m "feat: clinic settings GET/PATCH and member role/status management with audit"
```

---

### Task A9: RLS migration + advisors + CLAUDE.md update

**Files:**
- Create: `alembic/versions/0003_enable_rls.py`
- Modify: `CLAUDE.md` (auth/tenancy conventions)
- Test: `tests/test_rls.py` (asserts RLS is enabled on the new tables)

**Interfaces:** none (DB hardening + docs).

- [ ] **Step 1: Write the failing RLS test**

`tests/test_rls.py`:
```python
from sqlalchemy import text


def test_rls_enabled_on_app_tables(db_session) -> None:
    tables = [
        "clinic_beta", "clinic_settings_beta", "app_user_beta",
        "clinic_member_beta", "clinic_invite_beta", "audit_event_beta",
    ]
    rows = db_session.execute(text(
        "select relname, relrowsecurity from pg_class "
        "where relname = any(:names)"
    ), {"names": tables}).all()
    by_name = {r[0]: r[1] for r in rows}
    for t in tables:
        assert by_name.get(t) is True, f"RLS not enabled on {t}"
```

- [ ] **Step 2: Create the RLS migration**

`alembic/versions/0003_enable_rls.py` — `upgrade()` runs, for each of the six tables:
```python
op.execute("ALTER TABLE clinic_beta ENABLE ROW LEVEL SECURITY")
```
(…repeat for all six). No policies and no `anon`/`authenticated` GRANTs are added — the tables are not exposed to the Data API; FastAPI uses the privileged connection. `downgrade()` runs `DISABLE ROW LEVEL SECURITY` for each.

- [ ] **Step 3: Apply + test**

Run: `make migrate` then `make test` → `test_rls` passes (the test DB is built by migrations, so RLS flags are present).

- [ ] **Step 4: Update CLAUDE.md**

Add an "Auth & tenancy" section to the backend `CLAUDE.md`: Supabase Auth (phone-OTP/email-pw) → JWT validated by FastAPI via JWKS (ES256); `app_user.auth_user_id` is a soft UUID ref to `auth.users`; clinic boundary via `clinic_member`; the dep chain `current_auth → current_user → current_membership → require_role`; audit in-transaction; `_beta` tables; RLS on + not exposed to the Data API; tests mock Supabase with a test keypair.

- [ ] **Step 5: Lint and commit**

```bash
uv run ruff check .
git add -A
git commit -m "feat: enable RLS on auth/clinic tables; document auth conventions"
```

---

### Task A10: Apply to Supabase + backend CI sanity + open PR

**Files:** none (ops + integration); the backend CI from the skeleton already runs ruff + migrations + pytest.

- [ ] **Step 1: Confirm full suite green locally**

Run: `make test` (all auth/clinic/member/invite/settings/RLS tests pass, pristine) and `uv run ruff check .`.

- [ ] **Step 2: Apply migrations to the Supabase project**

Point a throwaway shell env at Supabase and run migrations there so the real schema exists:
```bash
DATABASE_URL="<supabase pooled connection string>" uv run alembic upgrade head
```
(The connection string is obtained from the Supabase dashboard / project settings; do NOT commit it. Alternatively, an operator applies the same SQL via the Supabase MCP `apply_migration`.) Then verify with the Supabase MCP `list_tables` that the six `*_beta` tables exist with RLS enabled, and run `get_advisors` (security) — resolve any findings (e.g., confirm no unintended `anon`/`authenticated` exposure).

- [ ] **Step 3: Push, open PR**

```bash
git push -u origin sp1-auth-backend
gh-personal pr create --title "SP1 backend: auth + clinic workspace" \
  --body "Implements Phase A of docs/plans/2026-06-17-auth-clinic-workspace-plan.md: Supabase JWT (ES256/JWKS) validation, app_user/clinic/clinic_settings/clinic_member/clinic_invite/audit_event, self-serve clinic creation, role-specific single-use invites, clinic-boundary + role authz, minimal in-transaction audit, RLS. Tests mock Supabase. Tracks Dentist-Register-System/dentail-register-docs#7"
```

---

# Phase B — Frontend (`dentist-registry-frontend`)

> Branch: `git switch -c sp1-auth-frontend` in the frontend repo before Task B1.
> Phase B assumes the SP1 backend runs locally on `:8000` for the e2e.

### Task B1: Supabase client + auth session + Bearer-attaching API client

**Files:**
- Create: `src/lib/supabase.ts`, `src/features/auth/session.ts` (hook), `.env.local.example` (add Supabase vars)
- Modify: `src/lib/env.ts` (add Supabase URL + publishable key), `src/lib/api-client.ts` (attach Bearer token), `src/app/providers.tsx` (auth/session context if needed)
- Install: `@supabase/supabase-js`
- Test: built + typechecked (e2e covers behavior in B4)

**Interfaces:**
- Produces: `supabase` browser client; `useSession()` (current Supabase session/JWT); `apiFetch` attaches `Authorization: Bearer <access_token>` when a session exists.

- [ ] **Step 1: Install + env**

```bash
npm install @supabase/supabase-js
```
Extend `src/lib/env.ts`:
```typescript
import { z } from "zod";

const schema = z.object({
  NEXT_PUBLIC_API_BASE_URL: z.string().url(),
  NEXT_PUBLIC_SUPABASE_URL: z.string().url(),
  NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY: z.string().min(1),
});

export const env = schema.parse({
  NEXT_PUBLIC_API_BASE_URL: process.env.NEXT_PUBLIC_API_BASE_URL,
  NEXT_PUBLIC_SUPABASE_URL: process.env.NEXT_PUBLIC_SUPABASE_URL,
  NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY: process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY,
});
```
`.env.local.example`:
```
NEXT_PUBLIC_API_BASE_URL=http://localhost:8000
NEXT_PUBLIC_SUPABASE_URL=https://wxwasnshmnttiixvzeod.supabase.co
NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY=sb_publishable_xxx
```
(Obtain the publishable key from the Supabase dashboard / MCP `get_publishable_keys`. Never commit the real value — only the example placeholder.)

- [ ] **Step 2: Supabase client**

`src/lib/supabase.ts`:
```typescript
import { createClient } from "@supabase/supabase-js";

import { env } from "@/lib/env";

export const supabase = createClient(
  env.NEXT_PUBLIC_SUPABASE_URL,
  env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY,
);
```

- [ ] **Step 3: Attach the Bearer token in api-client**

In `src/lib/api-client.ts`, before the fetch, read the session and add the header:
```typescript
import { supabase } from "@/lib/supabase";
// ...
export async function apiFetch<T>(path: string, init?: RequestInit): Promise<T> {
  const { data } = await supabase.auth.getSession();
  const token = data.session?.access_token;
  const res = await fetch(`${env.NEXT_PUBLIC_API_BASE_URL}${path}`, {
    headers: {
      "Content-Type": "application/json",
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
      ...(init?.headers ?? {}),
    },
    ...init,
  });
  // ... existing error-envelope handling unchanged
}
```

- [ ] **Step 4: Session hook + verify build**

`src/features/auth/session.ts`:
```typescript
"use client";

import { useEffect, useState } from "react";
import type { Session } from "@supabase/supabase-js";

import { supabase } from "@/lib/supabase";

export function useSession() {
  const [session, setSession] = useState<Session | null>(null);
  const [loading, setLoading] = useState(true);
  useEffect(() => {
    supabase.auth.getSession().then(({ data }) => {
      setSession(data.session);
      setLoading(false);
    });
    const { data: sub } = supabase.auth.onAuthStateChange((_e, s) => setSession(s));
    return () => sub.subscription.unsubscribe();
  }, []);
  return { session, loading };
}
```
Run: `cp .env.local.example .env.local && npm run build` (set a placeholder publishable key so env parses) → succeeds.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: add supabase-js client, session hook, and Bearer-attaching api-client"
```

---

### Task B2: Login screen (phone-OTP + email/password)

**Files:**
- Create: `src/features/auth/login-form.tsx`, `src/app/login/page.tsx`
- Test: build/typecheck (e2e in B4)

**Interfaces:**
- Produces: a `/login` route with phone-OTP (request code → verify) and email/password tabs, using `supabase.auth.signInWithOtp`, `verifyOtp`, `signInWithPassword`.

- [ ] **Step 1: Login form**

`src/features/auth/login-form.tsx` — two modes. Phone: `await supabase.auth.signInWithOtp({ phone })` then a second step `await supabase.auth.verifyOtp({ phone, token, type: "sms" })`. Email: `await supabase.auth.signInWithPassword({ email, password })`. On success, redirect to `/` (router.push). Use shadcn `Input`/`Button`/`Tabs` (run `npx shadcn@latest add tabs` if not present) + RHF + Zod, with error display from the returned Supabase `error.message`.

`src/app/login/page.tsx`:
```tsx
import { LoginForm } from "@/features/auth/login-form";

export default function LoginPage() {
  return (
    <main className="mx-auto max-w-md p-8">
      <h1 className="mb-4 text-2xl font-semibold">Sign in</h1>
      <LoginForm />
    </main>
  );
}
```

- [ ] **Step 2: Verify build + commit**

Run: `npm run build`
```bash
git add -A
git commit -m "feat: add login screen (phone-OTP + email/password)"
```

---

### Task B3: Onboarding (invite vs create) + authed shell + route guard

**Files:**
- Create: `src/features/auth/onboarding.tsx`, `src/features/clinic/api.ts`, `src/features/clinic/hooks.ts`, `src/components/auth-gate.tsx`
- Modify: `src/app/page.tsx` (authed shell: show clinic + role, or onboarding, or redirect to login)
- Test: build/typecheck (e2e in B4)

**Interfaces:**
- Produces: `useMe()` (GET /me), `useCreateClinic()`, `useJoinClinic()`; an `AuthGate` that redirects unauthenticated users to `/login`; an onboarding component (paste invite OR create clinic); a home shell that renders the current clinic + role.

- [ ] **Step 1: Clinic API + hooks**

`src/features/clinic/api.ts`:
```typescript
import { apiFetch } from "@/lib/api-client";

export type Membership = { clinic_id: string; clinic_name: string; role: string; status: string };
export type Me = {
  user_id: string | null; email: string | null; phone: string | null;
  needs_onboarding: boolean; memberships: Membership[];
};

export const fetchMe = () => apiFetch<Me>("/api/v1/me");
export const createClinic = (name: string) =>
  apiFetch<{ id: string; name: string }>("/api/v1/clinics", {
    method: "POST", body: JSON.stringify({ name }),
  });
export const joinClinic = (token: string) =>
  apiFetch<{ clinic_id: string; role: string }>("/api/v1/clinics/join", {
    method: "POST", body: JSON.stringify({ token }),
  });
```
`src/features/clinic/hooks.ts`: `useMe` (useQuery `["me"]`), `useCreateClinic`/`useJoinClinic` (useMutation → invalidate `["me"]`).

- [ ] **Step 2: AuthGate + onboarding + shell**

`AuthGate`: uses `useSession()`; while loading shows nothing; if no session → `router.replace("/login")`; else renders children. Home `page.tsx` wraps content in `AuthGate`, calls `useMe()`: if `needs_onboarding` → render `<Onboarding/>` (a toggle: "I have an invite" → paste token → `useJoinClinic`; "Create a new clinic" → name → `useCreateClinic`; both invalidate `["me"]`). Otherwise render the shell: "Clinic: {memberships[0].clinic_name} — role: {memberships[0].role}".

- [ ] **Step 3: Verify build + commit**

Run: `npm run build`
```bash
git add -A
git commit -m "feat: onboarding (invite/create), auth gate, and authed clinic shell"
```

---

### Task B4: Playwright e2e (Supabase mocked) + CI + CLAUDE.md + PR

**Files:**
- Create: `tests/e2e/auth.spec.ts`
- Modify: `tests/e2e/` (remove the old `ping.spec.ts`), `CLAUDE.md`, frontend `.github/workflows/ci.yml` if env needs the Supabase vars for build
- Test: the e2e itself

**Interfaces:** none (verification + meta).

- [ ] **Step 1: Remove the ping e2e; write the auth e2e**

```bash
git rm tests/e2e/ping.spec.ts
```
`tests/e2e/auth.spec.ts` — **mock Supabase Auth** so no real OTP/SMS is needed: use Playwright route interception to stub `**/auth/v1/**` Supabase endpoints (return a fake session with a signed-looking access token) OR inject a session via `page.addInitScript` setting the supabase-js localStorage session key, then stub the backend `/api/v1/me`, `/api/v1/clinics`, `/api/v1/clinics/join` via `page.route`. The happy path: load `/` with a mocked session + `needs_onboarding: true` → choose "Create a new clinic" → fill name → submit → assert the shell shows the clinic name + "owner". (Because the backend's real JWT verification can't accept a fake token, the e2e stubs the FastAPI responses; full real-token integration is the manual smoke test in Step 4.)

- [ ] **Step 2: Update frontend CI**

Ensure `.github/workflows/ci.yml`'s `npm run build` step has the Supabase env vars set (placeholders) so `env.ts` parses at build:
```yaml
        env:
          NEXT_PUBLIC_API_BASE_URL: http://localhost:8000
          NEXT_PUBLIC_SUPABASE_URL: https://example.supabase.co
          NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY: sb_publishable_ci
```

- [ ] **Step 3: Run e2e + build**

Run: `cp .env.local.example .env.local && npm run build && npm run test:e2e` → the mocked auth happy-path passes.

- [ ] **Step 4: Update CLAUDE.md, manual smoke, commit, PR**

Add an "Auth" section to the frontend `CLAUDE.md`: supabase-js login (phone-OTP/email-pw), session via `useSession`, api-client attaches the Bearer JWT, onboarding (invite/create), AuthGate. Note the **manual smoke test**: with the backend pointed at Supabase (`DATABASE_URL` → Supabase) and real Supabase Auth, log in with a real account and create a clinic end-to-end (real JWT verified by the backend).
```bash
git add -A
git commit -m "chore: add auth e2e (Supabase mocked), CI env, and CLAUDE.md"
git push -u origin sp1-auth-frontend
gh-personal pr create --title "SP1 frontend: auth + clinic workspace" \
  --body "Implements Phase B of docs/plans/2026-06-17-auth-clinic-workspace-plan.md: supabase-js login (phone-OTP/email-pw), Bearer-attaching api-client, onboarding (invite/create), auth gate + clinic shell, Playwright happy-path with Supabase mocked. Tracks Dentist-Register-System/dentail-register-docs#7"
```

---

## Final Acceptance (both PRs merged)

Verify against spec §15:
1. Sign up via phone-OTP and email/password; FastAPI validates the JWT (ES256/JWKS). ✔ A2, B1–B2 (+ manual smoke)
2. No-invite user creates a clinic and becomes `owner`; `clinic_settings` defaults created. ✔ A5
3. Authorized member creates a role-specific invite; redeemed once → that role; second redemption fails; expired/revoked rejected. ✔ A7
4. `GET /me` reports user, memberships, onboarding status. ✔ A4
5. Cross-clinic access denied; role guards enforce settings/member restrictions. ✔ A6, A8
6. Every mutating action writes the expected append-only `audit_event` in the same transaction. ✔ A3, A5, A7, A8
7. Frontend supports login + onboarding (invite/create) → authed shell with clinic + role. ✔ B2–B3
8. RLS enabled on all new tables; none exposed to the Data API; advisors clean. ✔ A9, A10
9. Backend + frontend tests pass (authz isolation, invite edge cases, audit); CI green. ✔ all
10. Throwaway `ping` slice removed. ✔ A1, B4
