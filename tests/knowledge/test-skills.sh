#!/bin/bash
# Structural tests for the five oh-my-knowledge skills (SKILL.md text contracts).
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
# shellcheck source=../test-helpers.sh
. "$REPO_ROOT/tests/test-helpers.sh"

PLUGIN="$REPO_ROOT/plugins/oh-my-knowledge"
SKILLS="$PLUGIN/skills"
COMMON="$PLUGIN/scripts/lib/common.sh"
NAMES="kb-setup kb-lookup kb-distill kb-lint kb-handoff"

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

fail() { printf '    FAIL: %s\n' "$1" >&2; TEST_FAILED=1; }

# Commands the skills must never spell out (storage seam: scripts own git).
GIT_RE='(^|[^.[:alnum:]-])git +(add|commit|status|diff|mv|rm|log|stash|reset|checkout|push|pull|fetch|init|rev-parse|config|restore|switch|clean|show|ls-files|branch|tag|merge|worktree|rebase|blame|-C|-c)([^[:alnum:]-]|$)'

# body <file> -> stdout: everything after the closing frontmatter fence
body() { awk 'f>=2{print; next} /^---[[:space:]]*$/{f++; next} f<2 && NR==1 && !/^---/{f=2; print}' "$1"; }
# fm_value <file> <key> -> value of a top-level frontmatter key
fm_value() {
  awk -v k="$2" 'NR==1 && !/^---/{exit} /^---[[:space:]]*$/{n++; if(n==2) exit; next}
    n==1 && index($0, k ":")==1 { v=substr($0, length(k)+2); sub(/^[[:space:]]+/, "", v); sub(/\r$/, "", v); print v; exit }' "$1"
}
has() { grep -qF -- "$2" "$1" 2>/dev/null; }
need() { has "$1" "$2" || fail "$3: missing $(printf %q "$2")"; }

start_test "git-command pattern self-check"
printf '%s\n' 'run `git add x` now' > "$T/p1"
printf '%s\n' 'then git -C kb log' > "$T/p2"
printf '%s\n' 'a stale .git/index.lock' > "$T/p3"
grep -qE "$GIT_RE" "$T/p1" || fail "pattern misses \`git add x\`"
grep -qE "$GIT_RE" "$T/p2" || fail "pattern misses git -C kb log"
grep -qE "$GIT_RE" "$T/p3" && fail "pattern matches .git/index.lock"
printf '%s\n' 'then git ls-files and git worktree list' > "$T/p4"
grep -qE "$GIT_RE" "$T/p4" || fail "pattern misses git ls-files / git worktree"
printf '%s\n' 'see the git line and gitattributes' > "$T/p5"
grep -qE "$GIT_RE" "$T/p5" && fail "pattern matches prose 'git line'"
end_test

for n in $NAMES; do
  f="$SKILLS/$n/SKILL.md"
  start_test "$n: SKILL.md exists with name = folder and bilingual description"
  if [ ! -f "$f" ]; then
    fail "missing $f"
  else
    assert_eq "$n" "$(fm_value "$f" name)" "frontmatter name"
    d="$(fm_value "$f" description)"
    printf '%s' "$d" | grep -qE '[A-Za-z]{3,}' || fail "description has no ASCII word"
    printf '%s' "$d" | LC_ALL=C grep -q "$(printf '[\343-\351]')" || fail "description has no CJK character"
    sz=$(wc -c < "$f" | tr -d ' ')
    [ "$sz" -le 8192 ] || fail "SKILL.md is $sz bytes (> 8192; move detail to reference.md)"
    need "$f" "SCHEMA.md" "$n points to SCHEMA.md"
  fi
  end_test
done

start_test "all skill files: scripts exist, OMK_* exist, quoting, no git commands, no stale paths"
found=0
for f in "$SKILLS"/*/*.md; do
  [ -f "$f" ] || continue
  found=1
  rel="${f#"$SKILLS"/}"
  body "$f" > "$T/body"
  for s in $(grep -oE '<scripts>/[A-Za-z0-9_./-]+\.sh' "$f" | sort -u); do
    p="$PLUGIN/scripts/${s#<scripts>/}"
    [ -f "$p" ] || fail "$rel mentions missing script $s"
  done
  for v in $(grep -oE 'OMK_[A-Z][A-Z_]*[A-Z]' "$f" | sort -u); do
    grep -qE "(^|[^A-Z_])$v([^A-Z_]|$)" "$COMMON" || fail "$rel uses $v, not defined in common.sh"
  done
  for bad in '${user_config.' '${CLAUDE_' 'claude plugin' 'CLAUDE.md' '.claude/' '/oh-my-knowledge:' 'CLAUDE_PLUGIN_ROOT'; do
    has "$f" "$bad" && fail "$rel still carries the Claude-ism $bad"
  done
  has "$f" '--time-style' && fail "$rel uses GNU-only ls --time-style"
  if grep -nE "$GIT_RE" "$T/body" > "$T/hits"; then fail "$rel spells out git commands: $(head -3 "$T/hits")"; fi
  if grep -nE '\$[0-9]|\$ARGUMENTS' "$T/body" > "$T/hits"; then fail "$rel has argument placeholders: $(head -3 "$T/hits")"; fi
  for bad in '~/.claude/skills/' 'kb.sh'; do
    has "$T/body" "$bad" && fail "$rel mentions $bad"
  done
  case "$rel" in kb-setup/*) ;; *) has "$T/body" '~/knowledge/' && fail "$rel mentions ~/knowledge/" ;; esac
done
[ "$found" = 1 ] || fail "no skill files found"
end_test

start_test "lookup, distill, lint commit through commit.sh"
for n in kb-lookup kb-distill kb-lint; do need "$SKILLS/$n/SKILL.md" '<scripts>/commit.sh' "$n"; done
end_test

start_test "kb-setup: knowledge.conf (no userConfig), init/commit scripts, GEMINI.md include, relocation check"
f="$SKILLS/kb-setup/SKILL.md"
for p in 'knowledge.conf' '<scripts>/init.sh' '<scripts>/commit.sh' '~/.gemini/GEMINI.md' '@[rules](' 'rules/INDEX.md' 'already initialized' \
  'case "$d" in '"'~/'" '"$d/SCHEMA.md"' '"$d/.git"' 'no-history' 'rules global projects index.md _retired lint' 'GEMINI.md.bak-' \
  'Never add it without asking' 'OMK_CONF' 'KNOWLEDGE_DIR' 'AUTO_HANDOFF_THRESHOLD'; do
  need "$f" "$p" kb-setup
done
# every setting key is documented in the table
for k in KNOWLEDGE_DIR LOOKUP_REMINDER AUTO_HANDOFF AUTO_HANDOFF_THRESHOLD AUTO_HANDOFF_REPEAT LINT_STALE_DAYS LINT_FLAG_DAYS LINT_REMIND_AFTER_DISTILLS MAX_FILE_KB MAX_INDEX_LINE_CHARS; do
  need "$f" "| \`$k\` |" kb-setup
done
# run setup's relocation check with ~/ paths: ok / no-history / missing
snip="$(awk '/^d=.<new knowledge_dir>.; case/{p=1} p{print} p && /^if \[/{exit}' "$f")"
if [ -z "$snip" ]; then fail "setup relocation check snippet not found"; else
  H="$T/home"; mkdir -p "$H/kb1/.git" "$H/kb2"; : > "$H/kb1/SCHEMA.md"; : > "$H/kb2/SCHEMA.md"
  for c in 'kb1 ok' 'kb2 no-history' 'kb3 missing'; do
    rep="~/${c%% *}"
    got="$(HOME="$H" bash -c "${snip//<new knowledge_dir>/$rep}" 2>&1)"
    assert_eq "${c#* }" "$got" "relocation check for $rep"
  done
  rep='~\kb1'
  got="$(HOME="$H" bash -c "${snip//<new knowledge_dir>/$rep}" 2>&1)"
  assert_eq "ok" "$got" 'relocation check for ~\kb1'
fi
end_test

start_test "kb-setup: the conf write snippet creates, replaces and keeps lines; the show snippet prints the path"
f="$SKILLS/kb-setup/SKILL.md"
wsnip="$(awk '/^conf=.*mkdir -p/{p=1} p{print} p && /^tmp=/{exit}' "$f")"
if [ -z "$wsnip" ]; then fail "setup conf write snippet not found"; else
  C="$T/gemini-home"; rm -rf "$C"
  run_w() { # <KEY> <value>
    OMK_CONF="$C/oh-my-agy/knowledge.conf" bash -c "$(printf '%s' "$wsnip" | sed "s#^k='KNOWLEDGE_DIR'; v='<new value>'#k='$1'; v='$2'#")" >/dev/null 2>&1
  }
  # the snippet's second line sets k/v; build it explicitly
  wsnip2="$(printf '%s\n' "$wsnip" | sed "/^k=/d")"
  put() { OMK_CONF="$C/knowledge.conf" bash -c "k='$1'; v='$2'; $wsnip2" >/dev/null 2>&1; }
  put KNOWLEDGE_DIR '~/kb'; assert_eq "KNOWLEDGE_DIR=~/kb" "$(cat "$C/knowledge.conf")" "created"
  printf '# my comment\nLINT_STALE_DAYS=60\n' >> "$C/knowledge.conf"
  put KNOWLEDGE_DIR '/new/kb'
  assert_eq "$(printf '# my comment\nLINT_STALE_DAYS=60\nKNOWLEDGE_DIR=/new/kb')" "$(cat "$C/knowledge.conf")" "replaced, comments and other keys kept"
  assert_eq "/new/kb|60" "$(OMK_CONF="$C/knowledge.conf" bash -c '. "$1"; omk_config; printf "%s|%s" "$OMK_KNOWLEDGE_DIR" "$OMK_LINT_STALE_DAYS"' _ "$COMMON")" "omk_config reads what the snippet wrote"
fi
ssnip="$(awk '/^conf=.*cat "\$conf"/{print; exit}' "$f")"
[ -n "$ssnip" ] || fail "setup show snippet not found"
assert_eq "$T/x.conf" "$(OMK_CONF="$T/x.conf" bash -c "$ssnip" | head -n1)" "show snippet prints the conf path first"
end_test

start_test "kb-setup: step 1 validates the stored knowledge_dir; step 2 rejects non-absolute and quotes"
s1="$(awk '/^## 1\./{p=1; next} /^## 2\./{exit} p' "$f")"
s2="$(awk '/^## 2\./{p=1; next} /^## 3\./{exit} p' "$f")"
case "$s1" in *'`~/`'*'go straight to step 2'*) ;; *) fail "setup step 1: stored value validation / go to step 2 missing" ;; esac
case "$s1" in *'`\` into `/`'*) ;; *) fail "setup step 1: backslash normalisation missing" ;; esac
case "$s2" in *'is not absolute'*'`kb` or `./kb`'*) ;; *) fail "setup step 2: reject non-absolute missing" ;; esac
case "$s2" in *"contains \`'\`"*) ;; *) fail "setup step 2: single-quote rejection missing" ;; esac
end_test

start_test "lookup, lint, handoff, distill: exit 2 naming knowledge_dir routes to setup"
for n in kb-lookup kb-handoff kb-distill; do
  grep -F 'Exit 2 naming `knowledge_dir` or "knowledge base not found"' "$SKILLS/$n/SKILL.md" | grep -qF 'kb-setup' \
    || fail "$n: exit-2 routing to kb-setup missing"
done
grep -F 'naming `knowledge_dir` or "knowledge base not found"' "$SKILLS/kb-lint/SKILL.md" | grep -qF 'kb-setup' || fail "lint: exit-2 routing missing"
grep -F 'exit 2 bad path' "$SKILLS/kb-distill/SKILL.md" | grep -qF 'fix' || fail "distill: commit-time 'exit 2 bad path -> fix' must stay"
sz="$(wc -c < "$SKILLS/kb-distill/SKILL.md" | tr -d ' ')"
[ "$sz" -le 8192 ] || fail "distill SKILL.md is $sz bytes (> 8192)"
end_test

start_test "lookup: search sections, four write-backs, inbox-only for auto memory"
f="$SKILLS/kb-lookup/SKILL.md"
need "$f" '<scripts>/search.sh' lookup
need "$f" '== auto memory:' lookup
for p in "'verify: " "'fix: " "'flag: " "'inbox: "; do need "$f" "$p" lookup; done
need "$f" '> ⚠ UNVERIFIED (YYYY-MM-DD):' lookup
need "$f" '(omk-project)' lookup
need "$f" 'metadata.verified' lookup
end_test

start_test "distill: harvest literals, modes, promote timing, close precondition"
f="$SKILLS/kb-distill/SKILL.md"
for p in '(omk-harvested)' '(omk-project)' '[[k:' '_retired/harvested/' \
  '- Knowledge base project: [[k:projects/<p>/index]] (omk-project)' '> Moved: [[k:' \
  'second project' 'migrate this project' 'attach' 'close this project' '## Projects' \
  '## [YYYY-MM-DD] harvest |' 'lint_remind_after_distills' "'distill: "; do
  need "$f" "$p" distill
done
grep -iE 'precondition' "$f" 2>/dev/null | grep -F 'migrate this project' | grep -qF 'full harvest' \
  || fail "distill: close-mode precondition (migrate if unmapped, full harvest if mapped) not on one line"
grep -E 'exit 3' "$f" 2>/dev/null | grep -qiE 'success' || fail "distill: commit.sh exit 3 = success missing"
r="$T/distill-ref.md"; cat "$SKILLS/kb-distill/reference.md" "$SKILLS/kb-distill/modes.md" > "$r" 2>/dev/null
for p in 'date -r' 'metadata.modified' 'inferred value'; do need "$f" "$p" distill; need "$r" "$p" distill/reference.md; done
need "$f" '<scripts>/harvest-copy.sh' distill; need "$r" 'harvest-copy.sh' distill/reference.md
[ -f "$SKILLS/kb-distill/modes.md" ] || fail "distill/modes.md missing"
msz="$(wc -c < "$SKILLS/kb-distill/modes.md" 2>/dev/null | tr -d ' ')"; [ "${msz:-0}" -le 8192 ] || fail "distill/modes.md is $msz bytes (> 8192)"
need "$f" '[modes.md](modes.md)' distill
need "$r" '<backup dir>' distill/reference.md
need "$r" '<name>.2.md' distill/reference.md
grep -F 'already exists' "$f" 2>/dev/null | grep -qF 'attach <p>' || fail "distill: migrate rule 'projects/<p>/ already exists -> attach <p>' missing"
grep -F 'already exists' "$r" 2>/dev/null | grep -qF 'attach <p>' || fail "reference: migrate rule 'already exists -> attach <p>' missing"
grep -F 'invalid marker' "$r" 2>/dev/null | grep -qF 'never add a second marker' || fail "reference: attach with invalid marker replaces it"
need "$r" 'demo-old' distill/reference.md
end_test

start_test "distill: always-on directive outcomes (spec C rule path, spec G project always-on)"
f="$SKILLS/kb-distill/SKILL.md"; r="$T/distill-ref.md"; cat "$SKILLS/kb-distill/reference.md" "$SKILLS/kb-distill/modes.md" > "$r" 2>/dev/null
need "$f" 'always-on directive' distill
grep -F 'always-on directive' "$f" 2>/dev/null | grep -F 'duplicate' | grep -qF 'all knowledge' || fail "distill: always-on row must state precedence over duplicate/all knowledge"
grep -F '<n> always-on' "$f" 2>/dev/null | grep -qF '<n> retired' || fail "distill: harvest log line lacks <n> always-on"
need "$f" 'copy-and-verify' distill
need "$f" '<scripts>/check-move.sh' distill; need "$f" '--spans-only' distill; need "$f" 'not success' distill; need "$f" 'no KB page links it' distill
need "$r" 'outside inline code' distill/reference.md; need "$r" 'on purpose' distill/reference.md; need "$r" 'extra target' distill/reference.md
grep -F 'Obsolete / not worth keeping' "$r" 2>/dev/null | grep -qF 'links it' || fail "distill: reference obsolete line must mention that a page links it"
need "$f" '- always-on rule → [[k:rules/<slug>]] (omk-harvested)' distill
need "$f" '> Moved: [[k:rules/<slug>]]' distill
# G: no tags anywhere
if grep -rnE 'omk: always-on|always-on-declined' "$PLUGIN/skills" "$PLUGIN/templates" "$PLUGIN/scripts/lib/lint-content.awk" >/dev/null 2>&1; then
  fail "an omk: always-on / always-on-declined tag is still mentioned in skills, SCHEMA template or lint awk"
fi
# G1: project always-on row (SKILL.md) and steps (reference.md)
grep -F 'always-on directive' "$f" 2>/dev/null | grep -qF 'projects/<p>/always-on.md' || fail "distill: always-on row lacks projects/<p>/always-on.md"
need "$f" '- always-on (this project) → [[k:projects/<p>/always-on]] (omk-harvested)' distill
need "$f" '> Moved: [[k:projects/<p>/always-on]]' distill
need "$f" 'make X a global rule' distill
need "$f" '改成全域規則' distill
grep -E '^description:' "$f" | grep -qF 'make X a global rule' || fail "distill: description lacks the 'make X a global rule' trigger"
grep -E '^description:' "$f" | grep -qF '改成全域規則' || fail "distill: description lacks 改成全域規則"
for p in 'rules/INDEX.md' 'setup step 6' '@[<slug>](<slug>.md)' \
  '- always-on rule → [[k:rules/<slug>]] (omk-harvested)' '> Moved: [[k:rules/<slug>]]' 'reuse' \
  'projects/<p>/always-on.md' '- always-on (this project) → [[k:projects/<p>/always-on]] (omk-harvested)' \
  '> Moved: [[k:projects/<p>/always-on]]' 'same directive' 'dedupe' 'stub' 'projects/<p>/index.md' \
  'no line' 'exact pointer line' 'make X a global rule' 'Never delete' 'last line' 'log.md' \
  'rules/INDEX.md' 'verified' 'user declines' 'change X' 'drop X' 'Closed'; do
  need "$r" "$p" distill/reference.md
done
grep -F 'rules/<slug>.md' "$r" 2>/dev/null | grep -F 'verified' | grep -qF 'ask the user' || fail "reference: always-on rule proposal must carry verified frontmatter and ask the user"
for o in 'all knowledge' 'mixed' 'duplicate' 'obsolete' 'always-on rule' 'project always-on' 'redirect stub'; do
  grep -F 'Copy-and-verify' "$r" 2>/dev/null | grep -qF "$o" || fail "reference: copy-and-verify must cover $o"
done
grep -F 'Copy-and-verify' "$r" 2>/dev/null | grep -qF 'seven' || fail "reference: copy-and-verify must say seven outcomes"
grep -F '<n> always-on' "$r" 2>/dev/null | grep -qF 'project always-on' || fail "reference: <n> always-on counting must include project always-on outcomes"
grep -E 'say .make X a global rule' "$r" 2>/dev/null | grep -qiE 'report' || fail "reference: report must carry the promote hint"
grep -F 'make X a global rule' "$r" 2>/dev/null | grep -qF 'rules-include check' || fail "reference: promote must run the rules-include check"
grep -F 'Never delete' "$r" 2>/dev/null | grep -qF 'page' || fail "reference: never-delete line must name the page"
grep -F 'commit' "$r" 2>/dev/null | grep -F 'projects/<p>/always-on.md' | grep -qF 'rules/INDEX.md' || fail "reference: promote commit list (rule, INDEX, always-on page, log) missing"
grep -F 'last line' "$r" 2>/dev/null | grep -qF '> Moved: [[k:rules/<slug>]]' || fail "reference: stub on last promote missing"
grep -F 'tub page' "$r" 2>/dev/null | grep -qF 'restore' || fail "reference: appending to a stub page must restore it and its index line"
need "$f" 'carry no conclusion' distill
# review pins (M1, M3, M4, M5)
grep -F 'user declines the include offer' "$r" 2>/dev/null | grep -qF 'project always-on' || fail "reference: a declined import offer must lead to project always-on"
grep -F 'user declines the rule' "$r" 2>/dev/null | grep -qF 'project always-on' || fail "reference: a declined rule must lead to project always-on"
grep -F 'exact pointer line' "$r" 2>/dev/null | grep -qF 'remove this file' || fail "reference: pointer-line dedupe must remove this file's line"
grep -F 'the user declines → stop' "$r" 2>/dev/null | grep -qF 'nothing changes' || fail "reference: promote with a declined import must stop, nothing changes"
need "$r" 'does not change `verified`' distill/reference.md
grep -F 'Page missing' "$r" 2>/dev/null | grep -qF 'index line' || fail "reference: page creation must add the index line"
grep -F 'delete the page' "$r" 2>/dev/null | grep -qF 'Never delete the page' || fail "reference: never-delete wording missing"
[ -z "$(grep -F 'delete the page' "$r" 2>/dev/null | grep -vF 'Never delete the page')" ] || fail "reference: a line allows deleting the always-on page"
grep -F 'index line stays' "$r" 2>/dev/null | grep -qF 'repoint' || fail "reference: promoted page keeps its index line"
grep -F 'only if it was removed or repointed' "$r" 2>/dev/null | grep -qF 'Stub page' || fail "reference: stub restore only when the index line was removed or repointed"
grep -F 'reuse that rule' "$r" 2>/dev/null | grep -qF 'existing rule' || fail "reference: promote reuses an existing rule"
grep -F 'detail link' "$r" 2>/dev/null | grep -qF 'global/' || fail "reference: promote must drop or replace [[k:projects/…]] detail links"
f="$SKILLS/kb-distill/SKILL.md"
need "$f" 'ask first' distill
need "$f" 'make X a global rule / change X / drop X' distill
need "$f" 'After **every** `MEMORY.md` write, re-check the marker line' distill
grep -E '^Report:' "$f" | grep -qF 'always-on promote hint' || fail "distill: report line lacks the always-on promote hint"
end_test

start_test "templates/SCHEMA.md and lint skill carry the always-on.md convention (spec G4)"
S="$PLUGIN/templates/SCHEMA.md"; f="$SKILLS/kb-lint/SKILL.md"
need "$S" 'always-on.md' SCHEMA
need "$S" 'no_promote' SCHEMA
need "$S" 'never link into `_retired/`' SCHEMA
grep -F 'always-on.md' "$S" | grep -qF 'reserved' || fail "SCHEMA: always-on.md must be a reserved slug"
grep -F 'always-on.md' "$S" | grep -qF 'session start' || fail "SCHEMA: always-on.md loaded at session start"
need "$f" 'always-on.md' lint
grep -F 'always-on.md' "$f" | grep -qiE 'informational|not a finding' || fail "lint: always-on counts must be informational"
grep -F 'stub_unreferenced' "$f" | grep -qF 'never offer it for retirement' || fail "lint: stub_unreferenced must exclude always-on.md"
grep -F 'Never retire' "$f" | grep -qF 'always-on.md' || fail "lint: retire section must exclude always-on.md"
end_test

start_test "lint: script stage, subagent groups, report, retire, harvested marker"
f="$SKILLS/kb-lint/SKILL.md"
for p in '<scripts>/lint.sh' '(omk-harvested)' '(omk-project)' 'lint/lint-YYYY-MM-DD.md' '_retired/YYYY-MM-DD/' \
  'REPORT.md' "'lint: "; do
  need "$f" "$p" lint
done
need "$f" 'missing_path' lint
need "$f" 'absolute native path' lint
need "$f" 'batches' lint
need "$f" 'lower recall' lint
grep -F '`promote_candidate`' "$f" | grep -qF 'no_promote' || fail "lint: promote_candidate row must mention no_promote"
need "$f" 'Concurrent subagent limit reached' lint
need "$f" 'at most 20' lint
need "$f" 'foreground' lint
grep -F 'batches' "$f" | grep -qF 'in parallel' && fail "lint: batches must go in waves, not 'in parallel'"
lr="$SKILLS/kb-lint/reference.md"
[ -f "$lr" ] || fail "lint/reference.md missing"
need "$lr" 'REPORT.md' lint/reference.md; need "$lr" '(`mv`)' lint/reference.md
need "$f" '[reference.md](reference.md)' lint
sz="$(wc -c < "$lr" 2>/dev/null | tr -d ' ')"; [ "${sz:-0}" -le 8192 ] || fail "lint/reference.md is $sz bytes (> 8192)"
need "$f" 'link_into_retired' lint; need "$f" 'suspect_link_rewrite' lint
need "$lr" 'never `_retired/`' lint/reference.md
has "$lr" 'or the retired copy' && fail "lint/reference.md still offers a stub to the retired copy"
grep -F '`missing_path`' "$f" | grep -qF 'report only' || fail "lint: missing_path row must be report only"
grep -F '`broken_link`' "$f" | grep -qF 'backticks or a fence' || fail "lint: broken_link row must mention backticks or a fence"
awk '/^## 3\. Mechanical fixes/{m=NR} /^## 4\. Report/{r=NR} END{exit !(m && r && m < r)}' "$f" || fail "lint: report must come after the mechanical fixes"
end_test

start_test "handoff: status section only, marker, distill, handoff-<sid>, clear/compact"
f="$SKILLS/kb-handoff/SKILL.md"
for p in '## ⚡ 現況' '(omk-project)' 'distill' 'handoff-' 'Conversation id:' 'OMA_STATE_DIR' '/clear' '/compact'; do
  need "$f" "$p" handoff
done
need "$f" 'never the knowledge base' handoff
need "$f" 'If step 1 found a marker line' handoff
need "$f" 'auto_handoff_repeat' handoff
need "$f" 'Keep every existing line in either block that is not progress' handoff
need "$f" 'never delete or reword it' handoff
need "$f" 'is progress even when it holds a link or a directive' handoff
need "$f" 'keep its position among the lines' handoff
need "$f" '(plus kept lines, below)' handoff
has "$f" 'No conclusions or pitfalls here' && fail "handoff: old 'No conclusions or pitfalls here' wording is back"
need "$f" 'Do not add new conclusions or pitfalls' handoff
end_test

start_test "handoff step 4: marker gets max(r, c); 0 only when both invalid"
f="$SKILLS/kb-handoff/SKILL.md"
snip="$(awk '/^## 4\./{s=1; next} s && /^```bash/{p=1; next} p && /^```/{exit} p{print}' "$f")"
if [ -z "$snip" ]; then fail "handoff step 4 snippet not found"; else
  pat='<conversation id>'
  # run_h <marker|-> <ctx|-> -> prints stdout line, then the marker file content
  run_h() {
    local sd="$T/h-state"; rm -rf "$sd"; mkdir -p "$sd"
    [ "$1" = - ] || printf '%b' "$1" > "$sd/handoff-s_1"
    [ "$2" = - ] || printf '%b' "$2" > "$sd/ctx-s_1"
    OMA_STATE_DIR="$sd" bash -c "${snip//"$pat"/s/1}" >"$T/h-out" 2>&1
    printf '%s|%s' "$(tr -d '\r' < "$T/h-out")" "$(cat "$sd/handoff-s_1" 2>/dev/null | tr -d '\r')"
  }
  assert_eq "marker written: 80|80" "$(run_h '80\n' '60 200000\n')" "r > c"
  assert_eq "marker written: 75|75" "$(run_h '20\n' '75 200000\n')" "c > r"
  assert_eq "marker written: 0|0" "$(run_h 'abc\n' 'xyz 1\n')" "both invalid"
  assert_eq "marker written: 0|0" "$(run_h '150\n' '1000 200000\n')" "both out of range"
  assert_eq "marker written: 0|0" "$(run_h '' '')" "both empty"
  assert_eq "marker written: 0|0" "$(run_h - -)" "neither file"
  assert_eq "marker written: 75|75" "$(run_h '' '75 200000\r\n')" "empty marker, CRLF ctx"
  assert_eq "marker written: 72|72" "$(run_h '72\r\n' '10 200000\n')" "CRLF marker"
  assert_eq "marker written: 40|40" "$(run_h '00000000000000000090\n' '40 200000\n')" "20-digit marker invalid"
  assert_eq "marker written: 40|40" "$(run_h '30\n' '040 200000\n')" "leading zero ctx parsed base 10"
  assert_eq "marker written: 55|55" "$(run_h '55\n' ' 200000\n')" "ctx with empty first token"
  out="$(OMA_STATE_DIR="$T/h-state2" bash -c "$snip" 2>&1)"
  assert_eq "no conversation id; marker skipped" "$out" "unsubstituted sid skipped"
  [ -e "$T/h-state2" ] && fail "unsubstituted sid created state dir"
fi
end_test


start_test "distill/handoff: round-2 harvest safety (spec A)"
r="$SKILLS/kb-distill/reference.md"; f="$SKILLS/kb-distill/SKILL.md"; h="$SKILLS/kb-handoff/SKILL.md"; S="$PLUGIN/templates/SCHEMA.md"
sz="$(wc -c < "$r" | tr -d ' ')"
[ "$sz" -le 16000 ] || fail "reference.md is $sz bytes (> 16000)"
# same <file> <label> <needle>... : one line containing every needle
same() {
  local file="$1" label="$2"; shift 2
  local out; out="$(grep -F -- "$1" "$file" 2>/dev/null)"; shift
  local n; for n in "$@"; do out="$(printf '%s\n' "$out" | grep -F -- "$n")"; done
  [ -n "$out" ] || fail "$label: no single line has all needles"
}
same "$r" "reference status heading" 'first non-blank line below' 'heading'
same "$r" "reference 已完成 next" '已完成' 'next'
same "$r" "reference exactly two blocks" 'exactly' '## ⚡' 'done block'
same "$r" "reference between blocks" 'between' 'outside the status section'
same "$r" "reference overrides SCHEMA" 'overrides' 'SCHEMA.md'
same "$r" "reference index-shaped" 'index-shaped' '(omk-harvested)'
same "$r" "reference candidate index line" '(<file>.md)' '[[<file>]]' 'no other project-memory file'
same "$r" "reference mixed unchanged" 'mixed' 'unchanged'
same "$r" "reference dedupe at most once" 'at most once' 'outside the status section'
same "$r" "reference redirect stub final target" 'redirect stub' 'final target'
same "$r" "reference cycle ask" 'cycle' 'ask'
same "$r" "reference progress file unchanged" 'progress file' 'unchanged'
need "$r" '<that page>' distill/reference.md
same "$r" "reference no progress in the KB" 'No progress in the KB' 'pending' 'to-do' 'mixed'
same "$r" "reference warning directive" '`⚠`' 'outside the status section'
need "$r" 'Read the target back' distill/reference.md
need "$r" 'distinct target' distill/reference.md
same "$r" "reference contain arrow" 'contain' '→ [[k:'
same "$r" "reference Glob Grep" 'Glob' 'Grep'
need "$r" 're-judged' distill/reference.md
for p in '600000' 'unique' 'Edit-only' 'harvest-copy.sh' 'shell=True' 'OMK_KNOWLEDGE_DIR'; do need "$r" "$p" distill/reference.md; done
same "$r" "reference coordinator commit" 'coordinator' 'commit'
for p in 'Harvest never changes a status-section line' 'verbatim' 'The marker goes after the done block, or after the `## ⚡` block without one' '-newermt' 'at most 30' '(skip if present)' 'progress file or a mixed file' 'Grep `→ \[\[k:`'; do need "$r" "$p" distill/reference.md; done
same "$r" "reference done heading" 'above the marker line' '已完成'
need "$h" 'next `##` containing 已完成 or its translation, above marker' handoff
sed -n 3p "$r" | grep -qF 'except the status section' || fail "reference line 3 lacks 'except the status section'"
phrase='first non-blank line below its heading'
grep -qF "$phrase" "$r" || fail "reference lacks shared phrase"
grep -qF "$phrase" "$h" || fail "handoff lacks shared phrase"
grep -F 'type project:' "$f" | grep -F '→ [[k:' | grep -qF 'date -r' || fail "distill: type project line lacks '→ [[k:' and 'date -r'"
grep -qF 'only files modified' "$f" && fail "distill: 'only files modified' still present"
for p in 'moved text keeps its language' 'more outcomes' 'progress-free' '<that page>'; do need "$f" "$p" distill; done
same "$h" "handoff exactly two blocks" 'exactly two blocks' 'reference.md'
same "$h" "handoff between the blocks" 'between the blocks' 'byte-identical'
need "$h" 'No done block yet' handoff
grep -qF 'status-section boundary' "$h" && fail "handoff: 'status-section boundary' still present"
same "$S" "SCHEMA status sentence" '## ⚡' 'distill reference'
end_test

start_test "supporting skill files carry no placeholders (substituted only in SKILL.md)"
for f in "$SKILLS"/*/*.md; do
  [ "${f##*/}" = SKILL.md ] && continue
  grep -qE '\$\{(CLAUDE_(PLUGIN_[A-Z_]+|SKILL_DIR|SESSION_ID)|user_config\.)' "$f" && fail "${f#"$SKILLS"/} has a \${...} placeholder"
done
grep -F 'retire:' "$SKILLS/kb-lint/SKILL.md" | grep -qF '<scripts>/commit.sh' || fail "lint: the retire commit command must stay in SKILL.md"
end_test
print_summary
