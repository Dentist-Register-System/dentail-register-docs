# Manual Clinic Address (V1) — Design Spec

> Status: Draft for review · Date: 2026-06-19 · Requirement source: issue #37
> Scope: a small, dependency-free clinic-address feature. NO Google Maps / Places / geocoding / autocomplete / embedded maps / any third-party location provider.

---

## 1. Context & Purpose
Capture a **structured, manual** clinic address during owner onboarding and let owners edit it later. On save, generate + store a **formatted address string** on the clinic. This is consumed later (SP5/SP6) in patient **WhatsApp appointment confirmations** (clinic name + formatted address + optional directions link). The value is a clean address + optional directions link — not smart geocoding.

## 2. Scope Decisions (locked)
- **Extend `clinic_beta`** with the structured fields + `formatted_address` + `google_maps_url`. **Drop the existing unused `address` string** column (added in SP1, never populated). Migration **0007**.
- **Onboarding `POST /clinics` requires a valid address** — onboarding cannot complete without it. The backend **computes + stores `formatted_address`** on create/update (single source of truth).
- **Editing:** an "Edit clinic address" action on the **home clinic card** (owner/practice_manager) for now; this **relocates into Settings → Clinic profile** when #35 is built.
- **State** = free-text (V1, keep simple). **PIN** = 6-digit Indian PIN. **`google_maps_url`** = optional; if present, validate it looks like a URL (not required to be a Google URL in V1).
- Out of scope: everything in issue #37 §7 (maps/places/geocoding/autocomplete/embedded map/location picker/etc.). Manual + dependency-free.

## 3. Data Model — extend `clinic_beta` (migration 0007)
Add (all on the clinic): `address_line_1` (req), `address_line_2` (opt), `landmark` (opt), `area` (req), `city` (req), `state` (req), `pin_code` (req, 6-digit), `formatted_address` (computed, stored), `google_maps_url` (opt). **Remove** the old `address` column. Existing rows: the migration backfills new required columns as nullable-then-populated is not needed (only one test clinic; treat as a clean V1 — make the structured columns nullable at the DB level but **enforce required at the API/validation layer**, so the migration is non-breaking and the app guarantees completeness on write).

## 4. Formatted Address (backend-generated)
On create/update, compute and store:
```
{address_line_1}
{address_line_2}            # omit line if blank
Landmark: {landmark}        # omit line if blank
{area}
{city}, {state} - {pin_code}
```
Skip blank optional fields cleanly — never emit an empty line or a dangling label.

## 5. API
- **`POST /api/v1/clinics`** — extend the create payload with the address fields; **require** the required ones + valid PIN + optional-URL check; compute/store `formatted_address`; (owner = creator). Onboarding 422s if address invalid/missing.
- **`GET /api/v1/clinics/{id}`** — returns the clinic incl. address fields + `formatted_address`.
- **`PATCH /api/v1/clinics/{id}`** — edit clinic profile/address; **owner/practice_manager only**; recompute `formatted_address`; audit `clinic.updated` (before/after). (Add this endpoint — SP1 only had clinic create + settings.)

## 6. Frontend (M3 framework, Rule 17.0)
- **Onboarding → Create a new clinic:** add the address section (Address Line 1, Address Line 2, Landmark, Area, City, State, PIN, Maps link) with validation; required to submit. RHF + Zod with `t()`; M3 TextFields; reuse the framework.
- **Home clinic card:** show the clinic's `formatted_address` (+ a "Directions" link if `google_maps_url`), and an **Edit clinic address** action (owner/PM) → an M3 dialog/form using the same fields/validation → `PATCH`.
- i18n: all labels/placeholders/validation/copy in en + hi (parity). Both themes; mobile-first; a11y.

## 7. Validation
Required non-empty: `address_line_1, area, city, state, pin_code`. PIN: `^[1-9][0-9]{5}$` (6-digit Indian PIN). `google_maps_url`: optional; if present, valid-URL check. Stable backend error codes (`validation_error`); frontend Zod mirrors.

## 8. Permissions
Create: clinic creator (owner). Edit: owner/practice_manager (existing `require_role`). Others 403.

## 9. Testing
Backend: onboarding fails without required fields / invalid PIN / invalid URL; succeeds with valid → `formatted_address` correct; optional fields skipped cleanly in the formatted string; PATCH edits + recomputes; non-owner/PM cannot edit (403); audit row written. Frontend: onboarding requires + submits address; home card shows formatted address + edit flow; i18n parity.

## 10. Acceptance (mirrors issue #37)
Onboarding requires a valid clinic address; formatted address generated correctly with optional fields skipped; owner can edit later; unauthorized cannot edit; invalid PIN/URL rejected; no maps/geocoding/3rd-party location anything; data stored on the clinic for future WhatsApp confirmations.

## 11. Docs updated alongside
`Entities/01-clinic.md` (structured address fields + formatted_address), `Entities/02-clinic-settings.md` (note: address lives on the clinic, not settings), PRD (clinic profile & manual address, V1).
