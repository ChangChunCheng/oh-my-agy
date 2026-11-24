#!/bin/bash
# Tests for scripts/memory-dir.sh and the per-project memory location under ~/.gemini/oh-my-agy.
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
# shellcheck source=../test-helpers.sh
. "$REPO_ROOT/tests/test-helpers.sh"

PLUGIN="$REPO_ROOT/plugins/oh-my-knowledge"
MD="$PLUGIN/scripts/memory-dir.sh"
SEARCH="$PLUGIN/scripts/search.sh"

for v in $(compgen -e | grep -E '^(OMK_|OMA_)'); do unset "$v"; done
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
export HOME="$T/home"; mkdir -p "$HOME"
export OMA_STATE_DIR="$T/state"
export GIT_CONFIG_GLOBAL="$T/gitconfig-empty"; : > "$GIT_CONFIG_GLOBAL"
export GIT_CONFIG_NOSYSTEM=1

nat() { ( cd -P -- "$1" && pwd -P ); }
enc() { printf '%s' "$(nat "$1")" | LC_ALL=C sed 's/[^A-Za-z0-9]/-/g'; }

R="$T/work/my repo.v2"; mkdir -p "$R/sub/deep"; git -C "$R" init -q . >/dev/null 2>&1
NG="$T/work/plain"; mkdir -p "$NG"
DEF="$HOME/.gemini/oh-my-agy/projects"

start_test "memory-dir.sh prints <OMA_HOME>/projects/<encoded repo root>/memory (default under ~/.gemini/oh-my-agy)"
out="$(cd "$R" && bash "$MD")"
assert_eq "$DEF/$(enc "$R")/memory" "$out" "repo root"
assert_eq "$DEF/$(enc "$R")/memory" "$(cd "$R/sub/deep" && bash "$MD")" "subdirectory maps to the repo root"
assert_eq "$DEF/$(enc "$NG")/memory" "$(cd "$NG" && bash "$MD")" "non-git dir uses itself"
assert_eq "$DEF/$(enc "$R")/memory" "$(cd "$NG" && bash "$MD" "$R")" "explicit <cwd> argument"
b="${out%/memory}"; b="${b##*/}"
case "$b" in ''|*[!A-Za-z0-9-]*) printf '    FAIL: odd characters in encoded dir %q\n' "$b" >&2; TEST_FAILED=1;; esac
[ ! -e "$DEF" ] || { printf '    FAIL: printing must not create anything\n' >&2; TEST_FAILED=1; }
assert_eq "/o/projects/$(enc "$R")/memory" "$(cd "$R" && OMA_HOME=/o bash "$MD")" "OMA_HOME"
assert_eq "/x/mem" "$(cd "$R" && OMK_AUTO_MEMORY_DIR=/x/mem bash "$MD")" "OMK_AUTO_MEMORY_DIR override"
assert_eq "/g/$(enc "$R")/m" "$(cd "$R" && OMK_AUTO_MEMORY_GLOB='/g/*/m' bash "$MD")" "OMK_AUTO_MEMORY_GLOB"
end_test

start_test "memory-dir.sh --create makes the dir and an empty MEMORY.md, never clobbers"
d="$(cd "$R" && bash "$MD" --create)"
[ -d "$d" ] && [ -f "$d/MEMORY.md" ] && [ ! -s "$d/MEMORY.md" ] || { printf '    FAIL: not created: %q\n' "$d" >&2; TEST_FAILED=1; }
printf 'keep me\n' > "$d/MEMORY.md"
d2="$(cd "$R" && bash "$MD" --create)"
assert_eq "$d" "$d2" "same dir again"
assert_eq "keep me" "$(cat "$d/MEMORY.md")" "existing MEMORY.md untouched"
end_test

start_test "memory-dir.sh errors: bad usage and a glob without * exit 2; uncreatable exit 1"
bash "$MD" a b >/dev/null 2>&1; assert_eq 2 $? "two args"
OMK_AUTO_MEMORY_GLOB=/nostar bash "$MD" >/dev/null 2>&1; assert_eq 2 $? "glob without *"
: > "$T/afile"
OMK_AUTO_MEMORY_DIR="$T/afile/sub" bash "$MD" --create >/dev/null 2>&1; assert_eq 1 $? "cannot create"
end_test

start_test "search.sh sees the created project memory as '== auto memory:' (and migrated project via marker)"
KB="$T/kb"; mkdir -p "$KB/global" "$KB/projects/demo"; : > "$KB/SCHEMA.md"
printf -- '---\nname: g\ndescription: Quuxword global\n---\nbody\n' > "$KB/global/g.md"
printf -- '---\nname: p\ndescription: Quuxword proj\n---\nbody\n' > "$KB/projects/demo/p.md"
out="$(cd "$NG" && OMK_KNOWLEDGE_DIR="$KB" bash "$SEARCH" Quuxword)"
case "$out" in *'== auto memory: (none)'*) ;; *) printf '    FAIL: expected none: %q\n' "$out" >&2; TEST_FAILED=1;; esac
d="$(cd "$R" && bash "$MD" --create)"
{ printf '## ⚡ 現況\n- Quuxword in progress\n\n'; printf -- '- Knowledge base project: [[k:projects/demo/index]] (omk-project)\n'; } > "$d/MEMORY.md"
out="$(cd "$R/sub" && OMK_KNOWLEDGE_DIR="$KB" bash "$SEARCH" Quuxword)"
case "$out" in *"== auto memory: $d"*) ;; *) printf '    FAIL: auto memory dir missing: %q\n' "$out" >&2; TEST_FAILED=1;; esac
case "$out" in *'== project: demo'*) ;; *) printf '    FAIL: project not detected: %q\n' "$out" >&2; TEST_FAILED=1;; esac
case "$out" in *'MEMORY.md:2:- Quuxword in progress'*) ;; *) printf '    FAIL: MEMORY.md hit missing: %q\n' "$out" >&2; TEST_FAILED=1;; esac
end_test

start_test "hook and skill texts name only skills and scripts that exist"
for n in $(grep -ohE 'kb-[a-z]+' "$PLUGIN"/hooks/*.sh "$PLUGIN"/skills/*/*.md "$PLUGIN/plugin.json" "$PLUGIN/scripts/"*.sh "$PLUGIN/scripts/lib/"*.sh | sort -u); do
  [ -f "$PLUGIN/skills/$n/SKILL.md" ] || { printf '    FAIL: %s is mentioned but is not a skill\n' "$n" >&2; TEST_FAILED=1; }
done
for s in $(grep -ohE 'scripts/[a-z-]+\.sh' "$PLUGIN"/skills/*/*.md | sort -u); do
  [ -f "$PLUGIN/$s" ] || { printf '    FAIL: %s mentioned in a skill does not exist\n' "$s" >&2; TEST_FAILED=1; }
done
grep -q 'memory-dir.sh' "$PLUGIN/skills/kb-handoff/SKILL.md" || { printf '    FAIL: kb-handoff does not use memory-dir.sh\n' >&2; TEST_FAILED=1; }
end_test

print_summary
