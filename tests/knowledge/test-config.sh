#!/bin/bash
# omk_config regression table: fixed expected outputs (captured from the original
# fork-based implementation) for env/conf precedence, bool/int normalisation,
# knowledge.conf parsing and knowledge_dir forms. Also a speed guard.
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
# shellcheck source=../test-helpers.sh
. "$REPO_ROOT/tests/test-helpers.sh"

LIB="$REPO_ROOT/plugins/oh-my-knowledge/scripts/lib/common.sh"

# run_case <id> [VAR=value | conf:LINE ...] -> "id|KB|REMINDER|AUTO_HANDOFF|THRESHOLD|STALE_DAYS"
# A conf:LINE argument appends LINE to a knowledge.conf passed through OMK_CONF.
run_case() {
  local id="$1" out a cf="" envs=(); shift
  for a in "$@"; do
    case "$a" in
      conf:*) [ -n "$cf" ] || cf="$(mktemp)"; printf '%s\n' "${a#conf:}" >> "$cf" ;;
      *) envs+=("$a") ;;
    esac
  done
  [ -z "$cf" ] || envs+=("OMK_CONF=$cf")
  out="$(env -i PATH="$PATH" HOME="/h/home" "${envs[@]+"${envs[@]}"}" bash -c '. "$1"; omk_config; printf "%s|%s|%s|%s|%s" "$OMK_KNOWLEDGE_DIR" "$OMK_LOOKUP_REMINDER" "$OMK_AUTO_HANDOFF" "$OMK_AUTO_HANDOFF_THRESHOLD" "$OMK_LINT_STALE_DAYS"' _ "$LIB")"
  [ -z "$cf" ] || rm -f "$cf"
  printf '%s|%s\n' "$id" "$out"
}

actual_table() {
  run_case default
  local b t d
  for b in true TRUE True yes YES Yes on ON 1 y Y false FALSE False no No off OFF 0 n N maybe ''; do
    run_case "bool-$b" "OMK_LOOKUP_REMINDER=$b" "conf:AUTO_HANDOFF=$b"
  done
  run_case conf-env-wins OMK_AUTO_HANDOFF_THRESHOLD=55 conf:AUTO_HANDOFF_THRESHOLD=44
  run_case conf-only conf:AUTO_HANDOFF_THRESHOLD=44
  run_case conf-empty-env-falls-to-conf OMK_AUTO_HANDOFF_THRESHOLD= conf:AUTO_HANDOFF_THRESHOLD=44
  run_case conf-dquote 'conf:AUTO_HANDOFF_THRESHOLD="45"'
  run_case conf-squote "conf:AUTO_HANDOFF_THRESHOLD='46'"
  run_case conf-export 'conf:export AUTO_HANDOFF_THRESHOLD=47'
  run_case conf-spaces 'conf:  AUTO_HANDOFF_THRESHOLD = 48  '
  run_case conf-inline-comment 'conf:AUTO_HANDOFF_THRESHOLD=49 # why not'
  run_case conf-last-wins conf:AUTO_HANDOFF_THRESHOLD=41 conf:AUTO_HANDOFF_THRESHOLD=42
  run_case conf-comment-line 'conf:# AUTO_HANDOFF_THRESHOLD=99'
  run_case conf-unknown-key conf:FOO=1 conf:OMK_AUTO_HANDOFF_THRESHOLD=33
  run_case conf-crlf $'conf:AUTO_HANDOFF_THRESHOLD=43\r' $'conf:AUTO_HANDOFF=false\r'
  run_case conf-no-eval 'conf:LOOKUP_REMINDER=$(touch /h/never)' 'conf:AUTO_HANDOFF_THRESHOLD=44'
  run_case conf-missing-file OMK_CONF=/nonexistent/knowledge.conf
  for t in 10 29 70 95 abc 007 -5 '' 1.5; do
    run_case "thr-$t" "conf:AUTO_HANDOFF_THRESHOLD=$t" "OMK_LINT_STALE_DAYS=$t"
  done
  for d in '~/kb' '~' 'C:\x\y\' 'c:/x/y/' 'D:/' 'z:' '/a/b//' 'rel/dir' '/'; do
    run_case "kb-$d" "conf:KNOWLEDGE_DIR=$d"
  done
  run_case kb-quoted "conf:KNOWLEDGE_DIR='/q/kb dir'"
  run_case kb-env-over-conf OMK_KNOWLEDGE_DIR='C:/e' conf:KNOWLEDGE_DIR='D:/o'
}

EXPECTED='default|/h/home/knowledge|true|true|70|90
bool-true|/h/home/knowledge|true|true|70|90
bool-TRUE|/h/home/knowledge|true|true|70|90
bool-True|/h/home/knowledge|true|true|70|90
bool-yes|/h/home/knowledge|true|true|70|90
bool-YES|/h/home/knowledge|true|true|70|90
bool-Yes|/h/home/knowledge|true|true|70|90
bool-on|/h/home/knowledge|true|true|70|90
bool-ON|/h/home/knowledge|true|true|70|90
bool-1|/h/home/knowledge|true|true|70|90
bool-y|/h/home/knowledge|true|true|70|90
bool-Y|/h/home/knowledge|true|true|70|90
bool-false|/h/home/knowledge|false|false|70|90
bool-FALSE|/h/home/knowledge|false|false|70|90
bool-False|/h/home/knowledge|false|false|70|90
bool-no|/h/home/knowledge|false|false|70|90
bool-No|/h/home/knowledge|false|false|70|90
bool-off|/h/home/knowledge|false|false|70|90
bool-OFF|/h/home/knowledge|false|false|70|90
bool-0|/h/home/knowledge|false|false|70|90
bool-n|/h/home/knowledge|false|false|70|90
bool-N|/h/home/knowledge|false|false|70|90
bool-maybe|/h/home/knowledge|true|true|70|90
bool-|/h/home/knowledge|true|true|70|90
conf-env-wins|/h/home/knowledge|true|true|55|90
conf-only|/h/home/knowledge|true|true|44|90
conf-empty-env-falls-to-conf|/h/home/knowledge|true|true|44|90
conf-dquote|/h/home/knowledge|true|true|45|90
conf-squote|/h/home/knowledge|true|true|46|90
conf-export|/h/home/knowledge|true|true|47|90
conf-spaces|/h/home/knowledge|true|true|48|90
conf-inline-comment|/h/home/knowledge|true|true|49|90
conf-last-wins|/h/home/knowledge|true|true|42|90
conf-comment-line|/h/home/knowledge|true|true|70|90
conf-unknown-key|/h/home/knowledge|true|true|70|90
conf-crlf|/h/home/knowledge|true|false|43|90
conf-no-eval|/h/home/knowledge|true|true|44|90
conf-missing-file|/h/home/knowledge|true|true|70|90
thr-10|/h/home/knowledge|true|true|10|10
thr-29|/h/home/knowledge|true|true|29|29
thr-70|/h/home/knowledge|true|true|70|70
thr-95|/h/home/knowledge|true|true|95|95
thr-abc|/h/home/knowledge|true|true|70|90
thr-007|/h/home/knowledge|true|true|7|7
thr--5|/h/home/knowledge|true|true|70|90
thr-|/h/home/knowledge|true|true|70|90
thr-1.5|/h/home/knowledge|true|true|70|90
kb-~/kb|/h/home/kb|true|true|70|90
kb-~|/h/home|true|true|70|90
kb-C:\x\y\|/c/x/y|true|true|70|90
kb-c:/x/y/|/c/x/y|true|true|70|90
kb-D:/|/d|true|true|70|90
kb-z:|/z|true|true|70|90
kb-/a/b//|/a/b|true|true|70|90
kb-rel/dir|rel/dir|true|true|70|90
kb-/|/|true|true|70|90
kb-quoted|/q/kb dir|true|true|70|90
kb-env-over-conf|/c/e|true|true|70|90'

start_test "omk_config matches the fixed expected table"
GOT="$(actual_table)"
if [ "$GOT" != "$EXPECTED" ]; then
  printf '    FAIL: table differs:\n' >&2
  diff <(printf '%s\n' "$EXPECTED") <(printf '%s\n' "$GOT") | sed 's/^/      /' >&2
  TEST_FAILED=1
fi
end_test

start_test "omk_config: OMK_AUTO_HANDOFF_REPEAT default, precedence, int normalisation (no clamping)"
rep() { local a cf="" envs=(); for a in "$@"; do case "$a" in conf:*) [ -n "$cf" ] || cf="$(mktemp)"; printf '%s\n' "${a#conf:}" >> "$cf" ;; *) envs+=("$a") ;; esac; done; [ -z "$cf" ] || envs+=("OMK_CONF=$cf"); env -i PATH="$PATH" HOME="/h/home" "${envs[@]+"${envs[@]}"}" bash -c '. "$1"; omk_config; printf %s "$OMK_AUTO_HANDOFF_REPEAT"' _ "$LIB"; [ -z "$cf" ] || rm -f "$cf"; }
assert_eq "20" "$(rep)" "default"
assert_eq "35" "$(rep conf:AUTO_HANDOFF_REPEAT=35)" "conf"
assert_eq "25" "$(rep OMK_AUTO_HANDOFF_REPEAT=25 conf:AUTO_HANDOFF_REPEAT=35)" "env over conf"
assert_eq "35" "$(rep OMK_AUTO_HANDOFF_REPEAT= conf:AUTO_HANDOFF_REPEAT=35)" "empty env falls to conf"
assert_eq "20" "$(rep conf:AUTO_HANDOFF_REPEAT=abc)" "non-numeric -> default"
assert_eq "7" "$(rep conf:AUTO_HANDOFF_REPEAT=007)" "leading zeros normalised"
assert_eq "5" "$(rep conf:AUTO_HANDOFF_REPEAT=5)" "not clamped in config"
end_test

start_test "omk_config: ~\\ expands like ~/ (M1)"
assert_eq "/h/home/knowledge" "$(env -i PATH="$PATH" HOME="/h/home" 'OMK_KNOWLEDGE_DIR=~\knowledge' bash -c '. "$1"; omk_config; printf %s "$OMK_KNOWLEDGE_DIR"' _ "$LIB")" "~\\knowledge"
assert_eq "/h/home/a/b" "$(env -i PATH="$PATH" HOME="/h/home" bash -c '. "$1"; omk_resolve_dir "~\\a\\b"' _ "$LIB")" "resolve ~\\a\\b"
end_test

start_test "omk_config: knowledge_dir validation (M2): accepted forms leave OMK_CONFIG_ERROR empty"
cfg_err() { # <dir> [extra env…] -> "<rc>|<error>"
  local d="$1"; shift
  env -i PATH="$PATH" HOME="/h/home" "$@" "OMK_KNOWLEDGE_DIR=$d" bash -c '. "$1"; omk_config; rc=$?; printf "%s|%s" "$rc" "$OMK_CONFIG_ERROR"' _ "$LIB"
}
for d in 'C:/x' 'C:\x' 'c:' '/x' '//omk-test.invalid/share' '~' '~/x' '~\x' 'D:/'; do
  assert_eq "0|" "$(cfg_err "$d")" "accepted: $d"
done
end_test

start_test "omk_config: relative knowledge_dir is a configuration error, still returns 0"
CW="$(mktemp -d)"; mkdir -p "$CW/kb"
for d in 'kb' './kb' 'kb\x' 'rel/dir' '../kb' 'C:kb' '~user/kb'; do
  got="$(cd "$CW" && cfg_err "$d")"
  assert_eq "0|knowledge_dir must be an absolute path or start with ~/ (got: $d); run the kb-setup skill" "$got" "rejected: $d (exists in cwd: $([ -d "$CW/$d" ] && echo yes || echo no))"
done
assert_eq "0|" "$(cfg_err '/x' OMK_CONFIG_ERROR=stale)" "stale exported OMK_CONFIG_ERROR cleared for a valid dir"
got="$(env -i PATH="$PATH" HOME="/h/home" OMK_KNOWLEDGE_DIR=kb bash -c '. "$1"; omk_config; printf "%s" "$OMK_CONFIG_ERROR"' _ "$LIB")"
assert_eq "knowledge_dir must be an absolute path or start with ~/ (got: kb); run the kb-setup skill" "$got" "OMK_KNOWLEDGE_DIR env form is validated too"
rm -rf "$CW"
end_test

start_test "omk_config is fork-light (< 1 s; was ~1.7 s on Windows)"
s=$(date +%s%N)
bash -c '. "$1"; omk_config' _ "$LIB" >/dev/null 2>&1
e=$(date +%s%N)
ms=$(( (e - s) / 1000000 ))
if [ "$ms" -ge 1000 ]; then printf '    FAIL: omk_config took %d ms\n' "$ms" >&2; TEST_FAILED=1; fi
end_test

start_test "omk_today: env wins, otherwise today's date"
assert_eq "2020-01-02" "$(OMK_TODAY=2020-01-02 bash -c '. "$1"; omk_config; omk_today; printf %s "$OMK_TODAY"' _ "$LIB")" "env OMK_TODAY"
assert_eq "$(date +%F)" "$(env -u OMK_TODAY bash -c '. "$1"; omk_config; omk_today; printf %s "$OMK_TODAY"' _ "$LIB")" "default"
end_test

start_test "helpers do not shadow caller variables (p, r, t, v, up)"
OUT="$(bash -c '. "$1"; p=1; r=2; t=3; v=4; up=5; omk_native_path /a/b >/dev/null; omk_resolve_dir /a/b >/dev/null; omk_config; printf "%s%s%s%s%s" "$p" "$r" "$t" "$v" "$up"' _ "$LIB")"
assert_eq "12345" "$OUT" "caller vars untouched"
assert_eq "/a/b" "$(bash -c '. "$1"; p=x; q=y; omk_resolve_dir /a/b/' _ "$LIB")" "resolve with p/q set by caller"
end_test

start_test "omk_config leaves PWD and OLDPWD unchanged (normal cwd)"
D="$(mktemp -d)"; mkdir -p "$D/a" "$D/b" "$D/kb"
OUT="$(cd "$D/a" && cd "$D/b" && bash -c '. "$1"; a="$PWD|$OLDPWD"; OMK_KNOWLEDGE_DIR="$2" omk_config; omk_resolve_dir "$2" >/dev/null; printf "%s" "$a=$PWD|$OLDPWD"' _ "$LIB" "$D/kb")"
case "$OUT" in *"|"*"="*) BEFORE="${OUT%%=*}"; AFTER="${OUT#*=}"; assert_eq "$BEFORE" "$AFTER" "PWD|OLDPWD";; *) printf '    FAIL: bad output %q\n' "$OUT" >&2; TEST_FAILED=1;; esac
OUT="$(cd "$D/a" && bash -c '. "$1"; unset OLDPWD; omk_resolve_dir "$2" >/dev/null; printf "%s" "${OLDPWD-unset}"' _ "$LIB" "$D/kb")"
assert_eq "unset" "$OUT" "OLDPWD stays unset"
end_test

start_test "omk_config from a deleted cwd leaves PWD and OLDPWD unchanged"
mkdir -p "$D/gone"
OUT="$(cd "$D/a" && cd "$D/gone" && bash -c '. "$1"; rmdir "$2" 2>/dev/null || { printf SKIP; exit 0; }; a="$PWD|$OLDPWD"; export OMK_KNOWLEDGE_DIR="$3"; omk_config; r="$(omk_resolve_dir "$3")"; printf "%s" "$a=$PWD|$OLDPWD=$r=$OMK_KNOWLEDGE_DIR"' _ "$LIB" "$D/gone" "$D/kb" 2>/dev/null)"
if [ "$OUT" = SKIP ]; then
  printf '    (skipped: cannot remove the cwd on this platform)\n'
else
  BEFORE="${OUT%%=*}"; REST="${OUT#*=}"; AFTER="${REST%%=*}"; REST="${REST#*=}"
  assert_eq "$BEFORE" "$AFTER" "PWD|OLDPWD after deleted-cwd call"
  assert_eq "${REST%%=*}" "${REST#*=}" "resolve result == omk_config result"
  [ -n "${REST%%=*}" ] || { printf '    FAIL: empty resolve result\n' >&2; TEST_FAILED=1; }
fi
rm -rf "$D"
end_test

start_test "_omk_upper_into is ASCII-only regardless of globasciiranges"
OUT="$(bash -c 'shopt -u globasciiranges 2>/dev/null; . "$1"; _omk_upper_into u "aBcZ_d9"; printf %s "$u"' _ "$LIB")"
assert_eq "ABCZ_D9" "$OUT" "upper-case mapping (globasciiranges off)"
OUT="$(LC_ALL=en_US.UTF-8 bash -c 'shopt -u globasciiranges 2>/dev/null; . "$1"; _omk_upper_into u "aBcZ_d9"; printf %s "$u"' _ "$LIB" 2>/dev/null)"
assert_eq "ABCZ_D9" "$OUT" "upper-case mapping (en_US.UTF-8, if available)"
end_test

print_summary
