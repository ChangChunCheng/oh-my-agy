#!/bin/bash
# lint.sh [--checks structure|content|all]   (oh-my-knowledge health check, script stage)
# Prints one JSON document on stdout:
#   {"version":1,"generated":"YYYY-MM-DD","knowledge_dir":"...","findings":[{check,severity,file,line,detail}],
#    "groups":[{"name":"index:<slug>|project:<p>|family:<prefix>","pages":[rel paths]}],
#    "batches":[{"groups":[names],"pages":[rel paths]}]}   (<= 25 distinct pages each; groups whose pages are a subset of another group's are dropped)
# Scope: rules/, global/, projects/, index.md (skips .git/, lint/, _retired/). Paths are KB-relative; line 0 = whole file.
# Symlinked files are skipped (find -type f). long_index_line looks at bullet lines of index.md / index_*.md files. Groups come only from the structure pass
# (--checks content returns none). Content/reference checks (lib/lint-content.awk) cover KB pages, auto memory
# (OMK_AUTO_MEMORY_GLOB) and OMK_RULES_FILE in one gawk pass. Any failing find/gawk is fatal (exit 1).
# Exit: 0 | 1 a pass failed | 2 usage error, KB missing or not set up, gawk or jq missing.
set -u
set -o pipefail
case "${BASH_SOURCE[0]}" in */*) HERE="${BASH_SOURCE[0]%/*}" ;; *) HERE=. ;; esac
HERE="$(cd "$HERE" && pwd)"
# shellcheck source=lib/common.sh
. "$HERE/lib/common.sh"
omk_config
[ -z "${OMK_CONFIG_ERROR:-}" ] || { echo "lint.sh: $OMK_CONFIG_ERROR" >&2; exit 2; }
omk_today

USAGE="usage: lint.sh [--checks structure|content|all]"
CHECKS=all
while [ "$#" -gt 0 ]; do
  case "$1" in
    --checks) [ "$#" -ge 2 ] || { echo "$USAGE" >&2; exit 2; }; CHECKS="$2"; shift 2 ;;
    *) echo "$USAGE" >&2; exit 2 ;;
  esac
done
case "$CHECKS" in structure|content|all) ;; *) echo "$USAGE" >&2; exit 2 ;; esac
omk_resolve_gawk || { echo "lint.sh: gawk is required but was not found. Install it with: $(omk_install_hint gawk)" >&2; exit 2; }
omk_resolve_jq || { echo "lint.sh: jq is required but was not found ($OMK_JQ). Install it with: $(omk_install_hint jq)" >&2; exit 2; }
omk_resolve_gnu_find || { echo "lint.sh: GNU find (supporting -printf) is required. Install it with: $(omk_install_hint find)" >&2; exit 2; }
KB="$OMK_KNOWLEDGE_DIR"
[ -f "$KB/SCHEMA.md" ] || { echo "lint.sh: knowledge base not found or not set up (no SCHEMA.md): $KB; run the kb-setup skill" >&2; exit 2; }

RAW="$(mktemp)" || exit 2
trap 'rm -f "$RAW"' EXIT
: > "$RAW"
if [ "$CHECKS" != content ]; then
  {
    "$OMK_FIND" "$KB" -maxdepth 1 -type f -name '*.md' -printf '%s\0%p\0' || exit 1
    if [ -d "$KB/rules" ]; then "$OMK_FIND" "$KB/rules" -name .git -prune -o -type f -printf '%s\0%p\0' || exit 1; fi
    for d in global projects; do
      if [ -d "$KB/$d" ]; then "$OMK_FIND" "$KB/$d" \( -name .git -o -name _retired \) -prune -o -type f -name '*.md' -printf '%s\0%p\0' || exit 1; fi
    done
    for d in _retired lint; do   # existence only (link targets); no check runs on these pages
      if [ -d "$KB/$d" ]; then "$OMK_FIND" "$KB/$d" -name .git -prune -o -type f -name '*.md' -printf '%s\0%p\0' || exit 1; fi
    done
  } | LC_ALL=C.UTF-8 OMK_LINT_ROOT="$KB" OMK_MAX_FILE_KB="$OMK_MAX_FILE_KB" OMK_MAX_INDEX_LINE_CHARS="$OMK_MAX_INDEX_LINE_CHARS" \
    "$OMK_GAWK" -f "$HERE/lib/lint-structure.awk" > "$RAW" || { echo "lint.sh: structural pass failed" >&2; exit 1; }
fi

if [ "$CHECKS" != structure ]; then
  QFILE="$(mktemp)" || exit 2
  trap 'rm -f "$RAW" "$QFILE"' EXIT
  : > "$QFILE"
  # auto-memory dirs from OMK_AUTO_MEMORY_GLOB: one '*' path component (same rule as omk_auto_memory_for_cwd)
  AMDIRS=()
  case "$OMK_AUTO_MEMORY_GLOB" in
    *'*'*)
      amg="$OMK_AUTO_MEMORY_GLOB"; ampre="${amg%%\**}"; amsuf="${amg#*\*}"; amsuf="${amsuf//\\//}"
      ampre="$(omk_resolve_dir "$ampre")"
      if [ -d "$ampre" ]; then
        for e in "$ampre"/*/; do
          [ -d "${e%/}$amsuf" ] && AMDIRS[${#AMDIRS[@]}]="${e%/}$amsuf"
        done
      fi ;;
    "") ;;
    *) [ -d "$OMK_AUTO_MEMORY_GLOB" ] && AMDIRS[0]="$(omk_resolve_dir "$OMK_AUTO_MEMORY_GLOB")" ;;
  esac
  RULES_FILE="$(omk_resolve_dir "$OMK_RULES_FILE")"
  RULES_FILE="$(omk_resolve_dir "${RULES_FILE%/*}")/${RULES_FILE##*/}"
  WINP=0
  case "${OSTYPE:-}" in msys*|cygwin*) WINP=1 ;; esac
  # case-insensitive file system? (Windows, default macOS): probe the KB dir itself; OMK_LINT_ICASE=0|1 overrides
  ICASE="${OMK_LINT_ICASE:-}"
  case "$ICASE" in 0|1) ;; *)
    ICASE=0
    kb_b="${KB##*/}"; kb_u="$(printf %s "$kb_b" | tr 'a-z' 'A-Z')"
    [ "$kb_u" = "$kb_b" ] && kb_u="$(printf %s "$kb_b" | tr 'A-Z' 'a-z')"
    if [ "$kb_u" != "$kb_b" ] && [ -d "${KB%/*}/$kb_u" ] && [ "${KB%/*}/$kb_u" -ef "$KB" ]; then ICASE=1; fi ;;
  esac
  {
    "$OMK_FIND" "$KB" -maxdepth 1 -type f -name '*.md' -printf 'K\0%p\0' || exit 1
    for d in rules global projects; do
      if [ -d "$KB/$d" ]; then "$OMK_FIND" "$KB/$d" \( -name .git -o -name _retired \) -prune -o -type f -name '*.md' -printf 'K\0%p\0' || exit 1; fi
    done
    for d in _retired lint; do   # existence only (link targets); no check runs on these pages
      if [ -d "$KB/$d" ]; then "$OMK_FIND" "$KB/$d" -name .git -prune -o -type f -name '*.md' -printf 'X\0%p\0' || exit 1; fi
    done
    if [ -d "$KB/projects" ]; then "$OMK_FIND" "$KB/projects" -mindepth 1 -maxdepth 1 -xtype d -printf 'D\0%f\0' || exit 1; fi
    if [ "${#AMDIRS[@]}" -gt 0 ]; then "$OMK_FIND" "${AMDIRS[@]}" -maxdepth 1 -type f -name '*.md' -printf 'A\0%p\0' || exit 1; fi
    if [ -f "$RULES_FILE" ]; then printf 'C\0%s\0' "$RULES_FILE"; fi
  } | LC_ALL=C.UTF-8 OMK_LINT_ROOT="$KB" OMK_LINT_QFILE="$QFILE" OMK_LINT_WINPATHS="$WINP" OMK_LINT_ICASE="$ICASE" OMK_TODAY="$OMK_TODAY" \
    OMK_LINT_STALE_DAYS="$OMK_LINT_STALE_DAYS" OMK_LINT_FLAG_DAYS="$OMK_LINT_FLAG_DAYS" \
    "$OMK_GAWK" -f "$HERE/lib/lint-content.awk" >> "$RAW" || { echo "lint.sh: content pass failed" >&2; exit 1; }
  # missing_path: candidate ~/ paths are tested here with the [ -e ] builtin (no forks)
  while IFS=$'\t' read -r qf ql qp; do
    case "$qp" in "~/"*) ;; *) continue ;; esac
    [ -e "$HOME/${qp#\~/}" ] || printf 'F\tmissing_path\tblue\t%s\t%s\t%s does not exist\n' "$qf" "$ql" "$qp" >> "$RAW"
  done < "$QFILE"
fi

"$OMK_JQ" -Rn --arg gen "$OMK_TODAY" --arg kb "$(omk_native_path "$KB")" '
  def batches($max):
    [ .[] | {name, pages: (.pages | unique)} | select(.pages | length > 0) ]
    | sort_by([-(.pages | length), .name])
    | reduce .[] as $g ([];
        if any(.[]; ($g.pages - .pages) == []) then . else . + [$g] end)
    | [ .[] | . as $g | range(0; (($g.pages | length) + $max - 1) / $max | floor) as $i
        | {name: $g.name, i: $i, pages: $g.pages[($i * $max):(($i + 1) * $max)]} ]
    | sort_by([-(.pages | length), .name, .i])
    | reduce .[] as $u ([];
        (first(range(0; length) as $k | select((.[$k].pages + $u.pages | unique | length) <= $max) | $k) // null) as $k
        | if $k == null then . + [{groups: [$u.name], pages: $u.pages}]
          else .[$k].groups += [$u.name] | .[$k].pages = (.[$k].pages + $u.pages | unique) end);
  [inputs | rtrimstr("\r") | split("\t")] as $r
  | [$r[] | select(.[0] == "G") | {name: .[1], pages: .[2:]}] as $groups
  | {version: 1, generated: $gen, knowledge_dir: $kb,
     findings: [$r[] | select(.[0] == "F") | {check: .[1], severity: .[2], file: .[3], line: (.[4] | tonumber), detail: .[5]}],
     groups: $groups,
     batches: ($groups | batches(25))}' < "$RAW" | tr -d '\r' || { echo "lint.sh: JSON shaping failed" >&2; exit 1; }
exit 0
