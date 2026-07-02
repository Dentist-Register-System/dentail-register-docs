#!/usr/bin/env bash
# Spec Ledger Guard — enforces Golden Rule 2.4.
# An "Approved" spec must have ZERO unresolved decisions: no ⛔ HALT/OPEN markers and
# no unchecked "O…" Decision-Ledger checkboxes. Fails CI otherwise.
#
# Narrow by design (no prose false positives): it keys only on the ⛔ character and on
# unchecked ledger boxes referencing decision IDs (`- [ ] … O<n>`). A DRAFT/BLOCKED spec
# is free to contain those — the guard only bites once the spec claims "Approved".
#
# Teeth: tests/fixtures or a temporary Approved-spec-with-⛔ must make this exit non-zero.
set -uo pipefail
SPECS_DIR="${1:-docs/specs}"
fail=0
shopt -s nullglob
for f in "$SPECS_DIR"/*.md; do
  [ "$(basename "$f")" = "_TEMPLATE.md" ] && continue
  status="$(grep -m1 -iE '^\*\*Status:\*\*' "$f" || true)"
  echo "$status" | grep -qi 'approved'      || continue   # only gate Approved specs
  echo "$status" | grep -qi 'not approved'  && continue    # ...but not "not approved"
  if grep -q '⛔' "$f"; then
    echo "::error file=$f:: Approved spec still contains a ⛔ HALT/OPEN marker (Golden Rule 2.4)"
    fail=1
  fi
  if grep -qE '^- \[ \] .*\bO[0-9]' "$f"; then
    echo "::error file=$f:: Approved spec still has an unchecked Decision-Ledger box O… (Golden Rule 2.4)"
    fail=1
  fi
done
if [ "$fail" = 0 ]; then echo "spec-ledger-guard: OK"; else echo "spec-ledger-guard: FAILED"; fi
exit "$fail"
