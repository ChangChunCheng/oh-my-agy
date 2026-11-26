#!/bin/bash
# PreInvocation hook (agy's closest event to Claude's UserPromptSubmit): remind the
# agent to consult the knowledge base before answering a problem/diagnostic-style
# question. Only the first model invocation of a turn (invocationNum == 0) is
# considered, and the same prompt is reminded at most once per conversation.
# Output: {"injectSteps":[{"systemMessage":{"systemMessage":"..."}}]} or {}.
# Never breaks the session: any problem -> {} and exit 0. bash 3.2 compatible.
quiet() { printf '{}\n'; exit 0; }
case "${BASH_SOURCE[0]}" in */*) HOOK_DIR="${BASH_SOURCE[0]%/*}" ;; *) HOOK_DIR=. ;; esac
# shellcheck source=../scripts/lib/common.sh
. "$HOOK_DIR/../scripts/lib/common.sh" 2>/dev/null || quiet
omk_config 2>/dev/null || quiet
omk_resolve_jq 2>/dev/null || quiet
[ -z "${OMK_CONFIG_ERROR:-}" ] || quiet
[ "$OMK_LOOKUP_REMINDER" = true ] || quiet
# Not set up yet (no SCHEMA.md in the knowledge base): stay silent.
[ -f "$OMK_KNOWLEDGE_DIR/SCHEMA.md" ] || quiet

# One jq call: line 1 = invocationNum and conversationId joined by \001, the rest
# is the prompt (lastUserInput), passed through verbatim.
inp="$("$OMK_JQ" -r '([(.invocationNum // -1 | tostring), (.conversationId // "")] | join("\u0001")), (.lastUserInput // "")' 2>/dev/null)" || quiet
head1="${inp%%$'\n'*}"
case "$inp" in *$'\n'*) prompt="${inp#*$'\n'}" ;; *) prompt="" ;; esac
num="${head1%%$'\001'*}"; cid="${head1#*$'\001'}"
[ "${num%$'\r'}" = 0 ] || quiet
[ -n "$prompt" ] || quiet

# Slash commands are not questions.
trimmed="${prompt#"${prompt%%[![:space:]]*}"}"
case "$trimmed" in /*) quiet ;; esac
# Harness relays (subagent hand-backs, notifications) are not user questions.
# Starts-with only: a prompt merely quoting them is still checked.
case "$trimmed" in
  "<agent-message "*|"<task-notification>"*|"[SYSTEM NOTIFICATION"*) quiet ;;
esac

zh='為什麼|為何|怎麼|怎樣|如何|怎辦|是不是|會不會|要不要|慢|錯|壞|失敗|卡住|卡在|不行|不能|沒反應|跑不|掛了|爆了|異常|問題|影響'
en='why|how come|error|errors|fail(s|ed|ing|ure)?|slow|broken|crash(es|ed)?|hang(s|ing)?|stuck|timeout|timed out|flaky|not working'
hit=0
if [[ "$prompt" =~ $zh ]]; then
  hit=1
else
  en_re="(^|[^a-z])($en)([^a-z]|\$)"
  shopt -s nocasematch
  [[ "$prompt" =~ $en_re ]] && hit=1
  shopt -u nocasematch
fi
[ "$hit" = 1 ] || quiet

# Dedupe: remember (cksum, length) of the last prompt reminded in this conversation.
if [ -n "$cid" ]; then
  san="${cid//[^A-Za-z0-9_-]/_}"
  stamp="$OMA_STATE_DIR/kbremind-$san"
  sum="$(printf '%s' "$prompt" | cksum)"
  prev=""
  IFS= read -r prev 2>/dev/null < "$stamp"
  [ "$prev" != "$sum" ] || quiet
  if mkdir -p "$OMA_STATE_DIR" 2>/dev/null && printf '%s\n' "$sum" > "$stamp" 2>/dev/null; then
    # kbremind-* files belong to this plugin: drop the ones a week old.
    find "$OMA_STATE_DIR" -maxdepth 1 -name 'kbremind-*' -type f -mtime +7 -exec rm -f {} + 2>/dev/null
  fi
fi

ctx='[oh-my-knowledge hook] This message looks like a problem/diagnostic question (這則訊息像問題／診斷型提問). Before replying, run the kb-lookup skill first with 3-6 keywords (error fragments, tool names, symptoms, zh/en synonyms), read the 1-2 best-matching topic files in full, then answer and say in one sentence what the lookup found (or that the knowledge base has nothing). If the message is merely a command or a confirmation, skip it.'
"$OMK_JQ" -cn --arg c "$ctx" '{injectSteps:[{systemMessage:{systemMessage:$c}}]}' 2>/dev/null || quiet
exit 0
