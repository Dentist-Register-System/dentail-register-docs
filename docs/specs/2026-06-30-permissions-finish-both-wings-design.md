# Permissions — Finish Both Wings + Typed Decisions

- **Status:** Design — awaiting approval (no code written)
- **Date:** 2026-06-30
- **Author:** Dev session (Ponytail)
- **Scoreboard:** `docs/architecture/system-decision-trees.html` (the temple's living picture)
- **Doctrine:** `Rules/sentinel-rules.md` (created by this work) + the Golden Rules

---

## 1. Why

The permission **backend** engine is done and merged (`permissions/policy.py::can()`, PRs #52/#53/#54): one function decides, an anti-bypass CI guard (`tests/permissions/test_no_bypass.py`) forbids deciding anywhere else in `app/`, and 282 equivalence tests pin it byte-for-byte to the old scattered code.

But the Permissions *system* is not finished. Two fronts remain open, and both are live violations of the Sentinel doctrine:

1. **The frontend still decides.** `GET /api/v1/me` returns no capabilities, so **17 origin sites** in `dentist-registry-frontend` re-derive permissions from `memberships[0].role` (6 of them also interpreting clinic settings). That is a second, drift-prone copy of the permission rules — living in the client, which by doctrine must only *ask*.
2. **The engine returns a bare `bool`.** Sentinel Rule 9 requires engines to return a typed *decision* (allowed + reason, and next-action/audit where relevant), not a naked boolean. We adopt this now as the house pattern every future engine (Appointments, Availability, Invites) will follow.

This spec finishes Permissions on **both wings** (backend engine + frontend messenger) and establishes the typed-decision and dual-repo-guard patterns the rest of the temple inherits.

## 2. Goals / Non-goals

**Goals**
- `can()` returns a typed `Decision`, never a bare bool. Reasons become stable codes (i18n-friendly).
- The frontend asks one endpoint for "what may I do" and renders from it. Zero `role===` permission decisions remain in the FE.
- A CI guard in **each** repo makes future regressions impossible.
- The 14 Sentinel Rules get a canonical, cross-referenced home.
- Every step is behavior-preserving and proven against an OLD-vs-NEW matrix on the scoreboard before any decision logic is deleted.

**Non-goals**
- No change to *who can do what* — this is pure relocation, not a policy change. The 45/45 matrix must stay 45/45.
- No per-row appointment-action engine yet. The two row-specific self-gated checks (decide/book "my own") are handled with an explicit capability `scope` + a marked identity fact now; they migrate to the Appointment engine when it lands.
- No new FE test framework (no Vitest — that is the QA session's call). The FE guard is a plain-node script.
- `kind === "doctor"` / `kind === "assistant"` entity-type checks are **not** authz and are explicitly out of scope — they stay.

## 3. Architecture

The shape does not change — it gets completed and made typed:

```
            ┌─────────────── one engine, one function ───────────────┐
  caller →  │  permissions.can(role, settings, action, *, is_self,   │  → Decision{allowed, reason}
 (asks)     │                  target_role)                          │     (typed, not bool)
            └────────────────────────────────────────────────────────┘
                         ▲                              │
   server enforcement ───┘                              └─── resolve_capabilities() → CapabilityRead[]
   (require(), predicates)                                    (FE-facing projection of the same engine)

  Frontend (messenger, never decides):
    component → useMyCapabilities() → GET /clinics/{id}/me/capabilities → cap("key").allowed → render
```

One decider (`can`). One server projection for enforcement. One FE-facing projection (`resolve_capabilities`) served over HTTP. The FE consumes the projection; it never re-implements the rule.

## 4. Workstream 1 — BE: typed `Decision` (Rule 9)

**The type** (new, in the permissions module — the engine's public surface):

```python
@dataclass(frozen=True)
class Decision:
    allowed: bool
    reason: str | None = None   # stable code when denied (e.g. "staff_approval_disabled"); None when allowed
    # next_action / audit fields are added per-engine when a workflow needs them (Appointments will).
    # Permissions needs only allowed + reason today; we do not add speculative fields (YAGNI).
```

`can(...)` returns `Decision`. Internally the rule is unchanged; we wrap each return in `Decision(allowed=..., reason=...)`. Reason codes reuse the vocabulary already in `capabilities.py::_HINTS` (`staff_approval_disabled`, `owner_only`, `doctors_dont_manage_team`, …) so they are i18n-translatable per Golden Rule 16.2.

**Call-site migration.** Every `can(...)` caller (enforcement predicates in `booking.py`/`service.py`/`invites/service.py`, `require()` in `members/deps.py`, `resolve_capabilities`) changes from truthy use to explicit `.allowed`. `require()` additionally forwards `Decision.reason` into the `ForbiddenError` envelope, so denials carry a stable code instead of a hardcoded English string.

**Proof.** The existing 282 equivalence + 284 suite tests are updated to assert on `.allowed` and must stay green — that *is* the no-regression proof. A new table test asserts the exact `reason` code for every denied (role × action × setting) cell.

**Anti-bypass guard.** Unchanged in spirit; `test_no_bypass.py` continues to forbid role decisions outside the module. No new exemptions introduced.

## 5. Workstream 2 — BE: self-capabilities endpoint

**Route:** `GET /api/v1/clinics/{clinic_id}/me/capabilities`
**Returns:** `MyCapabilities { effective_role, capabilities: CapabilityRead[] }` — the same `CapabilityRead` shape the per-member endpoint already returns.

Clinic-scoped (not on identity-only `/me`) because capabilities depend on clinic settings. It calls the existing `resolve_capabilities(role, settings)` — no new decision logic, just exposure of the engine's projection for the *current* member.

**Catalog gap (honest).** The capability catalog (`capabilities.py::_CAPABILITIES`) today exposes only **6** capabilities (`approve_requests`, `book_appointments`, `manage_availability`, `manage_patients`, `manage_doctors`, `clinic_administration`). The 17 FE sites gate on more than that — at minimum `coordinate_booking`, `manage_invite`, and `view_clinic_schedule` have **no capability key yet**. So the catalog must be **extended** to cover every FE decision point, each mapped to its existing `Action` (the `can()` rule already exists for these actions — only the FE-facing projection entry is missing). The exact site → capability-key map and the precise list of new catalog entries are **pinned by the FE OLD-matrix calculation** (the deliverable immediately after this spec), so the catalog is extended to fit reality, not guessed.

**New field — `scope`.** `CapabilityRead` gains `scope: "all" | "self"` (additive, default `"all"`). Self-gated capabilities (a doctor's `decide_booking`, `create_booking`, `manage_availability`) report `scope="self"`. This lets the FE honor the engine-declared scope against an identity fact **without re-deriving the rule** — the rule ("doctors act only on their own") stays in the engine; the FE only learns *that* a scope applies. Existing consumers (`permissions-tab.tsx`) ignore the new field — safe.

**Additive + backward-compatible** → ships and deploys (BE→FE order, Golden Rule 19.3) before the FE consumes it.

**Tests.** Table-tested against the same (role × setting) grid as the backend matrix: the endpoint's `allowed`/`reason_code`/`scope` for every capability must equal `can(...)` for the same inputs.

## 6. Workstream 3 — FE: messenger-ification

**New plumbing (reusing what exists):**
- `useMyCapabilities()` — TanStack Query hook on the new endpoint, keyed by clinic. Mirrors `useMemberCapabilities()`.
- `cap(key)` — lookup returning the `Capability` (or a safe denied default while loading). The render pattern (`allowed`/`reason_code`/`note_code`/`setting_key`) already exists in `permissions-tab.tsx`; we reuse, not rebuild.

**The 17 sites.** Each `role===` origin is replaced by `cap("<key>").allowed`, where `<key>` is the **capability key** (e.g. `approve_requests`, `book_appointments`, `manage_availability`, `clinic_administration`, plus the new `coordinate_booking` / `manage_invite` / `view_clinic_schedule` entries from §5). The exact site → key map is the FE OLD-matrix deliverable. The prop-drilled `canX` booleans fanning out from these origins come free once the origin reads from `cap()`.

**The 2 self-gated row checks** (`canDecide`, `canBook` for "my own assigned"): the FE reads `cap("approve_requests")` (resp. `book_appointments`) — if `scope==="self"`, it ANDs `allowed` with the identity fact `row.doctor_id === my.doctorId`. That single AND is the FE applying an engine-declared scope to an identity it legitimately owns — exactly the backend's `# authz-exempt: is_self` pattern — and is marked `// sentinel-exempt: applies engine-declared scope to is_self identity fact`. It migrates to a per-row engine flag when the Appointment engine lands.

**Out of scope (untouched):** all `kind === "doctor"/"assistant"` entity-type branches (form/column shape), role-as-display-label, role query params. Demolishing these would break the doctor/assistant forms; the guard must not flag them.

**Proof.** Before deleting any role logic: compute the FE's effective permission matrix (or, where decisions are row/settings-coupled and a clean matrix can't capture them, a Mermaid decision-flow) from the *current* code, render it on the scoreboard, and confirm `useMyCapabilities()` reproduces it identically for all 3 roles × both settings. Only then delete the `role===` origins.

## 7. Workstream 4 — Guards + doctrine

**FE sentinel guard.** A plain-node script (no test framework) mirroring `test_no_bypass.py`: scans `src/` (excluding the capabilities plumbing), fails CI on permission-decision shapes — `role === / !==` against `"owner"/"doctor"/"assistant"`, role-keyed permission branching — unless marked `// sentinel-exempt: <reason>`. It must NOT flag `kind ===` entity checks or display-label use. Includes a self-test ("has teeth") asserting it catches a real decision and ignores a harmless label. Wired into the FE CI job that already runs typecheck + build.

**Doctrine.** `Rules/sentinel-rules.md` — the 14 Sentinel Rules verbatim, with the worked `user.role === DOCTOR` → `engine.can(...)` example. Cross-referenced from `Rules/register-golden-rules.md` and both repos' `CLAUDE.md` so it binds every future session.

## 8. Data flow & error handling

- **Enforcement:** route → `require(action)` → `can(...).allowed` → on deny, `ForbiddenError(code=Decision.reason)` → uniform error envelope `{error:{code,message,details}}` (FE translates `code`).
- **FE capability read:** mount → `useMyCapabilities()` → endpoint → cache. While loading or on error, `cap()` returns a denied default (fail-closed: never render an action the user might not have).
- **Settings:** still fetched server-side inside the endpoint; the FE never reads `allow_staff_*` to decide UI again (those settings-interpretation sites in §6 are removed).

## 9. Testing (honest — no empty assertions)

- **BE Decision:** every (role × action × setting) cell asserts `.allowed` **and** the exact `.reason` code. Equivalence + full suite stay green.
- **Endpoint:** table test — endpoint output ≡ `can(...)`/`resolve_capabilities(...)` for the full grid, including `scope`.
- **FE:** render-equivalence check (OLD-derived matrix vs `cap()`-driven render) for 3 roles × 2 settings; guard self-test.
- **No-regression spine:** the scoreboard OLD-vs-NEW matrix must remain identical at every step; deletion of FE role logic happens only after the new path is proven equal.

## 10. PR sequence (small, green, prove-then-wire)

| # | PR | Repo | Proven by |
|---|----|------|-----------|
| 1 | `can() → Decision` + reason codes | backend | equivalence + suite green; reason table test |
| 2 | `GET /clinics/{id}/me/capabilities` (+ `scope`) | backend | endpoint≡engine grid test; additive/backward-compatible |
| 3 | `useMyCapabilities()` + delete 17 `role===` sites | frontend | scoreboard OLD-vs-NEW render-equivalence |
| 4 | FE sentinel guard + `sentinel-rules.md` | frontend + docs | guard self-test; doctrine cross-linked |

Backend PRs (1,2) merge and deploy before frontend PRs (3,4) — Golden Rule 19.3.

## 11. Risks & mitigations

- **Touching the merged engine (PR 1).** Mitigated: behavior-preserving wrap, the 284-test net is the safety harness, byte-identical matrix required.
- **FE fail-open during load.** Mitigated: `cap()` defaults to denied.
- **Guard false positives on `kind===`.** Mitigated: guard self-test pins that entity/label use is not flagged; scoped patterns target role literals only.
- **Self-gated scope leak.** Mitigated: the one AND is explicitly marked and tracked for migration to the Appointment engine.

## 12. Open question

- The scoreboard file is `system-decision-trees.html`. We have been calling it the "matrix dashboard" / "picture of the temple." Optional trivial `git mv` to a clearer name (e.g. `temple-map.html` or `decision-map.html`) — non-blocking, decide separately.
