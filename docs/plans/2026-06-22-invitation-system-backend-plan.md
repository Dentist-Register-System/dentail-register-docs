# Invitation System (Slice 1) — Backend Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make invitations a first-class, email-deliverable, trackable entity: add a Resend-backed email module, send invite emails on create, enrich the invite list with real names + derived expiry, add Resend + public-preview endpoints, gate management per entity, and make doctor/assistant phone optional (email-centric invites).

**Architecture:** New `app/modules/email/` calls the Resend HTTP API via httpx (no SDK). The existing doctor/assistant create-with-invite flow sends the invite email at its service boundary. The invites router gains an enriched list (joined to the linked doctor/assistant), a resend route, and a public unauthenticated preview route. A small authorization helper applies #91's per-entity role rules to invite management. Migration `0017` makes `doctor_beta.phone` and `assistant_beta.phone` nullable.

**Tech Stack:** FastAPI, SQLAlchemy 2.x (sync), Pydantic v2, Alembic, httpx, pytest on Postgres (host port 5433, per-test transactional rollback).

## Global Constraints
- Spec: `docs/specs/2026-06-22-invitation-system-design.md`. This plan is the backend half of Slice 1.
- Module-boundary discipline: `core ← modules`; cross-module calls go through services; break cycles with local imports (as `invites/service.py` already does for doctors/assistants).
- `record_audit` is in-transaction (no commit inside it); `clinic_id` is required where known.
- Email is **failure-tolerant**: a failed/again-unconfigured send NEVER fails invite creation or resend. If `RESEND_API_KEY` is unset, sending is a logged no-op.
- Email body is **bilingual** (English + Hindi in one HTML body).
- Invite-management permissions mirror #91: **doctor** invites → `owner` + `assistant`; **assistant** invites → `owner` only.
- Migrations: implementers run `alembic upgrade head` against LOCAL PG :5433 only. The controller applies `0017` to Supabase via MCP and bumps `alembic_version`. Chain `0017` off `0016_user_preferences` (`down_revision = "0016"`).
- `uv run ruff check .` clean; `make test` green. Never commit secrets; never touch `.env`/`.env.local`.
- Ruff bans relative imports (`TID`); use absolute `app.…` imports.

## File Structure
- Create: `app/modules/email/__init__.py`, `app/modules/email/service.py` — Resend sender + bilingual invite template.
- Modify: `app/core/config.py` — add `resend_api_key`, `email_from`, `app_base_url`.
- Modify: `pyproject.toml` — move/add `httpx` to runtime `dependencies`.
- Create: `alembic/versions/0017_invite_email_centric.py` — phone nullable on doctor + assistant.
- Modify: `app/modules/doctors/models.py`, `app/modules/assistants/models.py` — `phone` nullable.
- Modify: `app/modules/doctors/schemas.py`, `app/modules/assistants/schemas.py` — `phone` optional in Create/Read.
- Modify: `app/modules/doctors/service.py`, `app/modules/assistants/service.py` — send invite email on create.
- Modify: `app/modules/invites/schemas.py` — enriched `InviteRead`, preview schema.
- Modify: `app/modules/invites/service.py` — enriched list + display status + resend + preview + auth helper.
- Modify: `app/modules/invites/router.py` — resend route, public preview route, role filter, per-entity gates.
- Tests: `tests/email/test_email.py`, `tests/invites/test_invite_delivery.py`, `tests/doctors/test_doctors.py` (extend), `tests/assistants/test_assistants.py` (extend).

---

### Task 1: Email module (Resend sender + bilingual template)

**Files:**
- Create: `app/modules/email/__init__.py` (empty)
- Create: `app/modules/email/service.py`
- Modify: `app/core/config.py:1-25`
- Modify: `pyproject.toml` (deps)
- Test: `tests/email/__init__.py` (empty), `tests/email/test_email.py`

**Interfaces:**
- Produces: `send_invite_email(*, to: str, clinic_name: str, inviter_name: str | None, role: str, accept_url: str, expires_at: datetime) -> bool` in `app/modules/email/service.py`. Returns `True` if a send was attempted+succeeded, `False` if skipped (no key) or failed (logged). Never raises.
- Consumes: `settings.resend_api_key`, `settings.email_from`, `settings.app_base_url`.

- [ ] **Step 1: Add config fields**

In `app/core/config.py`, inside `Settings`:

```python
    resend_api_key: str | None = None
    email_from: str = "Register <onboarding@resend.dev>"
    app_base_url: str = "http://localhost:3000"
```

- [ ] **Step 2: Make httpx a runtime dependency**

In `pyproject.toml`, add `"httpx>=0.27",` to `[project].dependencies` (keep it in dev too, harmless). Run `uv sync` so the lockfile updates.

- [ ] **Step 3: Write the failing tests**

`tests/email/test_email.py`:

```python
import datetime as dt
from unittest.mock import patch

from app.core.config import settings
from app.modules.email import service


def _args():
    return dict(
        to="doc@example.com",
        clinic_name="Test Pune Clinic",
        inviter_name="Asha Rao",
        role="doctor",
        accept_url="http://localhost:3000/invite/abc",
        expires_at=dt.datetime(2026, 6, 30, tzinfo=dt.timezone.utc),
    )


def test_send_is_noop_without_key(monkeypatch):
    monkeypatch.setattr(settings, "resend_api_key", None)
    with patch("app.modules.email.service.httpx.post") as post:
        assert service.send_invite_email(**_args()) is False
        post.assert_not_called()


def test_send_posts_to_resend_with_key(monkeypatch):
    monkeypatch.setattr(settings, "resend_api_key", "re_test")
    monkeypatch.setattr(settings, "email_from", "Register <x@y.z>")
    with patch("app.modules.email.service.httpx.post") as post:
        post.return_value.status_code = 200
        assert service.send_invite_email(**_args()) is True
        post.assert_called_once()
        kwargs = post.call_args.kwargs
        assert kwargs["headers"]["Authorization"] == "Bearer re_test"
        body = kwargs["json"]
        assert body["to"] == ["doc@example.com"]
        assert body["from"] == "Register <x@y.z>"
        assert "Test Pune Clinic" in body["html"]
        # bilingual: contains a Devanagari character
        assert any("ऀ" <= ch <= "ॿ" for ch in body["html"])
        assert "http://localhost:3000/invite/abc" in body["html"]


def test_send_swallows_errors(monkeypatch):
    monkeypatch.setattr(settings, "resend_api_key", "re_test")
    with patch("app.modules.email.service.httpx.post", side_effect=RuntimeError("boom")):
        assert service.send_invite_email(**_args()) is False
```

- [ ] **Step 4: Run tests, verify they fail**

Run: `make test PYTEST_ARGS="tests/email/test_email.py"` (or `uv run pytest tests/email/test_email.py -v`)
Expected: FAIL (module `app.modules.email.service` not found).

- [ ] **Step 5: Implement `service.py`**

```python
import datetime as dt
import logging

import httpx

from app.core.config import settings

logger = logging.getLogger(__name__)

_RESEND_URL = "https://api.resend.com/emails"


def _build_html(*, clinic_name: str, inviter_name: str | None, role: str, accept_url: str, expires_at: dt.datetime) -> str:
    by = f" by {inviter_name}" if inviter_name else ""
    by_hi = f" {inviter_name} द्वारा" if inviter_name else ""
    when = expires_at.strftime("%d %b %Y")
    return (
        f"<div style='font-family:sans-serif;max-width:480px;margin:auto'>"
        f"<h2>You're invited to join {clinic_name}</h2>"
        f"<p>You have been invited{by} to join <b>{clinic_name}</b> as a <b>{role}</b> on Register.</p>"
        f"<p><a href='{accept_url}' style='background:#6750A4;color:#fff;padding:12px 20px;"
        f"border-radius:8px;text-decoration:none;display:inline-block'>Accept invitation</a></p>"
        f"<p style='color:#555'>This invitation expires on {when}.</p>"
        f"<hr style='border:none;border-top:1px solid #eee'>"
        f"<h2>{clinic_name} में शामिल होने का निमंत्रण</h2>"
        f"<p>आपको{by_hi} Register पर <b>{clinic_name}</b> में "
        f"<b>{role}</b> के रूप में शामिल होने के लिए "
        f"आमंत्रित किया गया है।</p>"
        f"<p><a href='{accept_url}'>{accept_url}</a></p>"
        f"</div>"
    )


def send_invite_email(
    *,
    to: str,
    clinic_name: str,
    inviter_name: str | None,
    role: str,
    accept_url: str,
    expires_at: dt.datetime,
) -> bool:
    if not settings.resend_api_key:
        logger.warning("RESEND_API_KEY unset; skipping invite email to %s", to)
        return False
    html = _build_html(
        clinic_name=clinic_name, inviter_name=inviter_name, role=role,
        accept_url=accept_url, expires_at=expires_at,
    )
    try:
        resp = httpx.post(
            _RESEND_URL,
            headers={"Authorization": f"Bearer {settings.resend_api_key}"},
            json={
                "from": settings.email_from,
                "to": [to],
                "subject": f"You're invited to join {clinic_name} on Register",
                "html": html,
            },
            timeout=10.0,
        )
        if resp.status_code >= 400:
            logger.error("Resend send failed (%s): %s", resp.status_code, resp.text)
            return False
        return True
    except Exception:  # noqa: BLE001 — email must never break the request
        logger.exception("Resend send raised for %s", to)
        return False
```

- [ ] **Step 6: Run tests, verify PASS**

Run: `uv run pytest tests/email/test_email.py -v` → PASS (3 tests).

- [ ] **Step 7: Commit**

```bash
git add app/modules/email app/core/config.py pyproject.toml uv.lock tests/email
git commit -m "feat(email): Resend-backed bilingual invite email module"
```

---

### Task 2: Migration 0017 + email-centric schemas (phone nullable)

**Files:**
- Create: `alembic/versions/0017_invite_email_centric.py`
- Modify: `app/modules/doctors/models.py` (phone), `app/modules/assistants/models.py` (phone)
- Modify: `app/modules/doctors/schemas.py`, `app/modules/assistants/schemas.py`
- Test: `tests/doctors/test_doctors.py` (extend), `tests/assistants/test_assistants.py` (extend)

**Interfaces:**
- Produces: `DoctorCreate.phone: str | None`, `AssistantCreate.phone: str | None`, `DoctorRead.phone: str | None`, `AssistantRead.phone: str | None`. Models `Doctor.phone`/`Assistant.phone` nullable.

- [ ] **Step 1: Write the failing test**

Add to `tests/doctors/test_doctors.py`:

```python
def test_create_doctor_with_email_only_no_phone(auth_client):
    owner, _ = auth_client(sub="aaaa1111-1111-1111-1111-111111111111")
    from tests.conftest import make_clinic
    cid = make_clinic(owner)
    resp = owner.post(f"/api/v1/clinics/{cid}/doctors", json={"name": "Dr Roy", "email": "roy@example.com"})
    assert resp.status_code == 201, resp.text
    assert resp.json()["doctor"]["phone"] is None
```

Add the analogous `test_create_assistant_with_email_only_no_phone` to `tests/assistants/test_assistants.py` (POST `/assistants` with `{"name": "Roy", "email": "roy@example.com"}`).

- [ ] **Step 2: Run, verify fail**

Run: `uv run pytest tests/doctors/test_doctors.py::test_create_doctor_with_email_only_no_phone -v`
Expected: FAIL (422 — phone required).

- [ ] **Step 3: Make phone nullable in models + schemas**

`app/modules/doctors/models.py`: change `phone: Mapped[str]` → `phone: Mapped[str | None] = mapped_column(String(32), nullable=True)`. Same for `assistant_beta` in `app/modules/assistants/models.py`.

`app/modules/doctors/schemas.py`: `DoctorCreate.phone: str | None = None`; `DoctorRead.phone: str | None`. `app/modules/assistants/schemas.py`: `AssistantCreate.phone: str | None = None`; `AssistantRead.phone: str | None`.

- [ ] **Step 4: Write migration 0017**

`alembic/versions/0017_invite_email_centric.py`:

```python
"""invite email-centric: phone nullable on doctor + assistant

Revision ID: 0017
Revises: 0016
"""
from alembic import op

revision = "0017"
down_revision = "0016"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.alter_column("doctor_beta", "phone", nullable=True)
    op.alter_column("assistant_beta", "phone", nullable=True)


def downgrade() -> None:
    op.alter_column("assistant_beta", "phone", nullable=False)
    op.alter_column("doctor_beta", "phone", nullable=False)
```

- [ ] **Step 5: Apply migration locally, run tests**

Run: `ALEMBIC_DB_URL=$TEST_DATABASE_URL alembic upgrade head` then `uv run pytest tests/doctors/test_doctors.py tests/assistants/test_assistants.py -v`
Expected: PASS (the new tests + existing ones; the per-session schema fixture runs `upgrade head`).

- [ ] **Step 6: Commit**

```bash
git add alembic/versions/0017_invite_email_centric.py app/modules/doctors app/modules/assistants tests/doctors tests/assistants
git commit -m "feat(invites): email-centric invites — phone nullable on doctor + assistant (0017)"
```

---

### Task 3: Send the invite email on create

**Files:**
- Modify: `app/modules/doctors/service.py:20-55` (create_doctor), `app/modules/assistants/service.py` (create_assistant)
- Test: `tests/doctors/test_doctors.py`, `tests/assistants/test_assistants.py` (extend)

**Interfaces:**
- Consumes: `app.modules.email.service.send_invite_email`, `settings.app_base_url`, `AppUser.name` (inviter), `Clinic.name`.

- [ ] **Step 1: Write the failing tests**

Add to `tests/doctors/test_doctors.py`:

```python
from unittest.mock import patch


def test_create_doctor_sends_invite_email_when_email_present(auth_client):
    owner, _ = auth_client(sub="bbbb1111-1111-1111-1111-111111111111")
    from tests.conftest import make_clinic
    cid = make_clinic(owner)
    with patch("app.modules.doctors.service.send_invite_email", return_value=True) as send:
        owner.post(f"/api/v1/clinics/{cid}/doctors", json={"name": "Dr Roy", "email": "roy@example.com"})
        send.assert_called_once()
        assert send.call_args.kwargs["to"] == "roy@example.com"
        assert "/invite/" in send.call_args.kwargs["accept_url"]


def test_create_doctor_no_email_does_not_send(auth_client):
    owner, _ = auth_client(sub="bbbb2222-2222-2222-2222-222222222222")
    from tests.conftest import make_clinic
    cid = make_clinic(owner)
    with patch("app.modules.doctors.service.send_invite_email") as send:
        owner.post(f"/api/v1/clinics/{cid}/doctors", json={"name": "Dr NoEmail"})
        send.assert_not_called()


def test_create_doctor_succeeds_even_if_email_raises(auth_client):
    owner, _ = auth_client(sub="bbbb3333-3333-3333-3333-333333333333")
    from tests.conftest import make_clinic
    cid = make_clinic(owner)
    # send_invite_email never raises (Task 1), but guard the call site too:
    with patch("app.modules.doctors.service.send_invite_email", return_value=False):
        resp = owner.post(f"/api/v1/clinics/{cid}/doctors", json={"name": "Dr Roy", "email": "roy@example.com"})
        assert resp.status_code == 201
```

Add the assistant analogues to `tests/assistants/test_assistants.py`.

- [ ] **Step 2: Run, verify fail** (import error / send not called).

Run: `uv run pytest tests/doctors/test_doctors.py -k invite_email -v` → FAIL.

- [ ] **Step 3: Implement the send in `create_doctor`**

In `app/modules/doctors/service.py`, add imports near the top:

```python
from app.core.config import settings
from app.modules.auth.models import AppUser
from app.modules.clinics.models import Clinic
from app.modules.email.service import send_invite_email
```

In `create_doctor`, after `db.refresh(invite)` and before `return`:

```python
    if doctor.email:
        clinic = db.get(Clinic, clinic_id)
        inviter = db.get(AppUser, actor_user_id)
        send_invite_email(
            to=doctor.email,
            clinic_name=clinic.name if clinic else "your clinic",
            inviter_name=inviter.name if inviter else None,
            role="doctor",
            accept_url=f"{settings.app_base_url}/invite/{invite.token}",
            expires_at=invite.expires_at,
        )
```

Mirror in `app/modules/assistants/service.py` `create_assistant` (role="assistant", `assistant.email`). Use local imports if a cycle appears (clinics imports nothing from doctors, so top-level is fine; verify ruff/import at test time).

- [ ] **Step 4: Run, verify PASS.** `uv run pytest tests/doctors tests/assistants -v`

- [ ] **Step 5: Commit**

```bash
git add app/modules/doctors/service.py app/modules/assistants/service.py tests/doctors tests/assistants
git commit -m "feat(invites): send invite email on doctor/assistant create"
```

---

### Task 4: Enriched invite list + display status + role filter + auth helper

**Files:**
- Modify: `app/modules/invites/schemas.py`
- Modify: `app/modules/invites/service.py` (list, helper)
- Modify: `app/modules/invites/router.py` (list signature, gate)
- Test: `tests/invites/test_invite_delivery.py` (new)

**Interfaces:**
- Produces:
  - `InviteRead` (replaces current): `{ id: UUID, invitee_name: str | None, email: str | None, role: str, status: str, created_at: datetime, expires_at: datetime, accepted_at: datetime | None }`.
  - `service.list_invites(db, clinic_id, role: MemberRole | None = None) -> list[dict]` returning enriched dicts (name/email resolved from linked doctor/assistant; `status` derived: a `pending` invite past `expires_at` → `"expired"`).
  - `service.authorize_invite_mgmt(membership, role: MemberRole) -> None` — raises `ForbiddenError` unless: `role == doctor` and membership.role in {owner, assistant}; or `role == assistant` and membership.role == owner; owner always allowed.
- Consumes: `Doctor`, `Assistant` models (for the join); `ForbiddenError` from `app.core.errors`.

- [ ] **Step 1: Write failing tests** (`tests/invites/test_invite_delivery.py`)

```python
import datetime as dt
from datetime import timedelta, timezone

from sqlalchemy import select

from app.modules.invites.models import ClinicInvite


def _owner_clinic(auth_client):
    from tests.conftest import make_clinic
    owner, _ = auth_client(sub="dddd0000-0000-0000-0000-000000000001")
    return owner, make_clinic(owner)


def test_list_invites_enriched_with_name_and_email(auth_client):
    owner, cid = _owner_clinic(auth_client)
    owner.post(f"/api/v1/clinics/{cid}/doctors", json={"name": "Dr Roy", "email": "roy@example.com"})
    rows = owner.get(f"/api/v1/clinics/{cid}/invites?role=doctor").json()
    assert len(rows) == 1
    assert rows[0]["invitee_name"] == "Dr Roy"
    assert rows[0]["email"] == "roy@example.com"
    assert rows[0]["role"] == "doctor"
    assert rows[0]["status"] == "pending"


def test_list_invites_derives_expired_status(auth_client, db_session):
    owner, cid = _owner_clinic(auth_client)
    owner.post(f"/api/v1/clinics/{cid}/doctors", json={"name": "Dr Old", "email": "old@example.com"})
    row = db_session.execute(select(ClinicInvite)).scalars().first()
    row.expires_at = dt.datetime.now(tz=timezone.utc) - timedelta(hours=1)
    db_session.flush()
    rows = owner.get(f"/api/v1/clinics/{cid}/invites?role=doctor").json()
    assert rows[0]["status"] == "expired"


def test_list_role_filter_scopes_results(auth_client):
    owner, cid = _owner_clinic(auth_client)
    owner.post(f"/api/v1/clinics/{cid}/doctors", json={"name": "Dr Roy", "email": "roy@example.com"})
    owner.post(f"/api/v1/clinics/{cid}/assistants", json={"name": "Asha", "email": "asha@example.com"})
    docs = owner.get(f"/api/v1/clinics/{cid}/invites?role=doctor").json()
    asst = owner.get(f"/api/v1/clinics/{cid}/invites?role=assistant").json()
    assert {r["role"] for r in docs} == {"doctor"}
    assert {r["role"] for r in asst} == {"assistant"}
```

- [ ] **Step 2: Run, verify fail.** `uv run pytest tests/invites/test_invite_delivery.py -v`

- [ ] **Step 3: Replace `InviteRead` schema**

`app/modules/invites/schemas.py`:

```python
class InviteRead(BaseModel):
    id: uuid.UUID
    invitee_name: str | None = None
    email: str | None = None
    role: str
    status: str
    created_at: dt.datetime
    expires_at: dt.datetime
    accepted_at: dt.datetime | None = None
```

(Keep `InviteCreate`, `JoinRequest`, `JoinResult`. Remove `token` from `InviteRead`; the token is returned only by the doctor/assistant create result and never listed.)

- [ ] **Step 4: Implement enriched list + helper in `service.py`**

```python
from app.core.errors import ForbiddenError
from app.modules.assistants.models import Assistant
from app.modules.doctors.models import Doctor


def _display_status(inv: ClinicInvite, now: dt.datetime) -> str:
    if inv.status == InviteStatus.pending and inv.expires_at < now:
        return "expired"
    return inv.status.value


def list_invites(db: Session, clinic_id: uuid.UUID, role: MemberRole | None = None) -> list[dict]:
    stmt = select(ClinicInvite).where(ClinicInvite.clinic_id == clinic_id)
    if role is not None:
        stmt = stmt.where(ClinicInvite.role == role)
    invites = list(db.execute(stmt.order_by(ClinicInvite.created_at.desc())).scalars().all())
    now = dt.datetime.now(tz=dt.timezone.utc)
    out = []
    for inv in invites:
        name = None
        if inv.doctor_id:
            d = db.get(Doctor, inv.doctor_id)
            name = d.name if d else None
        elif inv.assistant_id:
            a = db.get(Assistant, inv.assistant_id)
            name = a.name if a else None
        out.append({
            "id": inv.id,
            "invitee_name": name,
            "email": inv.invited_contact,
            "role": inv.role.value,
            "status": _display_status(inv, now),
            "created_at": inv.created_at,
            "expires_at": inv.expires_at,
            "accepted_at": inv.accepted_at,
        })
    return out


def authorize_invite_mgmt(membership, role: MemberRole) -> None:
    if membership.role == MemberRole.owner:
        return
    if role == MemberRole.doctor and membership.role == MemberRole.assistant:
        return
    raise ForbiddenError("Your role is not permitted to manage these invitations.")
```

(Use a local import for `Doctor`/`Assistant` inside `list_invites` if a top-level import creates a cycle.)

> **Important — `invited_contact` must be set on create.** Today `create_invite` does not store the email. In `doctors/service.create_doctor` and `assistants/service.create_assistant`, pass `invited_contact=data.email` into `invites_service.create_invite(...)` (add an `invited_contact: str | None = None` param to `create_invite` and set it on the `ClinicInvite`). Add this in this task so the enriched `email` field is populated. (Tests above assert `email`.)

- [ ] **Step 5: Update the list route + gate** in `app/modules/invites/router.py`

```python
from app.modules.members.deps import CurrentMembership
from app.modules.members.models import MemberRole

@router.get("/{clinic_id}/invites", response_model=list[InviteRead])
def list_invites(
    clinic_id: uuid.UUID,
    db: DbSession,
    membership: CurrentMembership,
    role: MemberRole | None = None,
) -> list[InviteRead]:
    if role is not None:
        service.authorize_invite_mgmt(membership, role)
    else:
        # No role filter → owner-only (sees everything)
        if membership.role != MemberRole.owner:
            from app.core.errors import ForbiddenError
            raise ForbiddenError("Your role is not permitted to manage these invitations.")
    return [InviteRead(**row) for row in service.list_invites(db, clinic_id, role)]
```

- [ ] **Step 6: Run, verify PASS.** `uv run pytest tests/invites -v`

- [ ] **Step 7: Commit**

```bash
git add app/modules/invites tests/invites/test_invite_delivery.py
git commit -m "feat(invites): enriched list with name/email + derived expiry + role filter + auth helper"
```

---

### Task 5: Resend endpoint + per-entity gate on cancel

**Files:**
- Modify: `app/modules/invites/service.py` (resend), `app/modules/invites/router.py` (resend route + cancel gate)
- Test: `tests/invites/test_invite_delivery.py` (extend)

**Interfaces:**
- Consumes: `authorize_invite_mgmt` (Task 4), `send_invite_email` (Task 1).
- Produces: `service.resend_invite(db, *, clinic_id, invite_id, actor_user_id) -> ClinicInvite` — same token, `expires_at = now + 72h`, status → `pending`, audit `clinic_invite.resent`, re-send email; returns the invite. `POST /clinics/{cid}/invites/{id}/resend` → `InviteRead`. `DELETE …/invites/{id}` now applies the per-entity gate.

- [ ] **Step 1: Write failing tests**

```python
def test_resend_keeps_token_extends_expiry_resends(auth_client, db_session):
    from unittest.mock import patch
    owner, cid = _owner_clinic(auth_client)
    owner.post(f"/api/v1/clinics/{cid}/doctors", json={"name": "Dr Roy", "email": "roy@example.com"})
    inv = owner.get(f"/api/v1/clinics/{cid}/invites?role=doctor").json()[0]
    before = db_session.execute(select(ClinicInvite)).scalars().first()
    old_token, old_exp = before.token, before.expires_at
    with patch("app.modules.invites.service.send_invite_email", return_value=True) as send:
        resp = owner.post(f"/api/v1/clinics/{cid}/invites/{inv['id']}/resend")
        assert resp.status_code == 200
        send.assert_called_once()
    after = db_session.execute(select(ClinicInvite)).scalars().first()
    assert after.token == old_token
    assert after.expires_at > old_exp


def test_assistant_can_manage_doctor_invites_but_not_assistant_invites(auth_client):
    # owner sets up clinic + an assistant who has joined
    owner, cid = _owner_clinic(auth_client)
    a_inv = owner.post(f"/api/v1/clinics/{cid}/assistants", json={"name": "Asha", "email": "asha@example.com"})
    a_token = owner.get(f"/api/v1/clinics/{cid}/invites?role=assistant").json()  # owner can list
    # promote: the assistant joins via their invite token
    from sqlalchemy import select as _sel  # token not exposed in list; fetch via create result instead
    # NOTE: capture token from a fresh doctor invite the assistant will manage
    asst = auth_client(sub="dddd9999-9999-9999-9999-999999999999")[0]
    # The assistant must accept their invite; reuse create result token:
    # (Implementer: capture the assistant invite token from the assistants create result.)
```

> Reviewer note: the assistant-permission test needs the assistant's join token. Capture it from the `AssistantCreateResult.invite_token` returned by `POST /assistants`, have a second `auth_client` accept it via `/clinics/join`, then assert that authed assistant can `POST .../invites/{doctorInviteId}/resend` (200) but gets 403 on an assistant invite's resend. Build this concretely from the existing `auth_client` + create-result patterns in `tests/invites/test_invites.py`.

- [ ] **Step 2: Run, verify fail.**

- [ ] **Step 3: Implement `resend_invite`**

```python
def resend_invite(db, *, clinic_id, invite_id, actor_user_id, ttl_hours: int = 72):
    invite = db.get(ClinicInvite, invite_id)
    if invite is None or invite.clinic_id != clinic_id:
        raise InviteError("Invite not found.")
    if invite.status not in (InviteStatus.pending, InviteStatus.expired):
        raise InviteError("Only pending invites can be resent.")
    invite.status = InviteStatus.pending
    invite.expires_at = dt.datetime.now(tz=dt.timezone.utc) + dt.timedelta(hours=ttl_hours)
    record_audit(db, action="clinic_invite.resent", entity_type="clinic_invite",
                 entity_id=invite.id, clinic_id=clinic_id, actor_user_id=actor_user_id)
    db.flush()
    if invite.invited_contact:
        from app.core.config import settings
        from app.modules.auth.models import AppUser
        from app.modules.clinics.models import Clinic
        from app.modules.email.service import send_invite_email
        clinic = db.get(Clinic, clinic_id)
        inviter = db.get(AppUser, actor_user_id)
        send_invite_email(
            to=invite.invited_contact,
            clinic_name=clinic.name if clinic else "your clinic",
            inviter_name=inviter.name if inviter else None,
            role=invite.role.value,
            accept_url=f"{settings.app_base_url}/invite/{invite.token}",
            expires_at=invite.expires_at,
        )
    db.commit()
    db.refresh(invite)
    return invite
```

- [ ] **Step 4: Add the resend route + cancel gate** in `router.py`

```python
@router.post("/{clinic_id}/invites/{invite_id}/resend", response_model=InviteRead)
def resend_invite(clinic_id: uuid.UUID, invite_id: uuid.UUID, db: DbSession, membership: CurrentMembership) -> InviteRead:
    invite = db.get(__import__("app.modules.invites.models", fromlist=["ClinicInvite"]).ClinicInvite, invite_id)
    if invite is None or invite.clinic_id != clinic_id:
        from app.core.errors import NotFoundError
        raise NotFoundError("Invite not found.")
    service.authorize_invite_mgmt(membership, invite.role)
    inv = service.resend_invite(db, clinic_id=clinic_id, invite_id=invite_id, actor_user_id=membership.user_id)
    row = service.list_invites(db, clinic_id)  # reuse enrichment
    match = next(r for r in row if r["id"] == inv.id)
    return InviteRead(**match)
```

> Implementer: prefer a clean top-level `from app.modules.invites.models import ClinicInvite` import over the `__import__` shown above — it's only illustrative. Update the existing `DELETE …/invites/{invite_id}` to fetch the invite, call `service.authorize_invite_mgmt(membership, invite.role)`, then `service.revoke_invite(...)`. Change its `Depends(_can_invite)` to `CurrentMembership`.

- [ ] **Step 5: Run, verify PASS.** `uv run pytest tests/invites -v`

- [ ] **Step 6: Commit**

```bash
git add app/modules/invites tests/invites/test_invite_delivery.py
git commit -m "feat(invites): resend endpoint + per-entity gate on cancel"
```

---

### Task 6: Public invite preview endpoint (no auth)

**Files:**
- Modify: `app/modules/invites/schemas.py` (InvitePreview), `app/modules/invites/service.py` (preview), `app/modules/invites/router.py` (public route)
- Test: `tests/invites/test_invite_delivery.py` (extend)

**Interfaces:**
- Produces: `InvitePreview { clinic_name: str, role: str, inviter_name: str | None, invitee_name: str | None, status: str, expires_at: datetime | None }`. `service.preview_invite(db, token) -> dict` with `status ∈ {valid, expired, accepted, revoked, invalid}`. Route `GET /api/v1/invites/{token}` — **no auth dependency**, returns 200 always (status field carries validity; `invalid` for unknown token).

- [ ] **Step 1: Write failing tests**

```python
def test_preview_valid_invite_is_public(client, auth_client):
    owner, cid = _owner_clinic(auth_client)
    owner.post(f"/api/v1/clinics/{cid}/doctors", json={"name": "Dr Roy", "email": "roy@example.com"})
    from app.modules.invites.models import ClinicInvite
    # fetch token directly from db via a fresh create result instead:
    # (Implementer: capture token from DoctorCreateResult.invite_token returned above.)


def test_preview_unknown_token_returns_invalid(client):
    resp = client.get("/api/v1/invites/does-not-exist")
    assert resp.status_code == 200
    assert resp.json()["status"] == "invalid"
```

> Implementer: for the valid/expired/accepted/revoked cases, capture the token from the `DoctorCreateResult.invite_token` of the create call (it IS returned), then GET `/api/v1/invites/{token}` with the **unauthenticated `client`** fixture and assert `clinic_name == "C"` (the `make_clinic` default), `role == "doctor"`, `status == "valid"`. Flip `expires_at`/`status` in the db to assert `expired`/`revoked`; accept the invite to assert `accepted`.

- [ ] **Step 2: Run, verify fail.**

- [ ] **Step 3: Implement preview**

```python
def preview_invite(db: Session, token: str) -> dict:
    invite = db.execute(select(ClinicInvite).where(ClinicInvite.token == token)).scalar_one_or_none()
    if invite is None:
        return {"clinic_name": "", "role": "", "inviter_name": None, "invitee_name": None,
                "status": "invalid", "expires_at": None}
    now = dt.datetime.now(tz=dt.timezone.utc)
    if invite.status == InviteStatus.accepted:
        status = "accepted"
    elif invite.status == InviteStatus.revoked:
        status = "revoked"
    elif invite.expires_at < now:
        status = "expired"
    else:
        status = "valid"
    from app.modules.assistants.models import Assistant
    from app.modules.auth.models import AppUser
    from app.modules.clinics.models import Clinic
    from app.modules.doctors.models import Doctor
    clinic = db.get(Clinic, invite.clinic_id)
    inviter = db.get(AppUser, invite.created_by)
    name = None
    if invite.doctor_id:
        d = db.get(Doctor, invite.doctor_id); name = d.name if d else None
    elif invite.assistant_id:
        a = db.get(Assistant, invite.assistant_id); name = a.name if a else None
    return {
        "clinic_name": clinic.name if clinic else "",
        "role": invite.role.value,
        "inviter_name": inviter.name if inviter else None,
        "invitee_name": name,
        "status": status,
        "expires_at": invite.expires_at,
    }
```

- [ ] **Step 4: Add public route** (note: prefix is `/clinics`, so add a SECOND router OR mount under a different prefix). Add to `app/modules/invites/router.py`:

```python
public_router = APIRouter(prefix="/invites", tags=["invites"])

@public_router.get("/{token}", response_model=InvitePreview)
def preview(token: str, db: DbSession) -> InvitePreview:
    return InvitePreview(**service.preview_invite(db, token))
```

In `app/main.py`, register it: `from app.modules.invites.router import public_router as invites_public_router` and `app.include_router(invites_public_router, prefix="/api/v1")`. (No auth dependency anywhere on this router.)

- [ ] **Step 5: Run, verify PASS.** `uv run pytest tests/invites -v`

- [ ] **Step 6: Commit**

```bash
git add app/modules/invites app/main.py tests/invites/test_invite_delivery.py
git commit -m "feat(invites): public token preview endpoint for acceptance page"
```

---

## Self-Review (against the spec)
- §4a email module (Resend, httpx, bilingual, no-op, failure-tolerant): Task 1. ✅
- §3 migration 0017 phone nullable + email-centric schemas: Task 2. ✅
- §4b send email on create: Task 3. ✅
- §4b enriched list + derived expiry + role filter; `invited_contact` populated: Task 4. ✅
- §4b resend (same token, extend expiry); cancel exists + gated: Task 5. ✅
- §4b public preview (no auth): Task 6. ✅
- §2 per-entity permissions (helper applied to list/resend/cancel): Tasks 4–5. ✅
- §4b accept via `/clinics/join` unchanged (auto-join is FE): covered by existing tests; no task needed. ✅
- Type consistency: `InviteRead` (no token, has invitee_name/email/status/expires_at/accepted_at) used by list + resend; `InvitePreview` used only by public route; `send_invite_email` signature identical across Tasks 1/3/5. ✅
- Placeholder scan: test scaffolds for the assistant-permission and preview-token cases carry explicit implementer notes (capture token from create result) rather than fake values — these are concrete instructions, not TBDs. ✅
