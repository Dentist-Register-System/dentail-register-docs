# Temple Dashboard Generator (v1)

- **Status:** Design — awaiting approval (no code written)
- **Date:** 2026-06-30
- **Author:** Dev session (Ponytail)
- **Related:** the Sentinel temple program; `Rules/sentinel-rules.md`; the hand-maintained `temple-map.html` (this replaces it)

---

## 1. Why

The temple-map is the system's picture — every engine and where its decisions live. Today it is **hand-maintained HTML**, which means it can (and did, twice) drift from the code and lie, and updating it is a manual chore on every relevant PR. The fix is to **generate it from the code** and **guard it against drift in CI**, so it is honest *by construction* and maintains itself.

This spec is **v1**: the **backend-derivable, single-repo, CI-guarded core**. Cross-repo views (FE exemption registry, FE health) are explicitly deferred to v2 (see §9) because a generator in one repo cannot see the other in CI.

## 2. Goals / Non-goals

**Goals**
- The dashboard is **generated** from the backend engines — never hand-edited.
- A **CI drift-guard** fails if the committed dashboard diverges from what the code produces. A permission-matrix change is then either red CI (forgot to regenerate) or a clean, reviewable data diff in the PR.
- The dashboard lives in the **backend repo** (alongside the README), clickable on the repo.
- New engines plug into **one registry**; their views appear automatically.

**Non-goals (v1)**
- Cross-repo views: FE `// sentinel-exempt` exemption registry, FE test counts / guard status. (v2.)
- State-machine diagrams, audit-coverage, matrix changelog — these need engines/infra that don't exist yet (Appointments, outbox, the snapshot history). They light up as those land.
- No new web framework / heavy deps. Plain generated static HTML + the existing dark-theme CSS + Mermaid CDN (the `#175` tabbed structure).

## 3. Architecture (all in `dentist-registry-backend`)

```
app/modules/<engine>/dashboard.py   # each engine exposes dashboard_data() -> dict
scripts/temple/registry.py          # ENGINES = {"permissions": permissions.dashboard_data, ...}  ← the ONE registry
scripts/temple/generate.py          # iterate ENGINES -> compute data -> render tabbed HTML   (`make temple`)
docs/architecture/temple-map.html   # committed, GENERATED, with the data embedded
tests/temple/test_no_drift.py       # the CI drift-guard + completeness check
```

One registry feeds everything. The generator is the only writer of `temple-map.html`; the guard is the wall that keeps it honest.

## 4. The `ENGINES` registry contract

`scripts/temple/registry.py` holds the single registry:

```python
from app.modules.permissions import dashboard as permissions_dashboard
ENGINES = {
    "permissions": permissions_dashboard.dashboard_data,
    # "appointments": appointments_dashboard.dashboard_data,   # added when the engine lands
}
```

Each engine module exposes a **pure** `dashboard_data() -> dict` returning a serialisable structure the generator renders. The v1 shape (permissions):

```python
{
  "title": "Permissions",
  "matrix": {            # role × action → decision, COMPUTED by running can()
     "actions": [{"key": "decide_booking", "label": "Approve/reject a booking", "owns": "app/modules/permissions/policy.py:53"}, ...],
     "roles": ["owner", "doctor", "assistant"],
     # each cell: {allowed: bool, qualifier?: str}. `qualifier` is DISPLAY-derived (the ●/⚙
     # markers), computed from can() — e.g. own-resource (can(is_self=True) but not is_self=False),
     # or setting-gated. It is NOT the removed CapabilityRead.scope field.
     "cells": {"decide_booking": {
        "owner":     {"allowed": true},
        "doctor":    {"allowed": true,  "qualifier": "own assigned only"},
        "assistant": {"allowed": false, "qualifier": "if allow_staff_approval"}}, ...},
  },
  "reverse_index": [{"question": "Approve a booking", "decided_at": "app/modules/permissions/policy.py:53", "via": "can(... DECIDE_BOOKING)"}, ...],
  "settings_behavior": [{"setting": "allow_staff_approval", "gates": ["decide_booking (assistant)"]}, ...],
  "personas": {"owner": ["...everything..."], "doctor": [...], "assistant": [...]},
}
```

The matrix/personas are computed by **executing `can()`** over the grid — the same technique the 45/45 proof already uses — so they are the engine's truth, not a transcription. `reverse_index` and `settings_behavior` are derived from the engine's action catalog + the policy's structure.

The **completeness check** (a registry contract, enforced by the guard): every module exposing a `dashboard_data` must be in `ENGINES`, so no engine escapes the dashboard.

## 5. The generator (`scripts/temple/generate.py`, `make temple`)

- Imports `ENGINES`, calls each `dashboard_data()`, assembles a top-level `temple_data` dict (plus repo-level facts that are backend-derivable: per-engine test count via collecting pytest, guard status, the snapshot ref).
- **Deterministic:** no wall-clock. The "snapshot" label is the **git commit short-SHA / date from `git`**, injected — never `datetime.now()` — so regenerating the same tree yields byte-identical output.
- Renders the **tabbed HTML** (reusing the `#175` structure: Overview / Permissions / per-engine tabs / Sentinel Rules; dark-theme tokens; Mermaid CDN), with the full `temple_data` embedded as `<script type="application/json" id="temple-data">…</script>`. Visible tables/cards/Mermaid are rendered from that data (server-side at generation, so the file is self-contained and static).
- Writes `docs/architecture/temple-map.html`.

`make temple` runs the generator. A developer never hand-edits the HTML; they change code and run `make temple`.

## 6. The drift-guard (`tests/temple/test_no_drift.py`, CI)

Two assertions, both in one place — the single guard across all engines:

1. **No drift:** extract the `#temple-data` JSON from the committed `temple-map.html`, recompute `temple_data` from `ENGINES`, assert **equal**. If a permission rule changed and the HTML wasn't regenerated → fail, pointing at "run `make temple`". The PR diff of the embedded JSON shows exactly which cell flipped.
2. **Completeness:** assert every engine module exposing `dashboard_data` is registered in `ENGINES` — you cannot add an engine whose matrix escapes the dashboard.

This mirrors `tests/permissions/test_no_bypass.py` in spirit: one wall, in one place, that fails CI. It runs in the existing `make test` / pytest CI.

## 7. v1 views (all backend-derivable)

- **Permission matrices** — per engine (today: Permissions), computed by running `can()`.
- **Reverse index** — "where is X decided?" → the one `file:line`, from the registry/catalog.
- **Settings→behavior** — which clinic setting gates which decision.
- **Per-role persona cards** — "everything an assistant can do," one card per role.

The Overview tab keeps the doctrine banner + a per-engine status strip (engine present?, test count, guard 🟢/🔴 — backend only in v1). Appointments/Availability tabs remain the honest "no engine yet" placeholders until those engines register.

## 8. Migration: retire the docs-repo temple-map

The current `dentail-register-docs/docs/architecture/temple-map.html` (hand-maintained) is **retired**: replaced by a one-line pointer to the generated backend-repo `temple-map.html`, so there is a **single source**. The backend README links to the generated file. (GitHub renders committed HTML as source on a private repo; viewing rendered is local `open …` / future GitHub Pages — out of scope here.)

## 9. v2 (deferred, noted so the v1 boundaries are deliberate)

Cross-repo views, once we choose the mechanism: **per-repo data files** (each repo emits + CI-guards its own `temple-data-<repo>.json`; the dashboard assembles both) is the likely path. Adds: FE **exemption registry** (`// sentinel-exempt` markers), FE health (test counts, guard status), cross-repo dependency edges. Plus engine-gated views: **state machines** (Appointments transition table → Mermaid), **audit coverage** (outbox), **matrix changelog** (history of the embedded-data snapshot).

## 10. Testing

- The **drift-guard itself** is the primary test (no-drift + completeness), with a self-test ("has teeth": a mutated `temple_data` makes it fail).
- **Honest unit tests** for each `dashboard_data()` builder: assert the computed matrix equals `can()` for the grid (it must, since it calls `can()`), and that `reverse_index`/`settings_behavior` entries point at real `file:line`s.
- The generator is deterministic: a test asserts two runs on the same tree produce byte-identical HTML.

## 11. Risks & mitigations

- **Non-determinism breaks the guard** → no wall-clock/random; snapshot ref from git; determinism test.
- **Generator drifts from the view** (data embedded but HTML renders stale) → the HTML renders *from* the embedded data, so they can't disagree; the guard checks the data.
- **Scope creep into v2** → v1 is single-repo, backend-derivable only; cross-repo explicitly deferred.
- **`file:line` anchors rot** → derive them from the live symbols where possible (e.g. `inspect` the policy function), not hand-typed strings.

## 12. PR sequence

1. `dashboard_data()` for the permissions engine + the `ENGINES` registry + unit tests (no generator yet — prove the data).
2. The generator (`generate.py`, `make temple`) + the rendered `temple-map.html` (move into backend repo).
3. The drift-guard (`test_no_drift.py`) + CI wiring + the determinism test.
4. Retire the docs-repo temple-map (pointer) + README link.
