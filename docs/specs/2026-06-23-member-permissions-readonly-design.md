# Member Permissions — Read-only "What this member can do" view — Design Spec (#108)

**Status:** Approved in brainstorm (2026-06-23). Sub-issue **#108** of the invitation epic **#25**; activates the drawer's **Permissions tab** (rendered disabled in #107). System scope: **backend + frontend + docs** (NO database migration). Register Design System (Rule 17.0), i18n-first.

**Type:** Turn the member profile drawer's Permissions tab into a **read-only, plain-language view of what a given member can do in the clinic** — for every role including the owner. It is a *transparency* surface (show, don't configure), derived from the member's role + the existing clinic settings. **No per-member permission model, no new settings, no migration.**

---

## 1. Goal

When someone opens a teammate's Permissions tab their real question is *"what can this person do here — and if they can't do something, why?"*. #108 answers exactly that:

- A clear, grouped, read-only list of capabilities, each shown **Allowed** or **Not allowed + a one-line reason**.
- Capabilities are **derived from the single source of truth (backend authz)** — role + the existing clinic settings — never re-implemented in the frontend, so the view can never disagree with real enforcement.
- Where a capability is blocked **by a clinic setting**, the owner (and only the owner) gets a pointer to the one place to change it (**Settings → Scheduling**). Everyone else sees the reason only — no dead-end controls.

### Non-goals (explicitly out of scope)
- **No per-member permission toggles / grants.** (This was #125, **closed as not-planned** 2026-06-23 — per-assistant differentiation is intentionally not built; all assistants follow the clinic-wide policy.)
- **No new settings, no new columns, no migration.**
- **No writes of any kind** from this tab. It is purely informational.
- The **Activity tab** remains #109 (separate audit-read work).

---

## 2. Scope decisions (locked in brainstorm 2026-06-23)

1. **Read-only view, all roles incl. owner.** The owner's own tab shows everything Allowed. The tab is shown for the *viewed* member (the drawer's subject), not the viewer.
2. **6 capabilities / 3 groups** (see §3). Bundled so the list stays glanceable while remaining accurate.
3. **Backend-computed, authoritative.** A reusable resolver `resolve_capabilities(role, settings)` underlies a read endpoint; the FE renders and translates **stable reason/note codes** (i18n contract — backend never ships display English).
4. **Two flavors of "Not allowed":** *role-inherent* (just explained) vs *setting-gated* (explained **+** owner-only Settings pointer).
5. **Owner-doctor correctness:** capabilities follow the member's **effective membership role**. An owner who also has a doctor profile resolves to **owner** (superuser), not doctor.
6. **#126 coordination:** the invite wizard's reserved "Permissions step" is dropped; a one-line read-only capability summary may be folded into its Review card, reusing this resolver (non-blocking — see §6).

---

## 3. Capability inventory (final)

Each row is evaluated for the viewed member's **effective role** + current **clinic settings**. `setting_key` names the governing clinic setting (when any). `note_code` is a scope qualifier shown under an *allowed* row.

### Group A — Scheduling
| # | Capability `key` | Owner | Assigned Doctor | Assistant | Blocked `reason_code` / scope `note_code` |
|---|---|:--:|:--:|:--:|---|
| 1 | `approve_requests` | ✅ | ✅ *(note `assigned_requests_only`)* | ✅ **iff** `allow_staff_approval` | assistant-off → `staff_approval_disabled` (`setting_key: scheduling`) |
| 2 | `book_appointments` *(create / cancel / reschedule)* | ✅ | ❌ | ✅ | doctor → `coordination_by_staff` |
| 3 | `manage_availability` | ✅ *(any)* | ✅ *(note `own_schedule_only`)* | ✅ **iff** `allow_staff_manage_availability` | assistant-off → `staff_availability_disabled` (`setting_key: scheduling`) |

### Group B — Patients
| # | Capability `key` | Owner | Doctor | Assistant | Notes |
|---|---|:--:|:--:|:--:|---|
| 4 | `manage_patients` *(add / edit / remove)* | ✅ | ✅ | ✅ | No role gate today (`CurrentMembership` only). Always allowed; shown for completeness. |

### Group C — Team & clinic
| # | Capability `key` | Owner | Doctor | Assistant | Blocked `reason_code` |
|---|---|:--:|:--:|:--:|---|
| 5 | `manage_doctors` *(add / edit / remove doctor profiles)* | ✅ | ❌ | ✅ | doctor → `doctors_dont_manage_team` |
| 6 | `clinic_administration` *(manage staff, invitations & clinic settings)* | ✅ | ❌ | ❌ | non-owner → `owner_only` |

**Ground truth (verified in code 2026-06-23):**
- `approve_requests` → `scheduling/booking.py:authorize_decide` (owner; assigned doctor via `doctor.linked_user_id == membership.user_id`; assistant iff `settings.allow_staff_approval`).
- `book_appointments` → `authorize_create` / `authorize_coordinate` gated by `_COORDINATORS = {owner, assistant}`.
- `manage_availability` → `scheduling/service.py:authorize_manage_availability` (owner any; doctor own; assistant iff `settings.allow_staff_manage_availability`).
- `manage_patients` → `patients/router.py` uses `CurrentMembership` only (no `require_role`) → any active member.
- `manage_doctors` → `doctors/router.py: _can_manage = require_role(owner, assistant)`.
- `clinic_administration` → `assistants/router.py: require_role(owner)`, `invites/router.py: require_role(owner)` + `authorize_invite_mgmt`, `clinics/router.py: _settings_admin/_clinic_admin = require_role(owner)`.

### Reason & note code dictionary (stable; i18n keys)
| Code | Kind | Meaning (English reference — FE owns the localized copy) |
|---|---|---|
| `staff_approval_disabled` | reason | "Turned off — staff approval is disabled for this clinic." |
| `staff_availability_disabled` | reason | "Turned off — staff cannot manage availability for this clinic." |
| `coordination_by_staff` | reason | "Doctors approve requests; booking is handled by reception/owner." |
| `doctors_dont_manage_team` | reason | "Only the owner and assistants manage the team roster." |
| `owner_only` | reason | "Owner only." |
| `assigned_requests_only` | note | "Their own patients' requests only." |
| `own_schedule_only` | note | "Their own schedule only." |

`setting_key` values: `scheduling` (→ Settings → Scheduling pane). Extensible later.

---

## 4. Backend

**No migration. No model/schema changes to existing tables.** Pure read + a refactor that preserves behavior.

### 4a. Reusable authz predicates (refactor — behavior-preserving)
The capability resolver MUST call the same logic that enforces, to guarantee the view never drifts. Refactor the three authz functions so each exposes a **non-raising predicate** the existing raising guard delegates to:
- `scheduling/booking.py`: extract `can_decide(role, *, is_assigned_doctor, settings) -> bool`; `authorize_decide(...)` becomes "if not can_decide(...): raise ForbiddenError(...)". (`is_assigned_doctor` stays request-specific in the guard; the resolver passes the role-level truth — a doctor *can* decide their assigned requests → `True` at capability level, surfaced with `assigned_requests_only`.)
- `scheduling/booking.py`: `can_coordinate(role) -> bool` (`role in _COORDINATORS`); `authorize_create`/`authorize_coordinate` delegate.
- `scheduling/service.py`: `can_manage_availability(role, *, is_self_doctor, settings) -> bool`; `authorize_manage_availability(...)` delegates.
No behavior change — existing tests must stay green.

### 4b. Capability resolver (new) — `app/modules/members/capabilities.py`
Pure function, single source of truth:
```python
def resolve_capabilities(role: MemberRole, settings: ClinicSettings) -> list[Capability]:
    """Return the 6 capabilities for an effective membership role + clinic settings.
    Capability = (key, group, allowed, reason_code|None, note_code|None, setting_key|None)."""
```
- Maps the §3 table exactly. Owner → all allowed (notes: none). Doctor → `approve_requests` allowed+`assigned_requests_only`; `manage_availability` allowed+`own_schedule_only`; `book_appointments`/`manage_doctors`/`clinic_administration` blocked with their reason codes; `manage_patients` allowed. Assistant → `book_appointments`/`manage_patients`/`manage_doctors` allowed; `approve_requests`/`manage_availability` allowed-or-`*_disabled` per the two settings; `clinic_administration` blocked `owner_only`.
- `setting_key` is attached to `approve_requests` and `manage_availability` **whenever they are setting-gated** (regardless of allowed/blocked), so the FE can render the owner pointer consistently.

### 4c. Effective-role resolution (handles owner-doctor)
`resolve_member_role(db, clinic_id, *, kind, member_id) -> tuple[MemberRole, member]`:
- Load the `doctor_beta` / `assistant_beta` row (404 if not in clinic).
- If `linked_user_id` is set → look up `clinic_member_beta.role` for that user in the clinic; **use that** (so an owner-doctor resolves to `owner`).
- If `linked_user_id` is null (pending invite, not yet joined) → nominal role = `doctor` for the doctors resource, `assistant` for the assistants resource (prospective capabilities).

### 4d. Endpoints (read-only; mirror existing resource layout)
```
GET /api/v1/clinics/{clinic_id}/doctors/{doctor_id}/capabilities    -> CapabilitiesRead
GET /api/v1/clinics/{clinic_id}/assistants/{assistant_id}/capabilities -> CapabilitiesRead
```
- **Auth:** `CurrentMembership` (any active member of `clinic_id`); cross-clinic / non-member → 403 (capability data is non-sensitive but stays tenant-scoped).
- Service: `resolve_member_role(...)` → `get_settings(db, clinic_id)` → `resolve_capabilities(role, settings)` → shape `CapabilitiesRead`.
- Thin router (parse → service → response), no logic.

### 4e. Schema (response DTO only) — `members/schemas.py`
```python
class CapabilityRead(BaseModel):
    key: str
    group: str                       # "scheduling" | "patients" | "team_clinic"
    allowed: bool
    reason_code: str | None = None   # present when allowed is False
    note_code: str | None = None     # scope qualifier when allowed
    setting_key: str | None = None   # governing clinic setting, when any

class CapabilitiesRead(BaseModel):
    member_id: uuid.UUID
    kind: str                        # "doctor" | "assistant"
    effective_role: str              # "owner" | "doctor" | "assistant"
    capabilities: list[CapabilityRead]
```

### 4f. Tests (pytest; `uv run ruff check .` + `make test` green)
- **Resolver matrix** (`resolve_capabilities`): owner → 6× allowed, no reason codes; doctor → exact allowed/blocked set + `assigned_requests_only`/`own_schedule_only` notes + correct reason codes; assistant with each of the 4 `allow_staff_*` combinations → `approve_requests`/`manage_availability` flip with correct `*_disabled` reason + `setting_key: scheduling`; `clinic_administration` always `owner_only` for non-owners.
- **Effective role:** owner-doctor (linked to owner membership) → `effective_role == "owner"` (all allowed); plain doctor → doctor set; pending unlinked doctor/assistant → nominal role set.
- **Endpoint authz:** member of clinic → 200; non-member / other clinic → 403; unknown member id → 404.
- **No-drift guard:** a test asserting `can_decide`/`can_coordinate`/`can_manage_availability` agree with `resolve_capabilities` for each role (the refactor's contract).
- Refactor regression: all existing scheduling/availability authz tests stay green.

---

## 5. Frontend

Activates the disabled **Permissions** tab in `src/features/team/member-profile-drawer.tsx` (#107). Rule 17.0 — compose `components/ui/*` + semantic tokens; no per-page CSS; both themes; mobile full-width sheet; WCAG AA.

### 5a. API + hook
- `src/features/team/api.ts` (or member api): `getMemberCapabilities(clinicId, kind, memberId): Promise<CapabilitiesRead>` → `GET .../{kind}s/{id}/capabilities`.
- `useMemberCapabilities(clinicId, kind, memberId, { enabled })` (TanStack Query); `enabled` only when the Permissions tab is opened (lazy). Query key `["member-capabilities", clinicId, kind, memberId]`.

### 5b. `<PermissionsTab>` — `src/features/team/permissions-tab.tsx`
- Props: `clinicId`, `kind`, `member`, `me` (for viewer role).
- **Intro line** (i18n): "These are the actions {name} can take in this clinic. Some depend on clinic settings."
- **Three grouped cards** (`scheduling` / `patients` / `team_clinic`) — reuse the Overview tab's card + labeled-row pattern. Group header from `team.permissions.groups.<group>`.
- **Row** = leading capability icon + label (`team.permissions.capabilities.<key>.label`) + trailing **state**:
  - `allowed` → success check + "Allowed" (`team.permissions.allowed`); if `note_code`, a muted qualifier line beneath (`team.permissions.notes.<note_code>`).
  - `!allowed` → muted/grayed row + "Not allowed" (`team.permissions.blocked`) + reason line (`team.permissions.reasons.<reason_code>`). **If `setting_key` present AND `me` is the clinic owner** → an inline link/button "Change in Settings → {pane}" routing to `/settings` + the Scheduling pane (`setting_key` → pane map). Non-owners: reason only.
- **State conveyed by icon + text, never color alone** (a11y).
- Loading → skeleton rows; error → standard `apiErrors.<code>` (fallback `apiErrors.default`).
- testids: `permissions-tab`, `permission-row-<key>`, `permission-state-<key>` (`allowed`/`blocked`), `permission-settings-link-<key>`.
- Wire into the drawer: remove the Permissions tab's `disabled`; render `<PermissionsTab>` on select (lazy-load).

### 5c. i18n (en + hi parity — gated by `tests/e2e/i18n.spec.ts`)
Add under `team.permissions.*`: `intro`, `allowed`, `blocked`, `groups.{scheduling,patients,team_clinic}`, `capabilities.<key>.label` (6), `reasons.<reason_code>` (5), `notes.<note_code>` (2), `settingsLink` (with pane name). No hardcoded strings; codes → copy mapping lives in locale files only.

### 5d. FE tests
- Renders 6 rows grouped; allowed vs blocked styling; note line for doctor scope notes.
- Owner viewer sees the "Change in Settings" link on a setting-gated blocked row; non-owner viewer does not.
- Owner's own member → all allowed, no reason rows.
- i18n parity; both themes; a11y (role/aria, icon+text).
- **Render on :8753 + user sign-off before the dev builds** (drawer Permissions tab for owner-viewing-assistant with a toggle off, and a doctor).

---

## 6. #126 coordination (guided invite wizard)

#126 is frontend-only and under active implementation. Its reserved **Permissions step** has nothing to configure now (no per-member toggles).
- **Decision:** drop the dedicated step; optionally fold a **one-line read-only capability summary** into the wizard's existing **Review card** — "They'll be able to: book appointments, manage patients…" — computed from the **invited role + current clinic settings** via this resolver (the same `resolve_capabilities`, exposed for a prospective role).
- **Sequencing (keep #126 unblocked):** if #126 lands before #108, ship the Review card without the line and add it as a fast-follow when the resolver exists; or use a role-based stopgap string. Do not block #126 on #108. (Recorded as a comment on #126.)

---

## 7. Quality

- Backend: `uv run ruff check .` clean; `make test` green (resolver matrix, effective-role, endpoint authz, no-drift guard, refactor regressions). **No migration.**
- Frontend: `tsc --noEmit` + `npm run build` + i18n en/hi parity + e2e green.
- Rule 17.0 (semantic tokens, compose `components/ui/*`, no per-page CSS, no new tokens); both themes; mobile-first; WCAG AA (icon+text, focus, contrast).
- Never merge red (`gh-personal pr checks`). **Frontend PR held for user QA;** backend may merge after green review. Migrations: n/a.
- Docs work in a **git worktree** (shared docs repo). `gh-personal` for all GitHub ops.

---

## 8. Scope guards / deferred

- **No per-member permission model / toggles / grants** (#125 closed not-planned). If genuine per-assistant control resurfaces, it reopens with fresh justification.
- **No new clinic settings.** The only governing settings are the existing `allow_staff_approval` / `allow_staff_manage_availability`, changed only in Settings → Scheduling (owner-only).
- **No migration / no new columns.**
- **Activity tab** content remains **#109** (audit read API); this slice leaves it disabled.
- The capability set is fixed at 6; growth (if ever) is additive in `resolve_capabilities` + locale files + the inventory, no schema.

---

## 9. Self-review (against the request + the brainstorm)

- Read-only "what this member can do" view, all roles incl. owner: §1/§2/§5. ✅
- 6 capabilities / 3 groups, mappings verified against code: §3. ✅
- Backend-authoritative resolver reusing real authz predicates (no FE drift); stable reason/note codes the FE translates: §4a/§4b/§4e/§5. ✅
- Two "not allowed" flavors; owner-only Settings pointer for setting-gated rows: §3/§5b. ✅
- Owner-doctor resolves to owner: §4c. ✅
- No migration, no new settings, no writes: §4/§8. ✅
- i18n en/hi, Rule 17.0, both themes, a11y, render-before-build: §5/§7. ✅
- #125 closed; #126 step dropped → Review-card line, non-blocking: §2/§6. ✅
- Placeholder scan: concrete keys, endpoints, files, codes, tests — no TBD. ✅
