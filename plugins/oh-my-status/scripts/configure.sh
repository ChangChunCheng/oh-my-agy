#!/bin/bash
# oh-my-status: deterministic helper behind the /status-setup skill.
# Subcommands: status | install | missing-keys | backfill
case ${BASH_SOURCE[0]} in */*) SCRIPT_DIR=${BASH_SOURCE[0]%/*} ;; *) SCRIPT_DIR=. ;; esac
OMA_HOME="${OMA_HOME:-$HOME/.gemini/oh-my-agy}"
OMA_CONF="${OMA_CONF:-$OMA_HOME/status.conf}"
OMA_AGY_SETTINGS="${OMA_AGY_SETTINGS:-$HOME/.gemini/antigravity-cli/settings.json}"
OMA_STATUS_CMD='bash ~/.gemini/oh-my-agy/status/statusline.sh'
# Template: the plugin root in a repo checkout, else the installed copy.
if [ -z "${OMA_CONF_TEMPLATE:-}" ]; then
  for OMA_CONF_TEMPLATE in "$SCRIPT_DIR/../oh-my-status.conf" "$SCRIPT_DIR/oh-my-status.conf"; do
    [ -r "$OMA_CONF_TEMPLATE" ] && break
  done
fi
[ -r "$SCRIPT_DIR/lib/conf-keys.sh" ] && . "$SCRIPT_DIR/lib/conf-keys.sh"

need_jq() { command -v jq >/dev/null 2>&1 || { echo "configure.sh: jq is required" >&2; exit 2; }; }

# Prints "none|ours|other" then the current statusLine JSON (null when absent).
cmd_status() {
  need_jq
  local kind=none sl=null
  if [ -s "$OMA_AGY_SETTINGS" ]; then
    sl=$(jq -c '.statusLine // null' "$OMA_AGY_SETTINGS" 2>/dev/null) \
      || { echo "configure.sh: cannot parse $OMA_AGY_SETTINGS" >&2; exit 3; }
    if [ "$sl" != null ]; then
      if jq -e '(.statusLine | type == "object") and ((.statusLine.command | type) == "string")
                and (.statusLine.command | contains("oh-my-agy/status/statusline.sh"))' \
           "$OMA_AGY_SETTINGS" >/dev/null 2>&1; then kind=ours; else kind=other; fi
    fi
  fi
  printf '%s\n%s\n' "$kind" "$sl"
}

cmd_install() {
  need_jq
  local dir tmp
  dir=$(dirname "$OMA_AGY_SETTINGS"); mkdir -p "$dir" || exit 1
  tmp=$(mktemp "$dir/.settings.XXXXXX") || exit 1
  if [ -s "$OMA_AGY_SETTINGS" ]; then
    jq --arg c "$OMA_STATUS_CMD" '. + {statusLine: {type: "command", command: $c}}' "$OMA_AGY_SETTINGS" > "$tmp" \
      || { rm -f "$tmp"; echo "configure.sh: cannot parse $OMA_AGY_SETTINGS (left untouched)" >&2; exit 3; }
    cp "$OMA_AGY_SETTINGS" "$OMA_AGY_SETTINGS.bak" || { rm -f "$tmp"; exit 1; }
  else
    jq -n --arg c "$OMA_STATUS_CMD" '{statusLine: {type: "command", command: $c}}' > "$tmp" \
      || { rm -f "$tmp"; exit 1; }
  fi
  cat "$tmp" > "$OMA_AGY_SETTINGS"; rm -f "$tmp"
  echo "statusLine installed in $OMA_AGY_SETTINGS"
}

cmd_missing() {
  [ -s "$OMA_CONF" ] || return 0
  oma_missing_conf_keys "$OMA_CONF_TEMPLATE" "$OMA_CONF"
}

cmd_backfill() {
  [ -s "$OMA_CONF" ] || { echo "No conf to backfill (run setup.sh first)."; return 0; }
  local missing key line lines=""
  missing=$(oma_missing_conf_keys "$OMA_CONF_TEMPLATE" "$OMA_CONF") || exit 1
  [ -n "$missing" ] || { echo "Conf is already up to date."; return 0; }
  while IFS= read -r key; do
    [ -n "$key" ] || continue
    line=$(grep -E -m 1 -- "^[[:space:]]*${key}[[:space:]]*=" "$OMA_CONF_TEMPLATE")
    lines+="$line"$'\n'
  done <<MISSING
$missing
MISSING
  [ -n "$(tail -c 1 "$OMA_CONF")" ] && printf '\n' >> "$OMA_CONF"
  { printf '# --- added by /status-setup (%s) ---\n' "$(date +%F)"; printf '%s' "$lines"; } >> "$OMA_CONF"
  printf 'Added: %s\n' "$(printf '%s' "$missing" | paste -sd, -)"
}

case "${1-}" in
  status) cmd_status ;;
  install) cmd_install ;;
  missing-keys) cmd_missing ;;
  backfill) cmd_backfill ;;
  *) echo "usage: configure.sh status|install|missing-keys|backfill" >&2; exit 64 ;;
esac
