#!/bin/bash
# Runs every test suite under tests/ exactly once:
#   - each tests/*/run.sh (group runners, e.g. knowledge/run.sh, status/run.sh)
#   - each top-level tests/test-*.sh that no group runner already covers
# tests/test-helpers.sh is a helper library (sourced, not run). The cross-plugin
# contract test is run by knowledge/run.sh, so it is skipped here.
# Exits non-zero if any suite fails.
DIR="$(cd "$(dirname "$0")" && pwd)"
SKIP_TOP="test-helpers.sh test-cross-plugin-contract.sh"

suites=()
for s in "$DIR"/*/run.sh; do
  [ -f "$s" ] && suites+=("$s")
done
for t in "$DIR"/test-*.sh; do
  [ -f "$t" ] || continue
  name="${t##*/}"
  case " $SKIP_TOP " in *" $name "*) continue ;; esac
  suites+=("$t")
done

fail=0
for s in "${suites[@]}"; do
  rel="${s#"$DIR"/}"
  printf '=== %s\n' "$rel"
  if bash "$s"; then
    :
  else
    fail=$((fail + 1))
    printf '!!! %s FAILED\n' "$rel"
  fi
  echo
done

printf 'SUMMARY: %d suite(s), %d passed, %d failed\n' "${#suites[@]}" "$((${#suites[@]} - fail))" "$fail"
[ "$fail" -eq 0 ]
