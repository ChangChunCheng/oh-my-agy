---
name: kb-setup
description: Use to set up or reconfigure oh-my-knowledge — create the knowledge base or point to an existing one (for example copied from another machine), show and change plugin settings, move the knowledge base, add the rules include to ~/.gemini/GEMINI.md. 設定知識庫 / 初始化知識庫 / 換位置 / 改設定 / setup knowledge base.
---

# Set up oh-my-knowledge

The knowledge base (KB) is a local folder with version history. Its maintenance contract is `<knowledge_dir>/SCHEMA.md` (the plugin's default; the user may replace it, for example with a version in their own language) — it is the authority for every writing rule. `<scripts>` = the directory named "oh-my-knowledge scripts" in the session-start note (`scripts/` in the plugin folder, two levels above this SKILL.md; it is also shown by the not-set-up notice).

Settings live in one shell-style file, `~/.gemini/oh-my-agy/knowledge.conf` (`KEY=value` lines, `#` comments; it is parsed, never executed). Environment variables `OMK_<KEY>` override it (for scripts and tests). agy has no per-plugin settings UI, so this skill is the way to change them.

## 1. Show the settings

```bash
conf="${OMK_CONF:-${OMA_HOME:-$HOME/.gemini/oh-my-agy}/knowledge.conf}"; echo "$conf"; cat "$conf" 2>/dev/null || echo "(no file yet: all defaults)"
```

List every option: the value in the file, or "unset (default …)". Check `KNOWLEDGE_DIR`: after turning `\` into `/` it must start with `/`, `X:/` or `~/`, or be `~` or `X:`. If it does not (hooks and scripts report a configuration error for it), tell the user and go straight to step 2 for a corrected value.

| key | default | meaning |
|---|---|---|
| `KNOWLEDGE_DIR` | `~/knowledge` | KB folder (absolute or `~/…`; no single quote) |
| `LOOKUP_REMINDER` | `true` | remind to look things up on problem-like prompts |
| `AUTO_HANDOFF` | `true` | ask for a handoff when context reaches the threshold (needs oh-my-status) |
| `AUTO_HANDOFF_THRESHOLD` | `70` (30–90) | context % for the automatic handoff |
| `AUTO_HANDOFF_REPEAT` | `20` (10–60) | points usage must grow before it asks again |
| `LINT_STALE_DAYS` | `90` | stale after this many days |
| `LINT_FLAG_DAYS` | `14` | an UNVERIFIED flag older than this is reported |
| `LINT_REMIND_AFTER_DISTILLS` | `10` | remind to lint after this many distills |
| `MAX_FILE_KB` | `8` | page size limit |
| `MAX_INDEX_LINE_CHARS` | `200` | index line limit (characters) |

## 2. Change settings (on request)

- Reject a `KNOWLEDGE_DIR` that is not absolute (after `\` → `/`: starts with `/`, `X:/`, or `~/`, or is `~` / `X:`): a relative path such as `kb` or `./kb` is a configuration error; ask for an absolute one.
- Reject a `KNOWLEDGE_DIR` that contains `'` (it would break single-quoted values the skills pass to scripts); ask for another path.
- Range limits: the numeric options are clamped by their consumers (the table's ranges); do not write values outside them.
- Pointing at a KB the user moved or copied (step 7): run its check **before** writing the setting.
- Write the file (create the folder first; unrelated lines and comments are kept; an existing `KEY=` line is replaced by a new one at the end):

```bash
conf="${OMK_CONF:-${OMA_HOME:-$HOME/.gemini/oh-my-agy}/knowledge.conf}"; mkdir -p "$(dirname "$conf")"
k='KNOWLEDGE_DIR'; v='<new value>'
tmp="$(mktemp)" && { grep -v "^$k=" "$conf" 2>/dev/null; printf '%s=%s\n' "$k" "$v"; } > "$tmp" && cat "$tmp" > "$conf"; rm -f "$tmp"
```

- Hooks and scripts re-read the file on every run; no restart is needed for the scripts, but a running session keeps the session-start note it already received.

## 3. Initialize or check the KB

"Changed in this run" = you wrote a `KNOWLEDGE_DIR` in step 2 that differs from the file's earlier value. Either way the scripts read the new file; to be explicit you may also pass `OMK_KNOWLEDGE_DIR='<dir>'` in the environment.

```bash
bash "<scripts>/init.sh"
```

- `initialized <dir>`: a new KB (folders `rules/ global/ projects/ lint/ _retired/`, `SCHEMA.md`, `index.md`, `log.md`, `inbox.md`, `rules/INDEX.md`, `.gitattributes`, version history; a repo-local identity only when none exists — global settings are never touched).
- `already initialized <dir>`: an existing KB, for example copied from another machine. Nothing is overwritten; only missing skeleton parts are added. `rules/` and `global/` work right away; project knowledge reconnects per repo later (kb-distill offers "attach <p>").
- Relocation (step 6) must print `already initialized` — or `initialized` when the user chose to continue a `no-history` copy; anything else → stop and tell the user (folder not moved yet, or wrong path).
- Non-zero exit: show stderr and stop.

## 4. Commit what init created

`init.sh` never commits. Commit the skeleton files:

```bash
bash "<scripts>/commit.sh" 'setup: knowledge base skeleton' SCHEMA.md index.md log.md inbox.md rules/INDEX.md .gitattributes
```

If init printed `initialized` but `rules/`, `global/`, `projects/`, `_retired/` or `lint/` already hold files (for example a `no-history` copy, step 6), list them and offer to commit them too (folders are accepted as paths; an empty folder is skipped):

```bash
bash "<scripts>/commit.sh" 'setup: existing pages' rules global projects index.md _retired lint
```

Exit 0 committed; 3 nothing new to commit = success; 4 lock held → retry later; 1 or 2 → show stderr.

## 5. Rules include in GEMINI.md (ask first)

Rules in `<knowledge_dir>/rules/` load only through one include line in the user's global rules file `~/.gemini/GEMINI.md` (agy inlines `@[label](path)` includes; a path starting with `~/` expands to the home folder):

```
@[rules](<knowledge_dir>/rules/INDEX.md)
```

(write the real path; inside the home folder prefer the `~/…` form, e.g. `@[rules](~/knowledge/rules/INDEX.md)`). If the line is missing, ask whether to add it. On yes: if the file exists, first back it up (`cp -p` to `GEMINI.md.bak-YYYYMMDD` next to it), then append the line, and tell the user where the backup is; if the file does not exist, create it with just the include line. Never add it without asking. Takes effect in the next conversation.

## 6. Moving the KB

The user moves the whole folder (including its hidden version-history folder) themselves; you never move it. Then:

1. Check the new place (a leading `~/` or `~\` is expanded like init.sh does):

```bash
d='<new knowledge_dir>'; case "$d" in '~/'*|'~\'*) d="$HOME/${d#??}" ;; esac
if [ -f "$d/SCHEMA.md" ] && [ -e "$d/.git" ]; then echo ok; elif [ -f "$d/SCHEMA.md" ]; then echo no-history; else echo missing; fi
```

   - `ok` → continue; init.sh must print `already initialized`.
   - `no-history` → explain: the KB was copied without its hidden version-history folder (`.git`). Offer to continue: init.sh then starts a new history (prints `initialized`) and step 4 commits the existing pages. Stop if the user declines.
   - `missing` → stop: the folder is not moved yet, or the path is wrong.
2. Change `KNOWLEDGE_DIR` (step 2), run `init.sh` with the new value (step 3).
3. Offer to update the include line in GEMINI.md (step 5, with backup).

Links (`[[g:…]]`, `[[k:…]]`) and the relative includes in `rules/INDEX.md` need no rewrite. Do not put the KB in a cloud-synced folder: syncing a version-history folder can corrupt it.
