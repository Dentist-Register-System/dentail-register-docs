# Service Catalog — the foundation of the Register backend

> **Status:** canonical reference · last verified against `dentist-registry-backend@main` on **2026-06-29**.
>
> **Why this exists.** The app is a small set of **core services**, each the single
> authority for its domain, each backed by its own table. Everything else is built
> on top of that. The bar: the answer to *"what are the rules for X?"* should come
> from **one service or one table** — never a hunt across modules.

## The principle

A core service:
- does **exactly one** domain job (single responsibility),
- **owns its table(s)** — it is the only writer of its domain truth,
- is reached by other modules **only through its `service` API** (never their `models`/`router`),
- has a **clear authority boundary** — you can answer any question about its domain by reading it alone.

When that holds, a change is safe to reason about. When it doesn't (see **Permission**, below),
even a small change is frightening because the rules live in several places that can drift apart.

---

## Core domain services

Each is (or should be) the single authority for its domain, backed by its own table.

| # | Core Service | Does exactly this | Source-of-truth table(s) | Lives in | Squeaky-clean? |
|---|---|---|---|---|---|
| 1 | **Auth / Identity** | Verify the Supabase JWT; resolve it to the app user | `app_user_beta` | `auth/` (tokens, jwks, deps, service) | ✅ clean |
| 2 | **Permission / Authorization** | Decide what a role may do, and enforce it | `clinic_member_beta` (role) + `clinic_settings_beta` (staff flags) | **scattered** — see deep-dive | ❌ **scattered (the concern)** |
| 3 | **Membership** | Who belongs to a clinic; their role & active/inactive status | `clinic_member_beta` | `members/` | ✅ clean (invites writes it directly — minor) |
| 4 | **Clinic** | The clinic record + its settings | `clinic_beta`, `clinic_settings_beta` | `clinics/` | ✅ clean |
| 5 | **Invite** | Invite tokens + redemption (join a clinic) | `clinic_invite_beta` | `invites/` | ⚠️ does too much (writes membership, links doctor/assistant, reads 4 domains) |
| 6 | **Doctor** | Doctor profiles + lifecycle | `doctor_beta` | `doctors/` → `staff/crud` | ✅ clean (deduped) |
| 7 | **Assistant** | Assistant profiles + lifecycle | `assistant_beta` | `assistants/` → `staff/crud` | ✅ clean (deduped) |
| 8 | **Patient** | Patient records + duplicate detection | `patient_beta` | `patients/` | ✅ clean |
| 9 | **Availability** | Working windows, blocks, weekly schedule, slot derivation | `availability_window_beta`, `availability_block_beta`, `slot_beta` | `scheduling/service.py` + `rules.py` | ✅ clean |
| 10 | **Booking** | Appointment requests → appointments: the state machine + capacity | `appointment_request_beta`, `appointment_beta` | `scheduling/booking.py` | ✅ cohesive (its authz predicates belong to #2) |

## Supporting / cross-cutting services

No domain of their own — they serve the core.

| # | Service | Does exactly this | Table | Lives in | Clean? |
|---|---|---|---|---|---|
| 11 | **Schedule reads** | Read-only projections (day diary, appointment lists) | — (reads across) | `scheduling/reads.py` | ✅ clean |
| 12 | **Audit** | Append-only record of important actions | `audit_event_beta` | `audit/` | ✅ clean (in-txn, append-only) |
| 13 | **Notification (Email)** | Outbound email side-effects (only after commit) | — | `email/` | ✅ clean |
| 14 | **Preferences** | Per-user theme / language | `user_preferences_beta` | `preferences/` | ✅ clean |

---

## Table → owning service (single-writer map)

Every domain table has exactly one owning service. No other service should write it.

| Table | Owner |
|---|---|
| `app_user_beta` | Auth |
| `clinic_member_beta` | Membership (read by Permission) |
| `clinic_beta`, `clinic_settings_beta` | Clinic (flags read by Permission) |
| `clinic_invite_beta` | Invite |
| `doctor_beta` | Doctor |
| `assistant_beta` | Assistant |
| `patient_beta` | Patient |
| `availability_window_beta`, `availability_block_beta`, `slot_beta` | Availability |
| `appointment_request_beta`, `appointment_beta` | Booking |
| `audit_event_beta` | Audit |
| `user_preferences_beta` | Preferences |

---

## Deep-dive: the Permission model (today vs. target)

This is the crown jewel and the one ❌ in the catalog. **There is no single permission
service.** The rules for "who may do what" live in **five places**, and the same
`role × settings` logic is encoded more than once — which is exactly why a small change
is frightening: two encodings can drift apart.

### Where permission logic lives today

| Location | What it decides | Inputs |
|---|---|---|
| `members/capabilities.py::resolve_capabilities` | the capability **matrix** surfaced to the frontend | role + settings |
| `members/deps.py::require_role` | coarse route gate (e.g. owner-only) | role |
| `invites/service.py::authorize_invite_mgmt` | who may manage invites | role |
| `scheduling/service.py::can_manage_availability` / `authorize_manage_availability` | who may edit a doctor's availability | role + `allow_staff_manage_availability` |
| `scheduling/booking.py::can_decide` / `can_coordinate` / `authorize_create` / `authorize_decide` / `authorize_coordinate` | who may create / approve / reject bookings | role + `allow_staff_approval` |
| inline checks in routers (`invites/router.py`, etc.) | per-endpoint role rules | role |

**The core defect:** `capabilities.py` (the matrix shown to the UI) and the enforcement
predicates (`can_decide`, `can_manage_availability`, …) **encode the same rules twice**.
To answer *"can an assistant approve an appointment?"* you must read `booking.can_decide`
(`role + allow_staff_approval`) — but the matrix in `capabilities.py` claims to answer it too.
Two sources of truth → drift risk → fear.

### The whole permission answer, stated plainly

> **permission = role (`clinic_member_beta`) + staff flags (`clinic_settings_beta`) → allowed?**

Everything needed is those two tables plus the rule set. The problem is only that the *rule set*
is not in one place.

### Target (squeaky-clean) — this is work item **E**

A single `permissions` module that owns **every** `role × setting → allowed?` rule.
`resolve_capabilities` and every `authorize_*` / `can_*` call become thin lookups into it.
Then the entire permission answer is one function over two tables — one lookup, no wrestling.

> **E is gated on tests.** Because this is security-sensitive, E does not begin until there is
> a characterization test suite that pins **every** current `role × setting → outcome` for every
> protected action — so the consolidation is provably behavior-identical and *any* regression is caught.

---

## How this maps to recent cleanup (2026-06-29)

The backend audit (PRs #45–#51, merged) moved several rows to ✅:
- **Doctor/Assistant** deduped into the shared `staff/crud` generic.
- **Availability** split out of the old scheduling god-file; the `scheduling.service ↔ booking` cycle was removed (`scheduling/rules.py`, `scheduling/reads.py`).
- Routers made thin; dead code removed; in-function imports hoisted.

Still open, in priority order:
- **E — Permission consolidation** (collapses row #2 to ✅). *Test-gated, design-first.*
- **Invite slimming** (row #5): stop writing membership directly; move cross-domain reads out.
- **G** — drop the orphan `Clinic.operating_hours` column (destructive migration; gatekeeper-reviewed).
