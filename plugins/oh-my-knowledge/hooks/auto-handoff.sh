#!/bin/bash
# Stop hook: when the context usage written by oh-my-status (ctx-<conversation>)
# reaches the threshold, write the usage into handoff-<conversation> and keep the
# agent going once ({"decision":"continue"}) so it runs the kb-handoff skill. The
# marker holds the highest usage % at which a handoff was requested or completed
# in this conversation; it fires again once usage grows by auto_handoff_repeat
# points past a marker that is at/above the threshold (or by 5 points past a
# lower one, e.g. an early manual handoff). A stop that is itself the result of a
# hook continuation (continuationActive) is never continued again.
# Output: {"decision":"continue","reason":"..."} or {}. Never breaks the session:
# any problem -> {} and exit 0. bash 3.2 compatible.
quiet() { printf '{}\n'; exit 0; }
case "${BASH_SOURCE[0]}" in */*) HOOK_DIR="${BASH_SOURCE[0]%/*}" ;; *) HOOK_DIR=. ;; esac
# shellcheck source=../scripts/lib/common.sh
. "$HOOK_DIR/../scripts/lib/common.sh" 2>/dev/null || quiet
omk_config 2>/dev/null || quiet
omk_resolve_jq 2>/dev/null || quiet
[ -z "${OMK_CONFIG_ERROR:-}" ] || quiet
[ "$OMK_AUTO_HANDOFF" = true ] || quiet
# Not set up yet (no SCHEMA.md in the knowledge base): stay silent.
[ -f "$OMK_KNOWLEDGE_DIR/SCHEMA.md" ] || quiet

# One jq call; split on the tab with parameter expansion (read would collapse an
# empty first field) and strip the CR a Windows jq adds.
l="$("$OMK_JQ" -r '[(.continuationActive // false | tostring), (.conversationId // "")] | @tsv' 2>/dev/null)" || quiet
active="${l%%$'\t'*}"
sid="${l#*$'\t'}"
sid="${sid%$'\r'}"; active="${active%$'\r'}"
[ "$active" = false ] || quiet
[ -n "$sid" ] || quiet
san="${sid//[^A-Za-z0-9_-]/_}"

ctx_file="$OMA_STATE_DIR/ctx-$san"
marker="$OMA_STATE_DIR/handoff-$san"
[ -f "$ctx_file" ] || quiet

# Valid = first line (CR stripped), 1-3 digits, value <= 100.
line=""
IFS= read -r line 2>/dev/null < "$ctx_file"
line="${line%$'\r'}"
pct="${line%% *}"
case "$pct" in ''|*[!0-9]*|????*) quiet ;; esac
pct=$((10#$pct))
[ "$pct" -le 100 ] || quiet

r=0
m=""
IFS= read -r m 2>/dev/null < "$marker"
m="${m%$'\r'}"
case "$m" in ''|*[!0-9]*|????*) ;; *) r=$((10#$m)); [ "$r" -le 100 ] || r=0 ;; esac

thr="$OMK_AUTO_HANDOFF_THRESHOLD"
[ "$thr" -lt 30 ] && thr=30
[ "$thr" -gt 90 ] && thr=90
rep="$OMK_AUTO_HANDOFF_REPEAT"
[ "$rep" -lt 10 ] && rep=10
[ "$rep" -gt 60 ] && rep=60
[ "$pct" -ge "$thr" ] || quiet
if [ "$r" -lt "$thr" ]; then
  [ $((pct - r)) -ge 5 ] || quiet
else
  [ $((pct - r)) -ge "$rep" ] || quiet
fi

# Marker first, then continue: if the marker cannot be written, stay silent so we
# never continue without a marker.
mkdir -p "$OMA_STATE_DIR" 2>/dev/null
printf '%s\n' "$pct" 2>/dev/null > "$marker" || quiet
"$OMK_JQ" -cn --arg r "Context is at ${pct}%. Run the kb-handoff skill now (conversation id: ${sid}), then tell the user they can /clear or /compact." \
  '{decision:"continue",reason:$r}' 2>/dev/null || quiet
exit 0
