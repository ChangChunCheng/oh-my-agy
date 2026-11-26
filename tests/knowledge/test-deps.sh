#!/bin/bash
# Tests for oh-my-knowledge dependency detection, Homebrew auto-detection, and
# platform-specific install hints (common.sh, check-deps.sh, search.sh, lint.sh, check-move.sh).
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
# shellcheck source=../test-helpers.sh
. "$REPO_ROOT/tests/test-helpers.sh"

PLUGIN="$REPO_ROOT/plugins/oh-my-knowledge"
COMMON="$PLUGIN/scripts/lib/common.sh"
CHECK_DEPS="$PLUGIN/scripts/check-deps.sh"
SEARCH="$PLUGIN/scripts/search.sh"
LINT="$PLUGIN/scripts/lint.sh"
CHECK_MOVE="$PLUGIN/scripts/check-move.sh"

for v in $(compgen -e | grep -E '^(OMK_|OMA_)'); do unset "$v"; done
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
export HOME="$T/home"; mkdir -p "$HOME"
export GIT_CONFIG_GLOBAL="$T/gitconfig-empty"; : > "$GIT_CONFIG_GLOBAL"
export GIT_CONFIG_NOSYSTEM=1
export OMA_STATE_DIR="$T/state"

has() { grep -qF -- "$2" "$1" 2>/dev/null || { printf '    FAIL: %s (missing %q in %s)\n' "$3" "$2" "$1" >&2; sed 's/^/      | /' "$1" >&2; TEST_FAILED=1; }; }
hint() { local os="$1" mgr="$2"; shift 2; OMK_OSTYPE="$os" OMK_PKG_MGR="$mgr" bash -c '. "$1"; shift; omk_install_hint "$@"' _ "$COMMON" "$@"; }

start_test "omk_install_hint produces platform-specific commands and deduplicates packages"
assert_eq "brew install gawk findutils" "$(hint darwin24 '' gawk find)" "macOS gawk+find"
assert_eq "brew install jq" "$(hint darwin24 '' jq)" "macOS jq"
assert_eq "sudo apt install gawk findutils jq" "$(hint linux-gnu apt gawk find jq)" "Debian/Ubuntu"
assert_eq "sudo dnf install gawk findutils" "$(hint linux-gnu dnf gawk find)" "Fedora"
assert_eq "sudo pacman -S gawk findutils" "$(hint linux-gnu pacman gawk find)" "Arch"
assert_eq "winget install jqlang.jq" "$(hint msys '' jq)" "Windows jq"
assert_eq "winget install Git.Git" "$(hint msys '' gawk find git)" "Windows deduplicates Git.Git"
assert_eq "winget install jqlang.jq Git.Git" "$(hint msys '' jq gawk find)" "Windows jq + Git.Git"
end_test

# Build a clean minimal KB for search/lint tests
KB="$T/kb"; mkdir -p "$KB/global" "$KB/rules" "$KB/projects"
cp "$PLUGIN/templates/SCHEMA.md" "$KB/SCHEMA.md"
cp "$PLUGIN/templates/index.md" "$KB/index.md"
cp "$PLUGIN/templates/rules-INDEX.md" "$KB/rules/INDEX.md"
printf -- '---\nname: sample\ndescription: sample widget\nmetadata:\n  type: reference\n  verified: 2026-10-01\n  evidence: tested\n---\nWidget body.\n' > "$KB/global/sample.md"
printf -- '- [[sample]] — sample\n' >> "$KB/index.md"

REAL_GAWK="$(command -v gawk 2>/dev/null || true)"
REAL_JQ="$(command -v jq 2>/dev/null || true)"
REAL_GIT="$(command -v git 2>/dev/null || true)"
REAL_GFIND=""
for cand in "$(command -v find 2>/dev/null || true)" "$(command -v gfind 2>/dev/null || true)" /opt/homebrew/opt/findutils/libexec/gnubin/find /usr/local/opt/findutils/libexec/gnubin/find; do
  if [ -n "$cand" ] && [ -x "$cand" ] && "$cand" /dev/null -maxdepth 0 -printf '' >/dev/null 2>&1; then
    REAL_GFIND="$cand"; break
  fi
done

start_test "check-deps.sh succeeds when all required tools are available"
if [ -n "$REAL_GAWK" ] && [ -n "$REAL_JQ" ] && [ -n "$REAL_GIT" ] && [ -n "$REAL_GFIND" ]; then
  out="$(bash "$CHECK_DEPS" 2>&1)"; rc=$?
  assert_eq 0 "$rc" "exit 0"
  case "$out" in "ok: "*) ;; *) printf '    FAIL: expected ok: prefix, got: %s\n' "$out" >&2; TEST_FAILED=1 ;; esac
else
  echo "    (skipping: host missing one of git/jq/gawk/GNU find)"
fi
end_test

start_test "check-deps.sh reports missing gawk and BSD find with explicit install command"
BSDBIN="$T/bsdbin"; mkdir -p "$BSDBIN"
[ -n "$REAL_GIT" ] && ln -sf "$REAL_GIT" "$BSDBIN/git"
[ -n "$REAL_JQ" ] && ln -sf "$REAL_JQ" "$BSDBIN/jq"
printf '#!/bin/bash\necho "find: -printf: unknown primary or operator" >&2\nexit 1\n' > "$BSDBIN/find"
chmod +x "$BSDBIN/find"
PATH="$BSDBIN" OMK_OSTYPE=darwin24 "$BASH" "$CHECK_DEPS" >"$T/out" 2>"$T/err"; rc=$?
assert_eq 2 "$rc" "exit 2 when gawk and GNU find missing"
has "$T/err" "gawk" "names gawk"
has "$T/err" "GNU find" "names GNU find"
has "$T/err" "brew install gawk findutils" "gives exact brew install command"
end_test

start_test "lint.sh rejects BSD find with exit 2 and install command (without falling back to host)"
PATH="$BSDBIN" OMK_OSTYPE=darwin24 OMK_KNOWLEDGE_DIR="$KB" "$BASH" "$LINT" >"$T/out" 2>"$T/err"; rc=$?
assert_eq 2 "$rc" "lint exit 2 on missing gawk"
has "$T/err" "brew install gawk" "lint gawk install hint"
if [ -n "$REAL_GAWK" ]; then
  ln -sf "$REAL_GAWK" "$BSDBIN/gawk"
  PATH="$BSDBIN" OMK_OSTYPE=darwin24 OMK_KNOWLEDGE_DIR="$KB" "$BASH" "$LINT" >"$T/out" 2>"$T/err"; rc=$?
  assert_eq 2 "$rc" "lint exit 2 on BSD find"
  has "$T/err" "GNU find" "names GNU find"
  has "$T/err" "brew install findutils" "gives brew install findutils"
  rm -f "$BSDBIN/gawk"
fi
end_test

start_test "Homebrew fallback auto-detects gawk and GNU find when not on PATH"
if [ -n "$REAL_GAWK" ] && [ -n "$REAL_GFIND" ] && [ -n "$REAL_JQ" ] && [ -n "$REAL_GIT" ]; then
  BREW="$T/brew"; mkdir -p "$BREW/bin" "$BREW/opt/findutils/libexec/gnubin"
  ln -sf "$REAL_GAWK" "$BREW/bin/gawk"
  ln -sf "$REAL_GFIND" "$BREW/opt/findutils/libexec/gnubin/find"
  # Tool PATH has core POSIX utilities (xargs/sort/sed/tr/mktemp/wc/head/rm/cat/date) + BSD find, no gawk/gfind
  MINBIN="$T/minbin"; mkdir -p "$MINBIN"
  for u in git jq xargs sort sed tr mktemp wc head rm cat date dirname; do
    p="$(command -v "$u" 2>/dev/null || true)"
    [ -n "$p" ] && ln -sf "$p" "$MINBIN/$u"
  done
  # Fake BSD find: rejects -printf, passes -print0 through to real GNU find
  printf '#!/bin/bash\nfor a in "$@"; do if [ "$a" = "-printf" ]; then echo "find: -printf: unknown primary or operator" >&2; exit 1; fi; done\nexec "%s" "$@"\n' "$REAL_GFIND" > "$MINBIN/find"
  chmod +x "$MINBIN/find"
  PATH="$MINBIN" OMK_BREW_PREFIX="$BREW" "$BASH" "$CHECK_DEPS" >"$T/out" 2>"$T/err"; rc=$?
  assert_eq 0 "$rc" "check-deps succeeds via OMK_BREW_PREFIX"
  has "$T/out" "$BREW/bin/gawk" "found brew gawk"
  has "$T/out" "$BREW/opt/findutils/libexec/gnubin/find" "found brew find"
  PATH="$MINBIN" OMK_BREW_PREFIX="$BREW" OMK_KNOWLEDGE_DIR="$KB" "$BASH" "$LINT" --checks structure >"$T/out" 2>"$T/err"; rc=$?
  assert_eq 0 "$rc" "lint.sh succeeds via OMK_BREW_PREFIX"
  PATH="$MINBIN" OMK_BREW_PREFIX="$BREW" OMK_KNOWLEDGE_DIR="$KB" "$BASH" "$SEARCH" Widget >"$T/out" 2>"$T/err"; rc=$?
  assert_eq 0 "$rc" "search.sh succeeds via OMK_BREW_PREFIX"
  has "$T/out" "global/sample.md:2" "search hit via brew gawk"
  # Also verify gfind on PATH works even without OMK_BREW_PREFIX
  ln -sf "$REAL_GFIND" "$MINBIN/gfind"
  ln -sf "$REAL_GAWK" "$MINBIN/gawk"
  PATH="$MINBIN" "$BASH" "$CHECK_DEPS" >"$T/out" 2>"$T/err"; rc=$?
  assert_eq 0 "$rc" "check-deps succeeds with gfind on PATH"
  has "$T/out" "GNU find (gfind)" "reports gfind"
  PATH="$MINBIN" OMK_KNOWLEDGE_DIR="$KB" "$BASH" "$LINT" --checks structure >"$T/out" 2>"$T/err"; rc=$?
  assert_eq 0 "$rc" "lint.sh succeeds with gfind on PATH"
else
  echo "    (skipping: host missing one of git/jq/gawk/GNU find)"
fi
end_test

start_test "search.sh and check-move.sh missing gawk include install command"
NOG="$T/nogawk"; mkdir -p "$NOG"
PATH="$NOG" OMK_OSTYPE=darwin24 OMK_KNOWLEDGE_DIR="$KB" "$BASH" "$SEARCH" widget >"$T/out" 2>"$T/err"; rc=$?
assert_eq 2 "$rc" "search exit 2"
has "$T/err" "Install it with: brew install gawk" "search install hint"
PATH="$NOG" OMK_OSTYPE=linux-gnu OMK_PKG_MGR=apt "$BASH" "$CHECK_MOVE" "$KB/SCHEMA.md" "$KB/index.md" >"$T/out" 2>"$T/err"; rc=$?
assert_eq 2 "$rc" "check-move exit 2"
has "$T/err" "Install it with: sudo apt install gawk" "check-move install hint"
end_test

start_test "kb-setup/SKILL.md calls check-deps.sh"
has "$PLUGIN/skills/kb-setup/SKILL.md" "<scripts>/check-deps.sh" "kb-setup references check-deps.sh"
end_test

print_summary
