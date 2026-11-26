# Oh My Knowledge

A local, git-versioned knowledge base for Antigravity CLI (`agy`). Durable knowledge (decisions and their reasons, pitfalls, conventions, root causes) lives in one folder you own, instead of rotting in per-project notes. The agent looks it up before answering problem-style questions, writes back what it learns, and hands off project progress at the end of a session.

Two rules keep it tidy: **project progress lives only in the project's memory file; durable knowledge lives only in the knowledge base.** Never keep two writable copies of the same knowledge.

This is the agy port of `oh-my-knowledge` from oh-my-claude.

## Quick Start

1. Install both plugins (oh-my-status and oh-my-knowledge) in one command: `agy plugin install https://github.com/ChangChunCheng/oh-my-agy`.
2. Ask the agent to run the `kb-setup` skill (for example "set up the knowledge base"). It shows the settings, creates the knowledge base (default `~/knowledge`) or recognises an existing one, commits the skeleton, and offers to add the rules include to `~/.gemini/GEMINI.md` (it always asks first and backs the file up).
3. Start a new conversation: hooks and the session-start note pick the knowledge base up.

A project is "migrated" once you ask `kb-distill` to "migrate this project" (or "attach `<p>`"), which writes an `(omk-project)` marker line into that repo's project memory. Harvest runs only for migrated projects.

## Skills

| Skill | Purpose |
|---|---|
| `kb-setup` | Set up or reconfigure: create the folder with its own git history, show and change the settings (`knowledge.conf`), add the rules include, relocate the folder. |
| `kb-lookup` | Search the knowledge base and this project's memory before answering (error, slowness, flaky test, config change). Read-only apart from four small write-backs (verify, fix, flag, inbox). |
| `kb-distill` | Turn the session's durable knowledge into pages, digest `inbox.md`, harvest the project memory, migrate/attach/close a project, promote a directive to a global rule. |
| `kb-handoff` | End of session or before the context fills: rewrite only the status section of the project's `MEMORY.md`, run `kb-distill`, mark the handoff done. |
| `kb-lint` | Health check: a script screens (broken links, oversize, stale, progress leaks, markers, unharvested memory), the agent judges flagged groups with subagents, fixes the mechanical issues, writes `lint/lint-YYYY-MM-DD.md`. |

## Hooks

`hooks.json` (plugin root, commands relative to the plugin folder):

| Event | Script | What it does |
|---|---|---|
| `SessionStart` | `hooks/session-start.sh` | Injects the knowledge-base location, the scripts folder, the conversation id, the project's `MEMORY.md` (first 200 lines) and, for a migrated project, `projects/<p>/always-on.md` directives. |
| `PreInvocation` | `hooks/lookup-reminder.sh` | First model call of a turn only (`invocationNum == 0`), once per prompt per conversation: if the prompt looks like a problem (English or Traditional Chinese wording), reminds the agent to run `kb-lookup`. |
| `Stop` | `hooks/auto-handoff.sh` | When the context usage written by oh-my-status reaches the threshold, writes the marker and continues once (`{"decision":"continue"}`) so the agent runs `kb-handoff`. Never continues from its own continuation (`continuationActive`). |

All hooks print `{}` and exit 0 on any problem or when not applicable.

## Settings

agy plugins have no settings UI, so settings live in `~/.gemini/oh-my-agy/knowledge.conf` (shell-style `KEY=value`, parsed and never executed; `kb-setup` edits it). An environment variable `OMK_<KEY>` overrides the file.

| Key | Default | Meaning |
|---|---|---|
| `KNOWLEDGE_DIR` | `~/knowledge` | The knowledge-base folder (a local git repo). Absolute, or starting with `~/`; no single quote. |
| `LOOKUP_REMINDER` | `true` | Remind the agent to run `kb-lookup` on problem-like prompts. |
| `AUTO_HANDOFF` | `true` | Ask for a handoff when context usage reaches the threshold. |
| `AUTO_HANDOFF_THRESHOLD` | `70` (30-90) | Context usage percentage that triggers the automatic handoff. |
| `AUTO_HANDOFF_REPEAT` | `20` (10-60) | After a handoff at or above the threshold, ask again once usage grew by this many points. |
| `LINT_STALE_DAYS` | `90` | A page is stale only when `metadata.verified` is older than this and it mentions a version or time-sensitive wording. |
| `LINT_FLAG_DAYS` | `14` | An `UNVERIFIED` flag older than this is reported as overdue. |
| `LINT_REMIND_AFTER_DISTILLS` | `10` | Distill reminds you to lint after this many distills. |
| `MAX_FILE_KB` | `8` | Pages and sub-indexes larger than this are flagged for splitting. |
| `MAX_INDEX_LINE_CHARS` | `200` | Index lines longer than this (characters) are flagged. |

## Project memory

Claude Code keeps per-project "auto memory"; agy has none, so this plugin keeps the equivalent outside your repositories:

```
~/.gemini/oh-my-agy/projects/<encoded repo root>/memory/MEMORY.md
```

`<encoded repo root>` is the repository root (the main repo for linked worktrees; the working directory when not in git) with every character outside `[A-Za-z0-9]` turned into `-`. `bash scripts/memory-dir.sh [--create]` prints (and creates) it. `kb-handoff` writes the status section there, `kb-distill` harvests it, the session-start hook injects it, and `scripts/search.sh` searches it. Nothing is written into your repo.

## Automatic handoff (with oh-my-status)

The two plugins share only files in `~/.gemini/oh-my-agy/state/` (`$OMA_STATE_DIR`):

- `ctx-<id>`: written by the oh-my-status statusline on every render, content `<used_pct_int> <context_window_size>\n`.
- `handoff-<id>`: the highest usage percent at which a handoff was requested or completed in this conversation. Written by the Stop hook (before it continues) and by `kb-handoff` step 4.
- `<id>` is the conversation id with every character outside `[A-Za-z0-9_-]` replaced by `_`.

The Stop hook fires when usage is at or above `AUTO_HANDOFF_THRESHOLD` and either there is no marker, or the marker is below the threshold and usage is at least 5 points past it, or the marker is at or above the threshold and usage grew by `AUTO_HANDOFF_REPEAT` points. Without oh-my-status nothing writes `ctx-<id>` and the automatic handoff silently does nothing; manual handoff works either way. oh-my-status sweeps `handoff-*` only when the matching `ctx-*` is gone or older than 24 hours.

## Folder layout of the knowledge base

```
SCHEMA.md      the maintenance contract (you may replace it, e.g. with a translation)
index.md       router: sub-indexes, project list, maintenance status
log.md         append-only timeline
inbox.md       leads waiting for distill
rules/         rules to follow without being asked; rules/INDEX.md includes each one
global/        cross-project knowledge (index_<topic>.md + topic pages)
projects/<p>/  knowledge of a migrated project (index.md + topic pages)
lint/          lint-YYYY-MM-DD.md reports
_retired/      retired files by date, with REPORT.md
```

Links: `[[slug]]` inside the base; `[[g:slug]]` = `<kb>/global/<slug>.md` and `[[k:<relpath>]]` = `<kb>/<relpath>.md` from outside it.

## Rules include

Files in `rules/` load only through one include line in your global rules file `~/.gemini/GEMINI.md` (agy inlines `@[label](path)` includes, `~/` expands to home):

```
@[rules](~/knowledge/rules/INDEX.md)
```

`rules/INDEX.md` in turn includes each rule, one `@[<slug>](<slug>.md)` per line with a path relative to itself, so moving the folder needs no rewrite there. `kb-setup` offers to add the line and keeps a dated backup. Lint flags rule files missing from the index.

## Requirements

`bash` 3.2+, `gawk`, GNU `find` (`findutils`; lint uses `find -printf`), `jq` 1.7+, `git` 2.31+. `kb-setup` checks all prerequisites via `scripts/check-deps.sh` and prints the install command if anything is missing.

- macOS: `brew install gawk findutils jq` (Homebrew `gawk` / `gfind` are auto-detected even without updating `PATH`)
- Debian/Ubuntu: `sudo apt install gawk findutils jq`
- Windows: `winget install jqlang.jq` (Git Bash includes `gawk` and GNU `find`)

## Advanced / testing

| Variable | Default | Effect |
|---|---|---|
| `OMK_<KEY>` | the setting | Override one setting (see the table). |
| `OMK_CONF` | `$OMA_HOME/knowledge.conf` | The settings file. |
| `OMA_HOME` | `~/.gemini/oh-my-agy` | Base folder of shared state and project memory. |
| `OMA_STATE_DIR` | `$OMA_HOME/state` | Where `ctx-<id>` and `handoff-<id>` live. |
| `OMK_AUTO_MEMORY_DIR` | derived from the working directory | The current project's memory directory. |
| `OMK_AUTO_MEMORY_GLOB` | `$OMA_HOME/projects/*/memory` | Where project-memory directories are found. |
| `OMK_RULES_FILE` | `~/.gemini/GEMINI.md` | The rules file lint scans for `[[g:]]` / `[[k:]]` references. |
| `OMK_TODAY`, `OMK_JQ`, `OMK_COMMIT_RETRY_DELAY` | today, `jq`, `2` | Fixed lint date, jq executable, commit lock retry delay. |

Tests (temp HOME and env overrides only; nothing under the real `~/.gemini`, `~/knowledge` or `~/.claude` is touched):

```
bash tests/knowledge/run.sh            # all groups + the cross-plugin contract test
bash tests/knowledge/run.sh hooks      # only groups whose file name contains "hooks"
```

## License

MIT
