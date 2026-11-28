#!/bin/bash
# Render tests: feed statusline.sh agy statusLine payloads, assert the output.
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=test-helpers.sh
. "$SCRIPT_DIR/test-helpers.sh"

PLUGIN="$REPO_ROOT/plugins/oh-my-status"
STATUSLINE="$PLUGIN/scripts/statusline.sh"
[ -n "$REAL_JQ" ] || { echo "jq is required for these tests" >&2; exit 1; }

strip_ansi() { sed -E $'s/\033\\[[0-9;]*[a-zA-Z]//g'; }

NOGIT="$OMA_TEST_ROOT/nogit"; mkdir -p "$NOGIT"

# Base payload modeled on a real agy capture. Gemini and 3p buckets differ so
# the family selection is observable:
#   gemini: 5h 50% used, weekly 10% used      3p: 5h 20% used, weekly 5% used
base_json() {
  cat <<'JSON'
{"cwd":"/tmp","session_id":"abc-123","conversation_id":"abc-123",
 "model":{"id":"Gemini 4 Neon (High)","display_name":"Gemini 4 Neon (High)","effort":"high"},
 "workspace":{"current_dir":"/tmp","project_dir":"/tmp"},
 "context_window":{"context_window_size":1048576,"used_percentage":14.24,"current_usage":null},
 "quota":{"gemini-5h":{"remaining_fraction":0.5,"reset_in_seconds":1000},
          "gemini-weekly":{"remaining_fraction":0.9,"reset_in_seconds":500000},
          "3p-5h":{"remaining_fraction":0.8,"reset_in_seconds":1000},
          "3p-weekly":{"remaining_fraction":0.95,"reset_in_seconds":500000}},
 "cycle_mode":"plan","plan_tier":"Google AI Pro","email":"jacky@example.com",
 "cost":{"total_usd":0.4156},"task_count":2,
 "subagents":[{"name":"a","status":"running"},{"name":"b","status":"running"},{"name":"c","status":"completed"}]}
JSON
}
# jqp <filter>: base payload through a jq filter.
jqp() { base_json | "$REAL_JQ" -c "$1"; }

# render <json> [VAR=val ...]: run statusline.sh with a conf made from the
# VARs (always THEME/LAYOUT=pure unless overridden), ANSI stripped.
render() {
  local json="$1"; shift
  local conf="$OMA_TEST_ROOT/render.conf"
  { printf 'THEME=catppuccin\nLAYOUT=pure\n'; local kv; for kv in "$@"; do printf '%s\n' "$kv"; done; } > "$conf"
  ( cd "$NOGIT" && printf '%s' "$json" | OMA_CONF="$conf" bash "$STATUSLINE" 2>/dev/null | strip_ansi )
}
render_raw() { local json="$1" conf="$2"; ( cd "$NOGIT" && printf '%s' "$json" | OMA_CONF="$conf" bash "$STATUSLINE" 2>/dev/null ); }
# render_checked <json> <conf> <label>: run statusline.sh and assert exit 0,
# empty stderr, and non-empty stripped stdout (returned in REPLY).
render_checked() {
  local json="$1" conf="$2" label="$3" err rc=0
  err=$(cd "$NOGIT" && printf '%s' "$json" | OMA_CONF="$conf" bash "$STATUSLINE" 2>&1 >"$OMA_TEST_ROOT/rc.out") || rc=$?
  REPLY=$(strip_ansi < "$OMA_TEST_ROOT/rc.out")
  if [ "$rc" -ne 0 ] || [ -n "$err" ] || [ -z "$REPLY" ]; then
    echo "    FAIL: $label rc=$rc err=$err" >&2
    return 1
  fi
}

printf 'Running statusline render tests\n\n'

start_test "default QUOTA_FAMILY=all: shows every quota family (gemini then 3p)"
out=$(render "$(base_json)" 'SHOW_COST=true')
assert_contains "$out" "Gemini 4 Neon (High) [1M]" "model with ctx tag"
assert_contains "$out" "ctx:14%" "context"
assert_contains "$out" "gemini 5h:50% 7d:10%" "gemini group shown"
assert_contains "$out" "3p 5h:20% 7d:5%" "3p group shown"
assert_contains "$out" "gemini 5h:50% 7d:10%  3p 5h:20% 7d:5%" "gemini ordered before 3p"
assert_contains "$out" "jacky" "account user part"
assert_not_contains "$out" "example.com" "email domain hidden by default"
end_test

start_test "QUOTA_FAMILY=all: extra families follow gemini and 3p alphabetically"
out=$(render "$(jqp '.quota["zeta-5h"]={"remaining_fraction":0.7}|.quota["alpha-weekly"]={"remaining_fraction":0.6}')")
assert_contains "$out" "gemini 5h:50% 7d:10%  3p 5h:20% 7d:5%  alpha 7d:40%  zeta 5h:30%" "ordering and partial buckets"
end_test

start_test "QUOTA_FAMILY=all: renders both groups on one line in every layout"
for ln in default fancy mygo pure powerline; do
  out=$(render "$(base_json)" "LAYOUT=$ln")
  qline=$(printf '%s\n' "$out" | grep 'gemini' | head -n 1)
  assert_contains "$qline" "gemini" "$ln shows gemini"
  assert_contains "$qline" "3p" "$ln shows 3p on same line"
  assert_contains "$qline" "50%" "$ln shows gemini 5h"
  assert_contains "$qline" "20%" "$ln shows 3p 5h"
done
out=$(render "$(base_json)" 'LAYOUT=fancy2')
qline=$(printf '%s\n' "$out" | grep 'ctx' | head -n 1)
assert_contains "$qline" "50%" "fancy2 shows primary gemini 5h on ctx line"
assert_contains "$qline" "10%" "fancy2 shows primary gemini 7d on ctx line"
assert_contains "$qline" "│  3p 5h "$'\xf3\xb0\xaa\x9f'" 20% 7d "$'\xf3\xb0\x84\xb0'" 5%" "fancy2 shows secondary 3p as 9-step circle meters on ctx line"
out=$(render "$(jqp '.model={"id":"Claude Sonnet 4","display_name":"Claude Sonnet 4"}')" 'LAYOUT=fancy2')
qline=$(printf '%s\n' "$out" | grep 'ctx' | head -n 1)
assert_contains "$qline" "20%" "fancy2 on Claude promotes 3p 5h to bars"
assert_contains "$qline" "│  gemini 5h "$'\xf3\xb0\xaa\xa1'" 50% 7d "$'\xf3\xb0\xaa\x9e'" 10%" "fancy2 on Claude demotes gemini to 9-step circle meters"
out=$(render "$(jqp '.model={"id":"gemini-2.5-pro","display_name":"Custom Model"}')" 'LAYOUT=fancy2')
qline=$(printf '%s\n' "$out" | grep 'ctx' | head -n 1)
assert_contains "$qline" "50%" "fancy2 follows model.id for primary family even when display_name differs"
assert_contains "$qline" "│  3p 5h "$'\xf3\xb0\xaa\x9f'" 20%" "fancy2 keeps 3p secondary when model.id is gemini"
out=$(render "$(base_json)" 'LAYOUT=minimal')
assert_contains "$out" "gemini 50%/10%" "minimal gemini pair"
assert_contains "$out" "3p 20%/5%" "minimal 3p pair"
end_test

start_test "QUOTA_FAMILY=auto: follows model (incl. Orchestrator -> gemini, Claude -> 3p)"
out=$(render "$(base_json)" 'QUOTA_FAMILY=auto')
assert_contains "$out" "5h:50%" "gemini 5h used"
assert_contains "$out" "7d:10%" "gemini weekly used"
assert_not_contains "$out" "5h:20%" "3p hidden in auto"
out=$(render "$(jqp '.model={"id":"Orchestrator (Neon)","display_name":"Orchestrator (Neon)"}')" 'QUOTA_FAMILY=auto')
assert_contains "$out" "5h:50%" "orchestrator maps to gemini"
out=$(render "$(jqp '.model={"id":"Claude Sonnet 4","display_name":"Claude Sonnet 4"}')" 'QUOTA_FAMILY=auto')
assert_contains "$out" "Claude Sonnet 4" "model"
assert_contains "$out" "5h:20%" "3p 5h used"
assert_contains "$out" "7d:5%" "3p weekly used"
assert_not_contains "$out" "5h:50%" "gemini hidden in auto"
end_test

start_test "QUOTA_FAMILY overrides the model-based choice"
out=$(render "$(base_json)" 'QUOTA_FAMILY=3p')
assert_contains "$out" "5h:20%" "forced 3p"
assert_not_contains "$out" "5h:50%" "only 3p"
out=$(render "$(jqp '.model={"display_name":"Claude Sonnet 4"}')" 'QUOTA_FAMILY=gemini')
assert_contains "$out" "5h:50%" "forced gemini"
assert_not_contains "$out" "5h:20%" "only gemini"
end_test

start_test "missing quota object: no 5h/7d meters, ctx still shown"
out=$(render "$(jqp 'del(.quota)')")
assert_contains "$out" "ctx:14%" "ctx"
assert_not_contains "$out" "5h:" "no 5h"
assert_not_contains "$out" "7d:" "no 7d"
assert_not_contains "$out" "gemini" "no gemini label"
end_test

start_test "auto mode: family without the bucket falls back to any *-5h bucket"
out=$(render "$(jqp '.quota |= with_entries(select(.key|startswith("3p")))')" 'QUOTA_FAMILY=auto')
assert_contains "$out" "5h:20%" "fallback to 3p-5h for a gemini model"
end_test

start_test "disabled bucket hides its meter (and whole group when all disabled)"
out=$(render "$(jqp '.quota["gemini-5h"].disabled=true')")
assert_contains "$out" "gemini 7d:10%" "gemini keeps weekly"
assert_not_contains "$out" "gemini 5h:" "disabled gemini 5h hidden"
assert_contains "$out" "3p 5h:20% 7d:5%" "3p unaffected"
out=$(render "$(jqp '.quota["3p-5h"].disabled=true|.quota["3p-weekly"].disabled=true')")
assert_contains "$out" "gemini 5h:50% 7d:10%" "gemini shown"
assert_not_contains "$out" "3p" "fully disabled family omitted"
end_test

start_test "null model renders without error"
rc=0; out=$(render "$(jqp '.model=null')") || rc=$?
assert_eq "0" "$rc" "exit 0"
assert_not_contains "$out" "null" "no literal null"
assert_contains "$out" "ctx:14%" "rest of the line renders"
end_test

start_test "garbage and empty input never fail"
out=$(render 'not json at all'); assert_contains "$out" "jq 1.7+ required" "malformed input notice"
out=$(render ''); assert_contains "$out" "jq 1.7+ required" "empty input notice"
end_test

start_test "empty conversation_id: no ctx file written"
render "$(jqp '.conversation_id=""|.session_id=""')" >/dev/null
n=$(ls "$OMA_STATE_DIR" | grep -c '^ctx-' || true)
assert_eq "0" "$n" "no ctx-* file"
ls "$OMA_STATE_DIR" | grep -q '^ctx-$' && { echo "    FAIL: ctx- file" >&2; TEST_FAILED=1; }
end_test

start_test "conversation_id present: ctx file holds '<pct> <size>'"
render "$(base_json)" >/dev/null
assert_eq "14 1048576" "$(cat "$OMA_STATE_DIR/ctx-abc-123" 2>/dev/null)" "ctx file content"
end_test

start_test "conversation_id is sanitized in the ctx file name"
render "$(jqp '.conversation_id="../x y"|.session_id="../x y"')" >/dev/null
[ -f "$OMA_STATE_DIR/ctx-___x_y" ] || { echo "    FAIL: sanitized ctx file missing: $(ls "$OMA_STATE_DIR")" >&2; TEST_FAILED=1; }
end_test

start_test "above 80% used: reset countdown suffix in all and single modes; at/below 80% none"
out=$(render "$(jqp '.quota["gemini-5h"]={"remaining_fraction":0.1,"reset_in_seconds":10418}|.quota["gemini-weekly"]={"remaining_fraction":0.05,"reset_in_seconds":597218}|.quota["3p-5h"]={"remaining_fraction":0.15,"reset_in_seconds":3720}')" 'LAYOUT=default')
assert_contains "$out" "90% (2h53m)" "gemini 5h countdown"
assert_contains "$out" "95% (6d21h)" "gemini weekly countdown"
assert_contains "$out" "85% (1h2m)" "3p 5h countdown"
out=$(render "$(jqp '.quota["gemini-5h"]={"remaining_fraction":0.2,"reset_in_seconds":10418}')" 'LAYOUT=default' 'QUOTA_FAMILY=auto')
assert_not_contains "$out" "80% (" "exactly 80% has no suffix"
end_test

start_test "countdown formats: minutes and <1m"
out=$(render "$(jqp '.quota["gemini-5h"]={"remaining_fraction":0.1,"reset_in_seconds":2700}|.quota["gemini-weekly"]={"remaining_fraction":0.0,"reset_in_seconds":30}')" 'LAYOUT=default')
assert_contains "$out" "90% (45m)" "minutes"
assert_contains "$out" "100% (<1m)" "under a minute"
end_test

start_test "CRLF in jq QUOTA_ROWS (Windows jq.exe): 7d reset countdown still parsed"
CRLF_BIN="$OMA_TEST_ROOT/crlfjq"; mkdir -p "$CRLF_BIN"
cat > "$CRLF_BIN/jq" <<EOF
#!/bin/bash
cr=\$'\r'
nl=\$'\n'
while IFS= read -r -d '' rec; do
  rec="\${rec//\$cr/}"
  printf '%s\0' "\${rec//\$nl/\${cr}\${nl}}"
done < <("$REAL_JQ" "\$@")
EOF
chmod +x "$CRLF_BIN/jq"
printf 'THEME=catppuccin\nLAYOUT=default\nQUOTA_FAMILY=all\n' > "$OMA_TEST_ROOT/crlf.conf"
out=$(cd "$NOGIT" && printf '%s' "$(jqp '.quota["gemini-5h"]={"remaining_fraction":0.1,"reset_in_seconds":10418}|.quota["gemini-weekly"]={"remaining_fraction":0.05,"reset_in_seconds":597218}')" | PATH="$CRLF_BIN:$PATH" OMA_CONF="$OMA_TEST_ROOT/crlf.conf" bash "$STATUSLINE" 2>/dev/null | strip_ansi)
assert_contains "$out" "90% (2h53m)" "5h countdown with CRLF jq"
assert_contains "$out" "95% (6d21h)" "7d countdown with CRLF jq"
end_test

start_test "MODEL_STRIP_EFFORT strips the effort suffix (before the [1M] tag)"
out=$(render "$(base_json)" 'MODEL_STRIP_EFFORT=true')
assert_contains "$out" "Gemini 4 Neon [1M]" "stripped"
assert_not_contains "$out" "(High)" "effort removed"
out=$(render "$(base_json)")
assert_contains "$out" "(High) [1M]" "kept by default"
end_test

start_test "MODEL_CTX_TAG=false drops the [1M] tag; small windows never tagged"
out=$(render "$(base_json)" 'MODEL_CTX_TAG=false'); assert_not_contains "$out" "[1M]" "tag off"
out=$(render "$(jqp '.context_window.context_window_size=200000')" SHOW_MODE=false); assert_not_contains "$out" "[" "no tag under 1M"
end_test

start_test "ACCOUNT_FORMAT: user | email | tier | user+tier | email+tier"
out=$(render "$(base_json)" 'ACCOUNT_FORMAT=user'); assert_contains "$out" "jacky  " "user"
out=$(render "$(base_json)" 'ACCOUNT_FORMAT=email'); assert_contains "$out" "jacky@example.com" "email"
out=$(render "$(base_json)" 'ACCOUNT_FORMAT=tier'); assert_contains "$out" "Google AI Pro" "tier"; assert_not_contains "$out" "jacky" "tier only"
out=$(render "$(base_json)" 'ACCOUNT_FORMAT=user+tier'); assert_contains "$out" "jacky (Google AI Pro)" "user+tier"
out=$(render "$(base_json)" 'ACCOUNT_FORMAT=email+tier'); assert_contains "$out" "jacky@example.com (Google AI Pro)" "email+tier"
out=$(render "$(jqp 'del(.email)')" 'ACCOUNT_FORMAT=user+tier'); assert_contains "$out" "Google AI Pro" "missing email drops the part"
out=$(render "$(base_json)" 'ACCOUNT_SHOW=false'); assert_not_contains "$out" "jacky" "account hidden"
end_test

start_test "extras: defaults show mode and tasks, not cost"
out=$(render "$(base_json)")
assert_contains "$out" "[plan]" "mode"
assert_contains "$out" "2 tasks" "tasks"
assert_contains "$out" "2 agents" "running subagents only (completed excluded)"
assert_not_contains "$out" '$0.42' "cost off by default"
end_test

start_test "extras: toggles"
out=$(render "$(base_json)" 'SHOW_COST=true'); assert_contains "$out" '$0.42' "cost on"
out=$(render "$(base_json)" 'SHOW_MODE=false'); assert_not_contains "$out" "[plan]" "mode off"
out=$(render "$(base_json)" 'SHOW_TASKS=false'); assert_not_contains "$out" "task" "tasks off"; assert_not_contains "$out" "agent" "agents off"
out=$(render "$(jqp '.task_count=1|.subagents=[{"status":"running"}]')"); assert_contains "$out" "1 task" "singular task"; assert_not_contains "$out" "1 tasks" "no plural"; assert_contains "$out" "1 agent" "singular agent"
out=$(render "$(jqp 'del(.cycle_mode,.cost,.task_count,.subagents)')" 'SHOW_COST=true' 'MODEL_CTX_TAG=false'); assert_not_contains "$out" "[" "nothing to show"; assert_not_contains "$out" '$' "no cost without a value"
end_test

start_test "extras: oma_extras is safe with unset and non-numeric vars"
out=$(bash -c 'set -u; . "$1"; SHOW_TASKS=true SHOW_MODE=true SHOW_COST=true; TASKS=abc AGENTS=; oma_extras; printf "[%s]" "$REPLY"' _ "$PLUGIN/scripts/lib/render-common.sh")
assert_eq "[]" "$out" "empty"
out=$(bash -c 'set -u; . "$1"; oma_extras "|"; printf "[%s]" "$REPLY"' _ "$PLUGIN/scripts/lib/render-common.sh")
assert_eq "[]" "$out" "all unset"
out=$(bash -c '. "$1"; SHOW_MODE=true SHOW_TASKS=true MODE=auto TASKS=007 AGENTS=1; oma_extras "|"; printf "%s" "$REPLY"' _ "$PLUGIN/scripts/lib/render-common.sh")
assert_eq "[auto]|7 tasks|1 agent" "$out" "custom separator, leading zeros"
end_test

start_test "control characters and backslashes in payload strings are neutralized"
out=$(render "$(jqp '.model.display_name="Evil\u001b[31m\\n Model"|.email="a\u0007b@x"')" 'ACCOUNT_FORMAT=email')
case "$out" in *$'\a'*) echo "    FAIL: BEL leaked" >&2; TEST_FAILED=1 ;; esac
assert_contains "$out" 'Evil[31m\n Model' "escape char dropped, backslash literal"
end_test

start_test "home directory is shortened to ~"
out=$(render "$(jqp ".workspace.current_dir=\"$HOME/proj\"")")
assert_contains "$out" "~/proj" "tilde"
end_test

start_test "jq missing: a notice with an install hint, exit 0"
EMPTY_BIN="$OMA_TEST_ROOT/emptybin"; mkdir -p "$EMPTY_BIN"
rc=0; out=$(cd "$NOGIT" && printf '%s' "$(base_json)" | PATH="$EMPTY_BIN" OMA_CONF=/dev/null "$BASH_BIN" "$STATUSLINE" 2>/dev/null) || rc=$?
assert_eq "0" "$rc" "exit 0"
assert_contains "$out" "oh-my-status: jq 1.7+ required" "notice"
end_test

start_test "every theme x layout renders without error"
fails=0; count=0
for t in "$PLUGIN"/themes/*.sh; do
  for l in "$PLUGIN"/layouts/*.sh; do
    tn=${t##*/}; tn=${tn%.sh}; ln=${l##*/}; ln=${ln%.sh}
    printf 'THEME=%s\nLAYOUT=%s\nSHOW_COST=true\n' "$tn" "$ln" > "$OMA_TEST_ROOT/tl.conf"
    count=$((count + 1))
    if ! render_checked "$(base_json)" "$OMA_TEST_ROOT/tl.conf" "$tn/$ln"; then fails=$((fails + 1)); fi
    case "$ln" in
      fancy2)
        case "$REPLY" in *"plan mode on (shift+tab to cycle)"*"2 tasks"*) ;; *) fails=$((fails + 1)); echo "    FAIL: $tn/$ln lacks extras: $REPLY" >&2 ;; esac ;;
      *)
        case "$REPLY" in *"[plan]"*"2 tasks"*) ;; *) fails=$((fails + 1)); echo "    FAIL: $tn/$ln lacks extras: $REPLY" >&2 ;; esac ;;
    esac
  done
done
assert_eq "0" "$fails" "failures over $count combinations"
assert_eq "63" "$count" "9 themes x 7 layouts"
end_test

start_test "missing quota object exits 0 in every layout (all and auto)"
for fam in all auto; do
  for l in "$PLUGIN"/layouts/*.sh; do
    ln=${l##*/}; ln=${ln%.sh}
    printf 'THEME=catppuccin\nLAYOUT=%s\nQUOTA_FAMILY=%s\nSHOW_MODE=false\nSHOW_TASKS=false\n' "$ln" "$fam" > "$OMA_TEST_ROOT/noq.conf"
    rc=0; out=$(cd "$NOGIT" && printf '%s' "$(jqp 'del(.quota)')" | OMA_CONF="$OMA_TEST_ROOT/noq.conf" bash "$STATUSLINE" 2>/dev/null) || rc=$?
    assert_eq "0" "$rc" "$ln/$fam missing quota exit 0"
  done
done
end_test

start_test "fancy2 layout: mode line below meters with CLI-matched TrueColor codes"
printf 'THEME=catppuccin\nLAYOUT=fancy2\nQUOTA_FAMILY=auto\n' > "$OMA_TEST_ROOT/fancy2.conf"
for pair in "auto:229;192;123" "plan:97;175;239" "accept-edits:152;195;121"; do
  m="${pair%%:*}"; rgb="${pair#*:}"
  raw=$(render_raw "$(jqp ".cycle_mode=\"$m\"")" "$OMA_TEST_ROOT/fancy2.conf")
  plain=$(printf '%s\n' "$raw" | strip_ansi)
  last_line=$(printf '%s\n' "$plain" | tail -n 1)
  ctx_line=$(printf '%s\n' "$plain" | grep 'ctx' | head -n 1)
  assert_not_contains "$ctx_line" "mode on" "$m mode not on meters line"
  assert_contains "$last_line" "$m mode on (shift+tab to cycle)" "$m mode text on bottom line"
  assert_contains "$last_line" "2 tasks" "$m tasks kept on bottom line"
  assert_contains "$raw" $'\033'"[38;2;${rgb}m" "$m TrueColor escape"
done
printf 'THEME=catppuccin\nLAYOUT=fancy2\nSHOW_MODE=false\nSHOW_TASKS=true\n' > "$OMA_TEST_ROOT/fancy2_nomode.conf"
out=$(render_raw "$(base_json)" "$OMA_TEST_ROOT/fancy2_nomode.conf" | strip_ansi)
assert_not_contains "$out" "mode on" "SHOW_MODE=false hides mode line"
assert_contains "$out" "2 tasks" "tasks still shown when SHOW_MODE=false"
end_test

start_test "every layout exits 0 when quota row is empty (startup {} / no quota / QUOTA_FAMILY=auto)"
fails=0
no_quota=$(jqp 'del(.quota)')
full_json=$(base_json)
for l in "$PLUGIN"/layouts/*.sh; do
  ln=${l##*/}; ln=${ln%.sh}
  for mode in empty_obj no_quota auto_mode; do
    case "$mode" in
      empty_obj) qf=all;  payload='{}' ;;
      no_quota)  qf=all;  payload="$no_quota" ;;
      auto_mode) qf=auto; payload="$full_json" ;;
    esac
    printf 'THEME=catppuccin\nLAYOUT=%s\nQUOTA_FAMILY=%s\n' "$ln" "$qf" > "$OMA_TEST_ROOT/eq.conf"
    if ! render_checked "$payload" "$OMA_TEST_ROOT/eq.conf" "statusline $ln/$mode"; then fails=$((fails + 1)); fi
    # Also verify render() itself returns 0 (independent of statusline.sh's trailing exit 0).
    lrc=0
    (
      cd "$NOGIT" || exit 1
      OMA_TEST_LIB_ONLY=1 OMA_CONF="$OMA_TEST_ROOT/eq.conf" . "$STATUSLINE"
      parse_status_json "$payload"
      apply_model_ctx_tag
      split_gi_line ""
      resolve_account
      resolve_rate_suffixes
      render >/dev/null
    ) || lrc=$?
    if [ $lrc -ne 0 ]; then
      fails=$((fails + 1)); echo "    FAIL: render() $ln/$mode rc=$lrc" >&2
    fi
  done
done
assert_eq "0" "$fails" "failures across all layouts with empty quota row"
end_test

start_test "unknown theme/layout fall back to defaults"
printf 'THEME=nope\nLAYOUT=nope\n' > "$OMA_TEST_ROOT/bad.conf"
out=$(render_raw "$(base_json)" "$OMA_TEST_ROOT/bad.conf" | strip_ansi)
assert_contains "$out" "14%" "default layout rendered"; assert_contains "$out" "█" "default layout bars"
end_test

# --- git summary and cache ---
gi_mkrepo() {  # $1=dir $2=branch
  mkdir -p "$1"
  ( cd "$1" && git init -q . && git config user.email t@t.t && git config user.name t \
      && echo a > f.txt && git add f.txt && git commit -qm i && git branch -m "$2" )
  fs_tick
}
render_in() {  # $1=dir ; rest = conf lines
  local dir="$1"; shift
  local conf="$OMA_TEST_ROOT/git.conf"
  { printf 'THEME=catppuccin\nLAYOUT=pure\n'; local kv; for kv in "$@"; do printf '%s\n' "$kv"; done; } > "$conf"
  ( cd "$dir" && printf '%s' "$(base_json)" | OMA_CONF="$conf" bash "$STATUSLINE" 2>/dev/null | strip_ansi )
}

start_test "git: branch and change counts shown, cached within the TTL"
G="$OMA_TEST_ROOT/repo"; gi_mkrepo "$G" omabranch
echo b >> "$G/f.txt"; echo c > "$G/new.txt"
out=$(render_in "$G" GIT_CACHE_TTL=3600)
assert_contains "$out" "(omabranch)" "branch"
assert_contains "$out" "+1" "added"
assert_contains "$out" "~1" "modified"
echo d > "$G/new2.txt"; fs_tick
out2=$(render_in "$G" GIT_CACHE_TTL=3600)
assert_eq "$out" "$out2" "second render served from cache"
out3=$(render_in "$G" GIT_CACHE_TTL=0)
assert_contains "$out3" "+2" "TTL 0 recomputes"
end_test

start_test "git: non-repo directory and detached HEAD show no branch"
out=$(render_in "$NOGIT" MODEL_STRIP_EFFORT=true); assert_not_contains "$out" "(" "no branch parens outside a repo"
D="$OMA_TEST_ROOT/det"; gi_mkrepo "$D" main
( cd "$D" && echo b > f.txt && git add f.txt && git commit -qm c2 && git checkout -q HEAD~1 )
out=$(render_in "$D" GIT_CACHE_TTL=0); assert_not_contains "$out" "(main)" "detached"
end_test

print_summary
