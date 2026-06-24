# Doctor + Assistant Audit/Observability Consistency Pass — Design Spec (#34)

**Status:** Approved (2026-06-24). Issue **#34** (tech-debt). **Backend-only, isolated** (parallel-lane safe). **No migration, no frontend.** Four nits carried **verbatim across the Doctor and Assistant services** — fix BOTH mirrors together to keep them consistent. Surfaced in the SP2 Assistant review.

**Type:** Tighten audit/observability correctness in `doctors/service.py` + `assistants/service.py` (and one caller in `invites/service.py`), plus minor test hygiene.

---

## 1. Goal
Make the doctor/assistant audit trail honest and observable: no silent state corruption, no missed `*.updated` events on combined edits, stable enum values, and clean tests. Each fix is mirrored across **both** services so the Doctor/Assistant mirror never drifts.

## 2. Fixes (each mirrored: doctor **and** assistant)

### Nit 1 — `link_user_to_*` on missing entity → **log + raise** (rollback-safe)
- **Today:** `doctors/service.py:300` and `assistants/service.py:282` **silently `return`** if the entity row is missing → the membership is linked to nothing, with **no `*.activated` audit** and no trace.
- **Fix:** log a structured **error** (with `doctor_id`/`assistant_id`, `user_id`) and **`raise NotFoundError(...)`** with a clear message (e.g. *"The doctor profile for this invitation no longer exists."*).
- **Safe by construction:** the only caller, `invites/service.py` (accept flow, lines ~83–119), runs in a **single uncommitted transaction** — it `db.add(member)` + `db.flush()` and commits only at the end. Raising here **aborts the whole accept atomically**: the membership + `invite.status=accepted` roll back, the invite stays `pending`, no orphan member. The endpoint returns a clean **404** (existing `not_found` envelope) — the invitee sees "this invitation is no longer valid", and the owner can re-invite.
- **No caller change required** (the global exception handler converts `NotFoundError` → 404 + rolls back). Confirm the accept endpoint's session rolls back on exception (it does — FastAPI dep teardown). A nicer dedicated code (`invite_target_missing`) is an **optional** FE-i18n follow-up, **out of scope** here to keep #34 backend-only.

### Nit 2 — combined status + field edit → **emit BOTH events**
- **Today:** `doctors/service.py:115` / `assistants/service.py:112`: `action = "*.status_changed" if new_status is not None else "*.updated"`. A patch that changes **status AND non-status fields** emits only `*.status_changed`, so consumers filtering `*.updated` **miss the field edits**.
- **Fix:** compute two flags — `status_changed = new_status is not None and new_status != old_status`; `fields_changed = any non-status field actually changed`. Then emit:
  - `*.status_changed` **iff** `status_changed` (with the from/to status),
  - `*.updated` **iff** `fields_changed` (with the changed fields),
  - **both** when both are true (two append-only audit rows for one call).
- Keep each event's payload accurate (status event carries the status transition; updated event carries the non-status diff).

### Nit 3 — stable enum value, not literal
- **Today:** `doctors/service.py:311` / `assistants/service.py:293`: `new={"status": "active"}`.
- **Fix:** `new={"status": DoctorStatus.active.value}` / `AssistantStatus.active.value`.

### Nit 4 — test hygiene
- Extract the duplicated `_clinic` helper (repeated across doctor/assistant test files) into a shared **`conftest.py`** fixture.
- **Scope audit assertions to the test's `clinic_id`** (filter `audit_event` queries by the clinic under test) so they don't accidentally pass/fail on unrelated rows.

## 3. Tests (pytest; `uv run ruff check .` + `make test` green)
- **Nit 1:** accepting an invite whose linked doctor/assistant was deleted → raises `NotFoundError` (404), the membership is **not** created (transaction rolled back), invite stays `pending`, and a structured error was logged. (Mirror for both.)
- **Nit 2:** `update_*` with status-only → exactly `*.status_changed`; non-status-only → exactly `*.updated`; **both** → both events emitted, each with correct payload. (Mirror for both.)
- **Nit 3:** the `*.activated` audit row's `new["status"]` equals the enum value (regression-proof against enum renames).
- **Nit 4:** tests use the shared `_clinic` fixture; audit assertions are scoped to the test clinic.

## 4. Quality / scope
- **Backend-only**, **no migration**, **no FE** — a self-contained PR (parallel-lane safe; touches `app/modules/{doctors,assistants}/service.py`, `app/modules/invites/service.py` only for verification, and `tests/`). Does **not** touch scheduling/home/shell.
- `uv run ruff check .` clean; `make test` green; dead-code/cruft removed as found (HULK-dev hygiene). Branch → PR → squash via `gh-personal`; backend merges on green. Worktree isolation; do not create migrations.

## 5. Self-review (against the issue)
- Nit 1 silent-return → log + raise, rollback-safe via the single-transaction accept: §2. ✅
- Nit 2 combined edit → emit both: §2. ✅
- Nit 3 enum value: §2. ✅
- Nit 4 conftest dedup + clinic-scoped audit asserts: §2. ✅
- Mirrored doctor + assistant throughout; backend-only; tests per nit: §2/§3/§4. ✅
- Placeholder scan: exact files/lines, concrete behavior + tests; the only optional item (`invite_target_missing` code) is explicitly out of scope. ✅
