#!/bin/bash
# Tests for the oh-my-knowledge agy hooks: SessionStart, PreInvocation (lookup
# reminder) and Stop (auto-handoff). Hook I/O is agy's camelCase JSON: injectSteps
# for SessionStart/PreInvocation, {"decision":"continue"} for Stop, `{}` when silent.
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
# shellcheck source=../test-helpers.sh
. "$REPO_ROOT/tests/test-helpers.sh"

PLUGIN="$REPO_ROOT/plugins/oh-my-knowledge"
HOOKS="$PLUGIN/hooks"

for v in $(compgen -e | grep -E '^(OMK_|OMA_)'); do unset "$v"; done
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
export HOME="$T/home"; mkdir -p "$HOME/knowledge"; : > "$HOME/knowledge/SCHEMA.md"
export OMA_HOME="$T/oma"; mkdir -p "$OMA_HOME"
export OMA_STATE_DIR="$T/state"

contains() { # <file> <needle> <msg>
  if ! grep -qF -- "$2" "$1" 2>/dev/null; then
    printf '    FAIL: %s\n      missing: %q\n      in: %q\n' "$3" "$2" "$(cat "$1" 2>/dev/null)" >&2; TEST_FAILED=1
  fi
}
lacks() {
  if grep -qF -- "$2" "$1" 2>/dev/null; then
    printf '    FAIL: %s\n      unexpected: %q\n' "$3" "$2" >&2; TEST_FAILED=1
  fi
}
# empty <file> <msg>: agy's "nothing to say" is exactly {} (valid JSON, exit 0)
empty() {
  if [ "$(jq -c . "$1" 2>/dev/null | tr -d '\r')" != '{}' ]; then
    printf '    FAIL: %s (expected {})\n      got: %q\n' "$2" "$(cat "$1")" >&2; TEST_FAILED=1
  fi
}
# sysmsg <file>: the injected system message text
sysmsg() { jq -r '.injectSteps[0].systemMessage.systemMessage // empty' "$1" 2>/dev/null | tr -d '\r'; }

# --- hooks.json ------------------------------------------------------------
start_test "hooks.json: flat handler lists, relative bash commands, root of the plugin"
H="$PLUGIN/hooks.json"
if jq -e '.["oh-my-knowledge"] | (.SessionStart[0].command and .PreInvocation[0].command and .Stop[0].command)' "$H" >/dev/null 2>&1; then :; else
  printf '    FAIL: hooks.json missing/invalid\n' >&2; TEST_FAILED=1; fi
contains "$H" '"bash ./hooks/lookup-reminder.sh"' "reminder command"
contains "$H" '"bash ./hooks/auto-handoff.sh"' "handoff command"
contains "$H" '"bash ./hooks/session-start.sh"' "session-start command"
lacks "$H" 'PLUGIN_ROOT' "no PLUGIN_ROOT in hooks.json (hooks run in the plugin dir)"
lacks "$H" 'UserPromptSubmit' "no Claude event names"
end_test

# --- lookup reminder (PreInvocation) --------------------------------------
# prompt_hook <prompt> [env assignments...] -> $T/out ; invocationNum 0, conversation c1
CID=c1
prompt_hook() {
  local p="$1"; shift
  jq -n --arg p "$p" --arg c "$CID" '{invocationNum:0,initialNumSteps:1,conversationId:$c,workspacePaths:["/tmp"],lastUserInput:$p}' \
    | env "$@" bash "$HOOKS/lookup-reminder.sh" >"$T/out" 2>"$T/err"; RC=$?
}
fresh_remind() { rm -f "$OMA_STATE_DIR"/kbremind-*; }
mkdir -p "$OMA_STATE_DIR"

start_test "lookup-reminder fires on zh and en triggers (injectSteps/systemMessage)"
fresh_remind
prompt_hook '為什麼 docker 很慢'
assert_eq 0 "$RC" "exit"
contains "$T/out" 'kb-lookup' "zh trigger names the kb-lookup skill"
jq -e '.injectSteps[0].systemMessage.systemMessage | startswith("[oh-my-knowledge hook]")' "$T/out" >/dev/null 2>&1 || { printf '    FAIL: not the agy inject shape: %q\n' "$(cat "$T/out")" >&2; TEST_FAILED=1; }
lacks "$T/out" 'hookSpecificOutput' "no Claude output shape"
CID=c2; prompt_hook 'why does it fail'
contains "$T/out" 'kb-lookup' "en trigger"
CID=c3; prompt_hook 'The build TIMED OUT again'
contains "$T/out" 'kb-lookup' "en trigger uppercase"
end_test

start_test "lookup-reminder silent cases ({} and exit 0)"
fresh_remind; CID=c1
prompt_hook '/kb-handoff why is it slow'; empty "$T/out" "slash command"
prompt_hook '   /kb-handoff 為什麼'; empty "$T/out" "slash command after spaces"
prompt_hook 'OK'; empty "$T/out" "OK"
prompt_hook 'please change the color'; empty "$T/out" "no trigger"
prompt_hook 'somewhat showy'; empty "$T/out" "word boundary"
prompt_hook ''; empty "$T/out" "empty prompt"
prompt_hook '為什麼 docker 很慢' OMK_LOOKUP_REMINDER=false; empty "$T/out" "setting off (env)"
printf 'LOOKUP_REMINDER=false\n' > "$T/off.conf"
prompt_hook '為什麼 docker 很慢' OMK_CONF="$T/off.conf"; empty "$T/out" "setting off (knowledge.conf)"
prompt_hook '為什麼 docker 很慢' OMK_CONF="$T/off.conf" OMK_LOOKUP_REMINDER=true; contains "$T/out" 'kb-lookup' "env overrides conf"
fresh_remind
prompt_hook 'why does it fail' OMK_JQ=/nonexistent; empty "$T/out" "jq missing"; assert_eq 0 "$RC" "jq missing exit"
printf 'garbage' | bash "$HOOKS/lookup-reminder.sh" >"$T/out" 2>/dev/null; assert_eq 0 $? "garbage stdin exit"; empty "$T/out" "garbage stdin"
printf '{}' | bash "$HOOKS/lookup-reminder.sh" >"$T/out" 2>/dev/null; empty "$T/out" "empty payload"
end_test

start_test "lookup-reminder: only the first invocation of a turn; one reminder per prompt per conversation"
fresh_remind; CID=c1
for n in 1 2 5; do
  jq -n --argjson n "$n" '{invocationNum:$n,conversationId:"c1",lastUserInput:"why is it slow"}' | bash "$HOOKS/lookup-reminder.sh" >"$T/out" 2>/dev/null
  empty "$T/out" "invocationNum $n"
done
jq -n '{conversationId:"c1",lastUserInput:"why is it slow"}' | bash "$HOOKS/lookup-reminder.sh" >"$T/out" 2>/dev/null; empty "$T/out" "no invocationNum"
prompt_hook 'why is it slow'; contains "$T/out" 'kb-lookup' "invocationNum 0 fires"
prompt_hook 'why is it slow'; empty "$T/out" "same prompt again in the same conversation (dedupe)"
prompt_hook 'why is it slower now'; contains "$T/out" 'kb-lookup' "a different prompt fires again"
CID=other; prompt_hook 'why is it slower now'; contains "$T/out" 'kb-lookup' "same prompt, other conversation fires"
[ -f "$OMA_STATE_DIR/kbremind-c1" ] || { printf '    FAIL: dedupe stamp missing\n' >&2; TEST_FAILED=1; }
CID='a/b c'; prompt_hook 'why is it slow'
[ -f "$OMA_STATE_DIR/kbremind-a_b_c" ] || { printf '    FAIL: sanitised dedupe stamp missing\n' >&2; TEST_FAILED=1; }
touch -d '10 days ago' "$OMA_STATE_DIR/kbremind-c1" 2>/dev/null && { CID=zz; prompt_hook 'why is it slow'; [ -e "$OMA_STATE_DIR/kbremind-c1" ] && { printf '    FAIL: week-old stamp not swept\n' >&2; TEST_FAILED=1; }; }
printf '{"invocationNum":0,"lastUserInput":"why is it slow"}' | bash "$HOOKS/lookup-reminder.sh" >"$T/out" 2>/dev/null
contains "$T/out" 'kb-lookup' "no conversationId: still reminds (no dedupe possible)"
CID=c1
end_test

start_test "lookup-reminder skips harness relays (starts-with only)"
fresh_remind
prompt_hook '<agent-message from="x">why did it fail</agent-message>'; empty "$T/out" "agent-message relay"
prompt_hook '<task-notification>task failed with error</task-notification>'; empty "$T/out" "task-notification relay"
prompt_hook '[SYSTEM NOTIFICATION] build failed'; empty "$T/out" "system notification relay"
prompt_hook '   <agent-message from="x">why did it fail</agent-message>'; empty "$T/out" "relay after leading spaces"
prompt_hook "$(printf '\n\t<task-notification>why error</task-notification>')"; empty "$T/out" "relay after leading newline/tab"
prompt_hook 'what does <agent-message > mean, why does it fail'; contains "$T/out" 'kb-lookup' "quoted mid-text still reminded"
prompt_hook 'why does the build fail'; contains "$T/out" 'kb-lookup' "normal question still reminded"
end_test

# --- auto-handoff (Stop) --------------------------------------------------
stop_hook() { # <json> [env...] -> $T/out, RC
  local j="$1"; shift
  printf '%s' "$j" | env "$@" bash "$HOOKS/auto-handoff.sh" >"$T/out" 2>"$T/err"; RC=$?
}
reset_state() { rm -f "$OMA_STATE_DIR"/ctx-* "$OMA_STATE_DIR"/handoff-*; }
STOP='{"conversationId":"sess-A","executionNum":1,"terminationReason":"model_stop","fullyIdle":true,"continuationActive":false}'

start_test "auto-handoff fires at default threshold 70, writes marker first"
reset_state
printf '70 200000\n' > "$OMA_STATE_DIR/ctx-sess-A"
stop_hook "$STOP"
assert_eq 0 "$RC" "exit"
contains "$T/out" '"decision":"continue"' "decision"
contains "$T/out" 'Context is at 70%' "pct in reason"
contains "$T/out" 'kb-handoff' "skill in reason"
contains "$T/out" 'conversation id: sess-A' "conversation id in reason"
jq -e '.decision == "continue" and (.reason | length > 0)' "$T/out" >/dev/null 2>&1 || { printf '    FAIL: bad JSON shape\n' >&2; TEST_FAILED=1; }
[ -f "$OMA_STATE_DIR/handoff-sess-A" ] || { printf '    FAIL: marker not written\n' >&2; TEST_FAILED=1; }
stop_hook "$STOP"; empty "$T/out" "second Stop with marker"
end_test

start_test "auto-handoff silent cases ({})"
reset_state
printf '69 200000\n' > "$OMA_STATE_DIR/ctx-sess-A"
stop_hook "$STOP"; empty "$T/out" "below threshold"
[ -f "$OMA_STATE_DIR/handoff-sess-A" ] && { printf '    FAIL: marker written below threshold\n' >&2; TEST_FAILED=1; }
printf '90 200000\n' > "$OMA_STATE_DIR/ctx-sess-A"
stop_hook '{"conversationId":"sess-A","continuationActive":true}'; empty "$T/out" "continuationActive (never loops)"
stop_hook '{"conversationId":"sess-B"}'; empty "$T/out" "missing ctx"
printf 'garbage\n' > "$OMA_STATE_DIR/ctx-sess-B"
stop_hook '{"conversationId":"sess-B"}'; empty "$T/out" "garbage ctx"
stop_hook "$STOP" OMK_AUTO_HANDOFF=false; empty "$T/out" "setting off (env)"
printf 'AUTO_HANDOFF=no\n' > "$T/off.conf"
stop_hook "$STOP" OMK_CONF="$T/off.conf"; empty "$T/out" "setting off (knowledge.conf)"
stop_hook "$STOP" OMK_JQ=/nonexistent; empty "$T/out" "jq missing"; assert_eq 0 "$RC" "jq missing exit"
stop_hook 'not json'; empty "$T/out" "garbage stdin"; assert_eq 0 "$RC" "garbage stdin exit"
stop_hook '{"executionNum":1}'; empty "$T/out" "no conversation id"
printf ' 200000\n' > "$OMA_STATE_DIR/ctx-sess-C"
stop_hook '{"conversationId":"sess-C"}'; empty "$T/out" "empty pct field"
printf '\n' > "$OMA_STATE_DIR/ctx-sess-C"
stop_hook '{"conversationId":"sess-C"}'; empty "$T/out" "blank ctx line"
printf '90\n' > "$OMA_STATE_DIR/handoff-sess-A"
printf '90 200000\n' > "$OMA_STATE_DIR/ctx-sess-A"
stop_hook "$STOP"; empty "$T/out" "existing marker at 90%"
end_test

# fire_case <label> <marker content|-> <ctx pct> <expect fire|silent> [env...]
fire_case() {
  local label="$1" mk="$2" pct="$3" want="$4"; shift 4
  reset_state
  printf '%s 200000\n' "$pct" > "$OMA_STATE_DIR/ctx-sess-A"
  [ "$mk" = - ] || printf '%b' "$mk" > "$OMA_STATE_DIR/handoff-sess-A"
  stop_hook "$STOP" "$@"
  assert_eq 0 "$RC" "$label exit"
  if [ "$want" = fire ]; then
    contains "$T/out" '"decision":"continue"' "$label fires"
    assert_eq "$pct" "$(head -n1 "$OMA_STATE_DIR/handoff-sess-A" 2>/dev/null)" "$label marker records pct"
  else
    empty "$T/out" "$label silent"
  fi
}

start_test "auto-handoff firing rule (thr 70, repeat 20)"
fire_case "no marker" - 70 fire
assert_eq "70" "$(cat "$OMA_STATE_DIR/handoff-sess-A")" "marker content is the pct"
fire_case "r<thr gap 4" '66\n' 70 silent
fire_case "r<thr gap 5" '65\n' 70 fire
fire_case "r<thr small r" '10\n' 70 fire
fire_case "r>=thr gap repeat-1" '70\n' 89 silent
fire_case "r>=thr gap repeat" '70\n' 90 fire
fire_case "r+repeat>100" '85\n' 100 silent
fire_case "r+repeat=100 (r=80)" '80\n' 100 fire
fire_case "below threshold, no marker" - 69 silent
end_test

start_test "auto-handoff marker validity"
fire_case "empty marker = 0" '' 70 fire
fire_case "abc marker = 0" 'abc\n' 70 fire
fire_case "150 marker = 0" '150\n' 70 fire
fire_case "20-digit marker = 0" '00000000000000000090\n' 70 fire
fire_case "CRLF marker 72 -> 72 (gap 18 silent)" '72\r\n' 90 silent
fire_case "CRLF marker 72 -> 72 (gap 20 fires)" '72\r\n' 92 fire
fire_case "first line only" '72\n10\n' 90 silent
reset_state
printf '100 200000\r\n' > "$OMA_STATE_DIR/ctx-sess-A"
stop_hook "$STOP"; contains "$T/out" 'Context is at 100%' "CRLF ctx"
reset_state
printf '75\r\n' > "$OMA_STATE_DIR/ctx-sess-A"
stop_hook "$STOP"; contains "$T/out" 'Context is at 75%' "CRLF ctx without size"
assert_eq "75" "$(cat "$OMA_STATE_DIR/handoff-sess-A" 2>/dev/null)" "CRLF ctx records 75"
reset_state
printf '0075 200000\n' > "$OMA_STATE_DIR/ctx-sess-A"
stop_hook "$STOP"; empty "$T/out" "4-digit ctx 0075 invalid"
reset_state
printf '150 200000\n' > "$OMA_STATE_DIR/ctx-sess-A"
stop_hook "$STOP"; empty "$T/out" "invalid ctx 150"
end_test

start_test "auto-handoff repeat setting is clamped 10-60"
fire_case "repeat=5 acts as 10 (gap 9)" '70\n' 79 silent OMK_AUTO_HANDOFF_REPEAT=5
fire_case "repeat=5 acts as 10 (gap 10)" '70\n' 80 fire OMK_AUTO_HANDOFF_REPEAT=5
fire_case "repeat=99 acts as 60 (gap 59)" '30\n' 89 silent OMK_AUTO_HANDOFF_REPEAT=99 OMK_AUTO_HANDOFF_THRESHOLD=30
fire_case "repeat=99 acts as 60 (gap 60)" '30\n' 90 fire OMK_AUTO_HANDOFF_REPEAT=99 OMK_AUTO_HANDOFF_THRESHOLD=30
fire_case "env repeat=30 (gap 29)" '70\n' 99 silent OMK_AUTO_HANDOFF_REPEAT=30
fire_case "env repeat=30 (gap 30)" '70\n' 100 fire OMK_AUTO_HANDOFF_REPEAT=30
printf 'AUTO_HANDOFF_REPEAT=30\nAUTO_HANDOFF_THRESHOLD=40\n' > "$T/rep.conf"
fire_case "conf repeat=30 thr=40 (gap 29)" '40\n' 69 silent OMK_CONF="$T/rep.conf"
fire_case "conf repeat=30 thr=40 (gap 30)" '40\n' 70 fire OMK_CONF="$T/rep.conf"
fire_case "threshold clamped to 30 (29 silent)" - 29 silent OMK_AUTO_HANDOFF_THRESHOLD=5
fire_case "threshold clamped to 30 (30 fires)" - 30 fire OMK_AUTO_HANDOFF_THRESHOLD=5
fire_case "threshold clamped to 90 (89 silent)" - 89 silent OMK_AUTO_HANDOFF_THRESHOLD=99
fire_case "threshold clamped to 90 (90 fires)" - 90 fire OMK_AUTO_HANDOFF_THRESHOLD=99
end_test

start_test "auto-handoff unwritable marker and continuationActive stay silent"
reset_state
printf '80 200000\n' > "$OMA_STATE_DIR/ctx-sess-A"
mkdir "$OMA_STATE_DIR/handoff-sess-A"
stop_hook "$STOP"; assert_eq 0 "$RC" "unwritable exit"; empty "$T/out" "unwritable marker (directory)"
rmdir "$OMA_STATE_DIR/handoff-sess-A"
stop_hook '{"conversationId":"sess-A","continuationActive":true}'; empty "$T/out" "continuationActive true"
[ -e "$OMA_STATE_DIR/handoff-sess-A" ] && { printf '    FAIL: marker written while continuationActive\n' >&2; TEST_FAILED=1; }
stop_hook '{"conversationId":"sess-A"}'; contains "$T/out" '"decision":"continue"' "continuationActive absent fires"
end_test

start_test "auto-handoff: loop guard (the continuation's own Stop does not continue again)"
reset_state
printf '80 200000\n' > "$OMA_STATE_DIR/ctx-sess-A"
stop_hook "$STOP"; contains "$T/out" '"decision":"continue"' "first Stop continues"
stop_hook '{"conversationId":"sess-A","continuationActive":true}'; empty "$T/out" "continuation Stop: silent"
stop_hook "$STOP"; empty "$T/out" "next plain Stop: silent (marker)"
end_test

start_test "auto-handoff: null continuationActive, payload without conversationId; sanitises the id"
reset_state
printf '80 200000\n' > "$OMA_STATE_DIR/ctx-sess-A"
stop_hook '{"continuationActive":false}'; empty "$T/out" "no conversationId (active false)"
stop_hook '{"continuationActive":true}'; empty "$T/out" "no conversationId (active true)"
stop_hook '{"conversationId":"sess-A","continuationActive":null}'; contains "$T/out" '"decision":"continue"' "null continuationActive"
reset_state
printf '50 200000\n' > "$OMA_STATE_DIR/ctx-a_b_c"
stop_hook '{"conversationId":"a/b c"}' OMK_AUTO_HANDOFF_THRESHOLD=50
contains "$T/out" '"decision":"continue"' "fires at 50"
[ -f "$OMA_STATE_DIR/handoff-a_b_c" ] || { printf '    FAIL: sanitised marker missing\n' >&2; TEST_FAILED=1; }
end_test

# --- session-start --------------------------------------------------------
start_hook() { # [env...] -> $T/out   (conversation sess-A, cwd $T/cwd0)
  mkdir -p "$T/cwd0"
  printf '{"conversationId":"sess-A","workspacePaths":["%s"],"cwd":"%s"}' "$T/cwd0" "$T/cwd0" \
    | env "$@" bash "$HOOKS/session-start.sh" >"$T/out" 2>"$T/err"; RC=$?
}
KB="$T/kbdir"; mkdir -p "$KB" "$HOME/knowledge"; : > "$KB/SCHEMA.md"
# native form of an existing dir: C:/… on Windows (pwd -W), plain physical path elsewhere
native() { ( cd -P -- "$1" && { pwd -W 2>/dev/null || pwd -P; } ); }

start_test "session-start: default dir, agy injectSteps shape, scripts path and conversation id"
start_hook
assert_eq 0 "$RC" "exit"
jq -e '.injectSteps | length == 1' "$T/out" >/dev/null 2>&1 || { printf '    FAIL: bad JSON: %q\n' "$(cat "$T/out")" >&2; TEST_FAILED=1; }
DEF="$(sysmsg "$T/out")"
case "$DEF" in "Knowledge base: "*"/knowledge. [[g:slug]]"*) ;; *) printf '    FAIL: default line: %q\n' "$DEF" >&2; TEST_FAILED=1;; esac
case "$DEF" in *"$(native "$HOME/knowledge")."*) ;; *) printf '    FAIL: ~/knowledge not resolved to native form: %q\n' "$DEF" >&2; TEST_FAILED=1;; esac
case "$DEF" in *"oh-my-knowledge scripts: $(native "$PLUGIN")/scripts "*) ;; *) printf '    FAIL: scripts path missing: %q\n' "$DEF" >&2; TEST_FAILED=1;; esac
case "$DEF" in *"Conversation id: sess-A."*) ;; *) printf '    FAIL: conversation id missing: %q\n' "$DEF" >&2; TEST_FAILED=1;; esac
contains "$T/out" '[[g:slug]]' "link defs"
lacks "$T/out" 'hookSpecificOutput' "no Claude output shape"
start_hook OMK_KNOWLEDGE_DIR="$KB"
contains "$T/out" "Knowledge base: $(native "$KB")." "configured dir"
printf 'KNOWLEDGE_DIR=%s\n' "$KB" > "$T/kb.conf"
start_hook OMK_CONF="$T/kb.conf"
contains "$T/out" "Knowledge base: $(native "$KB")." "dir from knowledge.conf"
start_hook PLUGIN_ROOT=/opt/plug OMK_KNOWLEDGE_DIR="$KB"
contains "$T/out" "oh-my-knowledge scripts: /opt/plug/scripts " "PLUGIN_ROOT wins"
start_hook OMK_JQ=/nonexistent; empty "$T/out" "jq missing"; assert_eq 0 "$RC" "jq missing exit"
printf 'garbage' | bash "$HOOKS/session-start.sh" >"$T/out" 2>/dev/null; empty "$T/out" "garbage stdin"
end_test

start_test "session-start leaves ctx/handoff state alone (agy has no compact/clear source)"
printf '70\n' > "$OMA_STATE_DIR/handoff-sess-A"; printf '80 200000\n' > "$OMA_STATE_DIR/ctx-sess-A"
start_hook OMK_KNOWLEDGE_DIR="$KB"
[ -f "$OMA_STATE_DIR/handoff-sess-A" ] && [ -f "$OMA_STATE_DIR/ctx-sess-A" ] || { printf '    FAIL: state removed\n' >&2; TEST_FAILED=1; }
end_test

start_test "configuration error (relative knowledge_dir): SessionStart prints it; other hooks silent"
ERRMSG='knowledge_dir must be an absolute path or start with ~/ (got: kb); run the kb-setup skill'
start_hook OMK_KNOWLEDGE_DIR=kb
assert_eq 0 "$RC" "exit"
got="$(sysmsg "$T/out")"
case "$got" in *"$ERRMSG"*) ;; *) printf '    FAIL: message missing: %q\n' "$got" >&2; TEST_FAILED=1 ;; esac
case "$got" in "Knowledge base: "*) printf '    FAIL: normal note not replaced: %q\n' "$got" >&2; TEST_FAILED=1 ;; esac
fresh_remind
prompt_hook '為什麼 docker 很慢' OMK_KNOWLEDGE_DIR=kb; empty "$T/out" "reminder silent on config error"
prompt_hook '為什麼 docker 很慢' OMK_KNOWLEDGE_DIR="$KB"; contains "$T/out" 'kb-lookup' "reminder fires with a valid dir (same prompt)"
reset_state; printf '90 200000\n' > "$OMA_STATE_DIR/ctx-sess-A"
stop_hook "$STOP" OMK_KNOWLEDGE_DIR=kb; empty "$T/out" "auto-handoff silent on config error"
[ -f "$OMA_STATE_DIR/handoff-sess-A" ] && { printf '    FAIL: marker written despite config error\n' >&2; TEST_FAILED=1; }
stop_hook "$STOP" OMK_KNOWLEDGE_DIR="$KB"; contains "$T/out" '"decision":"continue"' "auto-handoff continues with a valid dir"
reset_state
end_test

start_test "not set up (no SCHEMA.md): SessionStart prints the note; reminder and auto-handoff silent; each paired with a set-up KB"
NOKB="$T/nokb"; mkdir -p "$NOKB"
NOMSG="oh-my-knowledge: knowledge base not set up yet ($(native "$NOKB")) — run the kb-setup skill (scripts: $(native "$PLUGIN")/scripts)."
start_hook OMK_KNOWLEDGE_DIR="$NOKB"
assert_eq 0 "$RC" "exit"
got="$(sysmsg "$T/out")"
case "$got" in "$NOMSG"*) ;; *) printf '    FAIL: not-set-up note missing: %q\n' "$got" >&2; TEST_FAILED=1 ;; esac
case "$got" in *"[[g:slug]]"*) printf '    FAIL: link definitions not replaced: %q\n' "$got" >&2; TEST_FAILED=1 ;; esac
start_hook OMK_KNOWLEDGE_DIR="$KB"; contains "$T/out" 'Knowledge base:' "paired: set-up KB prints the normal note"
lacks "$T/out" 'not set up yet' "paired: set-up KB has no not-set-up note"
mkdir -p "$T/dirschema/SCHEMA.md"
start_hook OMK_KNOWLEDGE_DIR="$T/dirschema"; contains "$T/out" 'not set up yet' "SCHEMA.md as a directory is not set up"
fresh_remind
prompt_hook '為什麼 docker 很慢' OMK_KNOWLEDGE_DIR="$NOKB"; empty "$T/out" "reminder silent before setup"
prompt_hook '為什麼 docker 很慢' OMK_KNOWLEDGE_DIR="$KB"; contains "$T/out" 'kb-lookup' "paired: reminder fires with SCHEMA.md"
reset_state; printf '90 200000\n' > "$OMA_STATE_DIR/ctx-sess-A"
stop_hook "$STOP" OMK_KNOWLEDGE_DIR="$NOKB"; empty "$T/out" "auto-handoff silent before setup"
[ -f "$OMA_STATE_DIR/handoff-sess-A" ] && { printf '    FAIL: marker written before setup\n' >&2; TEST_FAILED=1; }
reset_state; printf '90 200000\n' > "$OMA_STATE_DIR/ctx-sess-A"
stop_hook "$STOP" OMK_KNOWLEDGE_DIR="$KB"; contains "$T/out" '"decision":"continue"' "paired: auto-handoff continues with SCHEMA.md"
reset_state
start_hook OMK_KNOWLEDGE_DIR=kb
contains "$T/out" 'knowledge_dir must be an absolute path' "config error shown"
lacks "$T/out" 'not set up yet' "config error wins over not set up"
end_test

# --- session-start: project memory + always-on ----------------------------
AO_HOME="$T/aohome"; AO_KB="$T/kbao"; AO_W="$T/aowork/proj"
mkdir -p "$AO_HOME/projects" "$AO_KB/projects/demo" "$AO_W"; : > "$AO_KB/SCHEMA.md"
git -C "$AO_W" init -q . >/dev/null 2>&1
AO_ENC="$(bash -c '. "$1"; omk_encode_path "$2"' _ "$PLUGIN/scripts/lib/common.sh" "$AO_W" | tr -d '\r')"
AO_MEM="$AO_HOME/projects/$AO_ENC/memory"
AO_PAGE="$AO_KB/projects/demo/always-on.md"
ao_marker() { printf -- '- Knowledge base project: [[k:projects/%s/index]] (omk-project)\n' "$1"; }
# ao_hook <cwd|-> [env...] -> $T/out ; cwd "-" omits the field
ao_hook() {
  local c="$1"; shift
  if [ "$c" = "-" ]; then
    printf '{"conversationId":"sess-A"}'
  else
    MSYS2_ARG_CONV_EXCL='*' jq -nc --arg c "$c" '{conversationId:"sess-A",workspacePaths:[$c],cwd:$c}'
  fi | env OMA_HOME="$AO_HOME" OMK_KNOWLEDGE_DIR="$AO_KB" "$@" bash "$HOOKS/session-start.sh" >"$T/out" 2>"$T/err"; RC=$?
}
ao_msg() { sysmsg "$T/out"; }
AO_HEAD='Always-on directives for this project (demo) — follow them in every reply:'
# ao_blk: the always-on block (heading to end of message), "" when absent
ao_blk() { local m; m="$(ao_msg)"; case "$m" in *"$AO_HEAD"*) printf '%s' "$AO_HEAD${m#*"$AO_HEAD"}" ;; esac; }
ao_expect() { # <got> <expected> <label>
  [ "$1" = "$2" ] || { printf '    FAIL: %s\n      want: %q\n      got:  %q\n' "$3" "$2" "$1" >&2; TEST_FAILED=1; }
}

start_test "session-start project memory: path always shown; MEMORY.md injected when present (capped at 200 lines)"
ao_hook "$AO_W"
contains "$T/out" "Project memory (progress of this project): $AO_MEM/MEMORY.md" "path shown even before the file exists"
lacks "$T/out" '--- MEMORY.md ---' "no body when missing"
mkdir -p "$AO_MEM"; : > "$AO_MEM/MEMORY.md"
ao_hook "$AO_W"; lacks "$T/out" '--- MEMORY.md ---' "no body when empty"
printf '## ⚡ 現況（2026-01-01）\n- 🎯 Goal: ship it\r\n\n' > "$AO_MEM/MEMORY.md"
ao_marker demo >> "$AO_MEM/MEMORY.md"
ao_hook "$AO_W"
M="$(ao_msg)"
case "$M" in *$'--- MEMORY.md ---\n## ⚡ 現況（2026-01-01）\n- 🎯 Goal: ship it\n\n- Knowledge base project:'*'--- end MEMORY.md ---'*) ;; *) printf '    FAIL: MEMORY.md body: %q\n' "$M" >&2; TEST_FAILED=1;; esac
# subdir of the repo maps to the same memory (repo root encoding)
mkdir -p "$AO_W/sub/deep"; ao_hook "$AO_W/sub/deep"
contains "$T/out" "$AO_MEM/MEMORY.md" "subdirectory maps to the repo root's memory"
# cwd falls back to $PWD, then to workspacePaths[0]
(cd "$AO_W" && printf '{"conversationId":"sess-A"}' | env OMA_HOME="$AO_HOME" OMK_KNOWLEDGE_DIR="$AO_KB" bash "$HOOKS/session-start.sh" >"$T/out" 2>/dev/null)
contains "$T/out" "$AO_MEM/MEMORY.md" "no cwd field falls back to \$PWD"
(cd "$T" && jq -nc --arg c "$AO_W" '{conversationId:"sess-A",workspacePaths:[$c]}' | env OMA_HOME="$AO_HOME" OMK_KNOWLEDGE_DIR="$AO_KB" bash "$HOOKS/session-start.sh" >"$T/out" 2>/dev/null)
contains "$T/out" "$AO_MEM/MEMORY.md" "workspacePaths[0] used when cwd is absent"
# cap: 200 lines
{ i=0; while [ "$i" -lt 250 ]; do i=$((i+1)); printf 'memline-%03d\n' "$i"; done; } > "$AO_MEM/MEMORY.md"
ao_hook "$AO_W"
contains "$T/out" 'memline-200' "line 200 injected"
lacks "$T/out" 'memline-201' "line 201 not injected"
# cap: bytes
{ i=0; while [ "$i" -lt 100 ]; do i=$((i+1)); printf '%s\n' "$(printf 'z%.0s' $(seq 1 300))"; done; } > "$AO_MEM/MEMORY.md"
ao_hook "$AO_W"; M="$(ao_msg)"
[ "${#M}" -lt 22000 ] || { printf '    FAIL: byte cap not applied (%s chars)\n' "${#M}" >&2; TEST_FAILED=1; }
OMK_KNOWLEDGE_DIR="$AO_KB" OMA_HOME="$AO_HOME" OMK_AUTO_MEMORY_DIR="$T/explicit" ao_hook "$AO_W" OMK_AUTO_MEMORY_DIR="$T/explicit"
contains "$T/out" "$T/explicit/MEMORY.md" "OMK_AUTO_MEMORY_DIR override"
end_test

ao_marker demo > "$AO_MEM/MEMORY.md"
printf -- '---\nname: ao\ndescription: d\ntags:\n- yaml-list-item\n---\n# Title\n- Reply in 繁體中文\n  - indented is not a directive\nprose line\n```\n- inside fence\n```\n<!-- single-line comment -->\n<!--\n- inside comment\n-->\n- say "hi" and C:\\path\\x\n-not a directive\n- last <!-- inline kept -->\n' > "$AO_PAGE"
AO_BODY="$(printf -- '- Reply in 繁體中文\n- say "hi" and C:\\path\\x\n- last <!-- inline kept -->')"

start_test "session-start always-on: heading and exactly the '- ' lines; frontmatter, fences and comments excluded"
ao_hook "$AO_W"
assert_eq 0 "$RC" "exit"
jq -e '.injectSteps[0].systemMessage.systemMessage' "$T/out" >/dev/null 2>&1 || { printf '    FAIL: bad JSON: %q\n' "$(cat "$T/out")" >&2; TEST_FAILED=1; }
ao_expect "$(ao_blk)" "$AO_HEAD"$'\n'"$AO_BODY" "injected block"
case "$(ao_msg)" in *$'\n\n'"$AO_HEAD"*) ;; *) printf '    FAIL: block not separated by a blank line\n' >&2; TEST_FAILED=1;; esac
end_test

start_test "session-start always-on: CRLF page, trailing CR on cwd"
printf -- '---\r\nname: ao\r\ntags:\r\n- yaml-list-item\r\n---\r\n- one\r\n- two\r\n' > "$AO_PAGE"
ao_hook "$AO_W"
ao_expect "$(ao_blk)" "$AO_HEAD"$'\n- one\n- two' "CRLF page"
assert_eq false "$(jq -r '.injectSteps[0].systemMessage.systemMessage | contains("\r")' "$T/out" | tr -d '\r')" "no CR in the message"
if [ "$(jq -n '"a"' | od -An -c | tr -d ' ')" = '"a"\n' ]; then
  printf '{"conversationId":"sess-A","cwd":"%s\\r"}' "$AO_W" | env OMA_HOME="$AO_HOME" OMK_KNOWLEDGE_DIR="$AO_KB" bash "$HOOKS/session-start.sh" >"$T/out" 2>/dev/null
  ao_expect "$(ao_blk)" "$AO_HEAD"$'\n- one\n- two' "payload cwd ending in CR"
fi
end_test

start_test "session-start always-on: anything unmapped leaves the note without a block"
printf -- '- one\n' > "$AO_PAGE"
ao_hook "$AO_W"; ao_expect "$(ao_blk)" "$AO_HEAD"$'\n- one' "baseline injects"
ao_hook "$T/aowork"; ao_expect "$(ao_blk)" "" "not migrated (cwd without marker)"
ao_marker demo > "$AO_MEM/MEMORY.md"; ao_marker other >> "$AO_MEM/MEMORY.md"; mkdir -p "$AO_KB/projects/other"
ao_hook "$AO_W"; ao_expect "$(ao_blk)" "" "multiple projects"
ao_marker nosuch > "$AO_MEM/MEMORY.md"
ao_hook "$AO_W"; ao_expect "$(ao_blk)" "" "marker names a missing project"
ao_marker demo > "$AO_MEM/MEMORY.md"
mv "$AO_PAGE" "$AO_PAGE.off"
ao_hook "$AO_W"; ao_expect "$(ao_blk)" "" "no page"
printf -- '---\nname: ao\n---\nno directives here\n  - indented\n' > "$AO_PAGE"
ao_hook "$AO_W"; ao_expect "$(ao_blk)" "" "page without '- ' lines"
printf -- '> Moved: [[k:rules/x]]\n' > "$AO_PAGE"
ao_hook "$AO_W"; ao_expect "$(ao_blk)" "" "stub page"
printf -- '```\n- never closed fence\n' > "$AO_PAGE"
ao_hook "$AO_W"; ao_expect "$(ao_blk)" "" "only an unclosed fence"
rm -f "$AO_PAGE"; mv "$AO_PAGE.off" "$AO_PAGE"
ao_hook "$AO_W" OMK_KNOWLEDGE_DIR=kb
case "$(ao_msg)" in *"Always-on directives"*) printf '    FAIL: injected despite config error\n' >&2; TEST_FAILED=1;; esac
NOKB2="$T/nokb2"; mkdir -p "$NOKB2/projects/demo"; cp "$AO_PAGE" "$NOKB2/projects/demo/always-on.md"
ao_hook "$AO_W" OMK_KNOWLEDGE_DIR="$NOKB2"
case "$(ao_msg)" in *"Always-on directives"*) printf '    FAIL: injected despite not set up\n' >&2; TEST_FAILED=1;; esac
contains "$T/out" 'not set up yet' "not-set-up note kept"
end_test

start_test "session-start always-on: cap of 4000 bytes at a line boundary, then the (more in ...) line"
: > "$AO_PAGE"
i=0; while [ "$i" -lt 100 ]; do i=$((i+1)); printf -- '- line-%03d %s\n' "$i" "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx" >> "$AO_PAGE"; done
ao_hook "$AO_W"
M="$(ao_msg)"
BLOCK="${M#*"$AO_HEAD"$'\n'}"
case "$BLOCK" in *$'\n(more in [[k:projects/demo/always-on]])') ;; *) printf '    FAIL: no (more in) line: %q\n' "${BLOCK: -80}" >&2; TEST_FAILED=1;; esac
LINES_ONLY="${BLOCK%$'\n(more in [[k:projects/demo/always-on]])'}"
assert_eq 1 "$([ "$(printf '%s' "$LINES_ONLY" | LC_ALL=C wc -c | tr -d ' ')" -le 4000 ] && echo 1 || echo 0)" "directive lines <= 4000 bytes"
NL="$(printf '%s\n' "$LINES_ONLY" | grep -c '^- line-[0-9]* x\{52\}$')"
assert_eq "$(printf '%s\n' "$LINES_ONLY" | wc -l | tr -d ' ')" "$NL" "every injected line is complete"
assert_eq 1 "$([ "$NL" -ge 50 ] && [ "$NL" -lt 100 ] && echo 1 || echo 0)" "truncated but not tiny (got $NL lines)"
jq -e . "$T/out" >/dev/null 2>&1 || { printf '    FAIL: invalid JSON when truncated\n' >&2; TEST_FAILED=1; }
: > "$AO_PAGE"
i=0; while [ "$i" -lt 60 ]; do i=$((i+1)); printf -- '- 行%02d 規則規則規則規則規則規則規則規則規則規則規則規則規則規則規則規則規則規則規則規則規則規則規則規則規則規則\n' "$i" >> "$AO_PAGE"; done
ao_hook "$AO_W"
M="$(ao_msg)"; BLOCK="${M#*"$AO_HEAD"$'\n'}"
case "$BLOCK" in *$'\n(more in [[k:projects/demo/always-on]])') ;; *) printf '    FAIL: CJK page not truncated\n' >&2; TEST_FAILED=1;; esac
LINES_ONLY="${BLOCK%$'\n(more in [[k:projects/demo/always-on]])'}"
assert_eq 1 "$([ "$(printf '%s' "$LINES_ONLY" | LC_ALL=C wc -c | tr -d ' ')" -le 4000 ] && echo 1 || echo 0)" "CJK lines <= 4000 bytes"
printf -- '- %s\n- short\n' "$(printf 'y%.0s' $(seq 1 4100))" > "$AO_PAGE"
ao_hook "$AO_W"
ao_expect "$(ao_blk)" "$AO_HEAD"$'\n(more in [[k:projects/demo/always-on]])' "oversized first line"
printf -- '- a\n- b\n' > "$AO_PAGE"
ao_hook "$AO_W"; lacks "$T/out" '(more in' "short page: no more-line"
end_test

print_summary
