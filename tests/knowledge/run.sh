#!/bin/bash
# Run every oh-my-knowledge test group plus the cross-plugin contract test.
#
#   bash tests/knowledge/run.sh [filter ...]
#
# filter: only run groups whose file name contains one of the words
#         (e.g. `hooks config`). Exits non-zero when any group fails.
# Every test uses a temp HOME and env overrides; the real ~/.gemini, ~/knowledge
# and ~/.claude are never touched.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TESTS_DIR="$(dirname "$SCRIPT_DIR")"
PLUGIN="$(dirname "$TESTS_DIR")/plugins/oh-my-knowledge"

FILTERS=("$@")
want() {
  local f="$1" x
  [ "${#FILTERS[@]}" -gt 0 ] || return 0
  for x in "${FILTERS[@]}"; do case "$f" in *"$x"*) return 0 ;; esac; done
  return 1
}

fail=0; total_run=0; total_pass=0; total_fail=0; groups=0
LOG="$(mktemp)"; trap 'rm -f "$LOG"' EXIT

# Syntax gate: every shell script of the plugin must parse (bash -n).
if want syntax || [ "${#FILTERS[@]}" -eq 0 ]; then
  bad=0
  for f in "$PLUGIN"/hooks/*.sh "$PLUGIN"/scripts/*.sh "$PLUGIN"/scripts/lib/*.sh "$SCRIPT_DIR"/*.sh "$TESTS_DIR"/*.sh; do
    bash -n "$f" 2>"$LOG" || { echo "SYNTAX ERROR: $f"; cat "$LOG"; bad=1; }
  done
  if [ "$bad" = 0 ]; then echo "== syntax (bash -n): ok"; else echo "== syntax (bash -n): FAILED"; fail=1; fi
fi

for t in "$SCRIPT_DIR"/test-*.sh "$TESTS_DIR/test-cross-plugin-contract.sh"; do
  [ -f "$t" ] || continue
  name="${t##*/}"
  want "$name" || continue
  groups=$((groups + 1))
  echo "== $name"
  bash "$t" 2>&1 | tee "$LOG" | grep -v '^  ✓' 
  rc=${PIPESTATUS[0]}
  line="$(grep -E '^[0-9]+ run, [0-9]+ passed, [0-9]+ failed' "$LOG" | tail -n1)"
  if [ -n "$line" ]; then
    r="${line%% run*}"; p="${line#*, }"; p="${p%% passed*}"; f="${line##*, }"; f="${f%% failed*}"
    total_run=$((total_run + r)); total_pass=$((total_pass + p)); total_fail=$((total_fail + f))
  else
    echo "  (no summary line)"; rc=1
  fi
  [ "$rc" -eq 0 ] || fail=1
done

echo
echo "TOTAL: $groups groups, $total_run tests, $total_pass passed, $total_fail failed"
[ "$fail" -eq 0 ] && echo "ALL PASSED" || echo "FAILURES"
exit "$fail"
