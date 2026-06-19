# Manual Clinic Address (V1) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development. Steps use `- [ ]` checkboxes.

**Goal:** Capture a structured manual clinic address in onboarding + a clinic-profile edit, generate/store a `formatted_address`, for future WhatsApp confirmations. NO maps/geocoding/3rd-party location.

**Spec:** `docs/specs/2026-06-19-clinic-address-design.md` · **Requirement:** issue #37.

## Global Constraints
- Backend: feature-first, sync SQLAlchemy 2.x, `_beta` tables, enums via raw DDL, audit in-transaction (single commit), RLS, uniform error envelope (stable codes). Tests on Postgres :5433. **Do NOT run `make migrate`/alembic against Supabase** (`.env` DATABASE_URL = live Supabase) — validate via `make test` (local); the controller applies migration 0007 to Supabase via MCP.
- Frontend: Material 3 framework (Golden Rule 17.0 — reuse tokens/components/templates, **no per-page CSS**, semantic tokens only), i18n-first (en+hi parity), a11y AA both themes, mobile-first. Don't clobber `.env.local`.
- Permissive-OSS only; no secrets. Backend `main` is at migration 0006; this adds 0007.

---

### Task 1: Backend — clinic address model + migration 0007 + create/edit + formatted address
**Files:** `app/modules/clinics/models.py` (extend `Clinic`, drop `address`), `schemas.py` (address fields + validators), `service.py` (`create_clinic` requires address + computes `formatted_address`; add `update_clinic`/profile edit), `router.py` (extend `POST /clinics`; add `GET`/`PATCH /clinics/{id}`); `alembic/versions/0007_clinic_address.py`; `tests/clinics/test_address.py`.

- [ ] **Step 1 — Model:** add to `Clinic`: `address_line_1`, `address_line_2`, `landmark`, `area`, `city`, `state` (String), `pin_code` (String(6)), `formatted_address` (Text), `google_maps_url` (String). Remove the old `address` column. (DB-nullable; required enforced in schema.)
- [ ] **Step 2 — Migration 0007** (`down_revision=0006`): `add_column` the new fields, `drop_column('clinic_beta','address')`; reversible downgrade. Validate via `make test` only (NOT Supabase).
- [ ] **Step 3 — Schemas + validators:** `ClinicAddress` (or extend `ClinicCreate`): required `address_line_1/area/city/state/pin_code`; `pin_code` matches `^[1-9][0-9]{5}$`; `google_maps_url` optional, valid-URL if present (pydantic `HttpUrl`/`AnyUrl` or a regex). `ClinicUpdate` for edits. `ClinicRead` includes all address fields + `formatted_address`.
- [ ] **Step 4 — Service:** `build_formatted_address(...)` (the §4 template, skipping blanks); `create_clinic` persists address + sets `formatted_address`; `update_clinic(clinic_id, data, actor)` (owner/PM) edits + recomputes `formatted_address` + audits `clinic.updated` (before/after), single commit.
- [ ] **Step 5 — Router:** extend `POST /clinics` payload; add `GET /clinics/{id}` (members) and `PATCH /clinics/{id}` (`require_role(owner, practice_manager)`). Thin.
- [ ] **Step 6 — Tests:** onboarding fails w/o required fields / invalid PIN / invalid URL (422); succeeds → `formatted_address` exactly correct (with + without optional fields, asserting blank lines are skipped); PATCH edits + recomputes; non-owner/PM PATCH → 403; audit row present. `make test` green, `make lint` clean.
- [ ] **Step 7 — Commit:** `feat(clinics): structured clinic address + formatted_address + profile edit (migration 0007)`.

---

### Task 2: Frontend — onboarding address fields + home clinic-card display & edit
**Files:** `src/features/clinic/api.ts` + `hooks.ts` (clinic create payload + `useUpdateClinic`/`fetchClinic`), `src/features/auth/onboarding.tsx` (add address section to Create-clinic), `src/app/page.tsx` (home clinic card: show `formatted_address` + Directions link + Edit), a new `src/features/clinic/edit-clinic-address-dialog.tsx`, `src/i18n/locales/{en,hi}.json`; `tests/e2e/` (onboarding + clinic-edit).

- [ ] **Step 1 — API/hooks:** extend `createClinic` to send the address fields; add `fetchClinic(id)` + `useUpdateClinic(id)` (PATCH, invalidate `["me"]`/clinic). Types include the address fields + `formatted_address`.
- [ ] **Step 2 — Onboarding:** add the **Clinic Address** section to the Create-clinic form (Address Line 1, Line 2, Landmark, Area, City, State, PIN, Maps link) — RHF + Zod built with `t()` (required + PIN regex + optional-URL); M3 TextFields; required to submit. Reuse the AuthShell/centered onboarding layout — no new styles.
- [ ] **Step 3 — Home clinic card:** show `formatted_address` (preserve line breaks) + a **Directions** link when `google_maps_url` is set; add an **Edit clinic address** action (owner/PM only) opening `edit-clinic-address-dialog.tsx` (same fields/validation) → `useUpdateClinic`.
- [ ] **Step 4 — i18n:** all new copy (field labels/placeholders, validation messages, "Edit clinic address", "Directions", dialog copy) in BOTH en.json + hi.json (parity).
- [ ] **Step 5 — Verify:** `npx tsc --noEmit && npm run build` clean; extend e2e (onboarding requires/submits address; edit flow; i18n parity). Run `npm run test:e2e -- <specs> i18n.spec.ts`.
- [ ] **Step 6 — Commit:** `feat(clinic): clinic address in onboarding + home clinic-card display & edit`.

---

## Docs (this docs PR)
Update `Entities/01-clinic.md` (structured address + formatted_address), `Entities/02-clinic-settings.md` (address is on the clinic, not settings), PRD (clinic profile & manual address, V1).

## Self-review
Spec coverage: §3 model → T1.S1-2; §4 formatted → T1.S4; §5 API → T1.S4-5; §6 frontend → T2; §7 validation → T1.S3 + T2.S2; §8 perms → T1.S5; §9 tests → T1.S6 + T2.S5. Migration applied to Supabase by controller via MCP (not by the implementer).
