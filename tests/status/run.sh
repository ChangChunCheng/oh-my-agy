#!/bin/bash
# Runs every test-*.sh in this directory; exits non-zero if any file fails.
DIR="$(cd "$(dirname "$0")" && pwd)"
fail=0 total=0
for t in "$DIR"/test-*.sh; do
  case "$t" in */test-helpers.sh) continue ;; esac
  total=$((total + 1))
  printf '== %s\n' "${t##*/}"
  bash "$t" || { fail=$((fail + 1)); printf '!! %s FAILED\n' "${t##*/}"; }
  echo
done
printf '%d test file(s), %d failed\n' "$total" "$fail"
[ "$fail" -eq 0 ]
