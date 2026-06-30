# Temple Dashboard Generator (v1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Generate the temple-map dashboard from the backend permission engine and guard it against drift in CI, so it is honest by construction and maintains itself.

**Architecture:** One `ENGINES` registry maps each engine to a pure `dashboard_data()` builder (computes its matrix by running `can()`). A generator assembles all builders' data, embeds it as a JSON block in a tabbed static HTML, and writes `temple-map.html`. A CI guard recomputes the data, compares it to the embedded block (no-drift), and asserts every engine is registered (completeness).

**Tech Stack:** Python 3 (stdlib only — `json`, `html`, `importlib`, `pkgutil`, `subprocess` for the git ref), pytest, the existing FastAPI backend (`dentist-registry-backend`). No new dependencies.

## Global Constraints

- Repo: `dentist-registry-backend`. Tests run with `uv run pytest` against Postgres :5433; lint `uv run ruff check .` (whole repo). All new files carry the Sentinel header docstring (`Rules/sentinel-rules.md`).
- The generator MUST be deterministic: NO `datetime.now()` / randomness. The snapshot label comes from `git` (commit short-SHA + committer date), injected.
- `dashboard_data()` builders are PURE: no DB, no I/O — they compute from the engine (`can()`, the `Action` catalog, `MemberRole`) only.
- The generated `temple-map.html` is NEVER hand-edited; change code → run `make temple`.
- Cross-repo views (FE exemption registry, FE health) are OUT OF SCOPE (v2).

---

### Task 1: Permissions `dashboard_data()` — the matrix from `can()`

**Files:**
- Create: `app/modules/permissions/dashboard.py`
- Create: `tests/temple/__init__.py` (empty)
- Test: `tests/temple/test_permissions_dashboard.py`

**Interfaces:**
- Consumes: `from app.modules.permissions.policy import can`; `from app.modules.permissions.actions import Action`; `from app.modules.members.models import MemberRole`. `can(role, settings, action, *, is_self=False, target_role=None) -> Decision` (`.allowed: bool`).
- Produces: `dashboard_data() -> dict` with keys `title:str`, `matrix:{actions:list, roles:list, cells:dict}`, `reverse_index:list`, `settings_behavior:list`, `personas:dict`. Each matrix cell = `{"allowed": bool, "qualifier": str|None}`.

- [ ] **Step 1: Write the failing test**

```python
# tests/temple/test_permissions_dashboard.py
from types import SimpleNamespace
from app.modules.permissions import dashboard
from app.modules.permissions.actions import Action
from app.modules.permissions.policy import can
from app.modules.members.models import MemberRole

def _s(asa=True, asma=True):
    return SimpleNamespace(allow_staff_approval=asa, allow_staff_manage_availability=asma)

def test_matrix_cells_equal_can_for_every_role_action():
    data = dashboard.dashboard_data()
    cells = data["matrix"]["cells"]
    # every action × role cell's `allowed` equals the engine's best-case answer
    for action in Action:
        for role in (MemberRole.owner, MemberRole.doctor, MemberRole.assistant):
            best = can(role, _s(), action, is_self=True, target_role=MemberRole.doctor).allowed
            assert cells[action.value][role.value]["allowed"] == best, f"{role} {action}"

def test_doctor_self_gated_actions_carry_own_qualifier():
    cells = dashboard.dashboard_data()["matrix"]["cells"]
    # DECIDE_BOOKING: doctor allowed (best case) but only on own → qualifier mentions "own"
    cell = cells["decide_booking"]["doctor"]
    assert cell["allowed"] is True and cell["qualifier"] and "own" in cell["qualifier"].lower()

def test_assistant_setting_gated_action_names_the_setting():
    cells = dashboard.dashboard_data()["matrix"]["cells"]
    # assistant DECIDE_BOOKING depends on allow_staff_approval → qualifier names it
    cell = cells["decide_booking"]["assistant"]
    assert cell["qualifier"] and "allow_staff_approval" in cell["qualifier"]

def test_reverse_index_points_at_real_file():
    data = dashboard.dashboard_data()
    assert data["reverse_index"], "reverse index not empty"
    for entry in data["reverse_index"]:
        assert entry["decided_at"].startswith("app/modules/permissions/policy.py:")

def test_personas_list_every_allowed_action_per_role():
    data = dashboard.dashboard_data()
    # an owner can do everything → owner persona lists all actions
    assert len(data["personas"]["owner"]) == len(list(Action))
```

- [ ] **Step 2: Run test to verify it fails**

Run: `uv run pytest tests/temple/test_permissions_dashboard.py -q`
Expected: FAIL — `ModuleNotFoundError: app.modules.permissions.dashboard`.

- [ ] **Step 3: Write minimal implementation**

```python
# app/modules/permissions/dashboard.py
"""Sentinel rules (full set: Rules/sentinel-rules.md). Core, in-file so they propagate:
  • Each decision lives in exactly ONE engine; callers ask — they never compare roles outside permissions/.
  • One source of truth per decision. No dead code. No imports inside functions.
  • Honest tests only — real assertions, no placeholders.

Permissions — the engine's projection for the temple dashboard (matrix computed by running can()).
"""

from types import SimpleNamespace

from app.modules.members.models import MemberRole
from app.modules.permissions.actions import Action
from app.modules.permissions.policy import can

_ROLES = [MemberRole.owner, MemberRole.doctor, MemberRole.assistant]
# Human labels for the matrix rows (display only; keys are the Action values).
_ACTION_LABEL = {
    Action.DECIDE_BOOKING: "Approve / reject a booking",
    Action.CREATE_BOOKING: "Create a booking",
    Action.COORDINATE_BOOKING: "Cancel / coordinate a booking",
    Action.MANAGE_AVAILABILITY: "Manage availability",
    Action.MANAGE_PATIENTS: "Manage patients",
    Action.MANAGE_DOCTORS: "Manage doctors",
    Action.EDIT_DOCTOR: "Edit a doctor's record",
    Action.INVITE_DOCTOR: "Invite a doctor",
    Action.SELF_CREATE_DOCTOR: "Create own doctor profile",
    Action.MANAGE_ASSISTANTS: "Manage assistants",
    Action.ADMINISTER_CLINIC: "Administer clinic + settings",
    Action.MANAGE_MEMBERS: "Manage members",
    Action.CREATE_INVITE: "Create an invite",
    Action.MANAGE_INVITE: "Manage invites",
    Action.VIEW_CLINIC_SCHEDULE: "View clinic schedule",
}
# The engine lives here — one file, one decider. Used for reverse-index anchors.
_POLICY_LOC = "app/modules/permissions/policy.py:53"
_SETTINGS = ["allow_staff_approval", "allow_staff_manage_availability"]


def _settings(**flags):
    base = {s: True for s in _SETTINGS}
    base.update(flags)
    return SimpleNamespace(**base)


def _cell(role, action):
    """Best-case allowed + a display qualifier, all derived from can()."""
    on = _settings()
    best = can(role, on, action, is_self=True, target_role=MemberRole.doctor).allowed
    qualifier = None
    if best:
        # own-resource: allowed only when acting on self.
        if not can(role, on, action, is_self=False, target_role=MemberRole.doctor).allowed:
            qualifier = "own assigned only"
    # setting-gated: a flag flip changes this role's answer for this action.
    for s in _SETTINGS:
        off = _settings(**{s: False})
        if can(role, off, action, is_self=True, target_role=MemberRole.doctor).allowed != best:
            qualifier = f"if {s}"
    return {"allowed": best, "qualifier": qualifier}


def dashboard_data() -> dict:
    cells = {
        a.value: {r.value: _cell(r, a) for r in _ROLES} for a in Action
    }
    actions = [
        {"key": a.value, "label": _ACTION_LABEL[a], "owns": _POLICY_LOC} for a in Action
    ]
    reverse_index = [
        {"question": _ACTION_LABEL[a], "decided_at": _POLICY_LOC, "via": f"can(... {a.name})"}
        for a in Action
    ]
    settings_behavior = [
        {
            "setting": s,
            "gates": [
                _ACTION_LABEL[a]
                for a in Action
                if any(cells[a.value][r.value]["qualifier"] == f"if {s}" for r in _ROLES)
            ],
        }
        for s in _SETTINGS
    ]
    personas = {
        r.value: [a.value for a in Action if cells[a.value][r.value]["allowed"]]
        for r in _ROLES
    }
    return {
        "title": "Permissions",
        "matrix": {"actions": actions, "roles": [r.value for r in _ROLES], "cells": cells},
        "reverse_index": reverse_index,
        "settings_behavior": settings_behavior,
        "personas": personas,
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `uv run pytest tests/temple/test_permissions_dashboard.py -q && uv run ruff check app/modules/permissions/dashboard.py`
Expected: PASS (5 tests) · ruff clean.

- [ ] **Step 5: Commit**

```bash
git add app/modules/permissions/dashboard.py tests/temple/__init__.py tests/temple/test_permissions_dashboard.py
git commit -m "feat(temple): permissions dashboard_data() — matrix computed from can()"
```

---

### Task 2: The `ENGINES` registry + completeness

**Files:**
- Create: `scripts/temple/__init__.py` (empty), `scripts/temple/registry.py`
- Test: `tests/temple/test_registry.py`

**Interfaces:**
- Consumes: `app.modules.permissions.dashboard.dashboard_data` (Task 1).
- Produces: `scripts.temple.registry.ENGINES: dict[str, Callable[[], dict]]`; `discovered_engines() -> set[str]` (module names that expose `dashboard_data`).

- [ ] **Step 1: Write the failing test**

```python
# tests/temple/test_registry.py
from scripts.temple import registry

def test_permissions_is_registered():
    assert "permissions" in registry.ENGINES
    data = registry.ENGINES["permissions"]()
    assert data["title"] == "Permissions"

def test_completeness_every_dashboard_module_is_registered():
    # The wall: an engine that exposes dashboard_data but isn't in ENGINES is a gap.
    assert registry.discovered_engines() == set(registry.ENGINES)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `uv run pytest tests/temple/test_registry.py -q`
Expected: FAIL — `ModuleNotFoundError: scripts.temple.registry`.

- [ ] **Step 3: Write minimal implementation**

```python
# scripts/temple/registry.py
"""Sentinel rules (full set: Rules/sentinel-rules.md). Core, in-file so they propagate:
  • Each decision lives in exactly ONE engine; callers ask — they never compare roles outside permissions/.
  • One source of truth per decision. No dead code. No imports inside functions.
  • Honest tests only — real assertions, no placeholders.

Temple — the ONE registry of dashboard engines. Add an engine in exactly one place: here.
"""

import importlib
import pkgutil

import app.modules
from app.modules.permissions import dashboard as permissions_dashboard

# The single registry. Add a new engine's builder here when it lands.
ENGINES = {
    "permissions": permissions_dashboard.dashboard_data,
}


def discovered_engines() -> set[str]:
    """Every app.modules.<x>.dashboard module exposing dashboard_data, by <x>."""
    found = set()
    for mod in pkgutil.iter_modules(app.modules.__path__):
        name = f"app.modules.{mod.name}.dashboard"
        try:
            m = importlib.import_module(name)
        except ModuleNotFoundError:
            continue
        if hasattr(m, "dashboard_data"):
            found.add(mod.name)
    return found
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `uv run pytest tests/temple/test_registry.py -q && uv run ruff check scripts/temple/`
Expected: PASS (2 tests) · ruff clean.

- [ ] **Step 5: Commit**

```bash
git add scripts/temple/__init__.py scripts/temple/registry.py tests/temple/test_registry.py
git commit -m "feat(temple): ENGINES registry + completeness discovery"
```

---

### Task 3: The generator (`generate.py`, `make temple`)

**Files:**
- Create: `scripts/temple/generate.py`
- Modify: `Makefile` (add a `temple` target)
- Create (output, committed): `docs/architecture/temple-map.html`
- Test: `tests/temple/test_generate.py`

**Interfaces:**
- Consumes: `scripts.temple.registry.ENGINES`.
- Produces: `build_data() -> dict` (the full `temple_data`: `{"snapshot": str, "engines": {name: dashboard_data()}}`); `render(data: dict) -> str` (the HTML string, with `<script type="application/json" id="temple-data">` embedding `data`); `TEMPLE_HTML: pathlib.Path` (the output path); `main()` writes the file.

- [ ] **Step 1: Write the failing test**

```python
# tests/temple/test_generate.py
import json
import re
from scripts.temple import generate

def _embedded(html):
    m = re.search(r'<script type="application/json" id="temple-data">(.*?)</script>', html, re.S)
    return json.loads(m.group(1))

def test_embedded_data_equals_build_data():
    data = generate.build_data()
    html = generate.render(data)
    assert _embedded(html) == data

def test_render_is_deterministic_for_same_data():
    data = generate.build_data()
    assert generate.render(data) == generate.render(data)

def test_html_contains_a_tab_per_engine_and_the_permissions_matrix():
    html = generate.render(generate.build_data())
    assert 'id="permissions"' in html  # the permissions tab
    assert "Approve / reject a booking" in html  # a matrix row label rendered

def test_snapshot_is_git_derived_not_wallclock():
    data = generate.build_data()
    # snapshot is a short sha (hex) — never a wall-clock timestamp this test can't reproduce
    assert re.match(r"^[0-9a-f]{7,40}\b", data["snapshot"])
```

- [ ] **Step 2: Run test to verify it fails**

Run: `uv run pytest tests/temple/test_generate.py -q`
Expected: FAIL — `ModuleNotFoundError: scripts.temple.generate`.

- [ ] **Step 3: Write minimal implementation**

```python
# scripts/temple/generate.py
"""Sentinel rules (full set: Rules/sentinel-rules.md). Core, in-file so they propagate:
  • Each decision lives in exactly ONE engine; callers ask — they never compare roles outside permissions/.
  • One source of truth per decision. No dead code. No imports inside functions.
  • Honest tests only — real assertions, no placeholders.

Temple — the generator. `make temple` runs main(); writes the committed, drift-guarded HTML.
Deterministic: the snapshot ref comes from git, never the wall clock.
"""

import html as html_lib
import json
import pathlib
import subprocess

from scripts.temple.registry import ENGINES

TEMPLE_HTML = pathlib.Path(__file__).resolve().parents[2] / "docs" / "architecture" / "temple-map.html"


def _git_snapshot() -> str:
    return subprocess.run(
        ["git", "rev-parse", "--short", "HEAD"], capture_output=True, text=True, check=True
    ).stdout.strip()


def build_data() -> dict:
    return {"snapshot": _git_snapshot(), "engines": {name: fn() for name, fn in ENGINES.items()}}


def _matrix_table(engine: dict) -> str:
    m = engine["matrix"]
    head = "".join(f"<th>{html_lib.escape(r)}</th>" for r in m["roles"])
    rows = []
    for a in m["actions"]:
        tds = []
        for r in m["roles"]:
            c = m["cells"][a["key"]][r]
            mark = "✓" if c["allowed"] else "✕"
            q = f" <small>{html_lib.escape(c['qualifier'])}</small>" if c["qualifier"] else ""
            tds.append(f"<td>{mark}{q}</td>")
        rows.append(f"<tr><td>{html_lib.escape(a['label'])}</td>{''.join(tds)}</tr>")
    return f"<table><thead><tr><th>Action</th>{head}</tr></thead><tbody>{''.join(rows)}</tbody></table>"


def render(data: dict) -> str:
    tabs, panels = [], []
    for name, engine in data["engines"].items():
        tabs.append(f'<a role="tab" href="#{name}">{html_lib.escape(engine["title"])}</a>')
        panels.append(f'<section id="{name}" role="tabpanel"><h2>{html_lib.escape(engine["title"])}</h2>{_matrix_table(engine)}</section>')
    blob = json.dumps(data, indent=2, sort_keys=True)
    return (
        "<!doctype html><html><head><meta charset='utf-8'><title>Register — Temple Map</title>"
        f'<script type="application/json" id="temple-data">{blob}</script>'
        "</head><body>"
        f'<nav role="tablist">{"".join(tabs)}</nav>{"".join(panels)}'
        f"<footer>Generated from code · snapshot {html_lib.escape(data['snapshot'])} · do not hand-edit (make temple)</footer>"
        "</body></html>\n"
    )


def main() -> None:
    TEMPLE_HTML.write_text(render(build_data()))


if __name__ == "__main__":
    main()
```

> Note for the implementer: this v1 render is intentionally minimal (correct + deterministic + embeds the data). A follow-up styling pass can restore the `#175` tabbed dark-theme CSS + Mermaid; the guard only cares about the embedded `#temple-data`, so visual polish never trips it.

- [ ] **Step 4: Add the Makefile target + generate the file**

Modify `Makefile` — add:

```makefile
temple:
	uv run python -m scripts.temple.generate
```

Run: `make temple` (writes `docs/architecture/temple-map.html`), then `uv run pytest tests/temple/test_generate.py -q && uv run ruff check scripts/temple/generate.py`
Expected: file written · PASS (4 tests) · ruff clean.

- [ ] **Step 5: Commit**

```bash
git add scripts/temple/generate.py Makefile docs/architecture/temple-map.html tests/temple/test_generate.py
git commit -m "feat(temple): generator + make temple + committed generated temple-map.html"
```

---

### Task 4: The drift-guard (`test_no_drift.py`) + CI

**Files:**
- Test (this IS the deliverable): `tests/temple/test_no_drift.py`
- (CI: the backend CI already runs `uv run pytest` / `make test`, so this test runs in CI with no workflow edit — verify and note.)

**Interfaces:**
- Consumes: `scripts.temple.generate.build_data`, `generate.TEMPLE_HTML`; `scripts.temple.registry.discovered_engines`, `registry.ENGINES`.

- [ ] **Step 1: Write the failing test**

```python
# tests/temple/test_no_drift.py
import json
import re
from scripts.temple import generate, registry

def _embedded():
    html = generate.TEMPLE_HTML.read_text()
    m = re.search(r'<script type="application/json" id="temple-data">(.*?)</script>', html, re.S)
    return json.loads(m.group(1))

def test_committed_html_is_not_stale():
    # The wall: the committed dashboard must equal what the code produces now.
    # NOTE: build_data()["snapshot"] is the live git sha; compare the ENGINE data only,
    # so an un-regenerated permission change fails here pointing at `make temple`.
    live = generate.build_data()["engines"]
    committed = _embedded()["engines"]
    assert committed == live, "temple-map.html is stale — run `make temple` and commit"

def test_every_engine_is_registered():
    assert registry.discovered_engines() == set(registry.ENGINES)

def test_guard_has_teeth():
    # A mutated live matrix must NOT equal the committed snapshot.
    live = generate.build_data()["engines"]
    mutated = json.loads(json.dumps(live))
    mutated["permissions"]["matrix"]["cells"]["decide_booking"]["owner"]["allowed"] = False
    assert mutated != _embedded()["engines"]
```

- [ ] **Step 2: Run test to verify it passes (HTML was committed in Task 3)**

Run: `uv run pytest tests/temple/test_no_drift.py -q`
Expected: PASS (3 tests). (If `test_committed_html_is_not_stale` fails, the Task-3 file is stale → `make temple` and re-commit.)

- [ ] **Step 3: Prove the teeth in practice**

Run: temporarily flip a label in `app/modules/permissions/dashboard.py` (e.g. `_ACTION_LABEL`), `uv run pytest tests/temple/test_no_drift.py::test_committed_html_is_not_stale -q` → expect FAIL; revert the label; re-run → PASS. Confirm `git diff` is clean after.

- [ ] **Step 4: Confirm CI runs it**

Inspect the backend CI (`.github/workflows/*.yml` or `make test`) — confirm `uv run pytest` (whole suite) runs, so `tests/temple/test_no_drift.py` runs in CI automatically. If the workflow scopes pytest to a subset, add `tests/temple` to it. Document the finding in the commit message.

- [ ] **Step 5: Commit**

```bash
git add tests/temple/test_no_drift.py
git commit -m "feat(temple): drift-guard — committed HTML must match the engines (no-drift + completeness + teeth)"
```

---

### Task 5: Retire the docs-repo temple-map + README link

**Files (docs repo `dentail-register-docs`):**
- Modify: `docs/architecture/temple-map.html` → replace with a one-line pointer
- **Files (backend repo):** Modify `README.md` → add a link to `docs/architecture/temple-map.html`

- [ ] **Step 1: Replace the docs-repo HTML with a pointer**

In `dentail-register-docs/docs/architecture/temple-map.html`, replace the whole file with:

```html
<!doctype html><meta charset="utf-8"><title>Moved</title>
<p>The temple-map is now <b>generated</b> and lives in the backend repo:
<code>dentist-registry-backend/docs/architecture/temple-map.html</code> (run <code>make temple</code>).
This hand-maintained copy is retired — there is one source.</p>
```

- [ ] **Step 2: Link it from the backend README**

In `dentist-registry-backend/README.md`, add under a "Temple map" heading:
`The system's decision picture is generated from the engines: docs/architecture/temple-map.html (run make temple; CI guards it against drift).`

- [ ] **Step 3: Commit (one per repo)**

```bash
# docs repo
git add docs/architecture/temple-map.html && git commit -m "docs: retire hand-maintained temple-map → pointer to the generated one"
# backend repo
git add README.md && git commit -m "docs: link the generated temple-map from the README"
```

---

## Self-Review

- **Spec coverage:** §3 architecture → Tasks 1–4. §4 registry contract → Task 2. §5 generator/`make temple`/deterministic → Task 3. §6 drift-guard (no-drift + completeness + teeth) → Task 4. §7 v1 views: matrix ✓ (Task 1/3); reverse_index/settings_behavior/personas are built in Task 1's `dashboard_data` (rendered minimally in Task 3 — a styling pass restores the rest, noted). §8 migration → Task 5. §10 testing (determinism, teeth, data==can()) → Tasks 1/3/4. **Gap surfaced & accepted:** Task 3's `render()` is minimal (matrix only); reverse_index/settings_behavior/personas are in the embedded data + guarded, but their *visual* rendering + the `#175` dark-theme/Mermaid polish is a deliberate follow-up (the data is honest now; the pixels come next). This keeps v1 shippable.
- **Placeholder scan:** none — every step has real code/commands.
- **Type consistency:** `dashboard_data()` keys (`title`/`matrix`/`reverse_index`/`settings_behavior`/`personas`) and cell shape (`{allowed, qualifier}`) are identical across Tasks 1, 3, 4. `build_data()` → `{snapshot, engines}` consistent in Tasks 3 & 4. `discovered_engines()` signature matches in Tasks 2 & 4.
