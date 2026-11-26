#!/bin/bash
# oh-my-knowledge shared helpers: path normalisation and configuration.
# Source this file; it defines functions only. Requirements: bash, gawk, GNU find, jq.

_OMK_UP=ABCDEFGHIJKLMNOPQRSTUVWXYZ
_OMK_LO=abcdefghijklmnopqrstuvwxyz

# _omk_resolve_into <outvar> <path>: fork-free core of omk_resolve_dir.
_omk_resolve_into() {
  local _p="$2" _q _pre _dl _old _hadold _oo
  _p="${_p//\\//}"
  case "$_p" in
    "~") _p="$HOME" ;;
    "~/"*) _p="$HOME/${_p#\~/}" ;;
  esac
  if [[ "$_p" =~ ^([A-Za-z]):(/.*)?$ ]]; then
    _dl="${BASH_REMATCH[1]}"
    _q="${BASH_REMATCH[2]}"
    _pre="${_OMK_UP%%"$_dl"*}"
    if [ "${#_pre}" -lt 26 ]; then _dl="${_OMK_LO:${#_pre}:1}"; fi
    _p="/$_dl$_q"
  fi
  while [ "${#_p}" -gt 1 ] && [ "${_p%/}" != "$_p" ]; do _p="${_p%/}"; done
  if [ -d "$_p" ]; then
    _old="$PWD"
    if [ -d "$_old" ]; then
      # Fork-free canonicalisation; caller's PWD and OLDPWD are restored.
      _hadold="${OLDPWD+set}"; _oo="${OLDPWD-}"
      if CDPATH= cd -P -- "$_p" 2>/dev/null; then
        _p="$PWD"
        cd -- "$_old" 2>/dev/null
      fi
      if [ "$_hadold" = set ]; then OLDPWD="$_oo"; else unset OLDPWD; fi
    else
      # Caller's cwd is gone (cd back impossible): canonicalise in a subshell.
      _q="$(CDPATH= cd -P -- "$_p" 2>/dev/null && pwd -P)" && _p="$_q"
    fi
  fi
  printf -v "$1" '%s' "$_p"
}

# omk_resolve_dir <path>
# Canonical absolute POSIX path used for every comparison. Expands a leading
# ~/, turns C:\a\b / C:/a/b / c:/a/b into /c/a/b, strips trailing slashes, and
# (when the directory exists) canonicalises it with cd -P so /tmp/x, 8.3 short
# names and symlinks all map to the same string as the long path.
omk_resolve_dir() {
  local _r
  _omk_resolve_into _r "$1"
  printf '%s' "$_r"
}

# omk_native_path <path>
# The canonical path in the form Claude Code encodes for auto-memory dir names:
# Windows -> C:/… with long names (pwd -W; never cygpath -m, which may return
# 8.3 names); elsewhere pwd -P. Non-existent paths: best-effort conversion.
omk_native_path() {
  local p q r
  _omk_resolve_into p "$1"
  case "${OSTYPE:-}" in
    msys*|cygwin*)
      if [ -d "$p" ] && q="$(CDPATH= cd -P -- "$p" 2>/dev/null && pwd -W)"; then
        printf '%s' "$q"
        return 0
      fi
      if [[ "$p" =~ ^/([a-z])(/.*)?$ ]]; then
        r="${BASH_REMATCH[1]}"
        _omk_upper_into r "$r"
        printf "%s:%s" "$r" "${BASH_REMATCH[2]:-/}"
      else
        printf '%s' "$p"
      fi
      ;;
    *)
      printf '%s' "$p"
      ;;
  esac
}

# omk_repo_root <dir>
# Project root: inside git, the parent of the common git dir (so linked
# worktrees map to the main repo); otherwise <dir>. Submodules are out of scope
# (their common dir lives under the parent's .git/modules/; use OMK_AUTO_MEMORY_DIR).
omk_repo_root() {
  local d g
  d="$(omk_resolve_dir "$1")"
  if g="$(git -C "$d" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" && [ -n "$g" ]; then
    g="${g%$'\r'}"
    # Anything but one absolute line (old git ignoring --path-format, noise) = not in git.
    case "$g" in
      *$'\n'*) printf '%s' "$d"; return 0 ;;
      /*|[A-Za-z]:|[A-Za-z]:[/\\]*) ;;
      *) printf '%s' "$d"; return 0 ;;
    esac
    g="$(omk_resolve_dir "$g")"
    omk_resolve_dir "$(dirname "$g")"
  else
    printf '%s' "$d"
  fi
}

# omk_encode_name <native string>
# Every character outside [A-Za-z0-9] becomes '-', one '-' per character (CJK too).
omk_encode_name() {
  local s="$1"
  local LC_ALL=C.UTF-8
  printf "%s" "${s//[^A-Za-z0-9]/-}"
}

# omk_encode_path <path>: the only way to derive an auto-memory dir name.
omk_encode_path() {
  omk_encode_name "$(omk_native_path "$1")"
}


# _omk_unset <value>: true when empty.
_omk_unset() {
  [ -z "$1" ]
}

# _omk_bool <outvar> <value> <default>
_omk_bool() {
  case "$2" in
    [Tt][Rr][Uu][Ee]|1|[Yy][Ee][Ss]|[Oo][Nn]|[Yy]) printf -v "$1" true ;;
    [Ff][Aa][Ll][Ss][Ee]|0|[Nn][Oo]|[Oo][Ff][Ff]|[Nn]) printf -v "$1" false ;;
    *) printf -v "$1" '%s' "$3" ;;
  esac
}

_omk_int() { # <outvar> <value> <default>
  case "$2" in
    ''|*[!0-9]*) printf -v "$1" '%s' "$3" ;;
    *) printf -v "$1" '%s' "$((10#$2))" ;;
  esac
}

# omk_today: set OMK_TODAY (env OMK_TODAY wins) and export it. Not part of
# omk_config (it forks `date`); call it from scripts that need the date (lint).
omk_today() {
  OMK_TODAY="${OMK_TODAY:-}"
  _omk_unset "$OMK_TODAY" && OMK_TODAY="$(date +%F)"
  export OMK_TODAY
}

# _omk_conf_load: parse the shell-style KEY=value file $OMK_CONF into the
# _OMK_C_<KEY> variables (never sourced or evaluated; only the known keys below
# are read). Accepted line forms: KEY=value, export KEY=value, with optional
# single or double quotes around the value, '#' comment lines, blank lines, CRLF.
# The last assignment of a key wins. Fork-free.
_omk_conf_load() {
  local _f="$OMK_CONF" _line _k _v _kk
  for _kk in KNOWLEDGE_DIR LOOKUP_REMINDER AUTO_HANDOFF AUTO_HANDOFF_THRESHOLD AUTO_HANDOFF_REPEAT \
    LINT_STALE_DAYS LINT_FLAG_DAYS LINT_REMIND_AFTER_DISTILLS MAX_FILE_KB MAX_INDEX_LINE_CHARS; do
    printf -v "_OMK_C_$_kk" '%s' ""
  done
  [ -f "$_f" ] && [ -r "$_f" ] || return 0
  while IFS= read -r _line || [ -n "$_line" ]; do
    _line="${_line%$'\r'}"
    _line="${_line#"${_line%%[![:space:]]*}"}"
    case "$_line" in ''|'#'*) continue ;; esac
    case "$_line" in "export "*) _line="${_line#export }"; _line="${_line#"${_line%%[![:space:]]*}"}" ;; esac
    case "$_line" in *=*) ;; *) continue ;; esac
    _k="${_line%%=*}"; _v="${_line#*=}"
    _k="${_k%"${_k##*[![:space:]]}"}"
    _v="${_v#"${_v%%[![:space:]]*}"}"
    case "$_v" in
      \"*) _v="${_v#\"}"; _v="${_v%%\"*}" ;;
      \'*) _v="${_v#\'}"; _v="${_v%%\'*}" ;;
      *) _v="${_v%%[[:space:]]#*}"; _v="${_v%"${_v##*[![:space:]]}"}" ;;
    esac
    case "$_k" in
      KNOWLEDGE_DIR|LOOKUP_REMINDER|AUTO_HANDOFF|AUTO_HANDOFF_THRESHOLD|AUTO_HANDOFF_REPEAT|LINT_STALE_DAYS|LINT_FLAG_DAYS|LINT_REMIND_AFTER_DISTILLS|MAX_FILE_KB|MAX_INDEX_LINE_CHARS)
        printf -v "_OMK_C_$_k" '%s' "$_v" ;;
    esac
  done < "$_f"
}

# _omk_pick <outvar> <KEY> <default>: env OMK_<KEY> (non-empty) > conf file KEY > default.
_omk_pick() {
  local _ev="OMK_$2" _cv="_OMK_C_$2" _v
  _v="${!_ev:-}"
  if _omk_unset "$_v"; then _v="${!_cv:-}"; fi
  if _omk_unset "$_v"; then _v="$3"; fi
  printf -v "$1" '%s' "$_v"
}

# omk_config: set and export every OMK_* setting (plus OMA_HOME, OMA_STATE_DIR).
# Precedence: env var OMK_<KEY> (if non-empty) > $OMK_CONF (default
# ~/.gemini/oh-my-agy/knowledge.conf, written by the kb-setup skill) > default.
# Fork-free (hooks run it on every event); OMK_TODAY is lazy, see omk_today.
omk_config() {
  local t _v
  OMA_HOME="${OMA_HOME:-}"
  _omk_unset "$OMA_HOME" && OMA_HOME="$HOME/.gemini/oh-my-agy"
  OMK_CONF="${OMK_CONF:-}"
  _omk_unset "$OMK_CONF" && OMK_CONF="$OMA_HOME/knowledge.conf"
  _omk_conf_load
  _omk_pick t KNOWLEDGE_DIR '~/knowledge'
  # Validate the picked raw value (backslashes as slashes) before resolving:
  # absolute = /…, X:/…, X:, or ~ / ~/…. Always assigned; omk_config still returns 0.
  OMK_CONFIG_ERROR=""
  _v="${t//\\//}"
  case "$_v" in
    /*|"~"|"~/"*|[A-Za-z]:|[A-Za-z]:/*) ;;
    *) OMK_CONFIG_ERROR="knowledge_dir must be an absolute path or start with ~/ (got: $t); run the kb-setup skill" ;;
  esac
  _omk_resolve_into OMK_KNOWLEDGE_DIR "$t"
  _omk_pick t LOOKUP_REMINDER true; _omk_bool OMK_LOOKUP_REMINDER "$t" true
  _omk_pick t AUTO_HANDOFF true; _omk_bool OMK_AUTO_HANDOFF "$t" true
  _omk_pick t AUTO_HANDOFF_THRESHOLD 70; _omk_int OMK_AUTO_HANDOFF_THRESHOLD "$t" 70
  _omk_pick t AUTO_HANDOFF_REPEAT 20; _omk_int OMK_AUTO_HANDOFF_REPEAT "$t" 20
  _omk_pick t LINT_STALE_DAYS 90; _omk_int OMK_LINT_STALE_DAYS "$t" 90
  _omk_pick t LINT_FLAG_DAYS 14; _omk_int OMK_LINT_FLAG_DAYS "$t" 14
  _omk_pick t LINT_REMIND_AFTER_DISTILLS 10; _omk_int OMK_LINT_REMIND_AFTER_DISTILLS "$t" 10
  _omk_pick t MAX_FILE_KB 8; _omk_int OMK_MAX_FILE_KB "$t" 8
  _omk_pick t MAX_INDEX_LINE_CHARS 200; _omk_int OMK_MAX_INDEX_LINE_CHARS "$t" 200
  OMK_AUTO_MEMORY_DIR="${OMK_AUTO_MEMORY_DIR:-}"
  OMK_AUTO_MEMORY_GLOB="${OMK_AUTO_MEMORY_GLOB:-}"
  _omk_unset "$OMK_AUTO_MEMORY_GLOB" && OMK_AUTO_MEMORY_GLOB="$OMA_HOME/projects/*/memory"
  OMK_RULES_FILE="${OMK_RULES_FILE:-}"
  _omk_unset "$OMK_RULES_FILE" && OMK_RULES_FILE="$HOME/.gemini/GEMINI.md"
  OMA_STATE_DIR="${OMA_STATE_DIR:-}"
  _omk_unset "$OMA_STATE_DIR" && OMA_STATE_DIR="$OMA_HOME/state"
  OMK_TODAY="${OMK_TODAY:-}"
  OMK_JQ="${OMK_JQ:-}"
  _omk_unset "$OMK_JQ" && OMK_JQ="jq"
  export OMA_HOME OMK_CONF OMK_KNOWLEDGE_DIR OMK_LOOKUP_REMINDER OMK_AUTO_HANDOFF OMK_AUTO_HANDOFF_THRESHOLD \
    OMK_AUTO_HANDOFF_REPEAT OMK_LINT_STALE_DAYS OMK_LINT_FLAG_DAYS OMK_LINT_REMIND_AFTER_DISTILLS OMK_MAX_FILE_KB \
    OMK_MAX_INDEX_LINE_CHARS OMK_AUTO_MEMORY_DIR OMK_AUTO_MEMORY_GLOB OMK_RULES_FILE \
    OMA_STATE_DIR OMK_TODAY OMK_JQ OMK_CONFIG_ERROR
}

# _omk_upper_into <outvar> <string>: ASCII upper-case without forking.
_omk_upper_into() {
  local _s="$2" _r="" _c _i _pre
  for ((_i = 0; _i < ${#_s}; _i++)); do
    _c="${_s:_i:1}"
    case "$_c" in
      [abcdefghijklmnopqrstuvwxyz]) _pre="${_OMK_LO%%"$_c"*}"; _c="${_OMK_UP:${#_pre}:1}" ;;
    esac
    _r+="$_c"
  done
  printf -v "$1" '%s' "$_r"
}

# _omk_brew_fallback_allowed: true on macOS when PATH looks like a real system
# PATH (contains /usr/bin or /bin), or when OMK_BREW_PREFIX is explicitly set.
# Keeps isolated tests (PATH=<empty dir>) from accidentally picking up host tools.
_omk_brew_fallback_allowed() {
  [ -n "${OMK_BREW_PREFIX:-}" ] && return 0
  case "${OMK_OSTYPE:-${OSTYPE:-}}" in
    darwin*)
      case ":${PATH:-}:" in
        *:/usr/bin:*|*:/bin:*) return 0 ;;
      esac ;;
  esac
  return 1
}

# _omk_brew_prefixes: prints candidate Homebrew prefixes, one per line.
_omk_brew_prefixes() {
  if [ -n "${OMK_BREW_PREFIX:-}" ]; then
    printf '%s\n' "$OMK_BREW_PREFIX"
  else
    printf '%s\n' /opt/homebrew /usr/local
  fi
}

# omk_install_hint <tool>...: prints a platform-appropriate install command for
# one or more tools (gawk, find, jq, git). OMK_OSTYPE / OMK_PKG_MGR override
# detection for tests.
omk_install_hint() {
  local _os="${OMK_OSTYPE:-${OSTYPE:-}}" _pkgs="" _t _p _seen=" "
  case "$_os" in
    darwin*)
      for _t in "$@"; do
        case "$_t" in
          find|gfind|findutils) _p=findutils ;;
          gawk) _p=gawk ;;
          jq) _p=jq ;;
          git) _p=git ;;
          *) _p="$_t" ;;
        esac
        case "$_seen" in *" $_p "*) ;; *) _seen="$_seen$_p "; _pkgs="${_pkgs:+$_pkgs }$_p" ;; esac
      done
      printf 'brew install %s' "$_pkgs" ;;
    msys*|cygwin*|mingw*|win*)
      for _t in "$@"; do
        case "$_t" in
          jq) _p=jqlang.jq ;;
          gawk|find|gfind|findutils|git) _p=Git.Git ;;
          *) _p="$_t" ;;
        esac
        case "$_seen" in *" $_p "*) ;; *) _seen="$_seen$_p "; _pkgs="${_pkgs:+$_pkgs }$_p" ;; esac
      done
      printf 'winget install %s' "$_pkgs" ;;
    *)
      local _mgr=""
      if [ -n "${OMK_PKG_MGR:-}" ]; then _mgr="$OMK_PKG_MGR"
      elif command -v apt-get >/dev/null 2>&1; then _mgr=apt
      elif command -v dnf >/dev/null 2>&1; then _mgr=dnf
      elif command -v pacman >/dev/null 2>&1; then _mgr=pacman
      elif command -v zypper >/dev/null 2>&1; then _mgr=zypper
      elif command -v apk >/dev/null 2>&1; then _mgr=apk
      elif command -v brew >/dev/null 2>&1; then _mgr=brew
      fi
      for _t in "$@"; do
        case "$_t" in
          find|gfind|findutils) _p=findutils ;;
          gawk) _p=gawk ;;
          jq) _p=jq ;;
          git) _p=git ;;
          *) _p="$_t" ;;
        esac
        case "$_seen" in *" $_p "*) ;; *) _seen="$_seen$_p "; _pkgs="${_pkgs:+$_pkgs }$_p" ;; esac
      done
      case "$_mgr" in
        apt) printf 'sudo apt install %s' "$_pkgs" ;;
        dnf) printf 'sudo dnf install %s' "$_pkgs" ;;
        pacman) printf 'sudo pacman -S %s' "$_pkgs" ;;
        zypper) printf 'sudo zypper install %s' "$_pkgs" ;;
        apk) printf 'sudo apk add %s' "$_pkgs" ;;
        brew) printf 'brew install %s' "$_pkgs" ;;
        *) printf 'install %s using your system package manager' "$_pkgs" ;;
      esac ;;
  esac
}

# omk_resolve_gawk: sets OMK_GAWK to gawk on PATH or Homebrew fallback.
omk_resolve_gawk() {
  if command -v gawk >/dev/null 2>&1; then
    OMK_GAWK="gawk"
    return 0
  fi
  if _omk_brew_fallback_allowed; then
    local _pfx
    while IFS= read -r _pfx; do
      if [ -x "$_pfx/bin/gawk" ]; then
        OMK_GAWK="$_pfx/bin/gawk"
        return 0
      fi
    done < <(_omk_brew_prefixes)
  fi
  OMK_GAWK=""
  return 1
}

# omk_resolve_jq: verifies OMK_JQ (default jq) on PATH or Homebrew fallback.
omk_resolve_jq() {
  local _j="${OMK_JQ:-jq}"
  if command -v "$_j" >/dev/null 2>&1; then
    OMK_JQ="$_j"
    return 0
  fi
  if [ "$_j" = "jq" ] && _omk_brew_fallback_allowed; then
    local _pfx
    while IFS= read -r _pfx; do
      if [ -x "$_pfx/bin/jq" ]; then
        OMK_JQ="$_pfx/bin/jq"
        return 0
      fi
    done < <(_omk_brew_prefixes)
  fi
  return 1
}

# _omk_is_gnu_find <bin>: true when <bin> supports GNU -printf.
_omk_is_gnu_find() {
  "$1" /dev/null -maxdepth 0 -printf '' >/dev/null 2>&1
}

# omk_resolve_gnu_find: sets OMK_FIND to a GNU find (supporting -printf).
# Prefers `find` on PATH, then `gfind` on PATH, then Homebrew findutils on macOS.
# A `find` on PATH that fails silently (no option/predicate error on stderr) is
# kept as-is so callers treat runtime find failures as fatal (exit 1).
omk_resolve_gnu_find() {
  local _err="" _pfx _cand
  if command -v find >/dev/null 2>&1; then
    if _omk_is_gnu_find find; then
      OMK_FIND="find"
      return 0
    fi
    _err="$(find /dev/null -maxdepth 0 -printf '' 2>&1)"
    if [ -z "$_err" ]; then
      OMK_FIND="find"
      return 0
    fi
  fi
  if command -v gfind >/dev/null 2>&1 && _omk_is_gnu_find gfind; then
    OMK_FIND="gfind"
    return 0
  fi
  if _omk_brew_fallback_allowed; then
    while IFS= read -r _pfx; do
      for _cand in "$_pfx/opt/findutils/libexec/gnubin/find" "$_pfx/bin/gfind"; do
        if [ -x "$_cand" ] && _omk_is_gnu_find "$_cand"; then
          OMK_FIND="$_cand"
          return 0
        fi
      done
    done < <(_omk_brew_prefixes)
  fi
  OMK_FIND=""
  return 1
}
