# Permissions: a single source of truth (work item E)

> **Status:** design / spec for review · 2026-06-29 · target repo `dentist-registry-backend`
>
> Companion reference: [`docs/architecture/service-catalog.md`](../architecture/service-catalog.md) (row #2).

## The golden line (the contract)

**Exactly one module — `permissions` — decides any permission or policy question.**
Every other part of the codebase *asks* it; nothing else *decides*. Future changes to
who-can-do-what happen in that one module, and a guard makes it impossible to decide
permissions anywhere else.

## Why

Today the `role × settings → allowed?` rules are encoded in **five places** that can drift:
`members/capabilities.py::resolve_capabilities` (the matrix shown to the FE) **plus** the
enforcement predicates `members/deps.require_role`, `invites/service.authorize_invite_mgmt`,
`scheduling/service.can_manage_availability`, and `scheduling/booking.can_decide /
can_coordinate / authorize_*`. The matrix and the predicates encode the **same rules twice** —
so a small change is dangerous: two encodings can disagree.

## Two hard principles

1. **Behavior-preserving.** E only *relocates* rules; it changes none of them. The exhaustive
   matrix (below) pins today's exact outcomes. If characterization reveals a rule that *looks*
   wrong, that is a **separate ticket** — never folded into this refactor.
2. **No back doors.** A guard (CI) fails if a `role ==` / `MemberRole.<x>` comparison appears
   anywhere outside `permissions/`. This is what makes "one place only" durable, not aspirational.

---

## Design

### The decision function (the sole decider)

A single module `app/modules/permissions/` exposing one pure decision function:

```python
def can(role: MemberRole, settings, action: Action, *, is_self: bool = False) -> bool
```

- `role` — the caller's membership role (`owner | doctor | assistant`), from `clinic_member_beta`.
- `settings` — the clinic's `ClinicSettings` (the staff flags), from `clinic_settings_beta`.
- `action` — a value from the **Action catalog** (an enum; see below).
- `is_self` — resource-ownership fact supplied by the call site (e.g. "this is the doctor's own
  record / own appointment"). **The call site supplies the fact; the policy makes the decision.**
  This is how ownership rules ("a doctor may approve their *own* appointment") stay inside the
  single source of truth instead of leaking back out to call sites.

`can` is pure (no DB, no I/O) → trivially and exhaustively testable.

### The Action catalog (enumerated, exhaustive)

Every protected action in the app becomes one `Action` enum member. Draft catalog
(**ground truth captured by the characterization net before any code** — see Risks):

| Action | Owner | Doctor | Assistant | Setting it depends on |
|---|---|---|---|---|
| `clinic.edit` | ✅ | ❌ | ❌ | — |
| `clinic.manage_settings` | ✅ | ❌ | ❌ | — |
| `member.manage` | ✅ | ❌ | ❌ | — |
| `invite.create` | ✅ | ❌ | ❌ | — |
| `invite.manage` | ✅ | ❌ | doctor-invites only | — |
| `doctor.list` | ✅ | ❌ | ✅ | — |
| `doctor.edit` | ✅ | ❌ | ❌ | — |
| `doctor.invite` | ✅ | ❌ | ❌ | — |
| `doctor.self_create` | ✅ | ✅ | ❌ | — |
| `assistant.manage` | ✅ | ❌ | ❌ | — |
| `availability.manage` | ✅ | self only (`is_self`) | if flag | `allow_staff_manage_availability` |
| `booking.create` | ✅ | self only (`is_self`) | ✅ | — |
| `booking.coordinate` | ✅ | ❌ | ✅ | — |
| `booking.decide` (approve/reject) | ✅ | assigned only (`is_self`) | if flag | `allow_staff_approval` |
| `schedule.view_clinic` | ✅ | ❌ | ✅ | — |

> This table is the **draft** policy. The characterization net (not this document) is the
> authority on current behavior; any mismatch is resolved in favor of the running code, then
> filed as a separate "is this rule correct?" question. Some actions carry a sub-condition that
> `invite.manage` can't express as a plain ✅/❌ (assistant may manage *doctor* invites but not
> *assistant* invites) — the decision function takes the target invite role as part of context
> for that action.

### Enforcement: one path in

- **Role-level routes** use a single FastAPI dependency:
  `require(action)` → resolves membership, calls `can(...)`, raises `403` (uniform
  `forbidden` envelope) if denied. This **replaces** `require_role(...)` and the inline
  `if membership.role == ...` checks.
- **Resource-level routes** (need `is_self` / target context) call an explicit
  `authorize(action, role, settings, *, is_self)` helper inside the service, which calls `can`.
  This **replaces** `authorize_manage_availability`, `authorize_decide`, `authorize_create`,
  `authorize_coordinate`, `authorize_invite_mgmt`.
- **No route or service computes a permission outcome itself.** They compute *facts*
  (`is_self`, target invite role) and pass them in.

### Capabilities are generated, not duplicated

`resolve_capabilities(role, settings)` (the matrix the FE reads) is rewritten as a **loop over
`can(role, settings, action)`** for the capability-bearing actions. The FE matrix and the BE
enforcement then come from the **same function** and cannot drift.

### The anti-bypass guard

A test (and/or ruff rule) that scans `app/` and **fails if `MemberRole.` or a `.role ==`
comparison appears outside `app/modules/permissions/`**. This is the mechanical guarantee of
"one place only." (Allow-list: the `permissions` module itself, and model/enum definitions.)

### Where it lives

A new top-level domain module `app/modules/permissions/` — peer to the others, owns no table
(it reads `clinic_member_beta.role` + `clinic_settings_beta` flags, both owned by other
services). It depends only on `members.models` (the `MemberRole` enum) and `core`. Nothing
in `permissions/` imports another module's service → no cycles.

---

## The safety net (built and green BEFORE any refactor)

An **exhaustive characterization matrix** in `tests/permissions/`:

```
for role in (owner, doctor, assistant):
  for allow_staff_approval in (True, False):
    for allow_staff_manage_availability in (True, False):
      for action in Action:               # every catalog entry
        for is_self in (True, False):     # where it applies
            assert can(role, settings, action, is_self=is_self) == GOLDEN[...]
```

- `GOLDEN[...]` is captured from **today's running code** — for each action we exercise the
  *current* predicate (`booking.can_decide`, `scheduling.can_manage_availability`,
  `resolve_capabilities`, the `require_role` gates) and record the outcome. The matrix is the
  frozen snapshot of that.
- **Plus endpoint-level tests**: for each protected route, assert the real HTTP `200/403` for
  the representative role/setting combos (so enforcement wiring, not just the pure function, is
  pinned).
- The suite is committed and green **against the current code first**. Only then do we introduce
  `permissions.can` and migrate call sites — the matrix must stay green at every step.

This is what makes a security-critical change safe: nothing is trusted, every outcome is locked.

---

## Migration plan (sequenced, each step keeps the matrix green)

1. **Net first.** Write the exhaustive matrix + endpoint authz tests against current code. Commit green. *(its own PR)*
2. **Introduce `permissions.can` + the Action catalog**, implemented to satisfy the matrix. No call sites changed yet. *(PR)*
3. **Migrate enforcement, one domain at a time** (invites → availability → booking → routers), replacing each `authorize_*`/`can_*`/`require_role`/inline check with `require(action)` / `authorize(action, …)`. Matrix + endpoint tests green after each. *(small PRs)*
4. **Generate `resolve_capabilities` from `can`**; delete the duplicate rule encoding. *(PR)*
5. **Add the anti-bypass guard**; delete now-dead predicates. *(PR)*

## Risks & mitigations

- **Hidden context dimension** (ownership) → handled by `is_self` in the signature; the net
  includes `is_self` both ways.
- **A characterized rule looks wrong** → do NOT fix here; file separately. E stays behavior-preserving.
- **Enforcement is security-critical** → the matrix + endpoint net is mandatory and built first;
  migration is incremental with the net green at each step; each step is independently revertible.
- **Scope creep into "fixing" the model** → explicitly out of scope; this is relocation only.

## Out of scope

Changing any permission rule; the `invites` god-module slimming (separate); `Clinic.operating_hours`
drop (item G).

## Open questions for review

1. Catalog granularity — is the ~15-action catalog the right grain, or do you want finer/coarser?
2. Module name/location — `app/modules/permissions/` ok?
3. Anti-bypass guard as a **CI-failing test** vs a softer warning to start?
