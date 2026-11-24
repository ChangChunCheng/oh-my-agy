#!/bin/bash
# Tests for oh-my-knowledge: common.sh helpers, omk_config, plugin.json/hooks.json manifest, templates, init.sh.
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
# shellcheck source=../test-helpers.sh
. "$REPO_ROOT/tests/test-helpers.sh"

PLUGIN="$REPO_ROOT/plugins/oh-my-knowledge"
COMMON="$PLUGIN/scripts/lib/common.sh"
INIT="$PLUGIN/scripts/init.sh"
PJ="$PLUGIN/plugin.json"
HJ="$PLUGIN/hooks.json"

# Isolation: temp HOME, temp git config, no inherited OMK_*/plugin options.
for v in $(compgen -e | grep -E '^(OMK_|OMA_)'); do unset "$v"; done
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
export HOME="$T/home"; mkdir -p "$HOME"
export GIT_CONFIG_GLOBAL="$T/gitconfig-empty"; : > "$GIT_CONFIG_GLOBAL"
export GIT_CONFIG_NOSYSTEM=1
export OMA_STATE_DIR="$T/state"

IS_WIN=0
case "${OSTYPE:-}" in msys*|cygwin*) IS_WIN=1;; esac

# call <fn> args...: run a common.sh function in a fresh bash.
call() { bash -c '. "$1"; shift; "$@"' _ "$COMMON" "$@" | tr -d '\r'; }

start_test "common.sh exists"
[ -f "$COMMON" ] || { printf '    FAIL: missing %s\n' "$COMMON" >&2; TEST_FAILED=1; }
end_test

start_test "omk_resolve_dir table"
assert_eq "$HOME/a" "$(call omk_resolve_dir '~/a')" "~/a"
assert_eq "/c/x/y" "$(call omk_resolve_dir 'C:\x\y')" "C:\\x\\y"
assert_eq "/c/x/y" "$(call omk_resolve_dir 'C:/x/y/')" "C:/x/y/"
assert_eq "/c/x" "$(call omk_resolve_dir 'c:/x')" "c:/x"
assert_eq "/c/x" "$(call omk_resolve_dir '/c/x')" "/c/x"
assert_eq "/c/中文 dir" "$(call omk_resolve_dir '/c/中文 dir')" "CJK+space"
assert_eq "/c/a b/c" "$(call omk_resolve_dir 'C:\a b\c\')" "space backslash"
end_test

start_test "omk_resolve_dir canonicalises existing dirs (/tmp vs long form)"
D="$(mktemp -d)"
LONGD="$(cd "$D" && pwd -P)"
assert_eq "$LONGD" "$(call omk_resolve_dir "$D")" "short/tmp form"
assert_eq "$LONGD" "$(call omk_resolve_dir "$LONGD/")" "long form with slash"
if [ "$IS_WIN" = 1 ]; then
  W="$(cd "$D" && pwd -W)"
  assert_eq "$LONGD" "$(call omk_resolve_dir "$W")" "C:/ form of existing dir"
fi
mkdir -p "$D/sp ace/中文"
assert_eq "$LONGD/sp ace/中文" "$(call omk_resolve_dir "$D/sp ace/中文")" "spaces+CJK existing"
end_test

start_test "omk_encode_name table (platform independent)"
assert_eq 'C--Users-jane-doe-Repos-P0001-----' "$(call omk_encode_name 'C:/Users/jane_doe/Repos/P0001_測試專案')" "jane_doe"
assert_eq 'a-b' "$(call omk_encode_name 'a b')" "space"
assert_eq 'a-b' "$(call omk_encode_name 'a.b')" "dot"
assert_eq 'a-b-' "$(call omk_encode_name 'a(b)')" "paren"
assert_eq 'a-b' "$(call omk_encode_name 'a@b')" "at"
assert_eq 'abcXYZ019' "$(call omk_encode_name 'abcXYZ019')" "alnum kept"
end_test

start_test "omk_encode_path == omk_encode_name of omk_native_path"
N="$(call omk_native_path "$D")"
assert_eq "$(call omk_encode_name "$N")" "$(call omk_encode_path "$D")" "encode_path"
if [ "$IS_WIN" = 1 ]; then
  case "$N" in [A-Za-z]:/*) ;; *) printf '    FAIL: native path not C:/ form: %s\n' "$N" >&2; TEST_FAILED=1;; esac
fi
end_test

start_test "omk_repo_root: main repo, subdir, linked worktree"
R="$(mktemp -d)"; WT="$(mktemp -d)"; rmdir "$WT"
git -C "$R" init -q . >/dev/null 2>&1
git -C "$R" -c user.name=t -c user.email=t@x commit -q --allow-empty -m init >/dev/null 2>&1
mkdir -p "$R/sub/deep"
git -C "$R" worktree add -q "$WT" -b wt >/dev/null 2>&1
mkdir -p "$WT/inner"
RR="$(call omk_resolve_dir "$R")"
[ -n "$RR" ] || { echo "    FAIL: empty repo root" >&2; TEST_FAILED=1; }
assert_eq "$RR" "$(call omk_repo_root "$R")" "main root"
assert_eq "$RR" "$(call omk_repo_root "$R/sub/deep")" "subdir"
assert_eq "$RR" "$(call omk_repo_root "$WT")" "linked worktree"
assert_eq "$RR" "$(call omk_repo_root "$WT/inner")" "worktree subdir"
NG="$(mktemp -d)"
assert_eq "$(call omk_resolve_dir "$NG")" "$(call omk_repo_root "$NG")" "non-git dir"
rm -rf "$R" "$WT" "$NG"
end_test

start_test "omk_config defaults"
out="$(bash -c '. "$1"; omk_config; for k in OMK_KNOWLEDGE_DIR OMK_LOOKUP_REMINDER OMK_AUTO_HANDOFF OMK_AUTO_HANDOFF_THRESHOLD OMK_AUTO_HANDOFF_REPEAT OMK_LINT_STALE_DAYS OMK_LINT_FLAG_DAYS OMK_LINT_REMIND_AFTER_DISTILLS OMK_MAX_FILE_KB OMK_MAX_INDEX_LINE_CHARS OMK_AUTO_MEMORY_DIR OMK_AUTO_MEMORY_GLOB OMK_RULES_FILE OMA_STATE_DIR OMK_JQ OMK_CONF; do echo "$k=${!k}"; done' _ "$COMMON" | tr -d '\r')"
for kv in "OMK_KNOWLEDGE_DIR=$HOME/knowledge" OMK_LOOKUP_REMINDER=true OMK_AUTO_HANDOFF=true OMK_AUTO_HANDOFF_THRESHOLD=70 OMK_AUTO_HANDOFF_REPEAT=20 \
  OMK_LINT_STALE_DAYS=90 OMK_LINT_FLAG_DAYS=14 OMK_LINT_REMIND_AFTER_DISTILLS=10 OMK_MAX_FILE_KB=8 OMK_MAX_INDEX_LINE_CHARS=200 \
  OMK_AUTO_MEMORY_DIR= "OMK_AUTO_MEMORY_GLOB=$HOME/.gemini/oh-my-agy/projects/*/memory" "OMK_RULES_FILE=$HOME/.gemini/GEMINI.md" "OMK_CONF=$HOME/.gemini/oh-my-agy/knowledge.conf" \
  "OMA_STATE_DIR=$T/state" OMK_JQ=jq; do
  grep -qxF -- "$kv" <<<"$out" || { printf '    FAIL: default missing: %s\n' "$kv" >&2; TEST_FAILED=1; }
done
v="$(env -u OMA_STATE_DIR bash -c '. "$1"; omk_config; echo "$OMA_STATE_DIR"' _ "$COMMON" | tr -d '\r')"
assert_eq "$HOME/.gemini/oh-my-agy/state" "$v" "OMA_STATE_DIR default"
end_test

start_test "omk_config precedence env > knowledge.conf > default; booleans normalised"
CONFF="$T/knowledge.conf"
cfg() { OMK_CONF="${CONFF:-/dev/null}" bash -c '. "$1"; omk_config; echo "${!2}"' _ "$COMMON" "$1" | tr -d '\r'; }
: > "$CONFF"
assert_eq "70" "$(cfg OMK_AUTO_HANDOFF_THRESHOLD)" "default"
printf 'AUTO_HANDOFF_THRESHOLD=44\nLOOKUP_REMINDER=false\nMAX_FILE_KB=7\n' > "$CONFF"
assert_eq "55" "$(OMK_AUTO_HANDOFF_THRESHOLD=55 cfg OMK_AUTO_HANDOFF_THRESHOLD)" "env wins"
assert_eq "44" "$(cfg OMK_AUTO_HANDOFF_THRESHOLD)" "conf value"
assert_eq "false" "$(cfg OMK_LOOKUP_REMINDER)" "conf false"
assert_eq "7" "$(cfg OMK_MAX_FILE_KB)" "max_file_kb conf"
assert_eq "false" "$(OMK_AUTO_HANDOFF=False cfg OMK_AUTO_HANDOFF)" "False->false"
assert_eq "false" "$(OMK_AUTO_HANDOFF=0 cfg OMK_AUTO_HANDOFF)" "0->false"
assert_eq "true" "$(OMK_AUTO_HANDOFF=1 cfg OMK_AUTO_HANDOFF)" "1->true"
assert_eq "true" "$(OMK_LOOKUP_REMINDER=TRUE cfg OMK_LOOKUP_REMINDER)" "env TRUE->true over conf false"
assert_eq "2026-01-02" "$(OMK_TODAY=2026-01-02 cfg OMK_TODAY)" "OMK_TODAY"
assert_eq "/x/y" "$(OMK_AUTO_MEMORY_DIR=/x/y cfg OMK_AUTO_MEMORY_DIR)" "project memory dir passthrough"
assert_eq "/p/projects/*/memory" "$(OMA_HOME=/p cfg OMK_AUTO_MEMORY_GLOB)" "OMA_HOME glob"
assert_eq "/p/state" "$(unset OMA_STATE_DIR; OMA_HOME=/p cfg OMA_STATE_DIR)" "OMA_HOME state dir"
assert_eq "/p/knowledge.conf" "$(OMA_HOME=/p OMK_CONF= bash -c '. "$1"; omk_config; echo "$OMK_CONF"' _ "$COMMON")" "OMA_HOME conf path"
assert_eq "/g/GEMINI.md" "$(OMK_RULES_FILE=/g/GEMINI.md cfg OMK_RULES_FILE)" "rules file override"
rm -f "$CONFF"; CONFF=""
end_test

start_test "plugin.json / hooks.json manifest: no userConfig, agy hooks shape, defaults documented in kb-setup == omk_config defaults"
assert_eq "oh-my-knowledge" "$(jq -r .name "$PJ" | tr -d '\r')" "name"
assert_eq "1.0.0" "$(jq -r .version "$PJ" | tr -d '\r')" "version"
assert_eq "false" "$(jq 'has("userConfig")' "$PJ" | tr -d '\r')" "no userConfig (agy has none)"
assert_eq "ChangChunCheng" "$(jq -r .author.name "$PJ" | tr -d '\r')" "author"
assert_eq "assets/logo.svg" "$(jq -r .logo "$PJ" | tr -d '\r')" "logo"
[ -s "$PLUGIN/assets/logo.svg" ] || { printf '    FAIL: logo missing\n' >&2; TEST_FAILED=1; }
[ ! -e "$PLUGIN/hooks/hooks.json" ] || { printf '    FAIL: hooks/hooks.json must not exist (root hooks.json only)\n' >&2; TEST_FAILED=1; }
assert_eq "PreInvocation,SessionStart,Stop" "$(jq -r '[.[] | keys[]] | sort | join(",")' "$HJ" | tr -d '\r')" "events"
assert_eq "true" "$(jq '[.[][][] | .command | startswith("bash ./hooks/")] | all' "$HJ" | tr -d '\r')" "relative hook commands"
for c in $(jq -r '.[][][] | .command | sub("^bash ";"")' "$HJ" | tr -d '\r'); do
  [ -f "$PLUGIN/$c" ] || { printf '    FAIL: hook script %s missing\n' "$c" >&2; TEST_FAILED=1; }
done
SK="$PLUGIN/skills/kb-setup/SKILL.md"
declare -A MAP=([KNOWLEDGE_DIR]=OMK_KNOWLEDGE_DIR [LOOKUP_REMINDER]=OMK_LOOKUP_REMINDER [AUTO_HANDOFF]=OMK_AUTO_HANDOFF \
  [AUTO_HANDOFF_THRESHOLD]=OMK_AUTO_HANDOFF_THRESHOLD [AUTO_HANDOFF_REPEAT]=OMK_AUTO_HANDOFF_REPEAT \
  [LINT_STALE_DAYS]=OMK_LINT_STALE_DAYS [LINT_FLAG_DAYS]=OMK_LINT_FLAG_DAYS \
  [LINT_REMIND_AFTER_DISTILLS]=OMK_LINT_REMIND_AFTER_DISTILLS [MAX_FILE_KB]=OMK_MAX_FILE_KB [MAX_INDEX_LINE_CHARS]=OMK_MAX_INDEX_LINE_CHARS)
for k in "${!MAP[@]}"; do
  row="$(grep -F "| \`$k\` |" "$SK" | head -n1)"
  [ -n "$row" ] || { printf '    FAIL: kb-setup table lacks %s\n' "$k" >&2; TEST_FAILED=1; continue; }
  jd="$(printf '%s' "$row" | awk -F'|' '{d=$3; sub(/\(.*/,"",d); gsub(/[ `]/,"",d); print d}')"
  [ "$k" = KNOWLEDGE_DIR ] && jd="$(call omk_resolve_dir "$jd")"
  assert_eq "$jd" "$(cfg "${MAP[$k]}")" "documented default of $k"
done
end_test

assert_has() { grep -qF -- "$2" "$1" 2>/dev/null || { echo "    FAIL: $3 (missing in $1: $2)" >&2; TEST_FAILED=1; }; }
start_test "templates present and carry the fixed literals"
TP="$PLUGIN/templates"
for f in SCHEMA.md index.md log.md inbox.md rules-INDEX.md; do
  [ -s "$TP/$f" ] || { printf '    FAIL: missing template %s\n' "$f" >&2; TEST_FAILED=1; }
done
assert_has "$TP/SCHEMA.md" '(omk-harvested)' "harvested marker"
assert_has "$TP/SCHEMA.md" '- Knowledge base project: [[k:projects/<p>/index]] (omk-project)' "project marker"
assert_has "$TP/SCHEMA.md" '> ⚠ UNVERIFIED (YYYY-MM-DD):' "unverified marker"
assert_has "$TP/SCHEMA.md" '> Moved: ' "stub marker"
assert_has "$TP/SCHEMA.md" '## [YYYY-MM-DD] <action> | <title>' "log heading"
assert_has "$TP/SCHEMA.md" '[[g:slug]]' "g link"
assert_has "$TP/SCHEMA.md" '[[k:<relpath>]]' "k link"
assert_has "$TP/SCHEMA.md" 'metadata.type' "type rule"
assert_has "$TP/index.md" '## Sub-indexes' "index sub-indexes"
assert_has "$TP/index.md" '## Projects' "index projects"
assert_has "$TP/index.md" '- [[k:projects/<p>/index]] — <description>' "index project line"
assert_has "$TP/index.md" '## Maintenance status' "index maintenance"
first="$(head -n1 "$TP/rules-INDEX.md" 2>/dev/null)"
case "$first" in *'[[g:'*'[[k:'*) ;; *) printf '    FAIL: rules-INDEX line 1 lacks link definition: %s\n' "$first" >&2; TEST_FAILED=1;; esac
assert_has "$TP/rules-INDEX.md" '@[label](path)' "include format explained"
assert_has "$TP/SCHEMA.md" 'global/index_architecture.md' "architecture sub-index rule"
assert_has "$TP/SCHEMA.md" 'status section' "status section definition"
assert_has "$TP/SCHEMA.md" 'handoff later creates the status section above it' "no-status-section rule"
# log.md template: the example heading must be inside a code fence (no real entry)
real="$(awk '/^```/{f=!f; next} !f && /^## \[/{print}' "$TP/log.md")"
assert_eq "" "$real" "log.md has no unfenced entry heading"
assert_has "$TP/log.md" '## [YYYY-MM-DD] <action> | <title>' "log example present"
case "$(grep -F 'max_file_kb' "$TP/SCHEMA.md" | grep -F 'index.md' | grep -F 'exempt')" in
  '') echo "    FAIL: SCHEMA max_file_kb line lacks the index.md exemption" >&2; TEST_FAILED=1 ;;
esac
sz=$(wc -c < "$TP/SCHEMA.md" 2>/dev/null || echo 0)
[ "$sz" -le 8192 ] || { printf '    FAIL: SCHEMA.md %s bytes > 8 KB\n' "$sz" >&2; TEST_FAILED=1; }
end_test

# --- init.sh ---
runinit() { OMK_KNOWLEDGE_DIR="$1" bash "$INIT" 2>&1 | tr -d '\r'; }

start_test "init.sh creates skeleton"
KB="$T/kb1"
out="$(runinit "$KB")"
assert_eq "initialized $(call omk_resolve_dir "$KB")" "$out" "message"
for d in rules global projects lint _retired .git; do [ -d "$KB/$d" ] || { printf '    FAIL: missing dir %s\n' "$d" >&2; TEST_FAILED=1; }; done
for f in SCHEMA.md index.md log.md inbox.md rules/INDEX.md; do [ -s "$KB/$f" ] || { printf '    FAIL: missing file %s\n' "$f" >&2; TEST_FAILED=1; }; done
assert_eq "oh-my-knowledge@localhost" "$(git -C "$KB" config user.email)" "local identity set"
assert_eq "oh-my-knowledge" "$(git -C "$KB" config user.name)" "local name"
assert_eq "" "$(cat "$GIT_CONFIG_GLOBAL")" "global git config untouched"
assert_eq "* text=auto eol=lf" "$(cat "$KB/.gitattributes" | tr -d '\r')" ".gitattributes content"
assert_eq "1" "$(wc -l < "$KB/.gitattributes" | tr -d ' ')" ".gitattributes is exactly one line"
assert_eq "19" "$(wc -c < "$KB/.gitattributes" | tr -d ' ')" ".gitattributes bytes (LF only)"
end_test

start_test "init.sh idempotent and keeps edited SCHEMA.md"
echo "custom schema 自訂" > "$KB/SCHEMA.md"
echo "x" >> "$KB/log.md"
before="$(cat "$KB/log.md")"
out="$(runinit "$KB")"
assert_eq "already initialized $(call omk_resolve_dir "$KB")" "$out" "message"
assert_eq "custom schema 自訂" "$(cat "$KB/SCHEMA.md")" "SCHEMA kept"
assert_eq "$before" "$(cat "$KB/log.md")" "log kept"
end_test

start_test "init.sh with spaced path in all three forms"
SP="$T/sp ace 中文/kb"
mkdir -p "$T/sp ace 中文"
out="$(runinit "$SP")"
assert_eq "initialized $(call omk_resolve_dir "$SP")" "$out" "posix form"
[ -d "$SP/rules" ] || { printf '    FAIL: skeleton missing\n' >&2; TEST_FAILED=1; }
out="$(runinit "$SP/")"
case "$out" in "already initialized "*) ;; *) printf '    FAIL: trailing-slash form: %s\n' "$out" >&2; TEST_FAILED=1;; esac
if [ "$IS_WIN" = 1 ]; then
  W="$(cd "$SP" && pwd -W)"
  out="$(runinit "$W")"
  case "$out" in "already initialized "*) ;; *) printf '    FAIL: C:/ form: %s\n' "$out" >&2; TEST_FAILED=1;; esac
  WB="${W//\//\\}"
  out="$(runinit "$WB")"
  case "$out" in "already initialized "*) ;; *) printf '    FAIL: C:\\ form: %s\n' "$out" >&2; TEST_FAILED=1;; esac
fi
mkdir -p "$HOME/kbhome"
out="$(runinit '~/kbhome')"
assert_eq "initialized $(call omk_resolve_dir "$HOME/kbhome")" "$out" "~ form"
end_test

start_test "init.sh sets identity only when none resolvable"
printf '[user]\n\temail = jane_doe@example.com\n\tname = Jane Doe\n' > "$T/gitconfig-id"
KB2="$T/kb2"
GIT_CONFIG_GLOBAL="$T/gitconfig-id" runinit "$KB2" >/dev/null
assert_eq "" "$(git -C "$KB2" config --local user.email)" "no local identity when global has one"
assert_eq "oh-my-knowledge@localhost" "$(git -C "$T/kb1" config --local user.email)" "local identity when none"
assert_eq "$(printf '[user]\n\temail = jane_doe@example.com\n\tname = Jane Doe')" "$(cat "$T/gitconfig-id")" "global id file untouched"
end_test

start_test "init.sh with a relative/garbage knowledge_dir creates nothing; with no setting it uses ~/knowledge"
mkdir -p "$T/cwd"
( cd "$T/cwd" && OMK_KNOWLEDGE_DIR='${garbage}' bash "$INIT" >/dev/null 2>&1 ); assert_eq "2" "$?" "exit 2"
assert_eq "" "$(find "$T/cwd" -name '*$*' 2>/dev/null)" "no \${ dirs in cwd"
assert_eq "" "$(find "$HOME" -name '*{*' 2>/dev/null)" "no \${ dirs in HOME"
( cd "$T/cwd" && bash "$INIT" >/dev/null 2>&1 )
[ -f "$HOME/knowledge/SCHEMA.md" ] || { printf '    FAIL: default ~/knowledge not created\n' >&2; TEST_FAILED=1; }
end_test

start_test "init.sh on an existing KB from elsewhere adds only missing skeleton parts (dirs, rules/INDEX.md, .gitattributes)"
EX="$T/existing"
mkdir -p "$EX/global" "$EX/projects/p1"
git -C "$EX" init -q . >/dev/null 2>&1
printf '# 我的 SCHEMA\n' > "$EX/SCHEMA.md"
printf '# 索引\n' > "$EX/index.md"
printf '# log\n' > "$EX/log.md"
printf '# inbox\n' > "$EX/inbox.md"
printf '頁面\n' > "$EX/global/page.md"
printf 'p\n' > "$EX/projects/p1/index.md"
snap() { (cd "$EX" && find . -path ./.git -prune -o -type f -print0 | sort -z | xargs -0 md5sum); }
b="$(snap)"; cfgb="$(cat "$EX/.git/config")"
out="$(GIT_CONFIG_GLOBAL="$T/gitconfig-id" runinit "$EX")"
assert_eq "already initialized $(call omk_resolve_dir "$EX")" "$out" "message"
a="$(snap | grep -vE 'rules/INDEX.md|.gitattributes')"
assert_eq "$b" "$a" "existing files byte-identical"
for d in rules lint _retired; do [ -d "$EX/$d" ] || { printf '    FAIL: dir %s not added\n' "$d" >&2; TEST_FAILED=1; }; done
assert_eq "* text=auto eol=lf" "$(tr -d '\r' < "$EX/.gitattributes")" ".gitattributes added to copied KB"
assert_eq "$cfgb" "$(cat "$EX/.git/config")" ".git/config unchanged when identity resolvable"
end_test

start_test "init.sh keeps an existing .gitattributes byte-identical"
EX2="$T/existing2"; mkdir -p "$EX2"; git -C "$EX2" init -q . >/dev/null 2>&1
printf '*.md -text
# 自訂
' > "$EX2/.gitattributes"; b2="$(md5sum < "$EX2/.gitattributes")"
runinit "$EX2" >/dev/null
assert_eq "$b2" "$(md5sum < "$EX2/.gitattributes")" ".gitattributes kept"
end_test

start_test "relative knowledge_dir: search/lint/commit/init exit 2 with the message, from a temp cwd, nothing created"
CWD2="$T/cwd2"; mkdir -p "$CWD2/kb"
SCR="$PLUGIN/scripts"
for rel in 'kb' './kb' 'kb\x'; do
  for sc in "search.sh word" "lint.sh" "commit.sh msg SCHEMA.md" "init.sh"; do
    set -- $sc
    s="$1"; shift
    out="$(cd "$CWD2" && OMK_KNOWLEDGE_DIR="$rel" bash "$SCR/$s" "$@" 2>&1 >/dev/null; echo "rc=$?")"
    case "$out" in
      *"knowledge_dir must be an absolute path or start with ~/ (got: $rel); run the kb-setup skill"*"rc=2") ;;
      *) printf '    FAIL: %s with %s: %s\n' "$s" "$rel" "$out" >&2; TEST_FAILED=1 ;;
    esac
  done
done
assert_eq "" "$(ls -A "$CWD2/kb")" "nothing created inside the relative dir"
assert_eq "kb" "$(ls -A "$CWD2")" "nothing created in the cwd"
end_test

print_summary
