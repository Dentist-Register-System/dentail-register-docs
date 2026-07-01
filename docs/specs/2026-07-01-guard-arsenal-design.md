# Guard Arsenal — Design Spec

> **Status:** approved design (2026-07-01). Next: implementation plan via `writing-plans`.
> **Implementation repo:** `dentist-registry-backend` (backend wing only).
> **Doctrine tie-in:** the Sentinel "temple" holds the *decisions*; this arsenal is the
> **outer wall** — the CI/pre-commit guards at the gate so bad code never reaches the sentinels.

## Goal

Stand up a layered set of automated quality guards on the backend so that a whole
class of defects — architecture drift, type errors, dead code, unformatted code,
un-Pythonic bug patterns, dependency CVEs, and coverage regressions — **cannot merge
to `main`**. Each guard breaks the build. Local commits stay fast; nothing leaves a
machine unguarded.

## Non-Goals

- No frontend guards (separate wing, separate effort).
- No new *runtime* behavior — this is tooling only; product code changes only to
  *satisfy* a guard (fix a type, delete dead code, upgrade a dep).
- No permanent suppression baselines. Every finding is fixed to zero (see Adoption).

## Current state (`origin/main` @ #64)

- **Ruff** selects `E, F, I, PLC0415, TID` + `C901, PLR0911/0912/0913/0915, PLR2004`
  (mccabe complexity ≤ 10; tests exempt from the complexity/magic gates).
- **CI** (`.github/workflows/ci.yml`): `uv sync` → `ruff check .` → `alembic upgrade head`
  → `make test`. Single `test` job with a Postgres service.
- **Absent:** pre-commit, `ruff format` enforcement, import-linter, mypy, pip-audit,
  vulture, coverage floor.

## The arsenal (8 components)

| # | Guard | Catches | Library (license) |
|---|-------|---------|-------------------|
| 1 | **ruff — more families** | bugs (`B`), un-Pythonic code (`SIM`/`RET`/`C4`/`PIE`), unused args (`ARG`), stale syntax (`UP`), naive datetimes (`DTZ`), security smells (`S`), test hygiene (`PT`), exception hygiene (`TRY`) | ruff (MIT) — installed |
| 2 | **ruff format --check** | any unformatted file | ruff (MIT) |
| 3 | **import-linter** | architecture drift: enforces `core/ ← modules/ ← main.py`, cross-module only via `service`, no import cycles | import-linter (BSD) |
| 4 | **mypy** | type errors / real bugs the types expose | mypy (MIT) — CI gate |
| 5 | **pip-audit** | known CVEs in dependencies | pip-audit (Apache-2.0) |
| 6 | **vulture** | dead code (unused/unreachable) | vulture (MIT) |
| 7 | **coverage floor** | test-coverage regressions (`--cov-fail-under`) | pytest-cov (MIT) |
| 8 | **pre-commit** (orchestrator) | runs the fast guards on every commit | pre-commit (MIT) |

**Editor-only (not a CI gate):** pyright / Pylance gives live in-editor type feedback.
mypy is the authoritative gate; pyright is the fast local mirror. The two mostly agree.

**Deliberately excluded:** `bandit` (ruff's `S` family covers it), `safety`
(pip-audit supersedes it). All eight libs are permissive — Golden §3 clean.

## Adoption model — fix-all-now, per tool

Every tool follows the same drill:

1. **Measure first.** Enable the tool, capture the *real* finding count, report it.
   No config guesses; the number drives the plan.
2. **Fix to zero.** Fix every finding in that tool's own PR. Merge green — no
   suppression baseline file, ever.
3. **Severity.** Most guards hard-fail always. Two carry a *justified-exception*
   policy — the same bar as the existing ruff work: a documented reason, never a
   silent dodge, never linter-gaming:
   - **pip-audit:** hard-fail on any **fixable** CVE (upgrade the dep). A CVE with
     **no fix available** → explicit `--ignore-vuln <ID>` with an inline comment
     naming the CVE, why it doesn't apply / can't be fixed, and a tracking note.
     A conscious, reviewed exception — not swept under the rug.
   - **vulture:** hard-fail; genuinely-intentional "dead" code (Pydantic validators,
     FastAPI `Depends`, dynamically-referenced attrs) goes in a justified whitelist,
     each entry reasoned. Start `min_confidence = 80` to cut false positives
     (`# ponytail:` naming the ceiling; tighten later).

**mypy is the wildcard.** Measure the error count first; drive it to **zero** at
`strict = true`. If the count is large, deliver it **staged by module** across
multiple PRs — still zero at the end, still no permanent baseline.

## Where guards run

- **pre-commit** (fast, every `git commit`): `ruff check --fix`, `ruff format --check`,
  `import-linter`. Sub-second; keeps commits instant.
- **pre-push + CI** (slow, before code leaves the machine): mypy, pytest+coverage,
  pip-audit, vulture.
- **CI shape:** a new **`guards` job** with **no Postgres service** (pure static
  analysis, runs fast, parallel to `test`) carries ruff / format / import-linter /
  mypy / pip-audit / vulture. **Coverage** stays inside the existing `test` job
  (it needs pytest + the DB).
- **`make guards`** runs the whole wall locally in one command.

## Sequencing — one green PR per tool

Cheap-and-high-signal first; biggest last so momentum banks quick wins. Each PR wires
its own tool into the `guards` job (and pre-commit where applicable) as it lands, so
`main` is always fully guarded up to that point.

1. **pre-commit scaffold + `ruff format`.** Install pre-commit; apply `ruff format`
   across the repo once (large but purely mechanical whitespace diff — isolated so
   review is trivial); wire the fast hooks (`ruff check`, `ruff format --check`);
   add `ruff format --check` to CI.
2. **import-linter.** Encode the dependency contracts CLAUDE.md already states
   (layered `core/ ← modules/ ← main.py`; cross-module only via `service`; no cycles).
3. **ruff extra families** (`B SIM RET ARG UP DTZ S PT TRY C4 PIE`). Measure per
   family; fix all. Split into more than one PR if a single family's backlog is huge.
4. **pip-audit.**
5. **vulture.**
6. **coverage floor.** Set `--cov-fail-under` = measured current %, ratchet up over
   time; never regress.
7. **mypy** (`strict = true`; staged by module if the error count is large).
8. **Final wrap.** temple-map "outer wall" picture (this docs repo), README section
   documenting the wall, `make guards` target consolidated.

## Files touched (across the effort)

- **New:** `.pre-commit-config.yaml`, `.importlinter` (or `[tool.importlinter]` in
  `pyproject.toml`), vulture whitelist file (if needed).
- **`pyproject.toml`:** ruff `select` additions; new `[tool.mypy]`, `[tool.coverage.*]`,
  `[tool.vulture]` (and import-linter config if inlined); `[dependency-groups] dev` +=
  `mypy`, `import-linter`, `pip-audit`, `vulture`, `pytest-cov`, `pre-commit`.
- **`.github/workflows/ci.yml`:** new `guards` job; coverage flag on the `test` job.
- **`Makefile`:** `make guards` (+ `make typecheck`, `make audit` conveniences).
- **`README.md`:** document the wall.
- **`docs/architecture/temple-map.html`** (this repo): the outer-wall picture (step 8).
- **Product code:** only as needed to reach zero findings per tool.

## Success criteria

- All 8 guards live; each breaks the build on a fresh violation.
- Zero findings across every guard on `main` (mypy possibly staged, but zero at the
  end), with only documented, justified pip-audit ignores / vulture whitelist entries.
- Local `git commit` runs the fast guards in < ~2s; `git push` / CI runs the full wall.
- `make guards` reproduces the CI wall locally.
