# Walking Skeleton Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Scaffold the FastAPI backend and Next.js frontend, prove the full stack end-to-end with one throwaway `ping_beta` vertical slice, and lock in the conventions every future feature will copy.

**Architecture:** Two separate repos. Backend is a feature-first modular monolith (FastAPI + SQLAlchemy 2.x sync + Alembic) talking to a local Postgres (Docker). Frontend is Next.js (App Router) calling the backend over REST via a typed client (TanStack Query + RHF + Zod + shadcn/ui). The slice is deleted once real features begin; its value is the proven plumbing.

**Tech Stack:** Backend — Python 3.12, FastAPI, SQLAlchemy 2.x (sync), Alembic, Pydantic v2, pydantic-settings, psycopg 3, pytest, ruff, uv. Frontend — Next.js (App Router) + TypeScript, TanStack Query, React Hook Form, Zod, shadcn/ui, Tailwind, Playwright.

**Spec:** `docs/specs/2026-06-17-walking-skeleton-design.md` (approved, merged in PR #4).

## Global Constraints

Every task's requirements implicitly include these (copied from the spec):

- **Repos & working dirs:** backend tasks run in `~/Documents/register_workspace/dentist-registry-backend`; frontend tasks in `~/Documents/register_workspace/dentist-registry-frontend`.
- **Git workflow:** never push to `main` directly; each repo gets a feature branch → PR → review → merge via `gh-personal` (remote `github-personal`, commit email `rohan2jos@gmail.com`).
- **Backend layout:** feature-first modular monolith. One-way imports: `core/ ← modules/ ← main.py`. Cross-module calls only via a module's `service`. No circular imports (string-based SQLAlchemy refs). Single Alembic model registry in `app/db/base.py`. Routers are thin.
- **DB conventions:** UUID primary keys; timezone-aware timestamps (`TIMESTAMP WITH TIME ZONE`); `MetaData` naming convention set once on `Base`.
- **API:** all app routes under `/api/v1`. Uniform error envelope `{ "error": { "code", "message", "details" } }` via FastAPI exception handlers.
- **Sync SQLAlchemy** only (no async).
- **Tests run against Postgres**, never SQLite.
- **Beta naming:** throwaway table is `ping_beta` (Golden Rule 4.5).
- **Dependencies:** permissive OSS only (MIT/Apache/BSD/ISC). Committed lockfiles (`uv.lock`, `package-lock.json`).
- **Secrets:** never commit real secrets; `.env.example` / `.env.local.example` only.

---

# Phase A — Backend (`dentist-registry-backend`)

> Branch: `git switch -c skeleton-backend` in the backend repo before Task 1.

### Task 1: Project scaffold + liveness health endpoint

**Files:**
- Create: `pyproject.toml`, `.python-version`, `.gitignore`, `Makefile`, `.env.example`
- Create: `app/__init__.py`, `app/main.py`, `app/core/__init__.py`, `app/core/config.py`, `app/core/logging.py`, `app/health.py`
- Test: `tests/__init__.py`, `tests/conftest.py`, `tests/test_health.py`

**Interfaces:**
- Produces: `app.main:create_app() -> FastAPI` and module-level `app`; `app.core.config.settings` (a `Settings` instance with `database_url: str`, `test_database_url: str`, `cors_origins: list[str]`, `environment: str`); `app.core.logging.configure_logging() -> None`.

- [ ] **Step 1: Create project metadata files**

`pyproject.toml`:
```toml
[project]
name = "dentist-registry-backend"
version = "0.1.0"
requires-python = ">=3.12"
dependencies = [
    "fastapi>=0.115",
    "uvicorn[standard]>=0.32",
    "sqlalchemy>=2.0",
    "alembic>=1.14",
    "pydantic>=2.9",
    "pydantic-settings>=2.6",
    "psycopg[binary]>=3.2",
]

[dependency-groups]
dev = ["pytest>=8.3", "httpx>=0.27", "ruff>=0.8"]

[tool.ruff]
line-length = 100
target-version = "py312"

[tool.ruff.lint]
select = ["E", "F", "I", "TID"]

[tool.ruff.lint.flake8-tidy-imports]
ban-relative-imports = "all"

[tool.pytest.ini_options]
testpaths = ["tests"]
```

`.python-version`:
```
3.12
```

`.gitignore`:
```
.venv/
__pycache__/
*.pyc
.env
.pytest_cache/
.ruff_cache/
```

`Makefile`:
```makefile
install:
	uv sync

run:
	uv run uvicorn app.main:app --reload --port 8000

migrate:
	uv run alembic upgrade head

testdb:
	uv run python -c "import psycopg; psycopg.connect('postgresql://register:register@localhost:5432/postgres', autocommit=True).execute('CREATE DATABASE register_test')" 2>/dev/null || true

test: testdb
	uv run pytest

lint:
	uv run ruff check .
```

> The `testdb` target creates a **dedicated** `register_test` database (idempotent — ignores
> "already exists"). Tests never touch the dev `register` database, so the schema
> create/drop in the test fixtures can't harm dev data.

`.env.example`:
```
DATABASE_URL=postgresql+psycopg://register:register@localhost:5432/register
TEST_DATABASE_URL=postgresql+psycopg://register:register@localhost:5432/register_test
CORS_ORIGINS=["http://localhost:3000"]
ENVIRONMENT=local
```

- [ ] **Step 2: Initialize the environment**

Run: `uv sync`
Expected: creates `.venv` and `uv.lock`.

- [ ] **Step 3: Write the failing test**

`tests/__init__.py`: (empty)

`tests/conftest.py`:
```python
import pytest
from fastapi.testclient import TestClient

from app.main import create_app


@pytest.fixture
def client() -> TestClient:
    return TestClient(create_app())
```

`tests/test_health.py`:
```python
from fastapi.testclient import TestClient


def test_health_returns_ok(client: TestClient) -> None:
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}
```

- [ ] **Step 4: Run test to verify it fails**

Run: `uv run pytest tests/test_health.py -v`
Expected: FAIL — `ModuleNotFoundError: No module named 'app.main'`.

- [ ] **Step 5: Implement config, health router, and app factory**

`app/__init__.py`, `app/core/__init__.py`: (empty)

`app/core/config.py`:
```python
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    database_url: str = "postgresql+psycopg://register:register@localhost:5432/register"
    test_database_url: str = "postgresql+psycopg://register:register@localhost:5432/register_test"
    cors_origins: list[str] = ["http://localhost:3000"]
    environment: str = "local"


settings = Settings()
```

`app/health.py`:
```python
from fastapi import APIRouter

router = APIRouter(tags=["health"])


@router.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}
```

`app/core/logging.py`:
```python
import logging


def configure_logging() -> None:
    # Minimal structured-ish logging. Do NOT log patient PII (Golden Rule 11.1):
    # prefer IDs and structured metadata over names/phones/complaint/message bodies.
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s %(name)s %(message)s",
    )
```

`app/main.py`:
```python
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.core.config import settings
from app.core.logging import configure_logging
from app.health import router as health_router


def create_app() -> FastAPI:
    configure_logging()
    app = FastAPI(title="Dentist Registry API")
    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.cors_origins,
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )
    app.include_router(health_router)
    return app


app = create_app()
```

- [ ] **Step 6: Run test to verify it passes**

Run: `uv run pytest tests/test_health.py -v`
Expected: PASS.

- [ ] **Step 7: Lint and commit**

Run: `uv run ruff check .` (expected: no errors)
```bash
git add -A
git commit -m "feat: scaffold backend with liveness health endpoint"
```

---

### Task 2: Database foundation + DB health check

**Files:**
- Create: `docker-compose.yml`, `app/core/base.py`, `app/core/database.py`, `app/core/deps.py`, `app/db/__init__.py`, `app/db/base.py`
- Create (via `alembic init`): `alembic.ini`, `alembic/env.py`, `alembic/script.py.mako`, `alembic/versions/`
- Modify: `app/health.py` (add `/health/db`), `tests/conftest.py` (DB fixtures)
- Test: `tests/test_health.py` (add DB health test)

**Interfaces:**
- Consumes: `app.core.config.settings`.
- Produces: `app.core.base.Base` (DeclarativeBase with naming convention); `app.core.database.engine`, `app.core.database.SessionLocal`, `app.core.database.get_db`; `app.core.deps.DbSession` (`Annotated[Session, Depends(get_db)]`); `app.db.base` (model registry importing `Base`). Test fixtures: `db_session`, `client` (with `get_db` overridden to `db_session`).

- [ ] **Step 1: Create the Postgres compose file and start it**

`docker-compose.yml`:
```yaml
services:
  postgres:
    image: postgres:16
    environment:
      POSTGRES_USER: register
      POSTGRES_PASSWORD: register
      POSTGRES_DB: register
    ports:
      - "5432:5432"
    volumes:
      - pgdata:/var/lib/postgresql/data

volumes:
  pgdata:
```

Run: `docker compose up -d`
Expected: a `postgres:16` container running on `localhost:5432`.

- [ ] **Step 2: Implement the SQLAlchemy base, engine, session, and deps**

`app/core/base.py`:
```python
from sqlalchemy import MetaData
from sqlalchemy.orm import DeclarativeBase

NAMING_CONVENTION = {
    "ix": "ix_%(column_0_label)s",
    "uq": "uq_%(table_name)s_%(column_0_name)s",
    "ck": "ck_%(table_name)s_%(constraint_name)s",
    "fk": "fk_%(table_name)s_%(column_0_name)s_%(referred_table_name)s",
    "pk": "pk_%(table_name)s",
}


class Base(DeclarativeBase):
    metadata = MetaData(naming_convention=NAMING_CONVENTION)
```

`app/core/database.py`:
```python
from collections.abc import Generator

from sqlalchemy import create_engine
from sqlalchemy.orm import Session, sessionmaker

from app.core.config import settings

engine = create_engine(settings.database_url, pool_pre_ping=True)
SessionLocal = sessionmaker(bind=engine, autoflush=False, expire_on_commit=False)


def get_db() -> Generator[Session, None, None]:
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
```

`app/core/deps.py`:
```python
from typing import Annotated

from fastapi import Depends
from sqlalchemy.orm import Session

from app.core.database import get_db

DbSession = Annotated[Session, Depends(get_db)]
```

`app/db/__init__.py`: (empty)

`app/db/base.py`:
```python
# Single model registry: import Base and (later) every model here so Alembic
# autogenerate sees the full metadata. Models are imported HERE ONLY — never
# sideways between modules.
from app.core.base import Base  # noqa: F401
```

- [ ] **Step 3: Initialize Alembic and wire it to the metadata**

Run: `uv run alembic init alembic`

Then edit `alembic/env.py` — replace the `target_metadata = None` line and add the URL wiring near the top of the run logic:
```python
from app.core.config import settings
from app.db.base import Base

config.set_main_option("sqlalchemy.url", settings.database_url)
target_metadata = Base.metadata
```
(Leave the rest of the generated `env.py` as-is.)

- [ ] **Step 4: Add the DB health endpoint**

Replace `app/health.py` with:
```python
from fastapi import APIRouter
from sqlalchemy import text

from app.core.deps import DbSession

router = APIRouter(tags=["health"])


@router.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@router.get("/health/db")
def health_db(db: DbSession) -> dict[str, str]:
    db.execute(text("SELECT 1"))
    return {"status": "ok", "database": "ok"}
```

- [ ] **Step 5: Replace conftest with Postgres-backed transactional fixtures**

`tests/conftest.py`:
```python
import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.database import get_db
from app.db.base import Base
from app.main import create_app

# Dedicated test database — never the dev `register` DB. Create it once with
# `make testdb` (or it's created in CI). Schema is built/torn down per session;
# each test runs in a transaction that is rolled back.
test_engine = create_engine(settings.test_database_url)


@pytest.fixture(scope="session", autouse=True)
def _schema() -> None:
    Base.metadata.create_all(bind=test_engine)
    yield
    Base.metadata.drop_all(bind=test_engine)


@pytest.fixture
def db_session() -> Session:
    connection = test_engine.connect()
    transaction = connection.begin()
    session = Session(bind=connection, join_transaction_mode="create_savepoint")
    try:
        yield session
    finally:
        session.close()
        transaction.rollback()
        connection.close()


@pytest.fixture
def client(db_session: Session) -> TestClient:
    app = create_app()

    def _override_get_db():
        yield db_session

    app.dependency_overrides[get_db] = _override_get_db
    return TestClient(app)
```

- [ ] **Step 6: Write the failing DB health test**

Append to `tests/test_health.py`:
```python
def test_health_db_returns_ok(client: TestClient) -> None:
    response = client.get("/health/db")
    assert response.status_code == 200
    assert response.json()["database"] == "ok"
```

- [ ] **Step 7: Run tests (Postgres must be up)**

Run: `make test` (creates `register_test` via `make testdb`, then runs pytest)
Expected: PASS (both health tests). If it errors on connection, confirm `docker compose up -d` is running.

- [ ] **Step 8: Lint and commit**

Run: `uv run ruff check .`
```bash
git add -A
git commit -m "feat: add database foundation, naming convention, and DB health check"
```

---

### Task 3: `ping_beta` model + migration

**Files:**
- Create: `app/modules/__init__.py`, `app/modules/ping/__init__.py`, `app/modules/ping/models.py`
- Modify: `app/db/base.py` (register the model)
- Create: `alembic/versions/0001_create_ping_beta.py`
- Test: `tests/ping/__init__.py`, `tests/ping/test_model.py`

**Interfaces:**
- Consumes: `app.core.base.Base`.
- Produces: `app.modules.ping.models.PingBeta` with columns `id: uuid.UUID` (PK), `message: str`, `created_at: datetime` (tz-aware, server-set on insert via `clock_timestamp()`).

- [ ] **Step 1: Implement the model**

`app/modules/__init__.py`, `app/modules/ping/__init__.py`: (empty)

`app/modules/ping/models.py`:
```python
import uuid
from datetime import datetime

from sqlalchemy import DateTime, String, func
from sqlalchemy.orm import Mapped, mapped_column

from app.core.base import Base


class PingBeta(Base):
    __tablename__ = "ping_beta"

    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid.uuid4)
    message: Mapped[str] = mapped_column(String(500))
    # clock_timestamp() (not now()) so rows inserted in one transaction get
    # distinct instants — keeps "newest first" ordering deterministic.
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.clock_timestamp()
    )
```

- [ ] **Step 2: Register the model in the Alembic registry**

`app/db/base.py`:
```python
# Single model registry: import Base and every model here so Alembic
# autogenerate sees the full metadata. Models are imported HERE ONLY — never
# sideways between modules.
from app.core.base import Base  # noqa: F401
from app.modules.ping.models import PingBeta  # noqa: F401
```

- [ ] **Step 3: Create the migration**

`alembic/versions/0001_create_ping_beta.py`:
```python
"""create ping_beta

Revision ID: 0001
Revises:
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0001"
down_revision: str | None = None
branch_labels: Sequence[str] | None = None
depends_on: Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "ping_beta",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("message", sa.String(length=500), nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("clock_timestamp()"),
            nullable=False,
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_ping_beta")),
    )


def downgrade() -> None:
    op.drop_table("ping_beta")
```

- [ ] **Step 4: Apply the migration**

Run: `uv run alembic upgrade head`
Expected: `Running upgrade  -> 0001, create ping_beta`. The `ping_beta` table now exists.

- [ ] **Step 5: Write and run the model persistence test**

`tests/ping/__init__.py`: (empty)

`tests/ping/test_model.py`:
```python
from app.modules.ping.models import PingBeta


def test_ping_beta_persists(db_session) -> None:
    ping = PingBeta(message="hello")
    db_session.add(ping)
    db_session.flush()
    db_session.refresh(ping)
    assert ping.id is not None
    assert ping.created_at is not None
```

Run: `uv run pytest tests/ping/test_model.py -v`
Expected: PASS.

- [ ] **Step 6: Lint and commit**

Run: `uv run ruff check .`
```bash
git add -A
git commit -m "feat: add ping_beta model and migration"
```

---

### Task 4: `ping` service + schemas (unit TDD)

**Files:**
- Create: `app/modules/ping/schemas.py`, `app/modules/ping/service.py`
- Test: `tests/ping/test_service.py`

**Interfaces:**
- Consumes: `PingBeta`, `Session`.
- Produces: `app.modules.ping.schemas.PingCreate` (`message: str`, min length 1, max 500) and `PingRead` (`id: uuid.UUID`, `message: str`, `created_at: datetime`, `from_attributes=True`); `app.modules.ping.service.create_ping(db: Session, data: PingCreate) -> PingBeta` and `list_pings(db: Session) -> list[PingBeta]` (newest first).

- [ ] **Step 1: Write the failing service tests**

`tests/ping/test_service.py`:
```python
from app.modules.ping.schemas import PingCreate
from app.modules.ping.service import create_ping, list_pings


def test_create_ping_persists(db_session) -> None:
    ping = create_ping(db_session, PingCreate(message="hello"))
    assert ping.id is not None
    assert ping.message == "hello"
    assert ping.created_at is not None


def test_list_pings_newest_first(db_session) -> None:
    create_ping(db_session, PingCreate(message="first"))
    create_ping(db_session, PingCreate(message="second"))
    messages = [p.message for p in list_pings(db_session)]
    assert messages == ["second", "first"]
```

- [ ] **Step 2: Run to verify it fails**

Run: `uv run pytest tests/ping/test_service.py -v`
Expected: FAIL — `ModuleNotFoundError: No module named 'app.modules.ping.schemas'`.

- [ ] **Step 3: Implement schemas and service**

`app/modules/ping/schemas.py`:
```python
import uuid
from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field


class PingCreate(BaseModel):
    message: str = Field(min_length=1, max_length=500)


class PingRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    message: str
    created_at: datetime
```

`app/modules/ping/service.py`:
```python
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.modules.ping.models import PingBeta
from app.modules.ping.schemas import PingCreate


def create_ping(db: Session, data: PingCreate) -> PingBeta:
    ping = PingBeta(message=data.message)
    db.add(ping)
    db.commit()
    db.refresh(ping)
    return ping


def list_pings(db: Session) -> list[PingBeta]:
    stmt = select(PingBeta).order_by(PingBeta.created_at.desc())
    return list(db.execute(stmt).scalars().all())
```

- [ ] **Step 4: Run to verify it passes**

Run: `uv run pytest tests/ping/test_service.py -v`
Expected: PASS.

- [ ] **Step 5: Lint and commit**

Run: `uv run ruff check .`
```bash
git add -A
git commit -m "feat: add ping schemas and service"
```

---

### Task 5: API error envelope + exception handlers

**Files:**
- Create: `app/core/errors.py`
- Modify: `app/main.py` (register handlers)
- Test: `tests/test_errors.py`

**Interfaces:**
- Produces: `app.core.errors.DomainError` (attrs `status_code: int`, `code: str`, `message: str`, `details: dict`); `error_body(code, message, details) -> dict`; `register_exception_handlers(app: FastAPI) -> None` (handles `RequestValidationError` → 422 envelope, `DomainError` → `exc.status_code` envelope).

- [ ] **Step 1: Write the failing unit test for the envelope shape**

`tests/test_errors.py`:
```python
from app.core.errors import error_body


def test_error_body_shape() -> None:
    body = error_body("validation_error", "Request validation failed.", {"k": "v"})
    assert body == {
        "error": {
            "code": "validation_error",
            "message": "Request validation failed.",
            "details": {"k": "v"},
        }
    }
```

- [ ] **Step 2: Run to verify it fails**

Run: `uv run pytest tests/test_errors.py -v`
Expected: FAIL — `ModuleNotFoundError: No module named 'app.core.errors'`.

- [ ] **Step 3: Implement the error module**

`app/core/errors.py`:
```python
from typing import Any

from fastapi import FastAPI, Request, status
from fastapi.encoders import jsonable_encoder
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse


class DomainError(Exception):
    """Base for application/domain errors surfaced through the API."""

    status_code: int = status.HTTP_400_BAD_REQUEST
    code: str = "domain_error"

    def __init__(self, message: str, details: dict[str, Any] | None = None) -> None:
        self.message = message
        self.details = details or {}
        super().__init__(message)


def error_body(
    code: str, message: str, details: dict[str, Any] | None = None
) -> dict[str, Any]:
    return {"error": {"code": code, "message": message, "details": details or {}}}


def register_exception_handlers(app: FastAPI) -> None:
    @app.exception_handler(RequestValidationError)
    async def _validation(_: Request, exc: RequestValidationError) -> JSONResponse:
        return JSONResponse(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            content=jsonable_encoder(
                error_body(
                    "validation_error",
                    "Request validation failed.",
                    {"errors": exc.errors()},
                )
            ),
        )

    @app.exception_handler(DomainError)
    async def _domain(_: Request, exc: DomainError) -> JSONResponse:
        return JSONResponse(
            status_code=exc.status_code,
            content=jsonable_encoder(error_body(exc.code, exc.message, exc.details)),
        )
```

- [ ] **Step 4: Register handlers in the app factory**

In `app/main.py`, import and call inside `create_app` (after `app = FastAPI(...)`, before returning):
```python
from app.core.errors import register_exception_handlers
```
```python
    register_exception_handlers(app)
```

- [ ] **Step 5: Run to verify it passes**

Run: `uv run pytest tests/test_errors.py -v`
Expected: PASS.

- [ ] **Step 6: Lint and commit**

Run: `uv run ruff check .`
```bash
git add -A
git commit -m "feat: add uniform API error envelope and exception handlers"
```

---

### Task 6: `ping` router (integration TDD)

**Files:**
- Create: `app/modules/ping/router.py`
- Modify: `app/main.py` (mount router under `/api/v1`)
- Test: `tests/ping/test_router.py`

**Interfaces:**
- Consumes: `DbSession`, `service.create_ping`, `service.list_pings`, `PingCreate`, `PingRead`, the error handlers from Task 5.
- Produces: `app.modules.ping.router.router` (APIRouter, prefix `/pings`) with `GET ""` → `list[PingRead]` and `POST ""` → `PingRead` (201). Mounted at `/api/v1/pings`.

- [ ] **Step 1: Write the failing integration tests**

`tests/ping/test_router.py`:
```python
from fastapi.testclient import TestClient


def test_create_and_list_ping(client: TestClient) -> None:
    created = client.post("/api/v1/pings", json={"message": "hello"})
    assert created.status_code == 201
    body = created.json()
    assert body["message"] == "hello"
    assert "id" in body
    assert "created_at" in body

    listing = client.get("/api/v1/pings")
    assert listing.status_code == 200
    assert any(p["message"] == "hello" for p in listing.json())


def test_create_ping_empty_message_returns_error_envelope(client: TestClient) -> None:
    response = client.post("/api/v1/pings", json={"message": ""})
    assert response.status_code == 422
    body = response.json()
    assert body["error"]["code"] == "validation_error"
    assert body["error"]["details"]
```

- [ ] **Step 2: Run to verify it fails**

Run: `uv run pytest tests/ping/test_router.py -v`
Expected: FAIL — 404 on `/api/v1/pings` (router not mounted).

- [ ] **Step 3: Implement the router**

`app/modules/ping/router.py`:
```python
from fastapi import APIRouter, status

from app.core.deps import DbSession
from app.modules.ping import service
from app.modules.ping.schemas import PingCreate, PingRead

router = APIRouter(prefix="/pings", tags=["ping"])


@router.get("", response_model=list[PingRead])
def list_pings(db: DbSession) -> list[PingRead]:
    return service.list_pings(db)


@router.post("", response_model=PingRead, status_code=status.HTTP_201_CREATED)
def create_ping(data: PingCreate, db: DbSession) -> PingRead:
    return service.create_ping(db, data)
```

- [ ] **Step 4: Mount the router under `/api/v1`**

In `app/main.py`, add the import and include (inside `create_app`, after the health router):
```python
from app.modules.ping.router import router as ping_router
```
```python
    app.include_router(ping_router, prefix="/api/v1")
```

- [ ] **Step 5: Run to verify it passes**

Run: `uv run pytest -v`
Expected: PASS (all tests, including the empty-message 422 envelope).

- [ ] **Step 6: Lint and commit**

Run: `uv run ruff check .`
```bash
git add -A
git commit -m "feat: add ping router under /api/v1"
```

---

### Task 7: Backend CI + CLAUDE.md + README

**Files:**
- Create: `.github/workflows/ci.yml`, `CLAUDE.md`, `README.md`

**Interfaces:** none (project meta).

- [ ] **Step 1: Add the CI workflow**

`.github/workflows/ci.yml`:
```yaml
name: CI

on:
  pull_request:
  push:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest
    services:
      postgres:
        image: postgres:16
        env:
          POSTGRES_USER: register
          POSTGRES_PASSWORD: register
          POSTGRES_DB: register
        ports:
          - 5432:5432
        options: >-
          --health-cmd pg_isready
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5
    env:
      DATABASE_URL: postgresql+psycopg://register:register@localhost:5432/register
    steps:
      - uses: actions/checkout@v4
      - uses: astral-sh/setup-uv@v5
        with:
          python-version: "3.12"
      - run: uv sync
      - run: uv run ruff check .
      - run: uv run alembic upgrade head   # migrates the dev `register` DB
      - run: make test                     # creates register_test, then pytest
```

- [ ] **Step 2: Add the backend CLAUDE.md**

`CLAUDE.md`:
```markdown
# dentist-registry-backend — Claude Code guide

FastAPI backend for the Register System. Source of truth for product behavior
lives in the **dentail-register-docs** repo (PRD, Entities, Workflows, Rules,
tech stack, testing) and its `docs/specs` + `docs/plans`. Read the relevant
spec/plan before building.

## Structure (feature-first modular monolith)
- `app/core/` — shared infra: config, database, base (DeclarativeBase + naming
  convention), deps, errors, logging. Imports nothing from `modules/`.
- `app/modules/<domain>/` — one folder per domain: `router.py`, `schemas.py`,
  `models.py`, `service.py`.
- `app/db/base.py` — the ONLY place that imports every model (for Alembic).
- `app/main.py` — app factory; mounts module routers under `/api/v1`.

## Import discipline (mandatory)
- One-way deps: `core/ ← modules/ ← main.py`.
- Cross-module calls go through the other module's `service` — never its
  `models`/`router`/internals.
- No circular imports: use string-based SQLAlchemy refs (`relationship("X")`,
  `ForeignKey("x.id")`).
- Routers are thin: parse input → call service → shape response. No business
  logic or direct DB queries in routers.

## Conventions
- Sync SQLAlchemy 2.x. UUID PKs. Timezone-aware timestamps. `*_beta` tables for
  test/experimental data.
- Uniform error envelope: `{ "error": { "code", "message", "details" } }`.
- Permissive-OSS dependencies only (MIT/Apache/BSD/ISC). Never commit secrets.

## Commands
- `docker compose up -d` — start Postgres
- `make install` (uv sync) · `make migrate` · `make run` · `make test` · `make lint`

## Tests
- pytest against Postgres (never SQLite). Per-test transactional rollback.
```

- [ ] **Step 3: Add the README**

`README.md`:
```markdown
# dentist-registry-backend

FastAPI backend for the Register System.

## Quickstart
```bash
cp .env.example .env
docker compose up -d
make install
make migrate
make run        # http://localhost:8000  (docs at /docs)
```

## Test & lint
```bash
make test
make lint
```

See `CLAUDE.md` for structure and conventions; product source of truth is the
`dentail-register-docs` repo.
```

- [ ] **Step 4: Final local verification**

Run: `uv run ruff check . && uv run pytest -v`
Expected: lint clean, all tests PASS.

- [ ] **Step 5: Commit, push, open PR**

```bash
git add -A
git commit -m "chore: add backend CI, CLAUDE.md, and README"
git push -u origin skeleton-backend
gh-personal pr create --title "Walking skeleton: backend scaffold + ping slice" \
  --body "Implements Phase A of docs/plans/2026-06-17-walking-skeleton-plan.md: FastAPI feature-first scaffold, ping_beta vertical slice (model → migration → service → router under /api/v1), error envelope, pytest against Postgres, CI, CLAUDE.md."
```

---

# Phase B — Frontend (`dentist-registry-frontend`)

> Branch: `git switch -c skeleton-frontend` in the frontend repo before Task 8.
> Phase B assumes the backend runs locally on `http://localhost:8000` for the e2e in Task 10.

### Task 8: Frontend scaffold + typed API client + health badge

**Files:**
- Create (via tooling): Next.js app (`src/app/*`, `package.json`, `tsconfig.json`, `next.config.ts`, Tailwind, `components.json`)
- Create: `src/lib/env.ts`, `src/lib/api-client.ts`, `src/app/providers.tsx`, `.env.local.example`
- Modify: `src/app/layout.tsx`, `src/app/page.tsx`

**Interfaces:**
- Produces: `@/lib/env` (`env.NEXT_PUBLIC_API_BASE_URL`); `@/lib/api-client` (`apiFetch<T>(path, init?) -> Promise<T>`, `ApiError` with `code`/`details`, type `ApiErrorBody`); `Providers` wrapping `QueryClientProvider`.

- [ ] **Step 1: Scaffold Next.js**

Run (the repo currently holds only `README.md` + `.git`; remove the README so the scaffolder doesn't conflict):
```bash
rm -f README.md
npx create-next-app@latest . --typescript --tailwind --eslint --app --src-dir --import-alias "@/*" --use-npm --no-turbopack
```
Expected: a Next.js App Router project with `src/`.

- [ ] **Step 2: Install runtime deps and init shadcn**

```bash
npm install @tanstack/react-query react-hook-form zod @hookform/resolvers
npx shadcn@latest init -d
npx shadcn@latest add button input card label form
```
Expected: `components.json` + components under `src/components/ui/`.

- [ ] **Step 3: Add env validation and the typed API client**

`src/lib/env.ts`:
```typescript
import { z } from "zod";

const schema = z.object({
  NEXT_PUBLIC_API_BASE_URL: z.string().url(),
});

export const env = schema.parse({
  NEXT_PUBLIC_API_BASE_URL: process.env.NEXT_PUBLIC_API_BASE_URL,
});
```

`src/lib/api-client.ts`:
```typescript
import { env } from "@/lib/env";

export type ApiErrorBody = {
  error: { code: string; message: string; details?: Record<string, unknown> };
};

export class ApiError extends Error {
  code: string;
  details?: Record<string, unknown>;
  constructor(body: ApiErrorBody) {
    super(body.error.message);
    this.code = body.error.code;
    this.details = body.error.details;
  }
}

export async function apiFetch<T>(path: string, init?: RequestInit): Promise<T> {
  const res = await fetch(`${env.NEXT_PUBLIC_API_BASE_URL}${path}`, {
    headers: { "Content-Type": "application/json", ...(init?.headers ?? {}) },
    ...init,
  });
  if (!res.ok) {
    const body = (await res.json().catch(() => null)) as ApiErrorBody | null;
    if (body?.error) throw new ApiError(body);
    throw new Error(`Request failed: ${res.status}`);
  }
  return (await res.json()) as T;
}
```

`.env.local.example`:
```
NEXT_PUBLIC_API_BASE_URL=http://localhost:8000
```

- [ ] **Step 4: Add the Query provider and wire the layout**

`src/app/providers.tsx`:
```tsx
"use client";

import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { useState } from "react";

export function Providers({ children }: { children: React.ReactNode }) {
  const [client] = useState(() => new QueryClient());
  return <QueryClientProvider client={client}>{children}</QueryClientProvider>;
}
```

Edit `src/app/layout.tsx` to wrap children with `<Providers>` (keep the generated metadata/fonts):
```tsx
import { Providers } from "@/app/providers";
```
Wrap the `{children}` inside `<body>`:
```tsx
        <Providers>{children}</Providers>
```

- [ ] **Step 5: Replace the home page with a backend health badge**

`src/app/page.tsx`:
```tsx
"use client";

import { useQuery } from "@tanstack/react-query";

import { apiFetch } from "@/lib/api-client";

function useHealth() {
  return useQuery({
    queryKey: ["health"],
    queryFn: () => apiFetch<{ database: string }>("/health/db"),
  });
}

export default function Home() {
  const health = useHealth();
  return (
    <main className="mx-auto max-w-xl p-8">
      <h1 className="text-2xl font-semibold">Register System</h1>
      <p className="mt-2" data-testid="backend-health">
        Backend: {health.isPending ? "checking…" : health.isError ? "unreachable" : "healthy"}
      </p>
    </main>
  );
}
```

- [ ] **Step 6: Verify it builds and runs**

Run: `cp .env.local.example .env.local && npm run build`
Expected: build succeeds. (With the backend running, `npm run dev` shows "Backend: healthy".)

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat: scaffold Next.js app with typed API client and health badge"
```

---

### Task 9: `ping` feature — list + create form

**Files:**
- Create: `src/features/ping/api.ts`, `src/features/ping/hooks.ts`, `src/features/ping/schema.ts`, `src/features/ping/ping-form.tsx`
- Modify: `src/app/page.tsx` (render list + form)

**Interfaces:**
- Consumes: `apiFetch`, `ApiError`, TanStack Query, RHF, Zod, shadcn `form`/`input`/`button`/`card`.
- Produces: `Ping` type; `usePings()`, `useCreatePing()`; `PingForm` component.

- [ ] **Step 1: Add the feature API and hooks**

`src/features/ping/api.ts`:
```typescript
import { apiFetch } from "@/lib/api-client";

export type Ping = { id: string; message: string; created_at: string };

export function fetchPings(): Promise<Ping[]> {
  return apiFetch<Ping[]>("/api/v1/pings");
}

export function createPing(message: string): Promise<Ping> {
  return apiFetch<Ping>("/api/v1/pings", {
    method: "POST",
    body: JSON.stringify({ message }),
  });
}
```

`src/features/ping/hooks.ts`:
```typescript
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";

import { createPing, fetchPings } from "@/features/ping/api";

export function usePings() {
  return useQuery({ queryKey: ["pings"], queryFn: fetchPings });
}

export function useCreatePing() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: createPing,
    onSuccess: () => qc.invalidateQueries({ queryKey: ["pings"] }),
  });
}
```

`src/features/ping/schema.ts`:
```typescript
import { z } from "zod";

export const pingFormSchema = z.object({
  message: z.string().min(1, "Message is required"),
});

export type PingFormValues = z.infer<typeof pingFormSchema>;
```

- [ ] **Step 2: Add the form component**

`src/features/ping/ping-form.tsx`:
```tsx
"use client";

import { zodResolver } from "@hookform/resolvers/zod";
import { useForm } from "react-hook-form";

import { Button } from "@/components/ui/button";
import {
  Form,
  FormControl,
  FormField,
  FormItem,
  FormLabel,
  FormMessage,
} from "@/components/ui/form";
import { Input } from "@/components/ui/input";
import { useCreatePing } from "@/features/ping/hooks";
import { pingFormSchema, type PingFormValues } from "@/features/ping/schema";

export function PingForm() {
  const form = useForm<PingFormValues>({
    resolver: zodResolver(pingFormSchema),
    defaultValues: { message: "" },
  });
  const createPing = useCreatePing();

  function onSubmit(values: PingFormValues) {
    createPing.mutate(values.message, { onSuccess: () => form.reset() });
  }

  return (
    <Form {...form}>
      <form onSubmit={form.handleSubmit(onSubmit)} className="flex items-end gap-2">
        <FormField
          control={form.control}
          name="message"
          render={({ field }) => (
            <FormItem className="flex-1">
              <FormLabel>Message</FormLabel>
              <FormControl>
                <Input placeholder="Say something…" {...field} />
              </FormControl>
              <FormMessage />
            </FormItem>
          )}
        />
        <Button type="submit" disabled={createPing.isPending}>
          Add ping
        </Button>
      </form>
    </Form>
  );
}
```

- [ ] **Step 3: Render the list and form on the home page**

`src/app/page.tsx`:
```tsx
"use client";

import { useQuery } from "@tanstack/react-query";

import { Card } from "@/components/ui/card";
import { usePings } from "@/features/ping/hooks";
import { PingForm } from "@/features/ping/ping-form";
import { apiFetch } from "@/lib/api-client";

function useHealth() {
  return useQuery({
    queryKey: ["health"],
    queryFn: () => apiFetch<{ database: string }>("/health/db"),
  });
}

export default function Home() {
  const health = useHealth();
  const pings = usePings();

  return (
    <main className="mx-auto max-w-xl space-y-6 p-8">
      <header>
        <h1 className="text-2xl font-semibold">Register System</h1>
        <p className="mt-1 text-sm" data-testid="backend-health">
          Backend: {health.isPending ? "checking…" : health.isError ? "unreachable" : "healthy"}
        </p>
      </header>

      <PingForm />

      <section className="space-y-2">
        {pings.isPending && <p>Loading…</p>}
        {pings.data?.map((p) => (
          <Card key={p.id} className="p-3">
            {p.message}
          </Card>
        ))}
      </section>
    </main>
  );
}
```

- [ ] **Step 4: Verify it builds**

Run: `npm run build`
Expected: build succeeds with no type errors.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: add ping list and create form"
```

---

### Task 10: Playwright e2e + frontend CI + CLAUDE.md + README

**Files:**
- Create: `playwright.config.ts`, `tests/e2e/ping.spec.ts`, `.github/workflows/ci.yml`, `CLAUDE.md`, `README.md`
- Modify: `package.json` (add `test:e2e` script)

**Interfaces:** none (verification + meta).

- [ ] **Step 1: Install and configure Playwright**

```bash
npm install -D @playwright/test
npx playwright install --with-deps chromium
```

`playwright.config.ts`:
```typescript
import { defineConfig } from "@playwright/test";

export default defineConfig({
  testDir: "./tests/e2e",
  use: { baseURL: "http://localhost:3000" },
  webServer: {
    command: "npm run dev",
    url: "http://localhost:3000",
    reuseExistingServer: !process.env.CI,
  },
});
```

Add to `package.json` scripts:
```json
    "test:e2e": "playwright test"
```

- [ ] **Step 2: Write the e2e happy-path**

`tests/e2e/ping.spec.ts`:
```typescript
import { expect, test } from "@playwright/test";

test("create a ping and see it in the list", async ({ page }) => {
  await page.goto("/");
  const message = `hello ${Date.now()}`;
  await page.getByLabel("Message").fill(message);
  await page.getByRole("button", { name: "Add ping" }).click();
  await expect(page.getByText(message)).toBeVisible();
});
```

- [ ] **Step 3: Run the e2e (backend + Postgres must be up)**

Ensure the backend is running (`make run` in the backend repo, with `docker compose up -d`), then:
Run: `cp .env.local.example .env.local && npm run test:e2e`
Expected: 1 passed — the new ping renders without a manual refresh.

- [ ] **Step 4: Add frontend CI (typecheck + build)**

`.github/workflows/ci.yml`:
```yaml
name: CI

on:
  pull_request:
  push:
    branches: [main]

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: "20"
          cache: npm
      - run: npm ci
      - run: npx tsc --noEmit
      - run: npm run build
        env:
          NEXT_PUBLIC_API_BASE_URL: http://localhost:8000
```

- [ ] **Step 5: Add CLAUDE.md and README**

`CLAUDE.md`:
```markdown
# dentist-registry-frontend — Claude Code guide

Next.js (App Router) frontend for the Register System. Product source of truth
lives in the **dentail-register-docs** repo; read the relevant `docs/specs` /
`docs/plans` before building.

## Structure (feature-first)
- `src/app/` — App Router pages, root layout, `providers.tsx` (TanStack Query).
- `src/lib/` — `env.ts` (zod-validated public env), `api-client.ts` (typed fetch
  wrapper that parses the backend error envelope).
- `src/features/<domain>/` — `api.ts`, `hooks.ts`, `schema.ts`, components.
- `src/components/ui/` — shadcn primitives.

## Conventions
- REST only; data via TanStack Query (no Redux). Forms via React Hook Form + Zod.
- Client components for anything using hooks/queries (`"use client"`). We don't
  force server-side fetching — the app talks to the separate FastAPI backend.
- Going forward: Vitest + React Testing Library for unit/component tests
  (API mocked); Playwright for true end-to-end flows.
- Permissive-OSS dependencies only. Never commit secrets.

## Commands
- `npm install` · `npm run dev` (http://localhost:3000) · `npm run build`
- `npm run test:e2e` — Playwright (needs the backend + Postgres running)
```

`README.md`:
```markdown
# dentist-registry-frontend

Next.js frontend for the Register System.

## Quickstart
```bash
cp .env.local.example .env.local
npm install
npm run dev        # http://localhost:3000
```
The backend must be running at `NEXT_PUBLIC_API_BASE_URL` (default
http://localhost:8000) for data to load. See `CLAUDE.md` for conventions.
```

- [ ] **Step 6: Verify, commit, push, open PR**

Run: `npx tsc --noEmit && npm run build`
Expected: clean.
```bash
git add -A
git commit -m "chore: add Playwright e2e, frontend CI, CLAUDE.md, and README"
git push -u origin skeleton-frontend
gh-personal pr create --title "Walking skeleton: frontend scaffold + ping slice" \
  --body "Implements Phase B of docs/plans/2026-06-17-walking-skeleton-plan.md: Next.js App Router scaffold, typed API client (parses error envelope), ping list + RHF/Zod form via TanStack Query, Playwright happy-path, CI, CLAUDE.md."
```

---

## Final Acceptance (both repos merged)

Verify against spec §11:
1. Backend: `docker compose up -d` + `make migrate` + `make run` → `/health` and `/health/db` healthy. ✔ Tasks 1–2
2. Frontend: `npm run dev` shows a healthy backend badge. ✔ Task 8
3. Submitting the form creates a ping; it appears without refresh. ✔ Tasks 9–10
4. Empty message surfaces the parsed error-envelope message. ✔ Tasks 5–6 (API); the client throws `ApiError`
5. Backend unit + integration + error-path tests pass against Postgres. ✔ Tasks 2–6
6. Frontend Playwright happy-path passes. ✔ Task 10
7. CI green on both repos' PRs. ✔ Tasks 7, 10
8. Lockfiles committed (`uv.lock`, `package-lock.json`). ✔ Tasks 1, 8
9. `CLAUDE.md` in each code repo. ✔ Tasks 7, 10
10. DB conventions in force (UUID PKs, tz-aware timestamps, naming convention). ✔ Tasks 2–3
11. `.env.example` / `.env.local.example` exist; no secrets committed. ✔ Tasks 1, 8
12. All three PRs (spec ✔ merged, backend, frontend) merged via `gh-personal`. ✔ Tasks 7, 10

(CD — Render/Vercel + remote Supabase — is a follow-on step once the above is green.)
