# Clinic Contact Details, Address Preview & Profile Completeness — Design Spec

> Status: Draft for review · Date: 2026-06-19 · Requirement source: issue #39
> Scope: a small usability/onboarding enhancement to the clinic profile. NO appointment/scheduling/notification/messaging workflows. NO Google Maps / Places / geocoding / embedded maps / third-party location provider. Builds on the manual clinic address feature (#37, `docs/specs/2026-06-19-clinic-address-design.md`).

---

## 1. Context & Purpose
The clinic profile today (home clinic card) captures name + structured manual address (#37). This slice rounds out the clinic profile so owners can keep **complete, accurate clinic information** and verify how it will appear to patients:

1. **Clinic contact details** — phone (required), WhatsApp (optional), email (optional).
2. **Address Preview** — a read-only "this is what patients will see" block (clinic name + formatted address + directions link).
3. **Profile Completeness** — an informational checklist + percentage nudging owners to fill missing fields (never blocks).
4. Plus: **editable clinic name** and a small India-first phone-placeholder polish.

The address preview represents information that will later appear in patient-facing communications (appointment confirmations/reminders). Those communications are **not** built here.

## 2. Scope Decisions (locked)
- **Surface:** everything lives on the existing **home (`/`) clinic card**. No new route. When #35 User Settings is built, this clinic-profile block migrates into Settings → Clinic profile. (Consistent with the #37 decision.)
- **Unified edit:** today's address-only dialog becomes a single **"Edit clinic details"** dialog with grouped sections — *Details* (name), *Contact* (phone / WhatsApp / email), *Address* (existing structured fields). Replaces the address-only dialog.
- **Phone is required** — enforced both in the edit form **and in onboarding** (`POST /clinics`). `clinic_beta.phone` already exists (nullable at DB level); required is enforced at the API/validation layer (non-breaking for the one existing test clinic; Completeness flags any pre-existing null-phone clinic).
- **WhatsApp & email optional** — validated only if provided.
- **Completeness is computed client-side** from clinic fields — no new backend endpoint.
- **Validation matches existing conventions** (see §6). No strict E.164 / Indian-10-digit rule (none exists in the codebase today).
- Out of scope: clinic timings, doctor schedules, maps/geocoding/embedded maps, and any appointment/notification/WhatsApp/email **sending** workflow. The active "complete your clinic details" sticky in-app notification is tracked separately (issue #40, gated on the in-app notifications system).

## 3. Data Model — `clinic_beta` (migration 0008)
Already present (from #37 / SP1): `phone` (String 32, nullable), `whatsapp_number` (String 32, nullable), all address fields + `formatted_address`.

Add one column:
- **`email`** — `String(255)`, nullable.

Migration **0008** adds `email` only. Applied to Supabase via the MCP `apply_migration` (SQL generated offline with `alembic upgrade 0007:0008 --sql`, including the `alembic_version` bump). Implementer subagents validate via `make test` against local Postgres (:5433) **only** — never run alembic against Supabase.

## 4. API
- **`POST /api/v1/clinics`** (onboarding create): `ClinicCreate` makes **`phone` required** (+ format validation); add **`email`** (optional, validated). `whatsapp_number` already accepted (optional, validated).
- **`PATCH /api/v1/clinics/{id}`** (edit): `ClinicUpdate` adds **`email`**; phone/whatsapp/email format validation when present; owner/practice_manager only (existing role gate); audit `clinic.updated` (existing behavior).
- **`GET /api/v1/clinics/{id}`**: `ClinicRead` adds **`whatsapp_number`** and **`email`** (currently `ClinicRead` exposes neither — frontend cannot display them today).

### Validation (backend, matching existing patterns in `clinics/schemas.py`)
- **Phone / WhatsApp:** permissive regex `^\+?[0-9\s\-().]+$` (same shape as the login phone field). Phone required & non-empty on create; whatsapp optional.
- **Email:** standard email format (module-level compiled regex, mirroring the existing `_PIN_RE` / `_URL_RE` constants), validated only when provided.
- Existing PIN + `google_maps_url` validators unchanged.

## 5. Profile Completeness (client-side)
Five criteria evaluated from the clinic record:

| Item | Present when |
|---|---|
| Clinic Name | `name` non-empty |
| Address | required address fields present (`address_line_1`, `area`, `city`, `state`, `pin_code`) |
| Phone | `phone` non-empty |
| WhatsApp | `whatsapp_number` non-empty |
| Email | `email` non-empty |

UI: a checklist with ✓ (present) / ○ (missing) per item + a **percentage** = present ÷ 5, rounded. Informational only — never blocks the app or creates requirements beyond onboarding. Optional and required fields both contribute positively.

## 6. Frontend (M3 framework, Rule 17.0)
- **Edit clinic details dialog** (owner/practice_manager) — unified RHF + Zod form, sections *Details* / *Contact* / *Address*, reusing existing `ui/*` (Dialog, Form, TextField/Input, Button) + the existing address fields/validation. Zod mirrors backend: phone required + permissive regex, whatsapp optional, email optional + email check. `PATCH`es the clinic; on success invalidates `["me"]` + `["clinic", id]`.
- **Onboarding "Create a new clinic"** — add a **required phone** field (+ optional WhatsApp/email) to the create form, validated to submit.
- **Address Preview block** (read-only, all members) — titled "Address Preview", shows clinic **name** + `formatted_address` + a "Directions" link when `google_maps_url` set. Frames the existing card data as the patient-facing preview.
- **Profile Completeness block** (read-only, all members) — checklist + percentage per §5.
- **`Clinic` type (frontend `features/clinic/api.ts`)** — add `phone`, `whatsapp_number`, `email` so the card can display them.
- **Phone placeholder polish:** `en.json` `auth.login.phonePlaceholder` `"+1 555 000 0000"` → `"+91 98765 43210"` (India; Hindi already correct). One key, reused by login/patient/doctor/assistant/clinic phone fields.

### i18n / a11y / theming
All new labels, placeholders, validation messages, checklist/preview copy via `t()` in **both** en + hi (key parity, enforced by `tests/e2e/i18n.spec.ts`). Both themes, mobile-first, WCAG AA, semantic tokens only, compose framework components (no per-page CSS).

## 7. Permissions
Only owner/practice_manager create/edit clinic contact details (existing role pattern). All clinic members may view the Address Preview and Completeness blocks.

## 8. Testing
- **Backend:** phone required on create; phone/WhatsApp/email format validation (valid + invalid); `email` round-trips create→read; `ClinicRead` exposes `whatsapp_number` + `email`; PATCH updates contact fields; unauthorized (non-owner/PM) update rejected (403); reuse `make_clinic` test helper (note: it now must pass a phone since create requires it).
- **Frontend:** completeness calculation across field combinations + reactivity when fields change; address preview rendering (present/absent directions); unified edit dialog validation (required phone, optional whatsapp/email); role-gated edit affordance; i18n en/hi key parity.

## 9. Docs to update (this PR)
- **`PRD/PRD_v3_1_Founder_Edition.md`** — extend the Clinic Profile section with contact details, address preview, and profile completeness.
- **`Entities/01-clinic.md`** — add clinic `email`; note address preview + profile completeness as clinic-profile concepts.

## 10. Out of Scope (explicit)
Clinic timings · doctor schedules · Google Maps/Places/geocoding/embedded maps · appointment workflows · notification workflows · WhatsApp/email **sending** · the sticky in-app "complete your clinic details" notification (issue #40, gated on in-app notifications).
