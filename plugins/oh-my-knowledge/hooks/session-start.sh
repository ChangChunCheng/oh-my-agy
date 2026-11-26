#!/bin/bash
# SessionStart hook: tell the agent where the knowledge base and the bundled
# scripts are, what [[g:slug]] / [[k:path]] mean, and which conversation id to use
# for the handoff marker. Also injects this project's memory (MEMORY.md, the
# first 200 lines) and, when the project is migrated and has
# projects/<p>/always-on.md, its "- " lines as always-on directives.
# Output: {"injectSteps":[{"systemMessage":{"systemMessage":"..."}}]} or {}.
# Never breaks the session. bash 3.2.
quiet() { printf '{}\n'; exit 0; }
case "${BASH_SOURCE[0]}" in */*) HOOK_DIR="${BASH_SOURCE[0]%/*}" ;; *) HOOK_DIR=. ;; esac
# shellcheck source=../scripts/lib/common.sh
. "$HOOK_DIR/../scripts/lib/common.sh" 2>/dev/null || quiet
omk_config 2>/dev/null || quiet
omk_resolve_jq 2>/dev/null || quiet

# One jq call, one value per line (not @tsv: it would double a backslash in cwd).
l="$("$OMK_JQ" -r '(.conversationId // ""), (.cwd // .workspacePaths[0]? // "")' 2>/dev/null)" || quiet
sid=""; cwd=""
{ IFS= read -r sid; IFS= read -r cwd; } <<< "$l"
sid="${sid%$'\r'}"; cwd="${cwd%$'\r'}"
[ -n "$cwd" ] || cwd="$PWD"

# Plugin root: agy exports PLUGIN_ROOT; the hook's cwd is the plugin dir.
root="${PLUGIN_ROOT:-}"
[ -n "$root" ] || root="$(cd "$HOOK_DIR/.." 2>/dev/null && pwd)"

kb="$(omk_native_path "$OMK_KNOWLEDGE_DIR")"
msg="Knowledge base: ${kb}. [[g:slug]] = ${kb}/global/<slug>.md; [[k:path]] = ${kb}/<path>.md. oh-my-knowledge scripts: ${root}/scripts (run them with bash). Conversation id: ${sid:-unknown}."
normal=1
# Precedence: configuration error > not set up > normal note.
if [ ! -f "$OMK_KNOWLEDGE_DIR/SCHEMA.md" ]; then
  normal=0
  msg="oh-my-knowledge: knowledge base not set up yet (${kb}) — run the kb-setup skill (scripts: ${root}/scripts)."
fi
if [ -n "${OMK_CONFIG_ERROR:-}" ]; then
  normal=0
  msg="oh-my-knowledge: $OMK_CONFIG_ERROR"
fi

# _omk_always_on_block <outvar> <project> <page>: assigns the directives block
# (heading + "- " lines, at most 4000 bytes counted under LC_ALL=C, cut at a line
# boundary) or "" when there is nothing to inject.
_omk_always_on_block() {
  local LC_ALL=C
  local _p="$2" _page="$3" _line _t _first=1 _infm=0 _fence=0 _cmt=0 _body="" _more=0 _total=0 _bom=$'\xef\xbb\xbf' _out=""
  printf -v "$1" '%s' ""
  [ -f "$_page" ] || return 0
  while IFS= read -r _line || [ -n "$_line" ]; do
    _line="${_line%$'\r'}"
    if [ "$_first" = 1 ]; then
      _first=0; _line="${_line#"$_bom"}"
      if [ "$_line" = "---" ]; then _infm=1; continue; fi
    fi
    if [ "$_infm" = 1 ]; then
      if [ "$_line" = "---" ]; then _infm=0; fi
      continue
    fi
    _t="${_line#"${_line%%[![:space:]]*}"}"
    if [ "$_cmt" = 1 ]; then
      case "$_line" in *'-->'*) _cmt=0 ;; esac
      continue
    fi
    if [ "$_fence" = 1 ]; then
      case "$_t" in '```'*|'~~~'*) _fence=0 ;; esac
      continue
    fi
    case "$_t" in
      '```'*|'~~~'*) _fence=1; continue ;;
      '<!--'*) case "$_t" in *'-->'*) ;; *) _cmt=1 ;; esac; continue ;;
    esac
    case "$_line" in
      '- '*)
        if [ $((_total + ${#_line} + 1)) -gt 4000 ]; then _more=1; break; fi
        _total=$((_total + ${#_line} + 1))
        _body="${_body:+$_body$'\n'}$_line" ;;
    esac
  done < "$_page"
  [ -n "$_body" ] || [ "$_more" = 1 ] || return 0
  _out="Always-on directives for this project (${_p}) — follow them in every reply:"
  [ -z "$_body" ] || _out="$_out"$'\n'"$_body"
  if [ "$_more" = 1 ]; then _out="$_out"$'\n'"(more in [[k:projects/${_p}/always-on]])"; fi
  printf -v "$1" '%s' "$_out"
}

# Project memory: progress notes of this repo, owned by the kb-handoff skill.
# Cap: first 200 lines and at most 20000 bytes (counted under LC_ALL=C).
if . "$HOOK_DIR/../scripts/lib/project.sh" 2>/dev/null; then
  mem=""
  _omk_memory_path_into mem "$cwd" 2>/dev/null
  if [ -n "$mem" ]; then
    msg="$msg"$'\n\n'"Project memory (progress of this project): ${mem}/MEMORY.md — the kb-handoff skill writes it."
    if [ -f "$mem/MEMORY.md" ] && [ -s "$mem/MEMORY.md" ]; then
      body=""; n=0; total=0
      while IFS= read -r line || [ -n "$line" ]; do
        line="${line%$'\r'}"
        n=$((n + 1)); [ "$n" -le 200 ] || break
        total=$((total + ${#line} + 1)); [ "$total" -le 20000 ] || break
        body="${body:+$body$'\n'}$line"
      done < "$mem/MEMORY.md"
      [ -z "$body" ] || msg="$msg"$'\n'"--- MEMORY.md ---"$'\n'"$body"$'\n'"--- end MEMORY.md ---"
    fi
  fi
fi

if [ "$normal" = 1 ]; then
  proj=""; block=""
  if . "$HOOK_DIR/../scripts/lib/project.sh" 2>/dev/null; then
    _omk_project_into proj "$cwd" 2>/dev/null
    if [ -n "$proj" ]; then
      _omk_always_on_block block "$proj" "$OMK_KNOWLEDGE_DIR/projects/$proj/always-on.md" 2>/dev/null
      [ -z "$block" ] || msg="$msg"$'\n\n'"$block"
    fi
  fi
fi

"$OMK_JQ" -cn --arg c "$msg" '{injectSteps:[{systemMessage:{systemMessage:$c}}]}' 2>/dev/null || quiet
exit 0
