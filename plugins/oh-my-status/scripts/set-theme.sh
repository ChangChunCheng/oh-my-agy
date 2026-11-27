#!/bin/bash
# oh-my-status: switch theme and/or layout.
# Usage: set-theme.sh <theme|layout> [layout]   |   set-theme.sh list
# Only the THEME= / LAYOUT= lines of status.conf are touched (appended when
# absent). A single argument that is both a theme and a layout name (mygo)
# sets both.
case ${BASH_SOURCE[0]} in */*|*\\*) SCRIPT_DIR=${BASH_SOURCE[0]%[/\\]*} ;; *) SCRIPT_DIR=. ;; esac
if [ -z "${OMA_DIR:-}" ]; then
  if [ -d "$SCRIPT_DIR/themes" ]; then OMA_DIR=$SCRIPT_DIR; else OMA_DIR=$SCRIPT_DIR/..; fi
fi
OMA_HOME="${OMA_HOME:-$HOME/.gemini/oh-my-agy}"
OMA_CONF="${OMA_CONF:-$OMA_HOME/status.conf}"

names() {  # $1 = themes|layouts -> one name per line
  local f
  for f in "$OMA_DIR/$1"/*.sh; do
    [ -f "$f" ] || continue
    f=${f##*/}; printf '%s\n' "${f%.sh}"
  done
}
has_name() { names "$1" | grep -qx -- "$2"; }
current() {  # $1 = THEME|LAYOUT
  local v=""
  [ -f "$OMA_CONF" ] && v=$(sed -n "s/^$1=[\"']\{0,1\}\([A-Za-z0-9_-]*\).*/\1/p" "$OMA_CONF" | tail -n 1)
  printf '%s' "$v"
}
show_list() {
  printf 'Current: theme=%s layout=%s\n' "$(current THEME)" "$(current LAYOUT)"
  printf 'Themes:  %s\n' "$(names themes | paste -sd' ' -)"
  printf 'Layouts: %s\n' "$(names layouts | paste -sd' ' -)"
}
# set_key KEY VALUE: replace the KEY= line, or append it.
set_key() {
  local key="$1" val="$2" tmp
  mkdir -p "$(dirname "$OMA_CONF")" 2>/dev/null
  [ -e "$OMA_CONF" ] || : > "$OMA_CONF"
  if grep -q "^$key=" "$OMA_CONF"; then
    tmp=$(mktemp "${TMPDIR:-/tmp}/oma-conf.XXXXXX") || return 1
    sed "s|^$key=.*|$key=\"$val\"|" "$OMA_CONF" > "$tmp" && cat "$tmp" > "$OMA_CONF"
    rm -f "$tmp"
  else
    [ -s "$OMA_CONF" ] && [ -n "$(tail -c 1 "$OMA_CONF")" ] && printf '\n' >> "$OMA_CONF"
    printf '%s="%s"\n' "$key" "$val" >> "$OMA_CONF"
  fi
}

case "${1-}" in
  ''|list) show_list; exit 0 ;;
esac

new_theme="" new_layout=""
if [ $# -ge 2 ]; then
  new_theme=$1 new_layout=$2
  has_name themes "$new_theme"  || { echo "Unknown theme: $new_theme" >&2; show_list >&2; exit 1; }
  has_name layouts "$new_layout" || { echo "Unknown layout: $new_layout" >&2; show_list >&2; exit 1; }
else
  if has_name themes "$1";  then new_theme=$1; fi
  if has_name layouts "$1"; then new_layout=$1; fi
  [ -n "$new_theme$new_layout" ] || { echo "Unknown theme or layout: $1" >&2; show_list >&2; exit 1; }
fi

[ -n "$new_theme" ]  && set_key THEME "$new_theme"
[ -n "$new_layout" ] && set_key LAYOUT "$new_layout"
printf 'Set theme=%s layout=%s\n' "$(current THEME)" "$(current LAYOUT)"
printf 'Applies on the next statusline refresh.\n'
