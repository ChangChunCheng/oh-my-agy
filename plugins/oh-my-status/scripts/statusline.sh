#!/bin/bash
# oh-my-status - Themeable statusline for Antigravity CLI (agy)
# https://github.com/ChangChunCheng/oh-my-agy
#
# agy runs this with `sh -c` whenever the agent state changes (at most every
# 300 ms, killed after 5 s), pipes the session state as JSON on stdin and shows
# stdout. See https://antigravity.google/docs/cli/statusline

# Use BASH_SOURCE so this resolves correctly whether the file is executed
# directly or sourced (e.g. by the test loader).
case ${BASH_SOURCE[0]} in */*|*\\*) SCRIPT_DIR=${BASH_SOURCE[0]%[/\\]*} ;; *) SCRIPT_DIR=. ;; esac
# Installed copy: themes/ and layouts/ sit next to this file. Repo checkout:
# this file lives in scripts/ and they sit one level up.
if [ -z "${OMA_DIR:-}" ]; then
  if [ -d "$SCRIPT_DIR/themes" ]; then OMA_DIR=$SCRIPT_DIR; else OMA_DIR=$SCRIPT_DIR/..; fi
fi
OMA_HOME="${OMA_HOME:-$HOME/.gemini/oh-my-agy}"
OMA_CONF="${OMA_CONF:-$OMA_HOME/status.conf}"

# Defaults
THEME="catppuccin"
LAYOUT="default"

# Load config
[ -f "$OMA_CONF" ] && source "$OMA_CONF"

# git_info() result cache TTL (seconds). 0 = disable caching (always
# recompute). Non-numeric/negative → 10.
: "${GIT_CACHE_TTL:=10}"
# Account segment. ACCOUNT_ICON is dash form: explicit "" disables it.
: "${ACCOUNT_SHOW:=true}"
: "${ACCOUNT_FORMAT:=user}"
# Model context tag: append " [NM]" to MODEL when context size >= 1M.
: "${MODEL_CTX_TAG:=true}"
# Strip the trailing " (High)" style effort suffix from the model name.
: "${MODEL_STRIP_EFFORT:=false}"
# Which quota buckets feed the 5h / 7d meters: auto (follow the model:
# Gemini models use gemini-*, others use 3p-*) | gemini | 3p.
: "${QUOTA_FAMILY:=auto}"
: "${SHOW_MODE:=true}"
: "${SHOW_COST:=false}"
: "${SHOW_TASKS:=true}"
ACCOUNT_ICON="${ACCOUNT_ICON-$'\xef\x80\x87'}"

OMA_STATE_DIR="${OMA_STATE_DIR:-$OMA_HOME/state}"

# Load theme and layout
THEME_FILE="${OMA_DIR}/themes/${THEME}.sh"
LAYOUT_FILE="${OMA_DIR}/layouts/${LAYOUT}.sh"

[ -f "$THEME_FILE" ] || THEME_FILE="${OMA_DIR}/themes/catppuccin.sh"
[ -f "$LAYOUT_FILE" ] || LAYOUT_FILE="${OMA_DIR}/layouts/default.sh"

source "$THEME_FILE"
# Shared render helpers (extras segment) used by every layout and preview.sh.
source "$SCRIPT_DIR/lib/render-common.sh"
source "$LAYOUT_FILE"

# RESET fallback (layouts usually define it).
: "${RESET:=$'\033[0m'}"

# ---------------------------------------------------------------------------
# Helper functions — defined before the render gate so test loaders can
# source this file (with OMA_TEST_LIB_ONLY=1) and access them without
# triggering JSON parsing or the render pipeline.
# ---------------------------------------------------------------------------

# Clock without a fork on bash >= 5 (EPOCHSECONDS); `date` otherwise.
# OMA_NOW_OVERRIDE is the test-only clock seam. Sets REPLY.
_oma_now() { REPLY=${OMA_NOW_OVERRIDE:-${EPOCHSECONDS:-$(date +%s)}}; }

# Sweep crash-orphaned temp files (>30s old) from the state dir. A writer
# SIGKILL'd between creating its temp file and the atomic rename leaves a
# `gitcache-*.tmp.<pid>` (cached_git_info) behind.
# A live writer renames its temp file within the
# same sub-second critical section, so 30s is far past any legitimate
# lifetime — nothing in use is ever swept. Best-effort, never fatal.
# The 24h sweep in setup.sh (SessionStart hook) is the coarse backstop; this keeps the dir tidy
# within a long-lived session. An unmatched glob stays literal and is
# filtered out by the `[ -f ]` test.
_oma_sweep_stale_tmp() {
  local now="" mt f
  for f in "$OMA_STATE_DIR"/gitcache-*.tmp.*; do
    [ -f "$f" ] || continue
    # The clock is only needed once a real orphan exists.
    if [ -z "$now" ]; then _oma_now; now=$REPLY; fi
    mt=$(stat -c %Y "$f" 2>/dev/null) || continue
    [ $((now - mt)) -gt 30 ] && rm -f "$f" 2>/dev/null
  done
}

# Git working-tree summary. Pure: runs git in the caller's $PWD, mutates no
# globals. stdout = exactly one line, 6 TAB-joined fields (NO trailing newline):
#   <BRANCH>\t<ADD>\t<MOD>\t<DEL>\t<LINES_ADD>\t<LINES_DEL>
# not-a-repo and detached HEAD → field 1 empty; fields 2–6 are integers.
# Two git calls on the normal path (status -b, diff --numstat); the branch
# comes from the `status -b` header and the counting is done in bash with the
# same predicates the old grep/awk used. If `git status` fails (dubious
# ownership, corrupt index, bare repo, cwd inside .git, git without
# --no-ahead-behind) the old command sequence runs, so every error edge keeps
# its old answer. Submodule guard: submodules are scanned only when
# .gitmodules exists at the toplevel.
git_info() {
  local branch="" add=0 mod=0 del=0 ladd=0 ldel=0 toplevel
  # `git status` opportunistically refreshes the index, taking .git/index.lock.
  # agy kills a statusline that overruns its budget; a git killed
  # mid-refresh leaves a stale 0-byte index.lock that blocks the user's own
  # `git add`/`commit`. GIT_OPTIONAL_LOCKS=0 skips that optional write. `local`
  # + export scopes it to this function and the git children it spawns
  # (including the nested ones under `submodule foreach`).
  local GIT_OPTIONAL_LOCKS=0; export GIT_OPTIONAL_LOCKS
  # Not inside any repo (and no GIT_* env): same answer git would give, no process.
  _oma_git_walk
  [ "$_OMA_GIT_FOUND" = none ] && { printf '\t0\t0\t0\t0\t0'; return; }
  # `$(exec 2>/dev/null; git ...)` instead of `$(git ... 2>/dev/null)`: bash only
  # execs the last command of a command substitution in place (no extra fork)
  # when that command has no redirections of its own.
  local st h sub_status="" diff_stats has_sub="" l a d
  if ! st=$(exec 2>/dev/null; git status --porcelain -b -uall --no-ahead-behind); then
    _oma_git_info_legacy; return
  fi
  # Toplevel (for the .gitmodules check): the walk's root; git decides when the
  # walk could not (GIT_* env, bash < 5, cwd gone).
  if [ "$_OMA_GIT_FOUND" = repo ]; then toplevel=$_OMA_GIT_ROOT
  else toplevel=$(git rev-parse --show-toplevel 2>/dev/null); fi
  [ -n "$toplevel" ] || { _oma_git_info_legacy; return; }
  h=${st%%$'\n'*}
  case $h in
    '## HEAD (no branch)') branch= ;;
    '## No commits yet on '*) branch=${h#'## No commits yet on '}; branch=${branch%%...*} ;;
    '## Initial commit on '*) branch=${h#'## Initial commit on '}; branch=${branch%%...*} ;;
    '## '*) branch=${h#'## '}; branch=${branch%%...*} ;;
  esac
  [ -f "$toplevel/.gitmodules" ] && has_sub=1
  if [ -n "$has_sub" ]; then
    sub_status=$(git submodule foreach --quiet 'git status --porcelain -uall 2>/dev/null' 2>/dev/null)
    diff_stats=$(git diff HEAD --numstat 2>/dev/null; git submodule foreach --quiet 'git diff HEAD --numstat 2>/dev/null' 2>/dev/null)
  else
    diff_stats=$(exec 2>/dev/null; git diff HEAD --numstat)
  fi
  # Same predicates as the former grep -c: add ^A|^??, mod ^ M|^M|^AM, del ^ D|^D
  # (AM counts in both add and mod). The header and blank lines match nothing.
  while IFS= read -r l; do
    case $l in A*|'??'*) add=$((add + 1)) ;; esac
    case $l in ' M'*|M*|AM*) mod=$((mod + 1)) ;; esac
    case $l in ' D'*|D*) del=$((del + 1)) ;; esac
  done <<< "$st"$'\n'"$sub_status"
  # numstat columns are TAB-separated (paths last); binary "-" counts as 0.
  while IFS=$'\t' read -r a d _; do
    [[ $a =~ ^[0-9]+$ ]] && ladd=$((ladd + 10#$a))
    [[ $d =~ ^[0-9]+$ ]] && ldel=$((ldel + 10#$d))
  done <<< "$diff_stats"
  printf '%s\t%s\t%s\t%s\t%s\t%s' "$branch" "$add" "$mod" "$del" "$ladd" "$ldel"
}

# The pre-5.2 command sequence, kept verbatim as the fallback when
# `git status -b --no-ahead-behind` fails. Runs under git_info's exported
# GIT_OPTIONAL_LOCKS=0. Prints the 6-field line itself.
_oma_git_info_legacy() {
  local branch="" add=0 mod=0 del=0 ladd=0 ldel=0 toplevel
  if toplevel=$(git rev-parse --show-toplevel 2>/dev/null) && [ -n "$toplevel" ]; then
    branch=$(git branch --show-current 2>/dev/null)
    local status sub_status all_status diff_stats has_sub=""
    [ -f "$toplevel/.gitmodules" ] && has_sub=1
    status=$(git status --porcelain -uall 2>/dev/null)
    if [ -n "$has_sub" ]; then
      sub_status=$(git submodule foreach --quiet 'git status --porcelain -uall 2>/dev/null' 2>/dev/null)
    else
      sub_status=""
    fi
    all_status=$(printf '%s\n%s' "$status" "$sub_status")
    add=$(echo "$all_status" | grep -c '^A\|^??')
    mod=$(echo "$all_status" | grep -c '^ M\|^M\|^MM\|^AM')
    del=$(echo "$all_status" | grep -c '^ D\|^D')
    if [ -n "$has_sub" ]; then
      diff_stats=$(git diff HEAD --numstat 2>/dev/null; git submodule foreach --quiet 'git diff HEAD --numstat 2>/dev/null' 2>/dev/null)
    else
      diff_stats=$(git diff HEAD --numstat 2>/dev/null)
    fi
    ladd=$(echo "$diff_stats" | awk '{s+=$1} END {print s+0}')
    ldel=$(echo "$diff_stats" | awk '{s+=$2} END {print s+0}')
  fi
  printf '%s\t%s\t%s\t%s\t%s\t%s' "$branch" "$add" "$mod" "$del" "$ladd" "$ldel"
}

# Locate the enclosing git repo with builtins only (no git process). Sets
# _OMA_GIT_FOUND = repo | none | env | skip, plus _OMA_GIT_ROOT / _OMA_GIT_DIR /
# _OMA_GIT_COMMON (repo only) and _OMA_GIT_WD (the $PWD the result belongs to).
#   none = no repo above the cwd (and no GIT_* env): safe to skip git entirely.
#   env  = GIT_DIR/GIT_WORK_TREE/GIT_COMMON_DIR set: git decides, no shortcut.
#   skip = bash < 5 or the cwd is gone: no shortcut, no invalidation.
# Walks the PHYSICAL cwd (what git uses): bash on Linux/macOS keeps an
# inherited logical $PWD that may go through symlinks. The result is memoized
# per $PWD.
_oma_git_walk() {
  if (( BASH_VERSINFO[0] < 5 )) || ! cd -P -e . 2>/dev/null; then
    _OMA_GIT_FOUND=skip _OMA_GIT_WD= _OMA_GIT_ROOT= _OMA_GIT_DIR= _OMA_GIT_COMMON=; return 0
  fi
  [ "${_OMA_GIT_WD-}" = "$PWD" ] && [ -n "${_OMA_GIT_FOUND-}" ] && return 0
  _OMA_GIT_WD=$PWD _OMA_GIT_ROOT= _OMA_GIT_DIR= _OMA_GIT_COMMON=
  if [ -n "${GIT_DIR-}${GIT_WORK_TREE-}${GIT_COMMON_DIR-}" ]; then _OMA_GIT_FOUND=env; return 0; fi
  case $PWD in /*) ;; *) _OMA_GIT_FOUND=skip; return 0 ;; esac   # defensive; cd -P yields an absolute path
  local d=$PWD l c
  while :; do
    if [ -d "$d/.git" ]; then
      # git skips a .git dir that is not a repo and keeps walking; so do we.
      if [ -f "$d/.git/HEAD" ] && [ -d "$d/.git/objects" ]; then _OMA_GIT_DIR=$d/.git; break; fi
    elif [ -f "$d/.git" ]; then
      l=; IFS= read -r l < "$d/.git" || [ -n "$l" ] || :
      case $l in "gitdir: "*) l=${l#gitdir: } ;; *) l= ;; esac
      case $l in /*|[A-Za-z]:*) ;; ?*) l=$d/$l ;; esac
      _OMA_GIT_DIR=$l; break                      # any gitfile = found; git decides
    fi
    [ -z "$d" ] && { _OMA_GIT_FOUND=none; return 0; }
    d=${d%/*}
  done
  _OMA_GIT_ROOT=${d:-/}; _OMA_GIT_FOUND=repo; _OMA_GIT_COMMON=$_OMA_GIT_DIR
  if [ -n "$_OMA_GIT_DIR" ] && [ -f "$_OMA_GIT_DIR/commondir" ]; then
    c=; IFS= read -r c < "$_OMA_GIT_DIR/commondir" || [ -n "$c" ] || :
    case $c in /*|[A-Za-z]:*) _OMA_GIT_COMMON=$c ;; ?*) _OMA_GIT_COMMON=$_OMA_GIT_DIR/$c ;; esac
  fi
}

# Git-info cache (sets the global GI_LINE = 6 TAB fields). Keyed by the
# physical cwd. File gitcache-<key> holds "<epoch>\t<6 fields>\n"; the empty
# file gitcache-<key>.stamp is created BEFORE git runs, so any repo write during
# git_info is newer than the stamp and the next render misses.
# A hit needs: a complete line (read rc 0; a missing trailing newline = torn
# write = miss), the 7-field guard, age <= TTL, and the stamp strictly newer
# than HEAD, index, logs/HEAD, the branch ref, packed-refs and reftable's
# tables.list. So a branch switch / commit / stage shows at the next render,
# while edits to working-tree files show within the TTL. No git, no cat, no
# subshell on a hit. Non-repo dirs never run git.
_oma_cached_git_info() {
  local ttl="$GIT_CACHE_TTL" wd key file stamp line epoch age out T=$'\t' re
  case "$ttl" in ''|*[!0-9]*) ttl=10 ;; esac
  _oma_git_walk
  if [ "$_OMA_GIT_FOUND" = none ]; then GI_LINE=$'\t0\t0\t0\t0\t0'; return; fi
  if [ "$ttl" = 0 ]; then GI_LINE=$(git_info); return; fi
  if [ "$_OMA_GIT_FOUND" = skip ]; then wd=$(pwd -P 2>/dev/null)   # bash < 5 or cd failed: old key path
  else wd=$PWD; fi                                                # the walk already did `cd -P -e .`
  # cwd gone (getcwd fails): compute fresh and write nothing, so a missing cwd
  # can never poison a shared key.
  [ -n "$wd" ] || { GI_LINE=$(git_info); return; }
  key=${wd//[^A-Za-z0-9]/-}; file="$OMA_STATE_DIR/gitcache-$key"; stamp="$file.stamp"
  if [ -f "$file" ] && [ -f "$stamp" ] && IFS= read -r line < "$file"; then
    re="^(0|[1-9][0-9]{0,17})${T}[^${T}]*${T}[0-9]+${T}[0-9]+${T}[0-9]+${T}[0-9]+${T}[0-9]+$"
    if [[ $line =~ $re ]]; then
      _oma_now; epoch=${line%%"$T"*}; age=$((REPLY - epoch))
      if [ "$age" -le "$ttl" ] && _oma_git_fresh "$stamp"; then GI_LINE=${line#*"$T"}; return; fi
    fi
  fi
  [ -d "$OMA_STATE_DIR" ] || mkdir -p "$OMA_STATE_DIR" 2>/dev/null
  { : > "$stamp"; } 2>/dev/null; _oma_now; epoch=$REPLY
  out=$(git_info)
  { printf '%s\t%s\n' "$epoch" "$out" > "$file"; } 2>/dev/null
  GI_LINE=$out
}
# 0 iff the stamp ($1) is strictly newer than every existing invalidation file.
_oma_git_fresh() {
  [ "$_OMA_GIT_FOUND" = repo ] || return 0
  local gd=$_OMA_GIT_DIR cdir=$_OMA_GIT_COMMON h= f ref=
  IFS= read -r h < "$gd/HEAD" 2>/dev/null || [ -n "$h" ] || :
  case $h in "ref: "*) ref="$cdir/${h#ref: }" ;; esac
  for f in "$gd/HEAD" "$gd/index" "$gd/logs/HEAD" "$cdir/packed-refs" "$cdir/reftable/tables.list" ${ref:+"$ref"}; do
    [ -e "$f" ] || continue
    [[ $1 -nt $f ]] || return 1
  done
  return 0
}
# Printing wrapper kept for the tests (and as the old public name).
cached_git_info() { _oma_cached_git_info; printf '%s' "$GI_LINE"; }

# The NUL-delimited reads of parse_status_json (stdin = jq output). Order
# must match _OMA_JQ_FILTER.
_oma_read_status_fields() {
  IFS= read -r -d '' JSON_OK
  IFS= read -r -d '' SESSION_ID
  IFS= read -r -d '' MODEL
  IFS= read -r -d '' DIR
  IFS= read -r -d '' CTX_PCT
  IFS= read -r -d '' CTX_SIZE
  IFS= read -r -d '' RATE5_PCT
  IFS= read -r -d '' RATE5_SECS
  IFS= read -r -d '' RATE7_PCT
  IFS= read -r -d '' RATE7_SECS
  IFS= read -r -d '' ACC_EMAIL
  IFS= read -r -d '' ACC_TIER
  IFS= read -r -d '' MODE
  IFS= read -r -d '' COST
  IFS= read -r -d '' TASKS
  IFS= read -r -d '' AGENTS
}

# One jq pass over the agy statusLine payload. Display strings are stripped
# of control characters (no terminal escapes from the payload) and have
# backslashes doubled so the layouts' `echo -e` prints them literally.
# Quota: agy reports buckets such as gemini-5h / gemini-weekly / 3p-5h /
# 3p-weekly with a remaining_fraction; the meters show the USED percentage of
# the 5h and weekly bucket of one family ($fam, or derived from the model).
# A family without the bucket falls back to any "*-5h" / "*-weekly" bucket.
_OMA_JQ_FILTER='
  def clean: (. // "") | tostring | gsub("[\u0000-\u001f\u007f-\u009f]"; "")
    | gsub("^[[:space:]]+|[[:space:]]+$"; "");
  def esc: gsub("\\\\"; "\\\\");
  def num: if type == "number" and . >= 0 and . < 1e15 then floor else 0 end;
  def pick($q; $f; $s): $q[$f + "-" + $s]
    // ([$q | to_entries[] | select(.key | endswith("-" + $s)) | .value] | first);
  def used: if type != "object" or (.disabled // false) then ""
    elif (.remaining_fraction | type) == "number"
      then ((1 - .remaining_fraction) * 100 | round
            | if . < 0 then 0 elif . > 100 then 100 else . end)
    else "" end;
  def secs: if type == "object" and (.reset_in_seconds | type) == "number"
    then (.reset_in_seconds | if . < 0 then 0 else floor end) else "" end;
  ((.quota | objects) // {}) as $q
  | (if $fam == "gemini" or $fam == "3p" then $fam
     elif ((.model.id // .model.display_name // "gemini") | tostring | test("gemini"; "i")) then "gemini"
     else "3p" end) as $f
  | pick($q; $f; "5h") as $b5 | pick($q; $f; "weekly") as $b7
  | "1",
    ((.conversation_id // .session_id // "") | clean),
    ((.model.display_name // .model.id // "") | clean | esc),
    ((.workspace.current_dir // .cwd // "") | clean),
    ((.context_window.used_percentage // 0) | num),
    ((.context_window.context_window_size // 0) | num),
    ($b5 | used), ($b5 | secs), ($b7 | used), ($b7 | secs),
    (.email | clean | esc),
    (.plan_tier | clean | esc),
    (.cycle_mode | clean | esc),
    (.cost.total_usd | if type == "number" and . >= 0 and . < 1e12
       then (. * 100 | round) as $c
         | "\($c / 100 | floor).\($c % 100 | tostring | if length < 2 then "0" + . else . end)"
       else "" end),
    ((.task_count // 0) | num),
    ([(.subagents // [])[]? | objects | select(.status == "running")] | length)'

# Parse the statusLine JSON into globals: from $1 when given (tests), else
# from the inherited stdin (render path). Pure (no render side effects).
# jq is a hard dep (1.7+ for --raw-output0); when it is absent, too old or the
# input is malformed, JSON_OK stays empty and the render gate prints a notice.
# (conversation_id is empty before the first conversation, so unlike Claude
# Code the session id cannot double as the "jq worked" signal.)
parse_status_json() {
  JSON_OK=""; SESSION_ID=""; MODEL=""; DIR=""; CTX_PCT=""; CTX_SIZE=""
  RATE5_PCT=""; RATE5_SECS=""; RATE7_PCT=""; RATE7_SECS=""
  ACC_EMAIL=""; ACC_TIER=""; MODE=""; COST=""; TASKS=""; AGENTS=""
  if [ $# -gt 0 ]; then
    _oma_read_status_fields < <(jq --raw-output0 --arg fam "$QUOTA_FAMILY" "$_OMA_JQ_FILTER" <<<"$1" 2>/dev/null)
  else
    _oma_read_status_fields < <(jq --raw-output0 --arg fam "$QUOTA_FAMILY" "$_OMA_JQ_FILTER" 2>/dev/null)
  fi
  [ "$JSON_OK" = 1 ] || JSON_OK=""
  if [ "$MODEL_STRIP_EFFORT" = true ]; then
    case $MODEL in *' ('*')') MODEL="${MODEL% (*}" ;; esac
  fi
  SANITIZED_SID="${SESSION_ID//[^A-Za-z0-9_-]/_}"    # tr -c equivalent, no fork
  # Windows path → ~/relative (display): drive C only, Users case-insensitive.
  DIR="${DIR//\\//}"
  if [[ "$DIR" =~ ^[Cc]:/[Uu][Ss][Ee][Rr][Ss]/[^/]*/(.*)$ ]]; then
    DIR="~/${BASH_REMATCH[1]}"
  elif [ -n "${HOME-}" ] && [ "$HOME" != / ]; then
    case $DIR in
      "$HOME") DIR="~" ;;
      "$HOME"/*) DIR="~/${DIR#"$HOME"/}" ;;
    esac
  fi
}

# Install hint for the jq-required notice, matched to the platform the
# statusline runs on. $1 overrides $OSTYPE (tests). Builtins only.
_oma_jq_install_hint() {
  case "${1:-${OSTYPE:-}}" in
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

# Model context tag. Pure, builtin-only, `set -u` safe. The regex check
# precedes any arithmetic so CTX_SIZE is never evaluated unchecked.
# agy reports 1048576 for a 1M window, so the integer division gives [1M].
apply_model_ctx_tag() {
  [ "${MODEL_CTX_TAG-}" = true ] || return 0
  [ -n "${MODEL-}" ] || return 0
  [[ ${CTX_SIZE-} =~ ^[1-9][0-9]{0,14}$ ]] || return 0
  if [ "$CTX_SIZE" -ge 1000000 ]; then
    MODEL="${MODEL} [$((CTX_SIZE / 1000000))M]"
  fi
}

# ACCOUNT from ACCOUNT_FORMAT (agy gives email and plan_tier on stdin).
#   user (default) = local part of the email; email; tier;
#   user+tier / email+tier = "<who> (<tier>)". A missing part is dropped.
resolve_account() {
  ACCOUNT=""
  [ "$ACCOUNT_SHOW" = true ] || return 0
  local user="${ACC_EMAIL%%@*}" who
  case "$ACCOUNT_FORMAT" in
    email)      ACCOUNT="$ACC_EMAIL" ;;
    tier)       ACCOUNT="$ACC_TIER" ;;
    user+tier|email+tier)
      if [ "$ACCOUNT_FORMAT" = email+tier ]; then who=$ACC_EMAIL; else who=$user; fi
      if [ -n "$who" ] && [ -n "$ACC_TIER" ]; then ACCOUNT="$who ($ACC_TIER)"
      else ACCOUNT="${who:-$ACC_TIER}"; fi ;;
    *)          ACCOUNT="$user" ;;
  esac
}

# Compact countdown for a reset in $1 seconds -> REPLY: 45m, 2h53m, 6d22h.
# Non-numeric input -> empty.
_oma_countdown() {
  REPLY=""
  [[ ${1-} =~ ^[0-9]{1,15}$ ]] || return 0
  local s=$((10#$1))
  if [ "$s" -ge 86400 ]; then REPLY="$((s / 86400))d$((s % 86400 / 3600))h"
  elif [ "$s" -ge 3600 ]; then REPLY="$((s / 3600))h$((s % 3600 / 60))m"
  elif [ "$s" -ge 60 ]; then REPLY="$((s / 60))m"
  else REPLY="<1m"
  fi
}

# Reset suffix " (2h53m)" once a meter is above 80% used.
resolve_rate_suffixes() {
  RATE5_SUFFIX=""; RATE7_SUFFIX=""
  if [[ ${RATE5_PCT-} =~ ^[0-9]+$ ]] && [ "$RATE5_PCT" -gt 80 ]; then
    _oma_countdown "$RATE5_SECS"; [ -n "$REPLY" ] && RATE5_SUFFIX=" ($REPLY)"
  fi
  if [[ ${RATE7_PCT-} =~ ^[0-9]+$ ]] && [ "$RATE7_PCT" -gt 80 ]; then
    _oma_countdown "$RATE7_SECS"; [ -n "$REPLY" ] && RATE7_SUFFIX=" ($REPLY)"
  fi
}

# Split cached_git_info's 6 TAB fields into globals. Zero-fork. TAB→US (\x1f)
# then `IFS=$'\x1f' read`: \x1f is NOT IFS-whitespace so an empty leading
# BRANCH (non-repo / detached HEAD) is preserved.
split_gi_line() {
  local GI_LINE="$1" _gi
  _gi="${GI_LINE//$'\t'/$'\x1f'}"
  IFS=$'\x1f' read -r BRANCH ADD_FILES MOD_FILES DEL_FILES LINES_ADD \
    LINES_DEL <<<"$_gi"
}

# ---------------------------------------------------------------------------
# Render pipeline — gated so test loaders can source this file without
# blocking on stdin or triggering side-effects.
# ---------------------------------------------------------------------------
if [ -z "${OMA_TEST_LIB_ONLY:-}" ]; then

parse_status_json
if [ -z "$JSON_OK" ]; then
  printf 'oh-my-status: jq 1.7+ required (%s)\n' "$(_oma_jq_install_hint)"
  exit 0
fi
# Usage file for oh-my-knowledge auto-handoff (builtins only). Skipped until
# agy has a conversation id.
if [ -n "$SANITIZED_SID" ]; then
  [ -d "$OMA_STATE_DIR" ] || mkdir -p "$OMA_STATE_DIR" 2>/dev/null
  { printf '%s %s\n' "$CTX_PCT" "$CTX_SIZE" > "$OMA_STATE_DIR/ctx-$SANITIZED_SID"; } 2>/dev/null
fi
apply_model_ctx_tag
# Reap any crash-orphaned temp files before this render writes its own.
_oma_sweep_stale_tmp
_oma_cached_git_info
split_gi_line "$GI_LINE"
resolve_account
resolve_rate_suffixes

render

fi # end OMA_TEST_LIB_ONLY gate
