#!/bin/bash
# check-deps.sh   (oh-my-knowledge prerequisite check)
# Checks required system tools (git, jq, gawk, GNU find).
# On macOS, automatically detects Homebrew gawk / gfind / findutils even when
# gnubin is not on PATH. When anything is missing, prints the exact install
# command for the current platform and exits 2.
# Exit: 0 all tools ready | 2 one or more tools missing.
set -u
case "${BASH_SOURCE[0]}" in */*) HERE="${BASH_SOURCE[0]%/*}" ;; *) HERE=. ;; esac
HERE="$(cd "$HERE" && pwd)"
# shellcheck source=lib/common.sh
. "$HERE/lib/common.sh"

missing_names=()
missing_pkgs=()
found=()

if command -v git >/dev/null 2>&1; then
  found+=("git")
else
  missing_names+=("git")
  missing_pkgs+=("git")
fi

if omk_resolve_jq; then
  found+=("jq ($OMK_JQ)")
else
  missing_names+=("jq")
  missing_pkgs+=("jq")
fi

if omk_resolve_gawk; then
  found+=("gawk ($OMK_GAWK)")
else
  missing_names+=("gawk")
  missing_pkgs+=("gawk")
fi

if omk_resolve_gnu_find && _omk_is_gnu_find "$OMK_FIND"; then
  found+=("GNU find ($OMK_FIND)")
else
  missing_names+=("GNU find (findutils)")
  missing_pkgs+=("find")
fi

if [ "${#missing_pkgs[@]}" -eq 0 ]; then
  out=""
  for item in "${found[@]}"; do out="${out:+$out, }$item"; done
  echo "ok: $out"
  exit 0
fi

names_str=""
for item in "${missing_names[@]}"; do names_str="${names_str:+$names_str, }$item"; done
cmd="$(omk_install_hint "${missing_pkgs[@]}")"
echo "Missing required tool(s): $names_str" >&2
echo "Run this command to install them:" >&2
echo "  $cmd" >&2
exit 2
