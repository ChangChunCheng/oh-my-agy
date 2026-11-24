#!/bin/bash
# Minimal bash test framework: assertions + setup helpers (oh-my-status).

TEST_FAILED=0
TEST_NAME=""
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Isolation: every test runs against private temp dirs, never the real
# ~/.gemini. OMA_CONF=/dev/null makes the conf defaults apply.
OMA_TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/oma-test-XXXXXX")"
export OMA_HOME="$OMA_TEST_ROOT/home"
export OMA_STATE_DIR="$OMA_TEST_ROOT/state"
export OMA_CONF="${OMA_CONF:-/dev/null}"
export OMA_AGY_SETTINGS="$OMA_TEST_ROOT/settings.json"
trap 'rm -rf "$OMA_TEST_ROOT"' EXIT

REAL_JQ="$(command -v jq 2>/dev/null || true)"
BASH_BIN="$(command -v bash)"

# fs_tick: return once the filesystem clock has moved past every file written
# so far (the git-info cache only trusts a stamp strictly newer than the repo
# files it watches).
fs_tick() {
  local a b n=0
  a=$(mktemp) || return 0
  while b=$(mktemp) && ! [ "$b" -nt "$a" ]; do
    rm -f "$b"; n=$((n + 1))
    if [ "$n" -ge 300 ]; then rm -f "$a"; echo "fs_tick: clock did not advance" >&2; TEST_FAILED=1; return 1; fi
    sleep 0.01
  done
  rm -f "$a" "$b"
}

start_test() {
  TEST_NAME="$1"; TEST_FAILED=0; TESTS_RUN=$((TESTS_RUN + 1))
  rm -rf "$OMA_STATE_DIR" "$OMA_HOME" "$OMA_AGY_SETTINGS" "$OMA_AGY_SETTINGS.bak"
  mkdir -p "$OMA_STATE_DIR"
}

end_test() {
  if [ "$TEST_FAILED" -eq 0 ]; then
    TESTS_PASSED=$((TESTS_PASSED + 1)); printf '  ok   %s\n' "$TEST_NAME"
  else
    TESTS_FAILED=$((TESTS_FAILED + 1)); printf '  FAIL %s\n' "$TEST_NAME"
  fi
}

assert_eq() {
  local expected="$1" actual="$2" msg="${3:-values differ}"
  if [ "$expected" != "$actual" ]; then
    printf '    FAIL: %s\n      expected: %q\n      actual:   %q\n' "$msg" "$expected" "$actual" >&2
    TEST_FAILED=1
  fi
}

assert_contains() {  # haystack needle msg
  case "$1" in *"$2"*) ;; *)
    printf '    FAIL: %s\n      needle:   %q\n      haystack: %q\n' "${3:-missing text}" "$2" "$1" >&2; TEST_FAILED=1 ;;
  esac
}

assert_not_contains() {
  case "$1" in *"$2"*)
    printf '    FAIL: %s\n      unexpected: %q\n      haystack:   %q\n' "${3:-unexpected text}" "$2" "$1" >&2; TEST_FAILED=1 ;;
  esac
}

assert_file_contains() {
  if ! grep -qF -- "$2" "$1" 2>/dev/null; then
    printf '    FAIL: %s\n      file: %s\n      pattern: %q\n' "${3:-pattern not found}" "$1" "$2" >&2; TEST_FAILED=1
  fi
}

assert_file_missing() {
  if [ -e "$1" ]; then printf '    FAIL: %s\n      exists: %s\n' "${2:-file should not exist}" "$1" >&2; TEST_FAILED=1; fi
}

print_summary() {
  printf '\n%d run, %d passed, %d failed\n' "$TESTS_RUN" "$TESTS_PASSED" "$TESTS_FAILED"
  [ "$TESTS_FAILED" -eq 0 ]
}
