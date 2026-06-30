# Register System — Sentinel Rules

> The internals of our system are a temple. These rules protect it. They sit
> alongside the [Golden Rules](register-golden-rules.md); where they overlap, the
> stricter binds. This is the **single source** for the Sentinel doctrine — per-file
> headers across the repos quote the core rules and point here for the full set.

## The one line

**Every business capability has exactly one engine, and that engine is the only
place its decision is made.** Not two places. Not "mostly one." One. Every other
part of the system — UI, API routes, hooks, components, other engines — *asks*.
Nobody else *decides*. If a decision can be found in two files, the architecture
is broken and we fix it.

## The 14 Sentinel Rules

1. **The caller never knows the business reason.** The caller asks the engine; the engine decides.
2. **No role checks outside the permission engine.** Never write `user.role === "doctor"` (or `role == MemberRole.doctor`) outside `permissions`.
3. **No workflow-state checks outside the owning engine.** Appointment status transitions belong only to the AppointmentEngine.
4. **No settings interpretation outside engines.** Callers may pass settings, but must not decide what settings *mean*.
5. **UI, hooks, API routes, and components are messengers, not decision-makers.**
6. **Every business capability has exactly one owner.** If two places decide the same thing, the architecture is broken.
7. **Engines expose one public gate.** Outside code imports only the engine's public surface.
8. **Engine internals are private.** No direct imports from an engine's rules / policies / helpers / internal files.
9. **Engines return typed decisions, not bare booleans.** Return `allowed/denied` plus a reason (and next-action / audit metadata where the workflow needs it).
10. **Business rules are table-tested.** Every role / action / status / setting combination gets an explicit, honest test.
11. **Old behavior is proven before a refactor is accepted.** Refactor without a behavioral characterization net is not allowed.
12. **Cross-engine calls go through public APIs only.** The AppointmentEngine may *ask* the PermissionEngine, but never touches its internals.
13. **Repositories store data; they do not decide business rules.**
14. **If changing one rule requires hunting across the codebase, the Sentinel Rules are already broken.**

### The smell we hunt

```
user.role === Role.DOCTOR        // ❌ the caller now knows doctors are allowed
PermissionEngine.canApproveAppointment(...)   // ✅ ask; don't decide
```
The enum comparison isn't the problem — the *caller knowing the rule* is. We hunt these down and destroy them.

## Client/server: PDP/PEP separation

The frontend is a **Policy Enforcement Point**, never a Policy Decision Point. It
**asks** the backend and **reads** the answer — it never computes a permission, not
even one clause of one.

- **Clinic-wide gates** read `cap("key").allowed` from `GET /clinics/{id}/me/capabilities`. The FE helper is `cap()` (a *reader*) — never `can()` (the FE has no `can`).
- **Per-resource decisions** (can I decide *this* request, manage *this* doctor) are emitted by the engine **on the row itself** (`can_decide`, `can_manage_availability`). The FE reads the boolean; it never combines scope + identity client-side. Adding a policy dimension tomorrow then touches only the engine, never the client. This is the industry standard (OpenID AuthZEN / Zanzibar / GitHub per-object permissions).
- The gate is **advisory UX**; the backend enforces every mutation regardless.

## Code as documentation

Agents imitate what's already in the files, so the rules live **in** the files.

- **Every hand-written source file** (`.ts/.tsx`, `.py`) carries a header stating the core rules + a one-line purpose, and points here for the full set. (Excluded: generated/vendored files, lockfiles, pure-data config, auto-generated migrations.)
- **Inline comments** state what a non-trivial function/test does and *why*.
- The full rule-set lives **here, once**. A new rule (e.g. for the AppointmentEngine) is added to this file — not copy-pasted across N files. Only files where the rule is relevant mention it; every new file written afterward carries the current header.

### Header template

TypeScript:
```ts
/**
 * Sentinel rules (full set: Rules/sentinel-rules.md). Core, in-file so they propagate:
 *   • The FE only ASKS the backend for permissions; it never decides (no role=== gates).
 *   • One source of truth per decision. No dead code. No imports inside functions.
 *   • Honest tests only — real assertions, no placeholders.
 *
 * <one-line purpose of this file>
 */
```

Python:
```python
"""Sentinel rules (full set: Rules/sentinel-rules.md). Core, in-file so they propagate:
  • Each decision lives in exactly ONE engine; callers ask (no role== outside permissions/).
  • One source of truth per decision. No dead code. No imports inside functions.
  • Honest tests only — real assertions, no placeholders.

<one-line purpose of this file>
"""
```

## Enforcement

- **Backend:** `tests/permissions/test_no_bypass.py` fails CI on a role-decision outside the engine without a `# authz-exempt:` marker.
- **Frontend:** a sentinel guard fails CI on any client-side permission decision (no `role===` in components) outside the allowed identity facts.
- **The temple-map** (generated, in the backend repo, guarded against drift) is the honest picture of every engine's matrix; any change to who-can-do-what is flagged in the PR.
