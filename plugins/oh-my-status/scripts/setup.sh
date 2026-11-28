#!/bin/bash
# oh-my-status setup: copies the runtime files to ~/.gemini/oh-my-agy/status/,
# creates status.conf from the template, sweeps stale state.
#
#   setup.sh          run by hand; prints human-readable messages
#   setup.sh --hook   run by the plugin's SessionStart hook (cwd = plugin dir).
#                     Reads and ignores stdin, ALWAYS prints exactly one JSON
#                     object on stdout and exits 0, so it can never fail a
#                     session. A missing-conf-key notice goes into an
#                     injectSteps systemMessage; otherwise the object is {}.
#
# No set -e on purpose: every step is best-effort. No jq needed.

HOOK=0
[ "${1-}" = "--hook" ] && HOOK=1

case ${BASH_SOURCE[0]} in */*|*\\*) SCRIPT_DIR=${BASH_SOURCE[0]%[/\\]*} ;; *) SCRIPT_DIR=. ;; esac
SCRIPT_DIR=$(cd "$SCRIPT_DIR" 2>/dev/null && pwd) || SCRIPT_DIR=.
PLUGIN_DIR="$SCRIPT_DIR/.."
OMA_HOME="${OMA_HOME:-$HOME/.gemini/oh-my-agy}"
OMA_DIR="${OMA_DIR:-$OMA_HOME/status}"
OMA_CONF="${OMA_CONF:-$OMA_HOME/status.conf}"
OMA_CONF_TEMPLATE="${OMA_CONF_TEMPLATE:-$PLUGIN_DIR/oh-my-status.conf}"
OMA_STATE_DIR="${OMA_STATE_DIR:-$OMA_HOME/state}"

say() { [ "$HOOK" = 1 ] || printf '%s\n' "$*"; }

# cp_atomic SRC DST: copy via a temp file in the destination dir, then rename.
cp_atomic() {
  local tmp="$2.tmp.$$"
  cp "$1" "$tmp" 2>/dev/null && mv -f "$tmp" "$2" 2>/dev/null || { rm -f "$tmp" 2>/dev/null; return 1; }
}

# copy_dir SRCDIR DSTDIR: copy every regular file one level deep.
copy_dir() {
  local f
  mkdir -p "$2" 2>/dev/null || return 1
  for f in "$1"/*; do
    [ -f "$f" ] && cp_atomic "$f" "$2/${f##*/}"
  done
  return 0
}

install_runtime() {
  local src_ok=1
  [ -f "$SCRIPT_DIR/statusline.sh" ] || src_ok=0
  [ "$src_ok" = 1 ] || return 1
  # Never copy a directory onto itself (setup.sh run from the installed copy).
  [ "$(cd "$OMA_DIR" 2>/dev/null && pwd)" = "$SCRIPT_DIR" ] && return 0
  mkdir -p "$OMA_DIR/lib" 2>/dev/null || return 1
  local f
  for f in statusline.sh preview.sh set-theme.sh configure.sh; do
    [ -f "$SCRIPT_DIR/$f" ] && cp_atomic "$SCRIPT_DIR/$f" "$OMA_DIR/$f"
  done
  for f in render-common.sh conf-keys.sh; do
    [ -f "$SCRIPT_DIR/lib/$f" ] && cp_atomic "$SCRIPT_DIR/lib/$f" "$OMA_DIR/lib/$f"
  done
  copy_dir "$PLUGIN_DIR/themes" "$OMA_DIR/themes"
  copy_dir "$PLUGIN_DIR/layouts" "$OMA_DIR/layouts"
  # Template next to the scripts so configure.sh can backfill from the install.
  [ -r "$OMA_CONF_TEMPLATE" ] && cp_atomic "$OMA_CONF_TEMPLATE" "$OMA_DIR/oh-my-status.conf"
  return 0
}

sweep_state() {
  [ -d "$OMA_STATE_DIR" ] || return 0
  # 24h age policy. gitcache-* is the git-info cache (an active one is rewritten
  # on every miss). A handoff-<sid> marker is only removed once ctx-<sid> is
  # missing or also older than 24h, i.e. the session is gone; this runs before
  # the ctx-* sweep so the check sees the real mtime.
  find "$OMA_STATE_DIR" -maxdepth 1 -name 'gitcache-*' -type f -mmin +1440 -exec rm -f {} + 2>/dev/null
  find "$OMA_STATE_DIR" -maxdepth 1 -name 'handoff-*' -type f -mmin +1440 2>/dev/null | while IFS= read -r hf; do
    hn="${hf##*/}"
    [ -z "$(find "$OMA_STATE_DIR" -maxdepth 1 -name "ctx-${hn#handoff-}" -type f ! -mmin +1440 2>/dev/null)" ] && rm -f "$hf" 2>/dev/null
  done
  find "$OMA_STATE_DIR" -maxdepth 1 -name 'ctx-*' -type f -mmin +1440 -exec rm -f {} + 2>/dev/null
  return 0
}

# Sets MISSING_CSV / MISSING_N (read-only; never writes the conf).
detect_missing() {
  MISSING_CSV=""; MISSING_N=0
  local lib="$SCRIPT_DIR/lib/conf-keys.sh" missing
  [ -r "$lib" ] || return 0
  . "$lib" || return 0
  [ -s "$OMA_CONF" ] && [ -r "$OMA_CONF_TEMPLATE" ] || return 0
  missing=$(oma_missing_conf_keys "$OMA_CONF_TEMPLATE" "$OMA_CONF" 2>/dev/null | tr -d '\r')
  [ -n "$missing" ] || return 0
  MISSING_N=$(printf '%s\n' "$missing" | wc -l | tr -d ' ')
  MISSING_CSV=$(printf '%s\n' "$missing" | paste -sd, -)
}

main() {
  install_runtime || say "oh-my-status: could not install runtime files into $OMA_DIR"
  if [ ! -s "$OMA_CONF" ] && [ -r "$OMA_CONF_TEMPLATE" ]; then
    mkdir -p "$(dirname "$OMA_CONF")" 2>/dev/null
    cp_atomic "$OMA_CONF_TEMPLATE" "$OMA_CONF" && say "Created $OMA_CONF"
  fi
  sweep_state
  detect_missing
  if [ -n "$MISSING_CSV" ]; then
    NOTICE="[oh-my-status] Context for the assistant: ${MISSING_N} new config option(s) (${MISSING_CSV}) exist in the bundled template but are not in the user's ${OMA_CONF}. At a natural moment, mention to the user once (not repeatedly within this session) that running /status-setup will add the new options with safe defaults while preserving existing values."
    say "$NOTICE"
  else
    NOTICE=""
  fi
  say "oh-my-status installed in $OMA_DIR"
}

# Hook mode: stdout is reserved for the single JSON object.
if [ "$HOOK" = 1 ]; then
  NOTICE=""
  IFS= read -r -t 2 -d "" _ || :   # read (and ignore) the hook payload, bounded
  main >/dev/null 2>&1 </dev/null
  if [ -n "$NOTICE" ]; then
    # Escape for JSON: backslash, quote; control chars are not present.
    esc=${NOTICE//\\/\\\\}; esc=${esc//\"/\\\"}
    printf '{"injectSteps":[{"systemMessage":{"systemMessage":"%s"}}]}\n' "$esc"
  else
    printf '{}\n'
  fi
  exit 0
fi
main
exit 0
