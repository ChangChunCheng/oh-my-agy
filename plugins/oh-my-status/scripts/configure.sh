#!/bin/bash
# oh-my-status: deterministic helper behind the /status-setup skill.
# Subcommands: status | install | missing-keys | backfill
case ${BASH_SOURCE[0]} in */*|*\\*) SCRIPT_DIR=${BASH_SOURCE[0]%[/\\]*} ;; *) SCRIPT_DIR=. ;; esac
OMA_HOME="${OMA_HOME:-$HOME/.gemini/oh-my-agy}"
OMA_CONF="${OMA_CONF:-$OMA_HOME/status.conf}"
OMA_AGY_SETTINGS="${OMA_AGY_SETTINGS:-$HOME/.gemini/antigravity-cli/settings.json}"
OMA_STATUS_CMD="${OMA_STATUS_CMD:-}"
# Template: the plugin root in a repo checkout, else the installed copy.
if [ -z "${OMA_CONF_TEMPLATE:-}" ]; then
  for OMA_CONF_TEMPLATE in "$SCRIPT_DIR/../oh-my-status.conf" "$SCRIPT_DIR/oh-my-status.conf"; do
    [ -r "$OMA_CONF_TEMPLATE" ] && break
  done
fi
[ -r "$SCRIPT_DIR/lib/conf-keys.sh" ] && . "$SCRIPT_DIR/lib/conf-keys.sh"

# Pure-bash fallback: /<letter>/rest -> <UPPER>:/rest when cygpath is absent.
_oma_to_win_m() {
  local p="$1"
  if command -v cygpath >/dev/null 2>&1; then
    local out
    out=$(cygpath -m "$p" 2>/dev/null)
    if [ -n "$out" ]; then printf '%s' "$out"; return 0; fi
  fi
  if [[ "$p" =~ ^/([A-Za-z])(/.*)?$ ]]; then
    local drv="${BASH_REMATCH[1]}" rest="${BASH_REMATCH[2]:-}"
    drv=$(printf '%s' "$drv" | tr '[:lower:]' '[:upper:]')
    printf '%s:%s' "$drv" "${rest:-/}"
  else
    printf '%s' "$p"
  fi
}

# Resolve the Git Bash wrapper on Windows, preferring <Git>/bin/bash.exe over
# <Git>/usr/bin/bash.exe (the wrapper adds /usr/bin to PATH for cmd.exe callers).
_oma_win_bash_path() {
  local raw="${OMA_BASH_BIN:-$(command -v bash 2>/dev/null || printf '/usr/bin/bash')}"
  local win_m
  win_m=$(_oma_to_win_m "$raw")
  if [ -z "${OMA_BASH_BIN:-}" ]; then
    local root=""
    case "$win_m" in
      */usr/bin/bash|*/usr/bin/bash.exe|*/usr/bin/bash.EXE)
        root="${win_m%/usr/bin/*}" ;;
    esac
    if [ -n "$root" ] && [ -f "${root}/bin/bash.exe" ]; then
      win_m="${root}/bin/bash.exe"
    fi
  fi
  if command -v cygpath >/dev/null 2>&1; then
    local short_p
    short_p=$(cygpath -d "$win_m" 2>/dev/null)
    if [ -n "$short_p" ]; then printf '%s' "$short_p"; return 0; fi
    short_p=$(cygpath -w "$win_m" 2>/dev/null)
    if [ -n "$short_p" ]; then printf '%s' "$short_p"; return 0; fi
  fi
  case "$win_m" in
    [A-Za-z]:/*) printf '%s' "${win_m//\//\\}" ;;
    *) printf '%s' "$win_m" ;;
  esac
}

# Resolve $OMA_HOME/status/statusline.sh as a Windows forward-slash path.
# Never shortens the trailing "<oma_home_name>/status/statusline.sh" segment.
_oma_win_script_path() {
  local shorten_parent="${1:-0}"
  local base="${OMA_HOME##*/}"
  if [ "$shorten_parent" = 1 ] && command -v cygpath >/dev/null 2>&1; then
    local parent short_parent
    parent=$(dirname "$OMA_HOME")
    short_parent=$(cygpath -d "$parent" 2>/dev/null)
    if [ -n "$short_parent" ]; then
      printf '%s/%s/status/statusline.sh' "${short_parent//\\//}" "$base"
      return 0
    fi
  fi
  _oma_to_win_m "$OMA_HOME/status/statusline.sh"
}

_oma_default_status_cmd() {
  case "${OMA_OSTYPE:-${OSTYPE:-}}" in
    msys*|cygwin*|mingw*|win*)
      local b s
      b=$(_oma_win_bash_path)
      s=$(_oma_win_script_path 0)
      case "$b" in
        *[[:space:]]*)
          case "$s" in
            *[[:space:]]*) s=$(_oma_win_script_path 1) ;;
          esac ;;
      esac
      case "$b" in
        *[[:space:]]*)
          case "$s" in
            *[[:space:]]*) printf 'call "%s" "%s"' "$b" "$s" ;;
            *) printf '"%s" %s' "$b" "$s" ;;
          esac ;;
        *)
          case "$s" in
            *[[:space:]]*) printf '%s "%s"' "$b" "$s" ;;
            *) printf '%s %s' "$b" "$s" ;;
          esac ;;
      esac ;;
    *)
      printf 'bash ~/.gemini/oh-my-agy/status/statusline.sh' ;;
  esac
}

_oma_jq_install_hint() {
  case "${1:-${OMA_OSTYPE:-${OSTYPE:-}}}" in
    msys*|cygwin*|mingw*|win*) printf 'winget install jqlang.jq' ;;
    darwin*) printf 'brew install jq' ;;
    *)
      if command -v apt-get >/dev/null 2>&1; then printf 'sudo apt install jq'
      elif command -v dnf >/dev/null 2>&1; then printf 'sudo dnf install jq'
      elif command -v pacman >/dev/null 2>&1; then printf 'sudo pacman -S jq'
      elif command -v zypper >/dev/null 2>&1; then printf 'sudo zypper install jq'
      elif command -v apk >/dev/null 2>&1; then printf 'sudo apk add jq'
      elif command -v brew >/dev/null 2>&1; then printf 'brew install jq'
      else printf 'see https://jqlang.org/download'
      fi ;;
  esac
}

need_jq() {
  if ! command -v jq >/dev/null 2>&1; then
    echo "configure.sh: jq 1.7+ is required. Install it with: $(_oma_jq_install_hint)" >&2
    exit 2
  fi
  if ! printf '{}' | jq --raw-output0 '.' >/dev/null 2>&1; then
    echo "configure.sh: jq 1.7+ is required (your jq does not support --raw-output0). Upgrade it with: $(_oma_jq_install_hint)" >&2
    exit 2
  fi
}

# Prints "none|ours|other" then the current statusLine JSON (null when absent).
cmd_status() {
  need_jq
  local kind=none sl=null
  if [ -s "$OMA_AGY_SETTINGS" ]; then
    sl=$(jq -c '.statusLine // null' "$OMA_AGY_SETTINGS" 2>/dev/null) \
      || { echo "configure.sh: cannot parse $OMA_AGY_SETTINGS" >&2; exit 3; }
    if [ "$sl" != null ]; then
      local cur_script="" short_script=""
      cur_script=$(_oma_win_script_path 0)
      short_script=$(_oma_win_script_path 1)
      if jq -e --arg s1 "$cur_script" --arg s2 "$short_script" \
           '(.statusLine | type == "object") and ((.statusLine.command | type) == "string")
            and ((.statusLine.command | contains("oh-my-agy/status/statusline.sh"))
                 or ($s1 != "" and (.statusLine.command | contains($s1)))
                 or ($s2 != "" and (.statusLine.command | contains($s2))))' \
           "$OMA_AGY_SETTINGS" >/dev/null 2>&1; then kind=ours; else kind=other; fi
    fi
  fi
  printf '%s\n%s\n' "$kind" "$sl"
}

cmd_install() {
  need_jq
  local dir tmp cmd
  cmd="${OMA_STATUS_CMD:-$(_oma_default_status_cmd)}"
  dir=$(dirname "$OMA_AGY_SETTINGS"); mkdir -p "$dir" || exit 1
  tmp=$(mktemp "$dir/.settings.XXXXXX") || exit 1
  if [ -s "$OMA_AGY_SETTINGS" ]; then
    jq --arg c "$cmd" '. + {statusLine: {type: "command", command: $c}}' "$OMA_AGY_SETTINGS" > "$tmp" \
      || { rm -f "$tmp"; echo "configure.sh: cannot parse $OMA_AGY_SETTINGS (left untouched)" >&2; exit 3; }
    cp "$OMA_AGY_SETTINGS" "$OMA_AGY_SETTINGS.bak" || { rm -f "$tmp"; exit 1; }
  else
    jq -n --arg c "$cmd" '{statusLine: {type: "command", command: $c}}' > "$tmp" \
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

if [ -z "${OMA_TEST_LIB_ONLY:-}" ]; then
  case "${1-}" in
    status) cmd_status ;;
    install) cmd_install ;;
    missing-keys) cmd_missing ;;
    backfill) cmd_backfill ;;
    *) echo "usage: configure.sh status|install|missing-keys|backfill" >&2; exit 64 ;;
  esac
fi
