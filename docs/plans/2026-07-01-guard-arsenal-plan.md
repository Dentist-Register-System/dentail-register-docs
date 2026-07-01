# Guard Arsenal Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up 8 automated quality guards on `dentist-registry-backend` so architecture drift, type errors, dead code, unformatted code, un-Pythonic bug patterns, dependency CVEs, and coverage regressions cannot merge to `main`.

**Architecture:** Each guard is adopted in its **own green PR** (one tool per PR), fix-all-now (zero findings, no suppression baselines). Fast guards run on pre-commit; slow guards run on pre-push + a new CI `guards` job. Config lives in `pyproject.toml` + `.pre-commit-config.yaml`; wiring lives in `.github/workflows/ci.yml` and `Makefile`.

**Tech Stack:** Python 3.12, uv, ruff, mypy, import-linter, pip-audit, vulture, pytest-cov, pre-commit. All MIT/BSD/Apache (Golden §3 clean).

## Global Constraints

- **One green PR per tool.** Each task = one branch off `origin/main` → PR → merge. `main` stays fully guarded to that point. Merge-only; **no releases** (releases run BE→FE through the QA gatekeeper, separately).
- **Fix-all-now, zero findings.** No `# noqa`/`# type: ignore`/baseline dodges. The only permitted suppressions are the two *justified-exception* policies (pip-audit no-fix CVEs; vulture confirmed-intentional whitelist), each with an inline reason.
- **Behavior-preserving.** Product code changes only to satisfy a guard (fix a type, delete dead code, upgrade a dep, reformat). No runtime behavior change. 842-test suite green after every task.
- **Ponytail on every code-writing dispatch.** Prepend the directive from `<scratch>/ponytail-mode.md` to every implementer/fixer subagent (Claude Code doesn't inherit it).
- **Split:** pre-commit = `ruff check`, `ruff format --check`, `import-linter` (fast). pre-push + CI `guards` job = mypy, pip-audit, vulture. Coverage lives in the existing `test` job.
- **Dev deps** go in `[dependency-groups] dev` in `pyproject.toml`; install via `uv sync`.
- **Baseline config (already on `origin/main` #64):** ruff `line-length = 100`, `target-version = "py312"`, `select = ["E","F","I","PLC0415","TID","C901","PLR0911","PLR0912","PLR0913","PLR0915","PLR2004"]`, mccabe `max-complexity = 10`, `per-file-ignores` exempts `tests/**` from PLC0415 + the complexity/magic gates.
- **CI baseline:** `.github/workflows/ci.yml` has one `test` job: `uv sync` → `ruff check .` → `alembic upgrade head` → `make test` (Postgres service on 5433).

**Per-task adoption protocol** (every tool task follows this — the config/wiring below is exact; the *fixes* are emergent and driven by this loop):
1. Add the dev dependency; `uv sync`.
2. Add the tool's config to `pyproject.toml` (exact blocks below).
3. **Measure:** run the tool, record the finding count, report it before fixing.
4. **Fix to zero:** fix every finding (Ponytail-guided — root cause, smallest correct diff). Re-run the 842-test suite; it must stay green.
5. **Wire:** add the tool to the CI `guards` job (+ pre-commit if it's a fast guard) exactly as specified.
6. **Verify:** the tool reports zero; `make guards` (once it exists) and `uv run pytest` both pass.
7. **Commit + open PR** off `origin/main`. Flag "no migration" in the PR body.

---

### Task 1: pre-commit scaffold + `ruff format`

Stands up the pre-commit framework and adopts `ruff format` repo-wide (the format pass is a large but purely mechanical whitespace diff — isolate it here so review is trivial).

**Files:**
- Create: `.pre-commit-config.yaml`
- Modify: `pyproject.toml` (`[dependency-groups] dev` += `pre-commit`)
- Modify: `.github/workflows/ci.yml` (add `guards` job with `ruff format --check`)
- Modify: `Makefile` (add `guards` target)
- Reformat: every `.py` under `app/` and `tests/` (mechanical)

- [ ] **Step 1: Add `pre-commit` to dev deps**, `uv sync`.

- [ ] **Step 2: Measure the format delta.** Run `uv run ruff format --check .` and record how many files would reformat (expected: many — format has never run).

- [ ] **Step 3: Apply the format once.** `uv run ruff format .` — this is the whole "fix". Confirm `uv run ruff check .` still passes (format + lint are compatible at line-length 100) and `uv run pytest` stays green (formatting never changes behavior).

- [ ] **Step 4: Create `.pre-commit-config.yaml`:**
```yaml
repos:
  - repo: https://github.com/astral-sh/ruff-pre-commit
    rev: v0.8.6
    hooks:
      - id: ruff
        args: [--fix]
      - id: ruff-format
        args: [--check]
```
(import-linter is added to this file in Task 2, not now.)

- [ ] **Step 5: Add the `guards` CI job** to `.github/workflows/ci.yml` (parallel to `test`, no Postgres):
```yaml
  guards:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: astral-sh/setup-uv@v5
        with:
          python-version: "3.12"
      - run: uv sync
      - run: uv run ruff check .
      - run: uv run ruff format --check .
```

- [ ] **Step 6: Add the `guards` Makefile target:**
```makefile
guards:
	uv run ruff check .
	uv run ruff format --check .
```
(Later tasks append their tool line to this target and the CI job.)

- [ ] **Step 7: Install the hook locally** — `uv run pre-commit install` — and run `uv run pre-commit run --all-files`; expect all-pass (repo already formatted).

- [ ] **Step 8: Verify + commit + PR.** `make guards` passes; `uv run pytest` green. Commit the format pass and the scaffold as **two commits** (format-only commit first, so reviewers can skip it) on branch `feat/guards-precommit-format`. Open PR (no migration).

---

### Task 2: import-linter (architecture contracts)

Encodes the dependency rules `CLAUDE.md` already states so drift breaks the build.

**Files:**
- Modify: `pyproject.toml` (`[dependency-groups] dev` += `import-linter`; add `[tool.importlinter]` config)
- Modify: `.pre-commit-config.yaml` (add a local `lint-imports` hook)
- Modify: `.github/workflows/ci.yml` `guards` job + `Makefile` `guards` target

**Contracts to enforce** (the rules from `CLAUDE.md` "Import discipline"):
1. **Layered:** `app.core` → (nothing in app), `app.modules` may import `app.core`, `app.main` may import both. i.e. `core` is the lowest layer, `modules` above it, `main` on top.
2. **Modules are siblings, isolated:** no `app.modules.X` imports `app.modules.Y` internals — cross-module only via the other module's `service` (independence contract with allowed `service` exception is not expressible directly; use a `layers`/`independence` contract and, where a legit cross-module `service` import exists, that's surfaced at measure-time and encoded as an allowed exception in the contract, documented inline).

- [ ] **Step 1: Add `import-linter` to dev deps**, `uv sync`.

- [ ] **Step 2: Add `[tool.importlinter]` to `pyproject.toml`:**
```toml
[tool.importlinter]
root_package = "app"

[[tool.importlinter.contracts]]
name = "Layered architecture (core <- modules <- main)"
type = "layers"
layers = [
    "app.main",
    "app.modules",
    "app.core",
]

[[tool.importlinter.contracts]]
name = "Modules are independent (cross-module only via service)"
type = "independence"
modules = [
    "app.modules.assistants",
    "app.modules.auth",
    "app.modules.clinics",
    "app.modules.doctors",
    "app.modules.invites",
    "app.modules.members",
    "app.modules.patients",
    "app.modules.permissions",
    "app.modules.preferences",
    "app.modules.scheduling",
    "app.modules.staff",
    "app.modules.audit",
    "app.modules.email",
]
```

- [ ] **Step 3: Measure.** `uv run lint-imports` and record violations. Expect the `independence` contract to surface real cross-module imports (e.g. scheduling → permissions, invites → members).

- [ ] **Step 4: Fix to zero.** For each violation decide, per the Sentinel doctrine: a legitimate cross-engine call must go through the other module's **public `service`/engine API** (Rule 12) — if it does, it's an *allowed* edge; encode it by narrowing the contract (e.g. an `independence` contract that excludes the public-API import, or a `forbidden` contract that bans only internals `models`/`router`/`repository`). If it's a genuine violation (importing another module's internals), refactor the import to the public surface. Document each allowed edge inline. Do **not** weaken a contract to hide a real violation.

- [ ] **Step 5: Wire.** Add to `.pre-commit-config.yaml`:
```yaml
  - repo: local
    hooks:
      - id: import-linter
        name: import-linter
        entry: uv run lint-imports
        language: system
        pass_filenames: false
        always_run: true
```
Add `uv run lint-imports` to the CI `guards` job and the `Makefile` `guards` target.

- [ ] **Step 6: Verify + commit + PR.** `uv run lint-imports` reports "Contracts: N kept, 0 broken"; `make guards` + `uv run pytest` green. Branch `feat/guards-import-linter`, PR (no migration).

---

### Task 3: ruff extra families

Extends the ruff `select` with bug/quality/security families, fixing each to zero.

**Files:** Modify `pyproject.toml` (`[tool.ruff.lint] select` + any `per-file-ignores`); product/test code fixes as found.

**Families to add:** `B` (bugbear), `SIM` (simplify), `RET` (return), `ARG` (unused args), `UP` (pyupgrade), `DTZ` (naive datetime), `S` (bandit/security), `PT` (pytest style), `TRY` (exception hygiene), `C4` (comprehensions), `PIE` (misc).

- [ ] **Step 1: Measure per family.** For each family run `uv run ruff check --select <FAM> --statistics .` and record counts. This reveals which families are cheap (fix now) and whether any single family is huge (→ its own PR).

- [ ] **Step 2: Adopt in ascending-backlog order.** Add families to `select` incrementally; after each, run `uv run ruff check --fix .` (auto-fixes the mechanical ones), then hand-fix the rest Ponytail-guided. Known judgement calls:
  - `S` (security): `S101` (asserts) fires in `tests/**` legitimately → add `"S101"` (and test-only `S` noise) to `per-file-ignores` for `"tests/**"`. Real `S` findings in `app/**` (e.g. `S105`/`S106` hardcoded-secret, `S608` SQL) are fixed, never ignored.
  - `DTZ`: naive `datetime.now()`/`utcnow()` → make tz-aware (`datetime.now(tz=UTC)`), matching the "Timezone-aware timestamps" convention in `CLAUDE.md`.
  - `ARG`: unused FastAPI/pytest fixture args are often required-by-framework → `ARG001` on those is a real signal to rename to `_`-prefixed or wire correctly, not blanket-ignore.

- [ ] **Step 3: Update `per-file-ignores`** for the genuinely test-only families only (e.g. `S101`, `PT` exemptions if any), each with a one-line comment. Never exempt `app/**`.

- [ ] **Step 4: Verify + commit + PR.** `uv run ruff check .` clean with the full `select`; `uv run pytest` green. Branch `feat/guards-ruff-families` (or split e.g. `feat/guards-ruff-security` if `S`/`B` backlog is large — decide from Step 1 counts). PR (no migration). Final `select` documented in the PR body.

---

### Task 4: pip-audit (dependency CVEs)

**Files:** Modify `pyproject.toml` (`[dependency-groups] dev` += `pip-audit`); `.github/workflows/ci.yml` `guards` job; `Makefile` `guards` target. Dep upgrades as found (lockfile).

- [ ] **Step 1: Add `pip-audit` to dev deps**, `uv sync`.

- [ ] **Step 2: Measure.** `uv run pip-audit` (audits the installed environment) — record every CVE, the affected package, and whether a fixed version exists.

- [ ] **Step 3: Fix to zero.** For each **fixable** CVE: bump the dependency floor in `pyproject.toml` `dependencies`, `uv sync`, re-run the suite (green). For a CVE with **no fix available**: add `--ignore-vuln <ID>` to the audit invocation with an inline comment naming the CVE, the package, why it's unfixable/not-applicable, and a tracking note. (Justified exception — the only permitted suppression.)

- [ ] **Step 4: Wire.** Add to CI `guards` job and `Makefile` `guards` target:
```
	uv run pip-audit
```
(pip-audit is CI/pre-push only — network-dependent, not on pre-commit.)

- [ ] **Step 5: Verify + commit + PR.** `uv run pip-audit` reports no known vulns (or only the documented ignores); `uv run pytest` green. Branch `feat/guards-pip-audit`. PR body flags any dep-floor bumps (no Alembic migration).

---

### Task 5: vulture (dead code)

**Files:** Modify `pyproject.toml` (`[dependency-groups] dev` += `vulture`; add `[tool.vulture]`); create `tests/vulture_whitelist.py` if needed; CI `guards` job; `Makefile`.

- [ ] **Step 1: Add `vulture` to dev deps**, `uv sync`.

- [ ] **Step 2: Add `[tool.vulture]` to `pyproject.toml`:**
```toml
[tool.vulture]
paths = ["app"]
min_confidence = 80
# ponytail: 80% floor cuts framework false positives (Pydantic validators,
# FastAPI Depends, dynamic attrs); tighten toward 60 later once the whitelist is stable.
```

- [ ] **Step 3: Measure.** `uv run vulture` and record findings.

- [ ] **Step 4: Fix to zero.** Genuinely dead code → delete it (Ponytail: deletion over addition). Framework false positives (referenced dynamically — Pydantic model validators, FastAPI dependency callables, SQLAlchemy event hooks) → add to `tests/vulture_whitelist.py`, each entry with a one-line reason. Run vulture with the whitelist: `uv run vulture app tests/vulture_whitelist.py`.

- [ ] **Step 5: Wire.** CI `guards` job + `Makefile` `guards` target:
```
	uv run vulture app tests/vulture_whitelist.py
```

- [ ] **Step 6: Verify + commit + PR.** vulture reports nothing (outside the justified whitelist); `uv run pytest` green. Branch `feat/guards-vulture`. PR (no migration).

---

### Task 6: coverage floor

**Files:** Modify `pyproject.toml` (`[dependency-groups] dev` += `pytest-cov`; add `[tool.coverage.run]`/`[tool.coverage.report]`; `[tool.pytest.ini_options] addopts`); `.github/workflows/ci.yml` `test` job.

- [ ] **Step 1: Add `pytest-cov` to dev deps**, `uv sync`.

- [ ] **Step 2: Measure.** `uv run pytest --cov=app --cov-report=term-missing` — record the current total coverage %.

- [ ] **Step 3: Set the floor at the measured value** (rounded down to a whole number — do NOT round up; the floor must pass today). Add to `pyproject.toml`:
```toml
[tool.pytest.ini_options]
addopts = "--cov=app --cov-report=term-missing --cov-fail-under=<MEASURED_FLOOR>"

[tool.coverage.run]
branch = true
omit = ["app/db/base.py", "*/__init__.py"]
```
(`<MEASURED_FLOOR>` filled from Step 2. `omit` excludes the Alembic model-aggregator + package inits — no logic.)

- [ ] **Step 4: Wire.** Coverage runs inside the existing `test` job automatically via `addopts` (no CI change needed beyond confirming `make test` now enforces the floor).

- [ ] **Step 5: Verify + commit + PR.** `uv run pytest` passes with the floor enforced (fails if coverage drops below it). Branch `feat/guards-coverage-floor`. PR body states the floor value and the ratchet-up intent (no migration).

---

### Task 7: mypy (strict, staged)

The wildcard. Measure first; drive to zero at `strict = true`; deliver staged by module if the count is large. No permanent baseline.

**Files:** Modify `pyproject.toml` (`[dependency-groups] dev` += `mypy`; add `[tool.mypy]`); create `py.typed` marker if needed; type-annotation fixes across `app/`; CI `guards` job; `Makefile`.

- [ ] **Step 1: Add `mypy` to dev deps**, `uv sync`.

- [ ] **Step 2: Add `[tool.mypy]` to `pyproject.toml`:**
```toml
[tool.mypy]
python_version = "3.12"
strict = true
plugins = ["pydantic.mypy"]
# SQLAlchemy 2.0 ships PEP 561 stubs; pydantic plugin handles model typing.

[[tool.mypy.overrides]]
module = "tests.*"
disallow_untyped_defs = false
```
(Add `pydantic` mypy plugin; SQLAlchemy 2.x is natively typed. Tests are looser — test fns need not be fully annotated, but are still type-checked.)

- [ ] **Step 3: Measure.** `uv run mypy app` and record the total error count. **Report it before fixing** — this number decides staging:
  - **< ~150 errors:** fix all in one PR.
  - **≥ ~150 errors:** stage by module — fix `app/core` first (everything depends on it), then modules in dependency order (`permissions`, `scheduling`, …), **one PR per module or small group**, each PR reaching zero mypy errors *for the modules checked so far* by narrowing the checked scope (e.g. `files`/`exclude` in config, tightened each PR) — NOT by baselining. The final PR removes the scope narrowing so `uv run mypy app` is fully clean.

- [ ] **Step 4: Fix to zero (per stage).** Add real annotations (Ponytail: minimal, correct — annotate the actual types, don't `Any`-cast to silence). A per-line `# type: ignore[code]` is allowed ONLY for a genuine third-party-stub gap, with the specific error code + an inline reason. Re-run the 842-test suite after each stage; green.

- [ ] **Step 5: Wire (final stage only).** Add to CI `guards` job + `Makefile` `guards` target:
```
	uv run mypy app
```

- [ ] **Step 6: Verify + commit + PR(s).** `uv run mypy app` reports "Success: no issues"; `uv run pytest` green. Branch(es) `feat/guards-mypy` (or `feat/guards-mypy-core`, `-modules`, … if staged). Each PR (no migration).

---

### Task 8: Final wrap — temple-map, README, `make guards`

Documents the outer wall and consolidates the local entry point.

**Files:**
- Modify (docs repo): `docs/architecture/temple-map.html` — add the "outer wall / guards at the gate" picture.
- Modify (backend): `README.md` — a "Quality guards" section listing the 8 guards, what each catches, and `make guards`.
- Verify: `Makefile` `guards` target now runs the full static wall (ruff, format, import-linter, vulture, mypy, pip-audit).

- [ ] **Step 1: Confirm `make guards` runs the whole static wall** (all lines accumulated across Tasks 1–7). Coverage stays in `make test`. Both pass locally.

- [ ] **Step 2: README section** — table of the 8 guards (guard / catches / where it runs), plus "run the wall locally: `make guards` + `make test`". Branch `docs/guards-readme`, PR.

- [ ] **Step 3: temple-map "outer wall"** — add a section/tab to `docs/architecture/temple-map.html` depicting the guards ringing the Sentinel engines (the gate wall). Work **via the remote/API or a fresh clone sandbox-off** (the local docs checkout is sandbox-flaky). Regenerate its content fingerprint if the generator drives it. Docs-repo PR.

- [ ] **Step 4: Verify.** temple-map renders; README accurate; `make guards` + `make test` green on `main` after all merges.

---

## Self-Review

**Spec coverage:** All 8 arsenal components → Tasks 1 (pre-commit+format), 2 (import-linter), 3 (ruff families), 4 (pip-audit), 5 (vulture), 6 (coverage), 7 (mypy), 8 (temple-map/README). Adoption model (measure→fix-zero→wire), severity policy (pip-audit/vulture justified exceptions), run-split (pre-commit vs guards job vs test job), and sequencing (cheap→big) are all encoded. ✅

**Placeholder scan:** `<MEASURED_FLOOR>` (Task 6) and the mypy error count (Task 7) are *measured values*, not placeholders — the plan specifies the exact command to derive each and the rule for using it. This is inherent to measure-then-adopt, not a gap. All config blocks, CI/pre-commit wiring, and commands are concrete. ✅

**Consistency:** The `guards` CI job and `Makefile guards` target are created in Task 1 and each later task appends one exact line; the split (fast→pre-commit, slow→guards/test job) is applied uniformly. Dev deps all land in `[dependency-groups] dev`. ✅

**Emergent-fix honesty:** Lint/type/dead-code *fixes* cannot be pre-enumerated (they're discovered at measure-time) — the plan gives the exact measure command + the fix-to-zero protocol + the named judgement calls per tool, which is the honest specifiable unit. ✅
