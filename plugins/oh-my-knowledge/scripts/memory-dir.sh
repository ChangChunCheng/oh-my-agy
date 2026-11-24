#!/bin/bash
# memory-dir.sh [--create] [<cwd>]   (oh-my-knowledge: where this project's memory lives)
# Prints the project-memory directory for the repository containing <cwd> (default:
# the working directory): <OMA_HOME>/projects/<encoded repo root>/memory, where the
# encoding turns every character outside [A-Za-z0-9] into '-' (the same scheme
# Claude Code uses). With --create the directory and an empty MEMORY.md are
# created when missing. OMK_AUTO_MEMORY_DIR overrides the whole location.
# Exit: 0 | 1 cannot create | 2 usage error or no location (glob without '*').
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$HERE/lib/common.sh"
# shellcheck source=lib/project.sh
. "$HERE/lib/project.sh"
omk_config
create=0
if [ "${1:-}" = "--create" ]; then create=1; shift; fi
[ "$#" -le 1 ] || { echo "usage: memory-dir.sh [--create] [<cwd>]" >&2; exit 2; }
d="$(omk_memory_dir_for_cwd "${1:-$PWD}")"
[ -n "$d" ] || { echo "memory-dir.sh: no project-memory location (OMK_AUTO_MEMORY_GLOB has no '*')" >&2; exit 2; }
if [ "$create" = 1 ]; then
  mkdir -p -- "$d" || { echo "memory-dir.sh: cannot create $d" >&2; exit 1; }
  [ -e "$d/MEMORY.md" ] || : > "$d/MEMORY.md" || { echo "memory-dir.sh: cannot create $d/MEMORY.md" >&2; exit 1; }
fi
printf '%s\n' "$(omk_native_path "$d")"
exit 0
