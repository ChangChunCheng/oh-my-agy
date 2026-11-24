#!/bin/bash
# Cross-plugin contract: oh-my-status (agy port) writes ctx-<conversation> in the
# shared state dir; oh-my-knowledge hooks read ctx-<conversation> and own
# handoff-<conversation>. The two plugins share only these files, so this test
# drives the real scripts.
#
#   ctx-<san>      "<used_pct_int> <context_window_size>\n"   (written by the statusline)
#   handoff-<san>  "<highest pct at which a handoff was requested>\n" (written by the Stop hook / kb-handoff)
#   <san> = conversationId with every character outside [A-Za-z0-9_-] replaced by _
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
# shellcheck source=test-helpers.sh
. "$SCRIPT_DIR/test-helpers.sh"

STATUSLINE="$REPO_ROOT/plugins/oh-my-status/scripts/statusline.sh"
PLUGIN="$REPO_ROOT/plugins/oh-my-knowledge"
HOOKS="$PLUGIN/hooks"

for v in $(compgen -e | grep -E '^(OMK_|OMA_)'); do unset "$v"; done
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
export HOME="$T/home"; mkdir -p "$HOME"
export OMA_HOME="$T/oma"; mkdir -p "$OMA_HOME"
export OMA_STATE_DIR="$T/state"          # the one directory both plugins resolve (default $OMA_HOME/state)
export OMA_CONF=/dev/null                # statusline: no real status.conf
export OMK_CONF=/dev/null                # knowledge: no real knowledge.conf
export OMK_KNOWLEDGE_DIR="$T/kb"
mkdir -p "$T/kb"; : > "$T/kb/SCHEMA.md"  # a set-up knowledge base (hooks are silent before setup)

SID='conv/contract 1'   # special chars: exercises the shared sanitisation
SAN='conv_contract_1'
strip() { sed -E 's/\x1b\[[0-9;]*[a-zA-Z]//g'; }
PCT=75
render() { # [sid]
  jq -n --arg s "${1:-$SID}" --argjson p "$PCT" '{conversation_id:$s,model:{display_name:"X"},workspace:{current_dir:"/tmp"},context_window:{used_percentage:$p,context_window_size:200000}}' \
    | COLUMNS=120 bash "$STATUSLINE" 2>/dev/null | strip
}
stop() { # [sid] [continuationActive]
  jq -n --arg s "${1:-$SID}" --argjson a "${2:-false}" '{conversationId:$s,executionNum:1,terminationReason:"model_stop",fullyIdle:true,continuationActive:$a}' \
    | OMK_AUTO_HANDOFF_THRESHOLD=70 bash "$HOOKS/auto-handoff.sh" 2>/dev/null
}
session_start() {
  jq -n --arg s "${1:-$SID}" '{conversationId:$s,workspacePaths:["/tmp"]}' | bash "$HOOKS/session-start.sh" 2>/dev/null
}

start_test "contract: statusline output file name and format"
render >/dev/null
assert_eq "75 200000" "$(cat "$OMA_STATE_DIR/ctx-$SAN" 2>/dev/null)" "render wrote ctx-<sanitized conversationId>"
case "$(cat "$OMA_STATE_DIR/ctx-$SAN")" in *$'\r'*) printf '    FAIL: CR in ctx file\n' >&2; TEST_FAILED=1;; esac
assert_eq "1" "$(ls "$OMA_STATE_DIR" | grep -c '^ctx-')" "exactly one ctx file"
PCT=0; render x >/dev/null; assert_eq "0 200000" "$(cat "$OMA_STATE_DIR/ctx-x")" "0% still written"
PCT=75
end_test

start_test "render -> Stop continues -> marker holds the pct -> statusline unaffected -> next Stop silent"
rm -f "$OMA_STATE_DIR"/*
render >/dev/null
R1="$(stop)"
case "$R1" in *'"decision":"continue"'*'Context is at 75%'*) ;; *) printf '    FAIL: first Stop did not continue: %q\n' "$R1" >&2; TEST_FAILED=1;; esac
jq -e '.decision == "continue"' <<<"$R1" >/dev/null 2>&1 || { printf '    FAIL: not valid agy Stop JSON: %q\n' "$R1" >&2; TEST_FAILED=1; }
case "$R1" in *"conversation id: $SID"*) ;; *) printf '    FAIL: reason lacks the raw conversation id\n' >&2; TEST_FAILED=1;; esac
assert_eq "75" "$(cat "$OMA_STATE_DIR/handoff-$SAN" 2>/dev/null)" "marker handoff-<sanitized> = pct"
render | grep -qiE 'handoff' && { printf '    FAIL: statusline shows a handoff badge\n' >&2; TEST_FAILED=1; }
assert_eq "75 200000" "$(cat "$OMA_STATE_DIR/ctx-$SAN" 2>/dev/null)" "render still writes ctx with marker present"
assert_eq "{}" "$(stop)" "second Stop is silent while the marker exists"
assert_eq "{}" "$(stop "$SID" true)" "a continuation's own Stop never continues"
end_test

start_test "another conversation is independent; usage growth by the repeat re-triggers"
rm -f "$OMA_STATE_DIR"/*
render >/dev/null; stop >/dev/null
PCT=75; render 'other conv' >/dev/null
case "$(stop 'other conv')" in *'"decision":"continue"'*) ;; *) printf '    FAIL: other conversation did not trigger\n' >&2; TEST_FAILED=1;; esac
[ -f "$OMA_STATE_DIR/handoff-other_conv" ] || { printf '    FAIL: other marker missing\n' >&2; TEST_FAILED=1; }
PCT=94; render >/dev/null; assert_eq "{}" "$(stop)" "19 points past the marker: silent"
PCT=95; render >/dev/null
case "$(stop)" in *'"decision":"continue"'*'Context is at 95%'*) ;; *) printf '    FAIL: no re-trigger after repeat (20)\n' >&2; TEST_FAILED=1;; esac
assert_eq "95" "$(cat "$OMA_STATE_DIR/handoff-$SAN")" "marker advanced"
PCT=75
end_test

start_test "SessionStart does not delete ctx/handoff (agy new conversation = new id); it hands over the conversation id"
rm -f "$OMA_STATE_DIR"/*
render >/dev/null; stop >/dev/null
msg="$(session_start | jq -r '.injectSteps[0].systemMessage.systemMessage')"
case "$msg" in *"Conversation id: $SID."*) ;; *) printf '    FAIL: conversation id not announced: %q\n' "$msg" >&2; TEST_FAILED=1;; esac
[ -f "$OMA_STATE_DIR/ctx-$SAN" ] && [ -f "$OMA_STATE_DIR/handoff-$SAN" ] || { printf '    FAIL: SessionStart removed state\n' >&2; TEST_FAILED=1; }
end_test

start_test "kb-handoff step 4 snippet reads the real ctx file and writes a marker the Stop hook respects"
rm -f "$OMA_STATE_DIR"/*
snip="$(awk '/^## 4\./{s=1; next} s && /^```bash/{p=1; next} p && /^```/{exit} p{print}' "$PLUGIN/skills/kb-handoff/SKILL.md")"
[ -n "$snip" ] || { printf '    FAIL: snippet not found\n' >&2; TEST_FAILED=1; }
PCT=82; render >/dev/null
out="$(bash -c "${snip//<conversation id>/$SID}" 2>&1)"
assert_eq "marker written: 82" "$out" "snippet output"
assert_eq "82" "$(cat "$OMA_STATE_DIR/handoff-$SAN")" "marker written under the sanitized name"
assert_eq "{}" "$(stop)" "Stop silent after a manual handoff at the same usage"
PCT=75
end_test

start_test "state dir default is shared: both plugins resolve \$OMA_HOME/state"
D="$(env -u OMA_STATE_DIR OMA_HOME="$T/h2" bash -c '. "$1"; omk_config; echo "$OMA_STATE_DIR"' _ "$PLUGIN/scripts/lib/common.sh")"
assert_eq "$T/h2/state" "$D" "knowledge default state dir"
rm -rf "$T/h2"; mkdir -p "$T/h2"
env -u OMA_STATE_DIR OMA_HOME="$T/h2" bash -c 'jq -n "{conversation_id:\"s1\",model:{display_name:\"X\"},workspace:{current_dir:\"/tmp\"},context_window:{used_percentage:55,context_window_size:1000000}}" | COLUMNS=120 bash "$1" >/dev/null 2>&1' _ "$STATUSLINE"
assert_eq "55 1000000" "$(cat "$T/h2/state/ctx-s1" 2>/dev/null)" "statusline default state dir is the same one"
end_test

start_test "hooks stay silent without oh-my-status (no ctx file) and always emit valid JSON"
rm -f "$OMA_STATE_DIR"/*
assert_eq "{}" "$(stop)" "no ctx -> {}"
jq -e . <<<"$(stop)" >/dev/null 2>&1 || { printf '    FAIL: not JSON\n' >&2; TEST_FAILED=1; }
end_test

print_summary
