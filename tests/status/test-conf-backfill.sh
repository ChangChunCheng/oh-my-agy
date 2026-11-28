#!/bin/bash
# Tests for lib/conf-keys.sh, setup.sh (install, --hook JSON, sweep),
# set-theme.sh, configure.sh and preview.sh. All paths are temp dirs.
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=test-helpers.sh
. "$SCRIPT_DIR/test-helpers.sh"

PLUGIN="$REPO_ROOT/plugins/oh-my-status"
TPL="$PLUGIN/oh-my-status.conf"
SETUP="$PLUGIN/scripts/setup.sh"
# shellcheck source=../../plugins/oh-my-status/scripts/lib/conf-keys.sh
. "$PLUGIN/scripts/lib/conf-keys.sh"
[ -n "$REAL_JQ" ] || { echo "jq is required for these tests" >&2; exit 1; }
# These tests exercise the real conf location under OMA_HOME.
unset OMA_CONF

printf 'Running conf-backfill / setup / helper tests\n\n'

# ---------------- oma_missing_conf_keys ----------------
t="$OMA_TEST_ROOT/tpl.conf"; u="$OMA_TEST_ROOT/user.conf"

start_test "absent key reported missing, template order preserved"
printf 'THEME=a\nLAYOUT=b\nQUOTA_FAMILY=auto\n' > "$t"; printf 'THEME=a\n' > "$u"
assert_eq "$(printf 'LAYOUT\nQUOTA_FAMILY')" "$(oma_missing_conf_keys "$t" "$u")" "missing"
end_test

start_test "present forms: plain, export, spaced, inline comment, duplicates, CRLF"
printf 'K=1\n' > "$t"
for line in 'K=0' 'export K=2' 'K = 5' 'K=5   # note' $'K=5\r'; do
  printf '%s\n' "$line" > "$u"
  assert_eq "" "$(oma_missing_conf_keys "$t" "$u")" "present: $line"
done
printf 'K=1\nK=2\n' > "$u"; assert_eq "" "$(oma_missing_conf_keys "$t" "$u")" "duplicates"
end_test

start_test "commented-only and prefix collisions count as missing"
printf '# K=1\n' > "$u"; assert_eq "K" "$(oma_missing_conf_keys "$t" "$u")" "commented"
printf 'KK=1\n' > "$u"; assert_eq "K" "$(oma_missing_conf_keys "$t" "$u")" "prefix"
end_test

start_test "blank/comment lines are never keys; unreadable template fails"
printf '# c\n\n  \nTHEME=x\n' > "$t"; printf 'THEME=x\n' > "$u"
assert_eq "" "$(oma_missing_conf_keys "$t" "$u")" "only THEME"
oma_missing_conf_keys "$OMA_TEST_ROOT/none" "$u" >/dev/null 2>&1; [ $? -ne 0 ] || { echo "    FAIL: expected non-zero" >&2; TEST_FAILED=1; }
end_test

start_test "oma_conf_has_key: uncommented assignment only"
printf 'QUOTA_FAMILY=3p\n' > "$u"; oma_conf_has_key "$u" QUOTA_FAMILY; assert_eq 0 "$?" "plain"
printf '# QUOTA_FAMILY=3p\n' > "$u"; oma_conf_has_key "$u" QUOTA_FAMILY; assert_eq 1 "$?" "commented"
oma_conf_has_key "$OMA_TEST_ROOT/none" QUOTA_FAMILY; assert_eq 1 "$?" "no file"
end_test

# ---------------- template ----------------
start_test "template: sourced defaults, QUOTA_FAMILY=all, no icon assigned"
out=$(env -u ACCOUNT_ICON -u QUOTA_FAMILY bash -c '. "$1"; printf "%s|%s|%s|%s|%s|%s|%s" "${THEME-}" "${GIT_CACHE_TTL-}" "${QUOTA_FAMILY-}" "${SHOW_MODE-}" "${SHOW_COST-}" "${SHOW_TASKS-}" "${ACCOUNT_ICON-unset}"' _ "$TPL")
assert_eq "catppuccin|10|all|true|false|true|unset" "$out" "defaults"
miss=$(oma_missing_conf_keys "$TPL" /dev/null | paste -sd, -)
for k in QUOTA_FAMILY SHOW_MODE SHOW_COST SHOW_TASKS ACCOUNT_FORMAT MODEL_CTX_TAG; do assert_contains ",$miss," ",$k," "$k listed for an empty conf"; done
assert_not_contains "$miss" "ICON" "icon is a commented example"
end_test

# ---------------- setup.sh ----------------
run_setup() {  # args passed to setup.sh; stdin from $SETUP_STDIN or empty
  printf '%s' "${SETUP_STDIN:-{\}}" | OMA_HOME="$OMA_HOME" bash "$SETUP" "$@"
}
valid_json_object() { printf '%s' "$1" | "$REAL_JQ" -e 'type == "object"' >/dev/null 2>&1; }

start_test "setup.sh installs the runtime and creates status.conf (idempotent)"
run_setup >/dev/null; rc=$?
assert_eq 0 "$rc" "exit 0"
for f in statusline.sh preview.sh set-theme.sh configure.sh lib/render-common.sh lib/conf-keys.sh themes/nord.sh layouts/fancy.sh oh-my-status.conf; do
  [ -f "$OMA_HOME/status/$f" ] || { echo "    FAIL: missing $f" >&2; TEST_FAILED=1; }
done
cmp -s "$TPL" "$OMA_HOME/status.conf" || { echo "    FAIL: status.conf is not the template" >&2; TEST_FAILED=1; }
printf 'THEME="dracula"\n' > "$OMA_HOME/status.conf"
run_setup >/dev/null
assert_eq 'THEME="dracula"' "$(cat "$OMA_HOME/status.conf")" "existing conf untouched by a second run"
ls "$OMA_HOME/status" | grep -q 'tmp' && { echo "    FAIL: temp files left behind" >&2; TEST_FAILED=1; }
end_test

start_test "setup.sh recreates an empty conf from the template"
mkdir -p "$OMA_HOME"; : > "$OMA_HOME/status.conf"
run_setup >/dev/null
cmp -s "$TPL" "$OMA_HOME/status.conf" || { echo "    FAIL: empty conf not refilled" >&2; TEST_FAILED=1; }
end_test

start_test "setup.sh honors OMA_CONF / OMA_DIR / OMA_CONF_TEMPLATE overrides"
OMA_CONF="$OMA_TEST_ROOT/custom.conf" OMA_DIR="$OMA_TEST_ROOT/rt" OMA_CONF_TEMPLATE="$TPL" bash "$SETUP" >/dev/null 2>&1
[ -f "$OMA_TEST_ROOT/custom.conf" ] && [ -f "$OMA_TEST_ROOT/rt/statusline.sh" ] || { echo "    FAIL: overrides ignored" >&2; TEST_FAILED=1; }
end_test

start_test "setup.sh (manual) is human readable and reports missing keys"
mkdir -p "$OMA_HOME"; printf 'THEME="x"\n' > "$OMA_HOME/status.conf"
out=$(run_setup)
assert_contains "$out" "/status-setup" "mentions the skill"
assert_contains "$out" "QUOTA_FAMILY" "names a missing key"
end_test

start_test "setup.sh --hook: {} on a fresh install (conf == template)"
out=$(run_setup --hook); rc=$?
assert_eq 0 "$rc" "exit 0"; assert_eq "{}" "$out" "empty object"
out=$(run_setup --hook); assert_eq "{}" "$out" "still {} on the second run"
end_test

start_test "setup.sh --hook: injectSteps systemMessage when keys are missing"
mkdir -p "$OMA_HOME"; printf 'THEME="x"\n' > "$OMA_HOME/status.conf"
out=$(run_setup --hook)
valid_json_object "$out" || { echo "    FAIL: not a JSON object: $out" >&2; TEST_FAILED=1; }
assert_eq "1" "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" "one line"
msg=$(printf '%s' "$out" | "$REAL_JQ" -r '.injectSteps[0].systemMessage.systemMessage')
assert_contains "$msg" "/status-setup" "skill name"
assert_contains "$msg" "QUOTA_FAMILY" "key listed"
assert_eq "THEME=\"x\"" "$(cat "$OMA_HOME/status.conf")" "hook never writes a non-empty conf"
end_test

start_test "setup.sh --hook: valid JSON for odd stdin, no stdin, broken template, unwritable home"
for stdin_case in '' 'garbage' '{"a":1}' ; do
  out=$(printf '%s' "$stdin_case" | OMA_HOME="$OMA_HOME" bash "$SETUP" --hook); rc=$?
  assert_eq 0 "$rc" "exit 0 ($stdin_case)"; valid_json_object "$out" || { echo "    FAIL: not JSON ($stdin_case): $out" >&2; TEST_FAILED=1; }
done
out=$(OMA_HOME="$OMA_HOME" bash "$SETUP" --hook </dev/null); valid_json_object "$out" || { echo "    FAIL: /dev/null stdin: $out" >&2; TEST_FAILED=1; }
out=$(printf '{}' | OMA_HOME="$OMA_HOME" OMA_CONF_TEMPLATE="$OMA_TEST_ROOT/none.conf" bash "$SETUP" --hook); rc=$?
assert_eq 0 "$rc" "broken template exit"; assert_eq "{}" "$out" "broken template -> {}"
printf 'x' > "$OMA_TEST_ROOT/afile"
out=$(printf '{}' | OMA_HOME="$OMA_TEST_ROOT/afile/sub" bash "$SETUP" --hook); rc=$?
assert_eq 0 "$rc" "unwritable home exit"; valid_json_object "$out" || { echo "    FAIL: unwritable home: $out" >&2; TEST_FAILED=1; }
end_test

start_test "setup.sh --hook works from the plugin dir as cwd (relative invocation, as agy runs it)"
out=$(cd "$PLUGIN" && printf '{}' | OMA_HOME="$OMA_HOME" bash ./scripts/setup.sh --hook); rc=$?
assert_eq 0 "$rc" "exit"; valid_json_object "$out" || { echo "    FAIL: $out" >&2; TEST_FAILED=1; }
[ -f "$OMA_HOME/status/statusline.sh" ] || { echo "    FAIL: runtime not installed" >&2; TEST_FAILED=1; }
end_test

start_test "setup.sh: 24h stale sweep (gitcache, ctx, handoff rules); account-* and fresh files stay"
S="$OMA_STATE_DIR"
touch "$S/gitcache-old" "$S/gitcache-old.stamp" "$S/gitcache-new" "$S/ctx-old" "$S/ctx-new" "$S/handoff-gone" "$S/handoff-alive" "$S/ctx-alive" "$S/account-x"
old=$(date -d '3 days ago' +%Y%m%d%H%M 2>/dev/null || date -v-3d +%Y%m%d%H%M)
touch -t "$old" "$S/gitcache-old" "$S/gitcache-old.stamp" "$S/ctx-old" "$S/handoff-gone" "$S/handoff-alive" "$S/account-x"
run_setup --hook >/dev/null
for f in gitcache-old gitcache-old.stamp ctx-old handoff-gone; do assert_file_missing "$S/$f" "$f swept"; done
for f in gitcache-new ctx-new ctx-alive handoff-alive account-x; do [ -e "$S/$f" ] || { echo "    FAIL: $f wrongly removed" >&2; TEST_FAILED=1; }; done
end_test

# ---------------- set-theme.sh ----------------
st() { OMA_HOME="$OMA_HOME" bash "$PLUGIN/scripts/set-theme.sh" "$@"; }
install_rt() { run_setup >/dev/null; }

start_test "set-theme: theme+layout, only those lines change"
install_rt
printf '# my comment\nTHEME="catppuccin"\nLAYOUT="fancy"\nSHOW_COST=true\n' > "$OMA_HOME/status.conf"
out=$(st nord minimal); assert_eq 0 "$?" "exit"
assert_eq "$(printf '# my comment\nTHEME="nord"\nLAYOUT="minimal"\nSHOW_COST=true')" "$(cat "$OMA_HOME/status.conf")" "conf"
assert_contains "$out" "theme=nord layout=minimal" "reports result"
end_test

start_test "set-theme: single theme, single layout, mygo sets both"
install_rt
printf 'THEME="catppuccin"\nLAYOUT="fancy"\n' > "$OMA_HOME/status.conf"
st dracula >/dev/null; assert_contains "$(cat "$OMA_HOME/status.conf")" 'THEME="dracula"' "theme"; assert_contains "$(cat "$OMA_HOME/status.conf")" 'LAYOUT="fancy"' "layout kept"
st powerline >/dev/null; assert_contains "$(cat "$OMA_HOME/status.conf")" 'LAYOUT="powerline"' "layout"; assert_contains "$(cat "$OMA_HOME/status.conf")" 'THEME="dracula"' "theme kept"
st mygo >/dev/null; assert_contains "$(cat "$OMA_HOME/status.conf")" 'THEME="mygo"' "both"; assert_contains "$(cat "$OMA_HOME/status.conf")" 'LAYOUT="mygo"' "both"
end_test

start_test "set-theme: appends absent keys (incl. missing trailing newline), creates missing conf"
install_rt
printf 'SHOW_COST=true' > "$OMA_HOME/status.conf"
st gruvbox pure >/dev/null
assert_eq "$(printf 'SHOW_COST=true\nTHEME="gruvbox"\nLAYOUT="pure"')" "$(cat "$OMA_HOME/status.conf")" "appended"
rm -f "$OMA_HOME/status.conf"; st nord >/dev/null
assert_eq 'THEME="nord"' "$(cat "$OMA_HOME/status.conf")" "created"
end_test

start_test "set-theme: invalid names rejected without touching the conf; list works"
install_rt
printf 'THEME="nord"\nLAYOUT="pure"\n' > "$OMA_HOME/status.conf"; before=$(cat "$OMA_HOME/status.conf")
st nope >/dev/null 2>&1; [ $? -ne 0 ] || { echo "    FAIL: unknown accepted" >&2; TEST_FAILED=1; }
st nord nope >/dev/null 2>&1; [ $? -ne 0 ] || { echo "    FAIL: bad layout accepted" >&2; TEST_FAILED=1; }
st nope pure >/dev/null 2>&1; [ $? -ne 0 ] || { echo "    FAIL: bad theme accepted" >&2; TEST_FAILED=1; }
st 'x|s&' >/dev/null 2>&1; [ $? -ne 0 ] || { echo "    FAIL: sed metachars accepted" >&2; TEST_FAILED=1; }
assert_eq "$before" "$(cat "$OMA_HOME/status.conf")" "conf unchanged"
out=$(st list); assert_eq 0 "$?" "list exit"
assert_contains "$out" "theme=nord layout=pure" "current"; assert_contains "$out" "tokyonight" "themes"; assert_contains "$out" "powerline" "layouts"
assert_eq "$before" "$(cat "$OMA_HOME/status.conf")" "list is read-only"
end_test

# ---------------- configure.sh ----------------
cf() { OMA_HOME="$OMA_HOME" bash "$PLUGIN/scripts/configure.sh" "$@"; }

start_test "configure status: none (no file, empty file, no statusLine)"
install_rt
out=$(cf status); assert_eq "none" "$(printf '%s\n' "$out" | sed -n 1p)" "no file"; assert_eq "null" "$(printf '%s\n' "$out" | sed -n 2p)" "null json"
printf '{"theme":"dark"}' > "$OMA_AGY_SETTINGS"; assert_eq "none" "$(cf status | sed -n 1p)" "no statusLine"
end_test

start_test "configure status: ours / other / non-object"
install_rt
printf '{"statusLine":{"type":"command","command":"bash ~/.gemini/oh-my-agy/status/statusline.sh"}}' > "$OMA_AGY_SETTINGS"
assert_eq "ours" "$(OMA_OSTYPE=darwin24 cf status | sed -n 1p)" "ours (POSIX)"
assert_eq "other" "$(OMA_OSTYPE=msys cf status | sed -n 1p)" "legacy tilde command flags as other on Windows for repair"
printf '{"statusLine":{"type":"command","command":"bash /a/custom/status/statusline.sh"}}' > "$OMA_AGY_SETTINGS"
assert_eq "ours" "$(OMA_OSTYPE=darwin24 OMA_HOME=/a/custom bash "$PLUGIN/scripts/configure.sh" status | sed -n 1p)" "POSIX single-letter top-level path not mangled"
printf '{"statusLine":{"type":"command","command":"~/mine.sh"}}' > "$OMA_AGY_SETTINGS"
out=$(cf status); assert_eq "other" "$(printf '%s\n' "$out" | sed -n 1p)" "other"; assert_contains "$out" "~/mine.sh" "prints current JSON"
printf '{"statusLine":"~/mine.sh"}' > "$OMA_AGY_SETTINGS"; assert_eq "other" "$(cf status | sed -n 1p)" "string statusLine"
printf '{"statusLine":true}' > "$OMA_AGY_SETTINGS"; assert_eq "other" "$(cf status | sed -n 1p)" "boolean statusLine"
printf 'not json' > "$OMA_AGY_SETTINGS"; cf status >/dev/null 2>&1; [ $? -ne 0 ] || { echo "    FAIL: invalid json accepted" >&2; TEST_FAILED=1; }
end_test

start_test "configure install: creates missing file; preserves other keys and writes .bak (POSIX)"
OMA_OSTYPE=darwin24 cf install >/dev/null; assert_eq "ours" "$(OMA_OSTYPE=darwin24 cf status | sed -n 1p)" "created"
assert_eq "command" "$("$REAL_JQ" -r .statusLine.type "$OMA_AGY_SETTINGS")" "type"
assert_eq "bash ~/.gemini/oh-my-agy/status/statusline.sh" "$("$REAL_JQ" -r .statusLine.command "$OMA_AGY_SETTINGS")" "command"
printf '{"model":"x","nested":{"a":[1,2]},"statusLine":{"command":"old.sh","padding":1}}' > "$OMA_AGY_SETTINGS"
orig=$(cat "$OMA_AGY_SETTINGS")
OMA_OSTYPE=darwin24 cf install >/dev/null
assert_eq "x" "$("$REAL_JQ" -r .model "$OMA_AGY_SETTINGS")" "model kept"
assert_eq "[1,2]" "$("$REAL_JQ" -c .nested.a "$OMA_AGY_SETTINGS")" "nested kept"
assert_eq "ours" "$(OMA_OSTYPE=darwin24 cf status | sed -n 1p)" "now ours"
assert_eq "$orig" "$(cat "$OMA_AGY_SETTINGS.bak")" "backup is the previous file"
end_test

start_test "configure install (Windows): resolves Git Bash and absolute script path, status=ours"
FAKE_GIT="$OMA_TEST_ROOT/Git"; mkdir -p "$FAKE_GIT/bin" "$FAKE_GIT/usr/bin"
: > "$FAKE_GIT/bin/bash.exe"; : > "$FAKE_GIT/usr/bin/bash.exe"
OMA_OSTYPE=msys cf install >/dev/null
win_cmd=$("$REAL_JQ" -r .statusLine.command "$OMA_AGY_SETTINGS")
assert_not_contains "$win_cmd" "~/" "no unexpanded tilde on Windows"
assert_contains "$win_cmd" "/status/statusline.sh" "absolute script path"
assert_eq "ours" "$(OMA_OSTYPE=msys cf status | sed -n 1p)" "status recognizes custom OMA_HOME as ours"
# Verify sibling bin/bash.exe is preferred over usr/bin/bash.exe via _oma_win_bash_path
win_pref=$(FAKE_GIT="$FAKE_GIT" OMA_TEST_LIB_ONLY=1 OMA_OSTYPE=msys OMA_HOME="$OMA_HOME" bash -c '
  . "$1"
  _oma_win_bash_path "$FAKE_GIT/usr/bin/bash.exe"
' _ "$PLUGIN/scripts/configure.sh" 2>/dev/null)
assert_contains "$win_pref" "bin" "resolved bin path"
assert_not_contains "$win_pref" "usr" "preferred Git/bin/bash.exe over Git/usr/bin/bash.exe"
# Verify running $BASH is preferred over a fake bash earlier on PATH (e.g. WSL System32\bash.exe)
FAKE_WSL="$OMA_TEST_ROOT/fakewsl"; mkdir -p "$FAKE_WSL"
printf '#!/bin/sh\nexit 0\n' > "$FAKE_WSL/bash"; chmod +x "$FAKE_WSL/bash"
win_self=$(PATH="$FAKE_WSL:$PATH" OMA_TEST_LIB_ONLY=1 OMA_OSTYPE=msys OMA_HOME="$OMA_HOME" bash -c '
  . "$1"
  _oma_win_bash_path
' _ "$PLUGIN/scripts/configure.sh" 2>/dev/null)
assert_not_contains "$win_self" "fakewsl" "prefers running \$BASH over PATH bash"
# Trailing slash and Windows backslashes in OMA_HOME preserve the leaf dir when shortening parent
trail_sp=$(OMA_TEST_LIB_ONLY=1 OMA_OSTYPE=msys OMA_HOME='/c/Users/User Space/.gemini/oh-my-agy/' bash -c '
  . "$1"
  cygpath() { [ "$1" = -d ] && printf "C:\\Users\\USERSP~1\\.gemini\n" || printf "%s\n" "$2"; }
  _oma_win_script_path 1
' _ "$PLUGIN/scripts/configure.sh" 2>/dev/null)
assert_eq "C:/Users/USERSP~1/.gemini/oh-my-agy/status/statusline.sh" "$trail_sp" "trailing slash preserves leaf dir"
bs_sp=$(OMA_TEST_LIB_ONLY=1 OMA_OSTYPE=msys OMA_HOME='C:\Users\User Space\.gemini\oh-my-agy\' bash -c '
  . "$1"
  cygpath() { [ "$1" = -d ] && printf "C:\\Users\\USERSP~1\\.gemini\n" || printf "%s\n" "$2"; }
  _oma_win_script_path 1
' _ "$PLUGIN/scripts/configure.sh" 2>/dev/null)
assert_eq "C:/Users/USERSP~1/.gemini/oh-my-agy/status/statusline.sh" "$bs_sp" "backslash OMA_HOME preserves leaf dir"
# Spaces in both bash and script paths fall back cleanly without broken outer quotes
SP_HOME="$OMA_TEST_ROOT/User Space/.gemini/oh-my-agy"
mkdir -p "$SP_HOME/status"
both_sp=$(OMA_TEST_LIB_ONLY=1 OMA_OSTYPE=msys OMA_HOME="$SP_HOME" OMA_BASH_BIN='C:/Program Files/Git/bin/bash.exe' bash -c '
  . "$1"
  command() { if [ "$1" = -v ] && [ "$2" = cygpath ]; then return 1; else builtin command "$@"; fi; }
  _oma_default_status_cmd
' _ "$PLUGIN/scripts/configure.sh" 2>/dev/null)
assert_contains "$both_sp" 'call "C:\Program Files\Git\bin\bash.exe" "' "call quoting when both paths have spaces"
end_test

start_test "configure install: invalid JSON is left untouched"
printf 'not json' > "$OMA_AGY_SETTINGS"
cf install >/dev/null 2>&1; [ $? -ne 0 ] || { echo "    FAIL: expected failure" >&2; TEST_FAILED=1; }
assert_eq "not json" "$(cat "$OMA_AGY_SETTINGS")" "unchanged"
ls "$(dirname "$OMA_AGY_SETTINGS")" | grep -q '^\.settings\.' && { echo "    FAIL: temp file left" >&2; TEST_FAILED=1; }
end_test

start_test "configure missing-keys / backfill: append-only, header, trailing newline"
install_rt
printf '# mine\nTHEME="x"   # keep\nSHOW_COST=true' > "$OMA_HOME/status.conf"
before=$(cat "$OMA_HOME/status.conf")
miss=$(cf missing-keys | paste -sd, -)
assert_contains ",$miss," ",QUOTA_FAMILY," "QUOTA_FAMILY missing"; assert_not_contains ",$miss," ",THEME," "THEME present"; assert_not_contains ",$miss," ",SHOW_COST," "SHOW_COST present"
assert_eq "$before" "$(cat "$OMA_HOME/status.conf")" "missing-keys is read-only"
out=$(cf backfill); assert_contains "$out" "QUOTA_FAMILY" "reports keys"
after=$(cat "$OMA_HOME/status.conf")
assert_eq "$before" "$(printf '%s' "$after" | head -n 3)" "existing lines unchanged byte for byte"
assert_contains "$after" "# --- added by /status-setup ($(date +%F)) ---" "header"
assert_eq "1" "$(grep -c -- '--- added by' "$OMA_HOME/status.conf")" "one header"
assert_contains "$after" "QUOTA_FAMILY=all" "template default value"
assert_eq "" "$(cf missing-keys)" "nothing missing afterwards"
cp "$OMA_HOME/status.conf" "$OMA_TEST_ROOT/snap"; out=$(cf backfill)
cmp -s "$OMA_TEST_ROOT/snap" "$OMA_HOME/status.conf" || { echo "    FAIL: second backfill changed the file" >&2; TEST_FAILED=1; }
assert_contains "$out" "up to date" "idempotent message"
end_test

start_test "configure backfill: ends with a single newline; no conf is a no-op"
install_rt
printf 'THEME="x"\n' > "$OMA_HOME/status.conf"; cf backfill >/dev/null
assert_eq "" "$(tail -n 1 "$OMA_HOME/status.conf" | tr -d '[:alnum:]=_"')" "no blank/extra trailing garbage" 2>/dev/null
[ -z "$(tail -c 1 "$OMA_HOME/status.conf")" ] || { echo "    FAIL: no trailing newline" >&2; TEST_FAILED=1; }
rm -f "$OMA_HOME/status.conf"; cf backfill >/dev/null; assert_file_missing "$OMA_HOME/status.conf" "no conf created by backfill"
end_test

start_test "configure.sh runs from the installed copy too (template next to the scripts)"
install_rt
printf 'THEME="x"\n' > "$OMA_HOME/status.conf"
out=$(OMA_HOME="$OMA_HOME" bash "$OMA_HOME/status/configure.sh" missing-keys | paste -sd, -)
assert_contains ",$out," ",QUOTA_FAMILY," "installed copy finds the template"
end_test

start_test "configure.sh reports install/upgrade command when jq 1.7+ is missing or too old"
EMPTY_BIN="$OMA_TEST_ROOT/emptybin"; mkdir -p "$EMPTY_BIN"
err=$(PATH="$EMPTY_BIN" OMA_OSTYPE=darwin24 OMA_HOME="$OMA_HOME" "$BASH_BIN" "$PLUGIN/scripts/configure.sh" status 2>&1); rc=$?
assert_eq 2 "$rc" "missing jq exit 2"
assert_contains "$err" "jq 1.7+ is required" "missing jq message"
assert_contains "$err" "brew install jq" "macOS install command"
err=$(PATH="$EMPTY_BIN" OMA_OSTYPE=msys OMA_HOME="$OMA_HOME" "$BASH_BIN" "$PLUGIN/scripts/configure.sh" status 2>&1); rc=$?
assert_eq 2 "$rc" "missing jq exit 2 (win)"
assert_contains "$err" "winget install jqlang.jq" "Windows install command"
OLD_JQ="$OMA_TEST_ROOT/oldjq"; mkdir -p "$OLD_JQ"
printf '#!/bin/bash\nfor a in "$@"; do [ "$a" = "--raw-output0" ] && exit 2; done\nexit 0\n' > "$OLD_JQ/jq"
chmod +x "$OLD_JQ/jq"
err=$(PATH="$OLD_JQ" OMA_OSTYPE=darwin24 OMA_HOME="$OMA_HOME" "$BASH_BIN" "$PLUGIN/scripts/configure.sh" status 2>&1); rc=$?
assert_eq 2 "$rc" "old jq exit 2"
assert_contains "$err" "Upgrade it with: brew install jq" "old jq upgrade hint"
end_test

# ---------------- preview.sh ----------------
start_test "preview.sh: themes, layouts, all; hint line; works from repo and installed copy"
install_rt
out=$(OMA_HOME="$OMA_HOME" bash "$PLUGIN/scripts/preview.sh" all | sed -E $'s/\033\\[[0-9;]*[a-zA-Z]//g')
assert_contains "$out" "Gemini 4 Neon (High) [1M]" "demo model"
assert_contains "$out" "[plan]" "demo mode in other layouts"
assert_contains "$out" "plan mode on (shift+tab to cycle)" "demo mode in fancy2 layout"
assert_contains "$out" "1 task" "demo task"
assert_contains "$out" "/status-theme <theme> <layout>" "hint"
for n in catppuccin rosepine mygo default powerline pure fancy fancy2 minimal; do assert_contains "$out" "[$n]" "lists $n"; done
out2=$(OMA_HOME="$OMA_HOME" bash "$OMA_HOME/status/preview.sh" all | sed -E $'s/\033\\[[0-9;]*[a-zA-Z]//g')
assert_eq "$out" "$out2" "installed copy gives the same output"
out=$(OMA_HOME="$OMA_HOME" bash "$PLUGIN/scripts/preview.sh" themes | sed -E $'s/\033\\[[0-9;]*[a-zA-Z]//g')
assert_not_contains "$out" "Available Layouts" "themes only"
end_test

print_summary
