# Team Table (search / filter / sort / pagination) — Design Spec

**Status:** Approved (brainstorm 2026-06-23; sub-issue #106 of #25; UI from the approved Assistants mockup). System-wide: **backend + frontend + docs** (no DB migration). Register Design System, Rule 17.0, i18n-first.
**Type:** Turn the Team tab's current simple list (on both Doctors & Assistants pages) into the full mockup table: server-side **search**, **status filter**, **role/specialty filter**, **sortable columns**, **pagination (10/page)**, and a **⋯ row menu** (Edit · Activate/Deactivate · Remove).

## 1. Goal
Make a clinic's staff list usable at scale: find a member by name/email/role, narrow by status, sort, page through, and act on a row — without leaving the Team tab. Built within the tabbed shell that #25 already shipped.

## 2. Scope decisions (locked in brainstorm)
- **Server-side** search/filter/sort/pagination (user choice), via a **dedicated paginated endpoint** per entity — see §4. (Rationale: the existing full-list endpoint feeds dropdowns/overview that must keep returning everything; a separate paginated endpoint avoids silently capping them.)
- **Sortable columns** (name · joined · status), asc/desc, default **joined desc**; **10 per page**.
- **Filters:** a search box (`q`), a **status** dropdown (Active/Inactive/Invited/All), and a **role/specialty** filter (assistant `title` / doctor `specialty`).
- **⋯ row menu:** **Edit** (dialog) · **Activate/Deactivate** (status toggle) · **Remove** (delete) — all this slice; all reuse existing write endpoints (no new ones).
- **Both** Doctors & Assistants pages, this slice.
- **No DB migration** — purely query params + UI.
- New shared **`dropdown-menu`** UI primitive (we lack any menu/popover today); reusable beyond this.
- The **Edit** dialog is built so #107's profile drawer can reuse it.

## 3. Data model
No changes. Reuses `doctor_beta` / `assistant_beta` and their existing statuses (`invited`/`active`/`inactive`).

## 4. Backend (no migration)
Mirror the Requests list pattern (`RequestListPage {items, total}`, scheduling #89).

- **New endpoint `GET /clinics/{clinic_id}/doctors/page`** → `DoctorListPage { items: DoctorRead[], total: int }`. Query params:
  - `q: str | None` — ILIKE over `name`, `email`, `specialty`.
  - `status: DoctorStatus | None` — filter (omit = all).
  - `specialty: str | None` — ILIKE filter on specialty (the "role/specialty filter").
  - `sort: "name" | "joined" | "status"` (default `joined`), `order: "asc" | "desc"` (default `desc`).
  - `page: int` (default 1, ≥1), `page_size: int` (default 10, 1–100).
  - Returns the page slice + the **total count before** limit/offset (for the pager). Clinic-scoped. Role-gated identically to the existing list (`CurrentMembership`, i.e. any active member can read; mutations stay owner/assistant-gated).
- **New endpoint `GET /clinics/{clinic_id}/assistants/page`** → `AssistantListPage { items: AssistantRead[], total: int }`. Same params; `q` over `name`/`email`/`title`; the role filter is `title` (ILIKE).
- **Existing `GET /clinics/{id}/doctors` and `…/assistants` are UNCHANGED** (still return the full `list[…Read]`) — they keep powering the Overview summary card, `doctor-picker`, and `requests-filters` dropdowns. No consumer breakage.
- **⋯ actions reuse existing endpoints** (no new writes): Edit → `PATCH …/{id}`; Activate/Deactivate → `PATCH …/{id}` with `status`; Remove → `DELETE …/{id}` (already guards active/linked members with `CannotDeleteActiveMemberError`). Permissions unchanged (#91: doctors manage = owner+assistant; assistants manage = owner).
- **Schemas:** `DoctorListPage`/`AssistantListPage` (`{items, total}`); a shared `_VALID_SORTS`/`_VALID_ORDERS` const + validation (invalid → 422).
- **Tests (pytest):** q matches across all configured columns; status filter; specialty/title filter; each sort+order; pagination (total-before-limit correct, page slice correct, page 2); empty result; invalid sort/order → 422; clinic-scoping (other clinic's members excluded); the full-list endpoint still returns everything (regression guard).

## 5. Frontend
### 5a. Data layer
- `doctors/api.ts` + `assistants/api.ts`: add `DoctorListPage`/`AssistantListPage` types and `fetchDoctorsPage(clinicId, params)` / `fetchAssistantsPage(clinicId, params)` (params: `q, status, specialty|role, sort, order, page, page_size`). Leave existing `fetchDoctors`/`fetchAssistants` (full list) untouched.
- `hooks.ts`: `useDoctorsPage(clinicId, params)` / `useAssistantsPage(clinicId, params)` — `useQuery` keyed on `["doctors-page", clinicId, params]` (params object in the key), `placeholderData: keepPreviousData` so paging/sorting doesn't flash. Existing `useDoctors`/`useAssistants` unchanged.

### 5b. `dropdown-menu` primitive
- New `src/components/ui/dropdown-menu.tsx` — a small accessible menu (trigger + items, keyboard nav, focus ring, semantic tokens, both themes). Built on the same base-ui primitive family already used by `tabs`/`dialog` if available; else a minimal popover. Exports `DropdownMenu*` parts. testids passthrough.

### 5c. Team table upgrade
- Rebuild `doctor-team-table.tsx` / `assistant-team-table.tsx` to consume the paginated hook:
  - **Toolbar:** debounced search input (`q`, ~300ms), status `<select>` (All/Active/Inactive/Invited), role/specialty filter input/select. testids `team-search`, `team-status-filter`, `team-role-filter`.
  - **Table:** columns Name · Role(specialty/title) · Phone · Joined · Status · Actions. **Sortable headers** (name/joined/status) toggle asc/desc with an indicator. Status via `Badge` (existing variants). Dates via the shared `formatDate` util.
  - **⋯ menu** per row (the new primitive): **Edit** → opens the edit dialog; **Activate/Deactivate** → `useUpdate…` status mutation (label depends on current status; invited rows show neither or "Cancel invite"→ out of scope, keep to active/inactive toggle); **Remove** → confirm → `useDelete…` (surfaces `cannot_delete_active_member` as a friendly error). testids `team-row-actions`, `team-edit`, `team-toggle-status`, `team-remove`.
  - **Pager:** "Showing X–Y of N" + prev/next (and page size shown as 10). testids `team-pager`, `team-page-next/prev`.
  - Loading / empty / error states; preserve existing testids the e2e suite uses (`doctors-section`, `doctor-row-*`, etc.).
- **Edit dialog** (`src/features/doctors/edit-member-dialog.tsx` or shared): a form pre-filled from the row (name, phone, email, specialty/title) → `PATCH`. Built generic enough for #107's drawer to reuse.

### 5d. Cross-cutting
- i18n en+hi parity for all new strings (`team.*` — search placeholder, filter labels, status options, actions, pager, confirm-remove). Rule 17.0 semantic tokens, both themes, mobile-first, WCAG AA.
- **Render on :8753** of the upgraded Team table (toolbar + sortable table + ⋯ menu + pager) — **user sign-off before building**.

## 6. Quality
- Backend: `uv run ruff check .` clean; `make test` green (new pagination/filter/sort tests); no migration.
- Frontend: `tsc --noEmit` + `npm run build` + i18n parity; e2e for search/filter/sort/paginate + ⋯ actions (mocked). FE PR **held for user QA**; backend merges on green.
- Render-before-build sign-off; never merge red; `gh-personal`; branch→PR→squash+delete.

## 7. Scope guards / deferred
- Member **profile drawer** (Overview/Permissions/Activity) → #107/#108/#109. The Edit dialog here is shared so the drawer reuses it.
- No bulk actions, no CSV export, no column show/hide (YAGNI).
- "Cancel invite" from the Team table is out of scope (invite lifecycle lives in the Invites tab).
- Sortable beyond name/joined/status not included.

## 8. Self-review (against #106 + the mockup)
- Server-side search/status/role-specialty filter + sortable columns + pagination 10/page: §2/§4/§5. ✅
- ⋯ menu Edit · Activate/Deactivate · Remove (delete included per user): §2/§5c. ✅
- Both Doctors & Assistants: §4/§5. ✅
- No silent dropdown breakage (separate paginated endpoint; full-list endpoint untouched): §4. ✅
- New dropdown-menu primitive; Edit dialog reusable by #107: §5b/§5c. ✅
- No migration; reuse existing write endpoints + #91 permissions: §3/§4. ✅
- Render-before-build + Rule 17.0 + i18n + tests: §5d/§6. ✅
- Placeholder scan: concrete endpoints/params/schemas/testids; no TBD. ✅
