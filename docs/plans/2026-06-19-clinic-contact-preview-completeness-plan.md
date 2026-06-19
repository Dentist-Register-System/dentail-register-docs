# Clinic Contact Details, Address Preview & Profile Completeness — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Round out the clinic profile on the home clinic card — editable name, contact details (phone required, WhatsApp + email optional), a read-only patient-facing address preview, and an informational profile-completeness indicator.

**Architecture:** Backend extends `clinic_beta` with one `email` column (migration 0008), makes `phone` required on clinic create, and validates the three contact fields; `ClinicRead` now exposes `whatsapp_number` + `email`. Frontend replaces the address-only edit dialog with a unified "Edit clinic details" dialog (Details / Contact / Address sections), adds contact fields to onboarding's create form, and adds two read-only blocks (Address Preview, Profile Completeness) to the home clinic card. Completeness is computed client-side from a pure helper.

**Tech Stack:** Backend — FastAPI, SQLAlchemy 2.x (sync), Pydantic v2, Alembic, pytest (Postgres :5433). Frontend — Next.js App Router, React, TanStack Query, React Hook Form + Zod, react-i18next, Tailwind v4 semantic tokens, Playwright (pure-logic + i18n parity tests; tsc + build are the CI gates).

**Spec:** `docs/specs/2026-06-19-clinic-contact-preview-completeness-design.md` (issue #39).

## Global Constraints

- **Backend migration → Supabase is a controller step, NOT a subagent step.** Implementers validate migrations ONLY via `make test` against local Postgres (:5433). Never run `make migrate`/alembic against Supabase (the repo `.env` points at Supabase). The controller applies 0008 to Supabase via the Supabase MCP `apply_migration` after merge (SQL generated offline with `ALEMBIC_DB_URL=postgresql+psycopg://x:x@localhost/x .venv/bin/alembic upgrade 0007:0008 --sql`).
- **Backend tests** run `alembic upgrade head` to build the schema (`tests/conftest.py`), so migration 0008 is exercised automatically by `make test`.
- **Phone / WhatsApp validation regex (exact):** `^\+?[0-9\s\-().]+$` (matches the existing login phone field). **Email:** standard format. **PIN** validator unchanged (`^[1-9][0-9]{5}$`).
- **Tables use the `_beta` suffix.** Uniform error envelope `{ "error": { "code", "message", "details" } }`. Audit writes happen in the same transaction (existing `record_audit`).
- **Frontend Rule 17.0:** compose existing `components/ui/*` + `components/layout/*`; semantic tokens only (no raw colours, no per-page CSS); both themes; mobile-first; WCAG AA.
- **i18n-first:** every user-facing string via `t()`; add each new key to BOTH `src/i18n/locales/en.json` and `hi.json` (parity enforced by `tests/e2e/i18n.spec.ts`).
- **Permissive-OSS only; never commit secrets. No new dependencies** are needed for this plan.
- **Next.js caveat (`AGENTS.md`):** this Next.js has breaking changes; consult `node_modules/next/dist/docs/` before any framework-level change. (This plan's frontend work is component-level only.)
- Backend repo: `dentist-registry-backend`. Frontend repo: `dentist-registry-frontend`. Commit with trailer `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`. Feature branch → PR (never push `main`).

---

## File Structure

**Backend (`dentist-registry-backend`)**
- Create: `alembic/versions/0008_clinic_email.py` — adds `clinic_beta.email`.
- Modify: `app/modules/clinics/models.py` — add `email` mapped column.
- Modify: `app/modules/clinics/schemas.py` — add `email`; expose `whatsapp_number`+`email` in `ClinicRead`; make `phone` required on create; add contact validators.
- Modify: `app/modules/clinics/service.py` — pass `email` in `create_clinic`.
- Modify: `tests/conftest.py` — `make_clinic` default payload includes `phone`.
- Modify: `tests/clinics/test_address.py` — `_VALID` includes `phone`.
- Create: `tests/clinics/test_contact.py` — contact-field tests.

**Frontend (`dentist-registry-frontend`)**
- Modify: `src/features/clinic/api.ts` — `Clinic` type + create/update payloads gain `phone`/`whatsapp_number`/`email`.
- Create: `src/features/clinic/completeness.ts` — pure completeness helper.
- Create: `src/features/clinic/edit-clinic-details-dialog.tsx` — unified edit dialog (replaces `edit-clinic-address-dialog.tsx`).
- Delete: `src/features/clinic/edit-clinic-address-dialog.tsx`.
- Create: `src/features/clinic/clinic-address-preview.tsx` — read-only preview block.
- Create: `src/features/clinic/clinic-completeness.tsx` — read-only completeness block.
- Modify: `src/app/page.tsx` — wire preview + completeness + new dialog into the clinic card.
- Modify: `src/features/auth/onboarding.tsx` — add contact fields to create form.
- Modify: `src/i18n/locales/en.json` + `src/i18n/locales/hi.json` — new keys + phone placeholder fix.
- Create: `tests/e2e/clinic-completeness.spec.ts` — pure unit test for the helper.

---

## Task 1: Backend — add clinic `email` end-to-end (migration + model + read exposure)

Adds the only new column and exposes the new contact fields on reads. Phone stays optional in this task (made required in Task 2) so existing fixtures keep passing.

**Files:**
- Create: `alembic/versions/0008_clinic_email.py`
- Modify: `app/modules/clinics/models.py`
- Modify: `app/modules/clinics/schemas.py`
- Modify: `app/modules/clinics/service.py`
- Test: `tests/clinics/test_contact.py` (new)

**Interfaces:**
- Produces: `clinic_beta.email` column; `ClinicCreate.email: str | None`, `ClinicUpdate.email: str | None`; `ClinicRead.whatsapp_number: str | None`, `ClinicRead.email: str | None`.

- [ ] **Step 1: Write the failing test**

Create `tests/clinics/test_contact.py`:

```python
"""Tests for clinic contact details (phone, whatsapp, email)."""

OWNER = "11111111-1111-1111-1111-111111111111"

_VALID = {
    "name": "Contact Clinic",
    "phone": "+91 98765 43210",
    "address_line_1": "123 Main Street",
    "area": "Koramangala",
    "city": "Bengaluru",
    "state": "Karnataka",
    "pin_code": "560034",
}


def test_create_persists_and_reads_back_contact_fields(auth_client):
    c, _ = auth_client(sub=OWNER)
    payload = {**_VALID, "whatsapp_number": "+91 90000 11111", "email": "clinic@example.com"}
    created = c.post("/api/v1/clinics", json=payload)
    assert created.status_code == 201, created.text
    clinic_id = created.json()["id"]

    got = c.get(f"/api/v1/clinics/{clinic_id}")
    assert got.status_code == 200, got.text
    body = got.json()
    assert body["phone"] == "+91 98765 43210"
    assert body["whatsapp_number"] == "+91 90000 11111"
    assert body["email"] == "clinic@example.com"


def test_read_exposes_null_contact_fields_when_absent(auth_client):
    c, _ = auth_client(sub=OWNER)
    created = c.post("/api/v1/clinics", json=_VALID)
    assert created.status_code == 201, created.text
    body = c.get(f"/api/v1/clinics/{created.json()['id']}").json()
    assert body["whatsapp_number"] is None
    assert body["email"] is None
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd dentist-registry-backend && make test PYTEST_ARGS="tests/clinics/test_contact.py -v"`
(If `make test` does not forward args, run `.venv/bin/pytest tests/clinics/test_contact.py -v` with the test DB up via `docker compose up -d`.)
Expected: FAIL — `KeyError: 'email'` / `KeyError: 'whatsapp_number'` (Read schema doesn't expose them yet).

- [ ] **Step 3: Write the migration**

Create `alembic/versions/0008_clinic_email.py`:

```python
"""clinic email

Revision ID: 0008
Revises: 0007
"""
from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "0008"
down_revision: str | None = "0007"
branch_labels: Sequence[str] | None = None
depends_on: Sequence[str] | None = None


def upgrade() -> None:
    op.add_column("clinic_beta", sa.Column("email", sa.String(255), nullable=True))


def downgrade() -> None:
    op.drop_column("clinic_beta", "email")
```

- [ ] **Step 4: Add the model column**

In `app/modules/clinics/models.py`, add `email` right after the `whatsapp_number` column:

```python
    whatsapp_number: Mapped[str | None] = mapped_column(String(32), nullable=True)
    email: Mapped[str | None] = mapped_column(String(255), nullable=True)
```

- [ ] **Step 5: Add `email` to Create/Update and expose contact fields on Read**

In `app/modules/clinics/schemas.py`:

In `ClinicCreate`, after the `whatsapp_number` field add:
```python
    email: str | None = Field(default=None, max_length=255)
```
In `ClinicUpdate`, after the `whatsapp_number` field add:
```python
    email: str | None = Field(default=None, max_length=255)
```
In `ClinicRead`, add `whatsapp_number` and `email` (it currently has neither). Place them after `phone`:
```python
    phone: str | None
    whatsapp_number: str | None
    email: str | None
```

- [ ] **Step 6: Persist `email` in the service create path**

In `app/modules/clinics/service.py`, inside `create_clinic`'s `Clinic(...)` constructor, add `email` next to `whatsapp_number`:

```python
        phone=data.phone,
        whatsapp_number=data.whatsapp_number,
        email=data.email,
```
(`update_clinic` already applies arbitrary fields via `model_dump(exclude_unset=True)`, so `email` updates need no service change.)

- [ ] **Step 7: Run the test to verify it passes**

Run: `cd dentist-registry-backend && .venv/bin/pytest tests/clinics/test_contact.py -v`
Expected: PASS (2 passed).

- [ ] **Step 8: Run the full clinic suite (no regressions)**

Run: `.venv/bin/pytest tests/clinics -v`
Expected: PASS (phone still optional, existing tests unaffected).

- [ ] **Step 9: Commit**

```bash
git add alembic/versions/0008_clinic_email.py app/modules/clinics/models.py app/modules/clinics/schemas.py app/modules/clinics/service.py tests/clinics/test_contact.py
git commit -m "feat(clinic): add email column + expose contact fields on read

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: Backend — phone required on create + contact-field validation

Makes `phone` required when creating a clinic and validates phone/WhatsApp/email format on create and update. Updates the two shared fixtures so existing create paths supply a phone.

**Files:**
- Modify: `app/modules/clinics/schemas.py`
- Modify: `tests/conftest.py`
- Modify: `tests/clinics/test_address.py`
- Test: `tests/clinics/test_contact.py` (extend)

**Interfaces:**
- Consumes: schemas/columns from Task 1.
- Produces: `ClinicCreate.phone: str` (required, validated); `_PHONE_RE`, `_EMAIL_RE` module constants; validators on `ClinicCreate` and `ClinicUpdate` for `phone`/`whatsapp_number`/`email`.

- [ ] **Step 1: Update shared fixtures to include phone**

In `tests/conftest.py`, add `phone` to the shared address payload so `make_clinic` succeeds once phone is required:

```python
_VALID_ADDRESS = {
    "phone": "+91 98765 43210",
    "address_line_1": "123 Main Street",
    "area": "Koramangala",
    "city": "Bengaluru",
    "state": "Karnataka",
    "pin_code": "560034",
}
```

In `tests/clinics/test_address.py`, add `phone` to the `_VALID` dict (right after `"name"`):

```python
_VALID = {
    "name": "Test Clinic",
    "phone": "+91 98765 43210",
    "address_line_1": "123 Main Street",
    "area": "Koramangala",
    "city": "Bengaluru",
    "state": "Karnataka",
    "pin_code": "560034",
}
```

- [ ] **Step 2: Write the failing tests**

Append to `tests/clinics/test_contact.py`:

```python
def test_create_fails_without_phone(auth_client):
    c, _ = auth_client(sub=OWNER)
    payload = {k: v for k, v in _VALID.items() if k != "phone"}
    assert c.post("/api/v1/clinics", json=payload).status_code == 422


def test_create_fails_with_invalid_phone(auth_client):
    c, _ = auth_client(sub=OWNER)
    assert c.post("/api/v1/clinics", json={**_VALID, "phone": "call-me"}).status_code == 422


def test_create_fails_with_invalid_whatsapp(auth_client):
    c, _ = auth_client(sub=OWNER)
    assert c.post("/api/v1/clinics", json={**_VALID, "whatsapp_number": "abc"}).status_code == 422


def test_create_fails_with_invalid_email(auth_client):
    c, _ = auth_client(sub=OWNER)
    assert c.post("/api/v1/clinics", json={**_VALID, "email": "not-an-email"}).status_code == 422


def test_create_succeeds_with_valid_contact(auth_client):
    c, _ = auth_client(sub=OWNER)
    payload = {**_VALID, "whatsapp_number": "+91 90000 11111", "email": "clinic@example.com"}
    assert c.post("/api/v1/clinics", json=payload).status_code == 201
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `.venv/bin/pytest tests/clinics/test_contact.py -v`
Expected: the four new failure-expecting tests FAIL (currently `phone` is optional and unvalidated → those posts return 201).

- [ ] **Step 4: Add validators and make phone required**

In `app/modules/clinics/schemas.py`, add module constants near `_PIN_RE`/`_URL_RE`:

```python
_PHONE_RE = re.compile(r"^\+?[0-9\s\-().]+$")
_EMAIL_RE = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")
```

In `ClinicCreate`, change `phone` to required and add validators:

```python
class ClinicCreate(BaseModel):
    name: str = Field(min_length=1, max_length=200)
    phone: str = Field(min_length=1, max_length=32)
    whatsapp_number: str | None = Field(default=None, max_length=32)
    email: str | None = Field(default=None, max_length=255)
    # ... existing address fields unchanged ...

    @field_validator("phone")
    @classmethod
    def validate_phone(cls, v: str) -> str:
        if not _PHONE_RE.match(v):
            raise ValueError("phone must be a valid phone number.")
        return v

    @field_validator("whatsapp_number")
    @classmethod
    def validate_whatsapp(cls, v: str | None) -> str | None:
        if v is not None and v != "" and not _PHONE_RE.match(v):
            raise ValueError("whatsapp_number must be a valid phone number.")
        return v

    @field_validator("email")
    @classmethod
    def validate_email(cls, v: str | None) -> str | None:
        if v is not None and v != "" and not _EMAIL_RE.match(v):
            raise ValueError("email must be a valid email address.")
        return v
```
(Keep the existing `validate_pin_code` and `validate_google_maps_url` validators.)

In `ClinicUpdate`, keep `phone` optional but add the same three validators (phone optional variant):

```python
    @field_validator("phone")
    @classmethod
    def validate_phone(cls, v: str | None) -> str | None:
        if v is not None and v != "" and not _PHONE_RE.match(v):
            raise ValueError("phone must be a valid phone number.")
        return v

    @field_validator("whatsapp_number")
    @classmethod
    def validate_whatsapp(cls, v: str | None) -> str | None:
        if v is not None and v != "" and not _PHONE_RE.match(v):
            raise ValueError("whatsapp_number must be a valid phone number.")
        return v

    @field_validator("email")
    @classmethod
    def validate_email(cls, v: str | None) -> str | None:
        if v is not None and v != "" and not _EMAIL_RE.match(v):
            raise ValueError("email must be a valid email address.")
        return v
```

- [ ] **Step 5: Run the contact tests to verify they pass**

Run: `.venv/bin/pytest tests/clinics/test_contact.py -v`
Expected: PASS (all contact tests).

- [ ] **Step 6: Run the full backend suite (fixtures updated → no regressions)**

Run: `make test`
Expected: PASS — the updated `make_clinic` / `_VALID` fixtures now supply a phone everywhere a clinic is created.

- [ ] **Step 7: Lint**

Run: `make lint`
Expected: clean.

- [ ] **Step 8: Commit**

```bash
git add app/modules/clinics/schemas.py tests/conftest.py tests/clinics/test_address.py tests/clinics/test_contact.py
git commit -m "feat(clinic): require phone on create + validate contact fields

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

> **Controller (post-merge, NOT the implementer):** generate `alembic upgrade 0007:0008 --sql` offline and apply to Supabase via Supabase MCP `apply_migration`. Confirm `alembic_version` = `0008`.

---

## Task 3: Frontend — extend Clinic types + API payloads

**Files:**
- Modify: `src/features/clinic/api.ts`

**Interfaces:**
- Produces: `Clinic` type gains `phone?`, `whatsapp_number?`, `email?`; `createClinic`/`updateClinic` payloads accept the three contact fields.

- [ ] **Step 1: Add a contact type and extend `Clinic`**

In `src/features/clinic/api.ts`, add a `ClinicContact` type and fold it into `Clinic`, and widen the create/update payloads:

```typescript
export type ClinicContact = {
  phone?: string;
  whatsapp_number?: string;
  email?: string;
};

export type Clinic = {
  id: string;
  name: string;
} & ClinicAddress & ClinicContact;

export const createClinic = (
  payload: { name: string } & Omit<ClinicAddress, "formatted_address"> & ClinicContact,
) =>
  apiFetch<Clinic>("/api/v1/clinics", {
    method: "POST",
    body: JSON.stringify(payload),
  });

export const updateClinic = (
  clinicId: string,
  payload: Partial<Omit<ClinicAddress, "formatted_address"> & ClinicContact & { name?: string }>,
) =>
  apiFetch<Clinic>("/api/v1/clinics/" + clinicId, {
    method: "PATCH",
    body: JSON.stringify(payload),
  });
```

- [ ] **Step 2: Type-check**

Run: `cd dentist-registry-frontend && npx tsc --noEmit`
Expected: PASS (no errors).

- [ ] **Step 3: Commit**

```bash
git add src/features/clinic/api.ts
git commit -m "feat(clinic): add contact fields to Clinic type and payloads

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: Frontend — i18n keys + India phone placeholder fix

**Files:**
- Modify: `src/i18n/locales/en.json`
- Modify: `src/i18n/locales/hi.json`

**Interfaces:**
- Produces translation keys used by Tasks 5–8: `clinic.editDetails`, `clinic.editDetailsTitle`, `clinic.editDetailsDescription`, `clinic.detailsSection`, `clinic.contactSection`, `clinic.addressSection`, `clinic.nameLabel`, `clinic.phoneLabel`, `clinic.phonePlaceholder`, `clinic.whatsappLabel`, `clinic.whatsappPlaceholder`, `clinic.emailLabel`, `clinic.emailPlaceholder`, `clinic.phoneDisplayLabel`, `clinic.whatsappDisplayLabel`, `clinic.emailDisplayLabel`, `clinic.addressPreviewTitle`, `clinic.addressPreviewHint`, `clinic.completeness.*`, `validation.whatsappInvalid`.

- [ ] **Step 1: Fix the phone placeholder (India)**

In `src/i18n/locales/en.json`, change the login phone placeholder:
```json
      "phonePlaceholder": "+91 98765 43210",
```
(Path: `auth.login.phonePlaceholder`. `hi.json` is already `"+91 98765 43210"`.)

- [ ] **Step 2: Replace the `clinic` block (en)**

In `src/i18n/locales/en.json`, replace the existing `"clinic": { ... }` block with:

```json
  "clinic": {
    "yourClinic": "Your Clinic",
    "clinicLabel": "Clinic",
    "roleLabel": "Role",
    "formattedAddressLabel": "Address",
    "directions": "Directions",
    "editDetails": "Edit clinic details",
    "editDetailsTitle": "Edit Clinic Details",
    "editDetailsDescription": "Update your clinic's name, contact details, and address.",
    "detailsSection": "Details",
    "contactSection": "Contact",
    "addressSection": "Address",
    "nameLabel": "Clinic name",
    "namePlaceholder": "Bright Smiles Dental",
    "phoneLabel": "Phone number",
    "phonePlaceholder": "+91 98765 43210",
    "whatsappLabel": "WhatsApp number",
    "whatsappPlaceholder": "+91 98765 43210",
    "emailLabel": "Email",
    "emailPlaceholder": "clinic@example.com",
    "phoneDisplayLabel": "Phone",
    "whatsappDisplayLabel": "WhatsApp",
    "emailDisplayLabel": "Email",
    "addressPreviewTitle": "Address Preview",
    "addressPreviewHint": "This is how your clinic will appear to patients.",
    "completeness": {
      "title": "Clinic Profile",
      "percent": "{{percent}}% complete",
      "name": "Clinic Name",
      "address": "Address",
      "phone": "Phone Number",
      "whatsapp": "WhatsApp Number",
      "email": "Email"
    }
  },
```

- [ ] **Step 3: Replace the `clinic` block (hi)**

In `src/i18n/locales/hi.json`, replace the existing `"clinic": { ... }` block with:

```json
  "clinic": {
    "yourClinic": "आपका क्लिनिक",
    "clinicLabel": "क्लिनिक",
    "roleLabel": "भूमिका",
    "formattedAddressLabel": "पता",
    "directions": "दिशा-निर्देश",
    "editDetails": "क्लिनिक विवरण संपादित करें",
    "editDetailsTitle": "क्लिनिक विवरण संपादित करें",
    "editDetailsDescription": "अपने क्लिनिक का नाम, संपर्क विवरण और पता अपडेट करें।",
    "detailsSection": "विवरण",
    "contactSection": "संपर्क",
    "addressSection": "पता",
    "nameLabel": "क्लिनिक का नाम",
    "namePlaceholder": "ब्राइट स्माइल्स डेंटल",
    "phoneLabel": "फ़ोन नंबर",
    "phonePlaceholder": "+91 98765 43210",
    "whatsappLabel": "व्हाट्सऐप नंबर",
    "whatsappPlaceholder": "+91 98765 43210",
    "emailLabel": "ईमेल",
    "emailPlaceholder": "clinic@example.com",
    "phoneDisplayLabel": "फ़ोन",
    "whatsappDisplayLabel": "व्हाट्सऐप",
    "emailDisplayLabel": "ईमेल",
    "addressPreviewTitle": "पता पूर्वावलोकन",
    "addressPreviewHint": "मरीज़ों को आपका क्लिनिक इस तरह दिखाई देगा।",
    "completeness": {
      "title": "क्लिनिक प्रोफ़ाइल",
      "percent": "{{percent}}% पूर्ण",
      "name": "क्लिनिक का नाम",
      "address": "पता",
      "phone": "फ़ोन नंबर",
      "whatsapp": "व्हाट्सऐप नंबर",
      "email": "ईमेल"
    }
  },
```

- [ ] **Step 4: Add the WhatsApp validation key**

In `src/i18n/locales/en.json`, in the `validation` block (next to `phoneInvalid`), add:
```json
    "whatsappInvalid": "Enter a valid WhatsApp number",
```
In `src/i18n/locales/hi.json`, add:
```json
    "whatsappInvalid": "मान्य व्हाट्सऐप नंबर दर्ज करें",
```
(`validation.phoneRequired`, `phoneInvalid`, `emailInvalid`, `clinicNameRequired` already exist in both files.)

- [ ] **Step 5: Verify key parity + non-empty values**

Run: `cd dentist-registry-frontend && npx playwright test tests/e2e/i18n.spec.ts`
Expected: PASS — `hi` has the same keys as `en`, and all `en` values are non-empty. (This spec runs as pure assertions; no dev server needed. If Playwright browsers aren't installed it still runs these node-side tests; if the run can't start, fall back to `node -e "const en=require('./src/i18n/locales/en.json'); const hi=require('./src/i18n/locales/hi.json'); const kp=(o,p='')=>Object.entries(o).flatMap(([k,v])=>v&&typeof v==='object'?kp(v,p+k+'.'):[p+k]); const a=new Set(kp(en)),b=new Set(kp(hi)); const miss=[...a].filter(x=>!b.has(x)).concat([...b].filter(x=>!a.has(x))); if(miss.length){console.error('MISMATCH',miss);process.exit(1)} console.log('parity OK')"`.)

- [ ] **Step 6: Commit**

```bash
git add src/i18n/locales/en.json src/i18n/locales/hi.json
git commit -m "i18n(clinic): contact/preview/completeness keys + India phone placeholder

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: Frontend — unified "Edit clinic details" dialog

Replaces the address-only dialog with one dialog covering Details (name), Contact (phone required, WhatsApp + email optional), and Address (existing fields).

**Files:**
- Create: `src/features/clinic/edit-clinic-details-dialog.tsx`
- Delete: `src/features/clinic/edit-clinic-address-dialog.tsx`
- Modify: `src/app/page.tsx` (import + usage)

**Interfaces:**
- Consumes: `useClinic`, `useUpdateClinic` (`src/features/clinic/hooks.ts`); keys from Task 4.
- Produces: `EditClinicDetailsDialog({ clinicId }: { clinicId: string })`.

- [ ] **Step 1: Create the unified dialog**

Create `src/features/clinic/edit-clinic-details-dialog.tsx`:

```tsx
"use client";

import { zodResolver } from "@hookform/resolvers/zod";
import { useEffect, useState } from "react";
import { useForm } from "react-hook-form";
import { useTranslation } from "react-i18next";
import { z } from "zod";

import { Button, buttonVariants } from "@/components/ui/button";
import {
  DialogClose,
  DialogDescription,
  DialogPopup,
  DialogRoot,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";
import {
  Form,
  FormControl,
  FormField,
  FormItem,
  FormLabel,
  FormMessage,
} from "@/components/ui/form";
import { Icon } from "@/components/ui/icon";
import { Input } from "@/components/ui/input";
import { ApiError } from "@/lib/api-client";
import { useClinic, useUpdateClinic } from "@/features/clinic/hooks";

const PHONE_RE = /^\+?[0-9\s\-().]+$/;

const _schemaStatic = z.object({
  name: z.string().min(1),
  phone: z.string().min(1),
  whatsapp_number: z.string().optional(),
  email: z.string().optional(),
  address_line_1: z.string().min(1),
  address_line_2: z.string().optional(),
  landmark: z.string().optional(),
  area: z.string().min(1),
  city: z.string().min(1),
  state: z.string().min(1),
  pin_code: z.string().min(1),
  google_maps_url: z.string().optional(),
});
type EditValues = z.infer<typeof _schemaStatic>;

function getApiErrorCode(error: unknown): string | null {
  if (error instanceof ApiError) return error.code;
  return null;
}

interface EditClinicDetailsDialogProps {
  clinicId: string;
}

export function EditClinicDetailsDialog({ clinicId }: EditClinicDetailsDialogProps) {
  const { t } = useTranslation();
  const clinic = useClinic(clinicId);
  const updateClinic = useUpdateClinic(clinicId);
  const [open, setOpen] = useState(false);

  const schema = z.object({
    name: z.string().min(1, t("validation.clinicNameRequired")),
    phone: z
      .string()
      .min(1, t("validation.phoneRequired"))
      .regex(PHONE_RE, t("validation.phoneInvalid")),
    whatsapp_number: z
      .string()
      .regex(PHONE_RE, t("validation.whatsappInvalid"))
      .optional()
      .or(z.literal("")),
    email: z
      .string()
      .email(t("validation.emailInvalid"))
      .optional()
      .or(z.literal("")),
    address_line_1: z.string().min(1, t("validation.addressLine1Required")),
    address_line_2: z.string().optional(),
    landmark: z.string().optional(),
    area: z.string().min(1, t("validation.areaRequired")),
    city: z.string().min(1, t("validation.cityRequired")),
    state: z.string().min(1, t("validation.stateRequired")),
    pin_code: z
      .string()
      .min(1, t("validation.pinCodeRequired"))
      .regex(/^[1-9][0-9]{5}$/, t("validation.pinCodeInvalid")),
    google_maps_url: z
      .string()
      .url(t("validation.mapsUrlInvalid"))
      .optional()
      .or(z.literal("")),
  });

  const defaults = (): EditValues => ({
    name: clinic.data?.name ?? "",
    phone: clinic.data?.phone ?? "",
    whatsapp_number: clinic.data?.whatsapp_number ?? "",
    email: clinic.data?.email ?? "",
    address_line_1: clinic.data?.address_line_1 ?? "",
    address_line_2: clinic.data?.address_line_2 ?? "",
    landmark: clinic.data?.landmark ?? "",
    area: clinic.data?.area ?? "",
    city: clinic.data?.city ?? "",
    state: clinic.data?.state ?? "",
    pin_code: clinic.data?.pin_code ?? "",
    google_maps_url: clinic.data?.google_maps_url ?? "",
  });

  const form = useForm<EditValues>({ resolver: zodResolver(schema), defaultValues: defaults() });

  useEffect(() => {
    if (clinic.data && open) form.reset(defaults());
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [clinic.data, open]);

  function onSubmit(values: EditValues) {
    const payload: Record<string, string> = {
      name: values.name,
      phone: values.phone,
      address_line_1: values.address_line_1,
      area: values.area,
      city: values.city,
      state: values.state,
      pin_code: values.pin_code,
    };
    if (values.whatsapp_number) payload.whatsapp_number = values.whatsapp_number;
    if (values.email) payload.email = values.email;
    if (values.address_line_2) payload.address_line_2 = values.address_line_2;
    if (values.landmark) payload.landmark = values.landmark;
    if (values.google_maps_url) payload.google_maps_url = values.google_maps_url;
    updateClinic.mutate(payload, { onSuccess: () => setOpen(false) });
  }

  function handleOpenChange(nextOpen: boolean) {
    setOpen(nextOpen);
    if (!nextOpen) {
      form.reset();
      updateClinic.reset();
    }
  }

  const sectionTitle = "text-sm font-medium text-muted-foreground";
  const optional = (
    <span className="ml-1 text-xs text-muted-foreground">({t("common.optional")})</span>
  );

  function textField(
    name: keyof EditValues,
    label: React.ReactNode,
    placeholder: string,
    testid: string,
  ) {
    return (
      <FormField
        control={form.control}
        name={name}
        render={({ field }) => (
          <FormItem>
            <FormLabel>{label}</FormLabel>
            <FormControl>
              <Input placeholder={placeholder} data-testid={testid} {...field} />
            </FormControl>
            <FormMessage />
          </FormItem>
        )}
      />
    );
  }

  return (
    <DialogRoot open={open} onOpenChange={handleOpenChange}>
      <DialogTrigger
        className={buttonVariants({ variant: "outlined", size: "default" })}
        data-testid="edit-clinic-details-button"
      >
        <Icon name="edit" size={18} aria-hidden />
        {t("clinic.editDetails")}
      </DialogTrigger>

      <DialogPopup>
        <DialogTitle>{t("clinic.editDetailsTitle")}</DialogTitle>
        <DialogDescription className="sr-only">
          {t("clinic.editDetailsDescription")}
        </DialogDescription>

        <Form {...form}>
          <form
            onSubmit={form.handleSubmit(onSubmit)}
            className="mt-4 space-y-4"
            data-testid="edit-clinic-details-form"
          >
            <p className={sectionTitle}>{t("clinic.detailsSection")}</p>
            {textField("name", t("clinic.nameLabel"), t("clinic.namePlaceholder"), "edit-clinic-name")}

            <p className={sectionTitle}>{t("clinic.contactSection")}</p>
            {textField("phone", t("clinic.phoneLabel"), t("clinic.phonePlaceholder"), "edit-clinic-phone")}
            {textField("whatsapp_number", <>{t("clinic.whatsappLabel")}{optional}</>, t("clinic.whatsappPlaceholder"), "edit-clinic-whatsapp")}
            {textField("email", <>{t("clinic.emailLabel")}{optional}</>, t("clinic.emailPlaceholder"), "edit-clinic-email")}

            <p className={sectionTitle}>{t("clinic.addressSection")}</p>
            {textField("address_line_1", t("onboarding.addressLine1Label"), t("onboarding.addressLine1Placeholder"), "edit-clinic-address-line1")}
            {textField("address_line_2", <>{t("onboarding.addressLine2Label")}{optional}</>, t("onboarding.addressLine2Placeholder"), "edit-clinic-address-line2")}
            {textField("landmark", <>{t("onboarding.landmarkLabel")}{optional}</>, t("onboarding.landmarkPlaceholder"), "edit-clinic-landmark")}
            {textField("area", t("onboarding.areaLabel"), t("onboarding.areaPlaceholder"), "edit-clinic-area")}
            {textField("city", t("onboarding.cityLabel"), t("onboarding.cityPlaceholder"), "edit-clinic-city")}
            {textField("state", t("onboarding.stateLabel"), t("onboarding.statePlaceholder"), "edit-clinic-state")}
            {textField("pin_code", t("onboarding.pinCodeLabel"), t("onboarding.pinCodePlaceholder"), "edit-clinic-pin")}
            {textField("google_maps_url", <>{t("onboarding.mapsUrlLabel")}{optional}</>, t("onboarding.mapsUrlPlaceholder"), "edit-clinic-maps-url")}

            {updateClinic.isError && (
              <p className="text-sm text-destructive" data-testid="edit-clinic-details-error">
                {(() => {
                  const code = getApiErrorCode(updateClinic.error);
                  return code
                    ? t(`apiErrors.${code}`, { defaultValue: t("apiErrors.default") })
                    : t("apiErrors.default");
                })()}
              </p>
            )}

            <div className="flex gap-2 justify-end">
              <DialogClose
                className={buttonVariants({ variant: "ghost", size: "sm" })}
                data-testid="cancel-edit-details-button"
              >
                {t("common.cancel")}
              </DialogClose>
              <Button
                type="submit"
                disabled={updateClinic.isPending}
                data-testid="save-clinic-details-button"
              >
                {t("patients.save")}
              </Button>
            </div>
          </form>
        </Form>
      </DialogPopup>
    </DialogRoot>
  );
}
```

- [ ] **Step 2: Swap the import/usage in the home page**

In `src/app/page.tsx`:
- Replace the import line
  `import { EditClinicAddressDialog } from "@/features/clinic/edit-clinic-address-dialog";`
  with
  `import { EditClinicDetailsDialog } from "@/features/clinic/edit-clinic-details-dialog";`
- Replace the usage `<EditClinicAddressDialog clinicId={clinicId} />` with `<EditClinicDetailsDialog clinicId={clinicId} />`.

- [ ] **Step 3: Delete the old dialog**

```bash
git rm src/features/clinic/edit-clinic-address-dialog.tsx
```

- [ ] **Step 4: Type-check + build**

Run: `npx tsc --noEmit && npm run build`
Expected: PASS (no references to the deleted file remain).

- [ ] **Step 5: Commit**

```bash
git add src/features/clinic/edit-clinic-details-dialog.tsx src/app/page.tsx
git commit -m "feat(clinic): unified edit-clinic-details dialog (name + contact + address)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 6: Frontend — onboarding create form gains required phone + optional WhatsApp/email

**Files:**
- Modify: `src/features/auth/onboarding.tsx`

**Interfaces:**
- Consumes: keys from Task 4; `createClinic` payload from Task 3.

- [ ] **Step 1: Extend the create schema + defaults**

In `src/features/auth/onboarding.tsx`, add `phone`/`whatsapp_number`/`email` to the static schema, the runtime `createSchema`, and `defaultValues`.

Static schema (after `name`):
```tsx
  name: z.string().min(1),
  phone: z.string().min(1),
  whatsapp_number: z.string().optional(),
  email: z.string().optional(),
```
Runtime `createSchema` (after `name`):
```tsx
    name: z.string().min(1, t("validation.clinicNameRequired")),
    phone: z
      .string()
      .min(1, t("validation.phoneRequired"))
      .regex(/^\+?[0-9\s\-().]+$/, t("validation.phoneInvalid")),
    whatsapp_number: z
      .string()
      .regex(/^\+?[0-9\s\-().]+$/, t("validation.whatsappInvalid"))
      .optional()
      .or(z.literal("")),
    email: z
      .string()
      .email(t("validation.emailInvalid"))
      .optional()
      .or(z.literal("")),
```
`defaultValues` (after `name: ""`):
```tsx
      name: "",
      phone: "",
      whatsapp_number: "",
      email: "",
```

- [ ] **Step 2: Include contact fields in the submit payload**

In `onSubmit`, after `name: values.name,` add `phone: values.phone,` to the base payload, and after the `name` assignment add the optionals:
```tsx
    const payload: Parameters<typeof createClinic.mutate>[0] = {
      name: values.name,
      phone: values.phone,
      address_line_1: values.address_line_1,
      area: values.area,
      city: values.city,
      state: values.state,
      pin_code: values.pin_code,
    };
    if (values.whatsapp_number) payload.whatsapp_number = values.whatsapp_number;
    if (values.email) payload.email = values.email;
    if (values.address_line_2) payload.address_line_2 = values.address_line_2;
    if (values.landmark) payload.landmark = values.landmark;
    if (values.google_maps_url) payload.google_maps_url = values.google_maps_url;
```

- [ ] **Step 3: Render the contact fields**

In `CreateClinicForm`, add a Contact section between the clinic-name field and the `{/* Clinic Address section */}` comment:

```tsx
        {/* Clinic Contact section */}
        <p className="text-sm font-medium text-muted-foreground">
          {t("clinic.contactSection")}
        </p>

        <FormField
          control={form.control}
          name="phone"
          render={({ field }) => (
            <FormItem>
              <FormLabel>{t("clinic.phoneLabel")}</FormLabel>
              <FormControl>
                <Input
                  placeholder={t("clinic.phonePlaceholder")}
                  data-testid="clinic-phone"
                  {...field}
                />
              </FormControl>
              <FormMessage />
            </FormItem>
          )}
        />

        <FormField
          control={form.control}
          name="whatsapp_number"
          render={({ field }) => (
            <FormItem>
              <FormLabel>
                {t("clinic.whatsappLabel")}
                <span className="ml-1 text-xs text-muted-foreground">
                  ({t("common.optional")})
                </span>
              </FormLabel>
              <FormControl>
                <Input
                  placeholder={t("clinic.whatsappPlaceholder")}
                  data-testid="clinic-whatsapp"
                  {...field}
                />
              </FormControl>
              <FormMessage />
            </FormItem>
          )}
        />

        <FormField
          control={form.control}
          name="email"
          render={({ field }) => (
            <FormItem>
              <FormLabel>
                {t("clinic.emailLabel")}
                <span className="ml-1 text-xs text-muted-foreground">
                  ({t("common.optional")})
                </span>
              </FormLabel>
              <FormControl>
                <Input
                  placeholder={t("clinic.emailPlaceholder")}
                  data-testid="clinic-email"
                  {...field}
                />
              </FormControl>
              <FormMessage />
            </FormItem>
          )}
        />
```

- [ ] **Step 4: Type-check + build**

Run: `npx tsc --noEmit && npm run build`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/features/auth/onboarding.tsx
git commit -m "feat(onboarding): require clinic phone + optional WhatsApp/email on create

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 7: Frontend — Address Preview block

**Files:**
- Create: `src/features/clinic/clinic-address-preview.tsx`
- Modify: `src/app/page.tsx`

**Interfaces:**
- Consumes: `Clinic` type (Task 3); keys from Task 4.
- Produces: `ClinicAddressPreview({ clinic }: { clinic: Clinic })`.

- [ ] **Step 1: Create the preview component**

Create `src/features/clinic/clinic-address-preview.tsx`:

```tsx
"use client";

import { useTranslation } from "react-i18next";

import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Icon } from "@/components/ui/icon";
import type { Clinic } from "@/features/clinic/api";

interface ClinicAddressPreviewProps {
  clinic: Clinic;
  clinicName: string;
}

export function ClinicAddressPreview({ clinic, clinicName }: ClinicAddressPreviewProps) {
  const { t } = useTranslation();
  if (!clinic.formatted_address) return null;

  return (
    <Card className="shadow-elevation-1" data-testid="clinic-address-preview">
      <CardHeader>
        <div className="flex items-center gap-3">
          <span className="flex size-10 items-center justify-center rounded-xl bg-primary-container">
            <Icon name="visibility" size={22} className="text-on-primary-container" aria-hidden />
          </span>
          <div>
            <CardTitle>{t("clinic.addressPreviewTitle")}</CardTitle>
            <CardDescription>{t("clinic.addressPreviewHint")}</CardDescription>
          </div>
        </div>
      </CardHeader>
      <CardContent>
        <div className="rounded-lg bg-muted/50 px-4 py-3">
          <p className="text-sm font-semibold text-foreground" data-testid="preview-clinic-name">
            {clinicName}
          </p>
          <pre
            className="mt-1 whitespace-pre-line text-sm text-foreground"
            data-testid="preview-formatted-address"
          >
            {clinic.formatted_address}
          </pre>
          {clinic.google_maps_url && (
            <a
              href={clinic.google_maps_url}
              target="_blank"
              rel="noopener noreferrer"
              className="mt-2 inline-block text-sm font-medium text-primary underline-offset-4 hover:underline"
              data-testid="preview-directions-link"
            >
              {t("clinic.directions")}
            </a>
          )}
        </div>
      </CardContent>
    </Card>
  );
}
```

- [ ] **Step 2: Render it on the home page**

In `src/app/page.tsx`, add the import:
```tsx
import { ClinicAddressPreview } from "@/features/clinic/clinic-address-preview";
```
Inside the `<section data-testid="clinic-shell">`, after the clinic summary `</Card>` (the one ending at the current line ~144) and before `</section>`, add:
```tsx
          {clinic.data && (
            <ClinicAddressPreview
              clinic={clinic.data}
              clinicName={membership?.clinic_name ?? clinic.data.name}
            />
          )}
```

- [ ] **Step 3: Type-check + build**

Run: `npx tsc --noEmit && npm run build`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add src/features/clinic/clinic-address-preview.tsx src/app/page.tsx
git commit -m "feat(clinic): patient-facing address preview block

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 8: Frontend — Profile Completeness (pure helper + block + unit test)

**Files:**
- Create: `src/features/clinic/completeness.ts`
- Create: `src/features/clinic/clinic-completeness.tsx`
- Create: `tests/e2e/clinic-completeness.spec.ts`
- Modify: `src/app/page.tsx`

**Interfaces:**
- Consumes: `Clinic` type (Task 3); keys `clinic.completeness.*` (Task 4).
- Produces: `computeClinicCompleteness(clinic): { items: { key: CompletenessKey; present: boolean }[]; percent: number }`; `type CompletenessKey = "name" | "address" | "phone" | "whatsapp" | "email"`; `ClinicCompleteness({ clinic })`.

- [ ] **Step 1: Write the failing unit test**

Create `tests/e2e/clinic-completeness.spec.ts`:

```typescript
import { test, expect } from "@playwright/test";

import { computeClinicCompleteness } from "../../src/features/clinic/completeness";

const FULL = {
  id: "1",
  name: "Bright Smiles",
  phone: "+91 98765 43210",
  whatsapp_number: "+91 90000 11111",
  email: "clinic@example.com",
  address_line_1: "Shop 4",
  area: "Baner",
  city: "Pune",
  state: "Maharashtra",
  pin_code: "411045",
  formatted_address: "Shop 4\nBaner\nPune, Maharashtra - 411045",
} as const;

test("full profile is 100% with all items present", () => {
  const r = computeClinicCompleteness(FULL);
  expect(r.percent).toBe(100);
  expect(r.items.every((i) => i.present)).toBe(true);
});

test("missing optional fields lower the percentage but never block", () => {
  const r = computeClinicCompleteness({ ...FULL, whatsapp_number: "", email: "" });
  expect(r.percent).toBe(60); // 3 of 5
  expect(r.items.find((i) => i.key === "whatsapp")?.present).toBe(false);
  expect(r.items.find((i) => i.key === "email")?.present).toBe(false);
});

test("address counts as present only when all required address fields exist", () => {
  const r = computeClinicCompleteness({ ...FULL, pin_code: "" });
  expect(r.items.find((i) => i.key === "address")?.present).toBe(false);
});

test("empty clinic is 0%", () => {
  const r = computeClinicCompleteness({ id: "1", name: "" });
  expect(r.percent).toBe(0);
});
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd dentist-registry-frontend && npx playwright test tests/e2e/clinic-completeness.spec.ts`
Expected: FAIL — `computeClinicCompleteness` not found / module missing.

- [ ] **Step 3: Implement the pure helper**

Create `src/features/clinic/completeness.ts`:

```typescript
import type { Clinic } from "@/features/clinic/api";

export type CompletenessKey = "name" | "address" | "phone" | "whatsapp" | "email";

export interface CompletenessItem {
  key: CompletenessKey;
  present: boolean;
}

export interface CompletenessResult {
  items: CompletenessItem[];
  percent: number;
}

function filled(value: string | undefined | null): boolean {
  return typeof value === "string" && value.trim().length > 0;
}

export function computeClinicCompleteness(clinic: Partial<Clinic>): CompletenessResult {
  const addressPresent =
    filled(clinic.address_line_1) &&
    filled(clinic.area) &&
    filled(clinic.city) &&
    filled(clinic.state) &&
    filled(clinic.pin_code);

  const items: CompletenessItem[] = [
    { key: "name", present: filled(clinic.name) },
    { key: "address", present: addressPresent },
    { key: "phone", present: filled(clinic.phone) },
    { key: "whatsapp", present: filled(clinic.whatsapp_number) },
    { key: "email", present: filled(clinic.email) },
  ];

  const present = items.filter((i) => i.present).length;
  const percent = Math.round((present / items.length) * 100);
  return { items, percent };
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `npx playwright test tests/e2e/clinic-completeness.spec.ts`
Expected: PASS (4 passed).

- [ ] **Step 5: Build the completeness block**

Create `src/features/clinic/clinic-completeness.tsx`:

```tsx
"use client";

import { useTranslation } from "react-i18next";

import {
  Card,
  CardContent,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Icon } from "@/components/ui/icon";
import type { Clinic } from "@/features/clinic/api";
import { computeClinicCompleteness } from "@/features/clinic/completeness";

interface ClinicCompletenessProps {
  clinic: Partial<Clinic>;
}

export function ClinicCompleteness({ clinic }: ClinicCompletenessProps) {
  const { t } = useTranslation();
  const { items, percent } = computeClinicCompleteness(clinic);

  return (
    <Card className="shadow-elevation-1" data-testid="clinic-completeness">
      <CardHeader>
        <div className="flex items-center justify-between gap-3">
          <CardTitle>{t("clinic.completeness.title")}</CardTitle>
          <span
            className="text-sm font-semibold text-primary"
            data-testid="completeness-percent"
          >
            {t("clinic.completeness.percent", { percent })}
          </span>
        </div>
      </CardHeader>
      <CardContent>
        <ul className="space-y-2">
          {items.map((item) => (
            <li
              key={item.key}
              className="flex items-center gap-2 text-sm text-foreground"
              data-testid={`completeness-item-${item.key}`}
            >
              <Icon
                name={item.present ? "check_circle" : "radio_button_unchecked"}
                size={18}
                className={item.present ? "text-primary" : "text-muted-foreground"}
                aria-hidden
              />
              <span>{t(`clinic.completeness.${item.key}`)}</span>
            </li>
          ))}
        </ul>
      </CardContent>
    </Card>
  );
}
```

- [ ] **Step 6: Render it on the home page**

In `src/app/page.tsx`, add the import:
```tsx
import { ClinicCompleteness } from "@/features/clinic/clinic-completeness";
```
Inside `<section data-testid="clinic-shell">`, after the `ClinicAddressPreview` block from Task 7, add:
```tsx
          {clinic.data && <ClinicCompleteness clinic={clinic.data} />}
```

- [ ] **Step 7: Type-check + build + re-run the unit test**

Run: `npx tsc --noEmit && npm run build && npx playwright test tests/e2e/clinic-completeness.spec.ts`
Expected: all PASS.

- [ ] **Step 8: Commit**

```bash
git add src/features/clinic/completeness.ts src/features/clinic/clinic-completeness.tsx tests/e2e/clinic-completeness.spec.ts src/app/page.tsx
git commit -m "feat(clinic): profile completeness indicator (helper + block + tests)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Final Verification (before PRs)

- [ ] Backend: `cd dentist-registry-backend && make test && make lint` → all green.
- [ ] Frontend: `cd dentist-registry-frontend && npx tsc --noEmit && npm run build` → clean.
- [ ] Frontend: `npx playwright test tests/e2e/i18n.spec.ts tests/e2e/clinic-completeness.spec.ts` → pass.
- [ ] Open two PRs (backend, frontend) with closing keyword `Closes Dentist-Register-System/dentail-register-docs#39`; set Project #1 Status → In Review.
- [ ] **Controller-only:** apply migration 0008 to Supabase via Supabase MCP `apply_migration`; verify `alembic_version` = `0008`.

## Self-Review (against the spec)

- **§3 data model (email column, migration 0008):** Task 1. ✅
- **§4 API (email on create/update/read; whatsapp+email on read; phone required; validators):** Tasks 1–2. ✅
- **§5 completeness (5 items, percent, client-side, never blocks):** Task 8 (helper + block + tests). ✅
- **§6 frontend (unified edit dialog, onboarding phone, address preview, completeness, Clinic type, phone placeholder):** Tasks 3–8. ✅
- **§7 permissions (owner/PM edit; all members view):** edit affordance stays role-gated in `page.tsx` (existing `['owner','practice_manager']` guard around the dialog, unchanged); preview + completeness render for all members. ✅
- **§8 testing (validation, read exposure, required phone, preview, completeness calc + reactivity, unauthorized rejected, i18n parity):** backend Tasks 1–2 + `test_address.py`'s existing unauthorized-PATCH test; frontend Tasks 4 & 8 + reactivity via TanStack Query invalidation in `useUpdateClinic` (unchanged). ✅
- **Placeholder scan:** no TBD/TODO; every code step has complete code. ✅
- **Type consistency:** `computeClinicCompleteness` / `CompletenessKey` / `CompletenessResult` names match across Tasks 8's test, helper, and component; `EditClinicDetailsDialog` prop name `clinicId` matches the `page.tsx` usage; `Clinic` contact fields defined in Task 3 are consumed in Tasks 5/7/8. ✅
