---
name: kb-lookup
description: Use BEFORE replying about any problem — explaining why something is slow or broken, listing options or recommendations — when an error, failure, slowness, flaky or hanging test, or an environment/tooling/network/CI issue shows up mid-task, or before proposing a workaround or changing a system setting. Searches the knowledge base and this project's project memory first, even if the answer seems obvious. 查知識庫 / 為什麼慢 / 為什麼壞 / 怎麼了 / 怎麼辦 / 要不要改 / 錯誤 / 改系統設定前.
---

# Look it up before answering

The knowledge base (KB) at `<knowledge_dir>` holds tested conclusions; they often beat a fresh guess. `<knowledge_dir>` is the folder named in the session-start note ("Knowledge base: …") and in the first line of the search output. Links: `[[g:slug]]` = `<knowledge_dir>/global/<slug>.md`, `[[k:<relpath>]]` = `<knowledge_dir>/<relpath>.md`.

`<knowledge_dir>/SCHEMA.md` is the authority for every writing rule. Read it before any write-back.

## When

- Before answering "why is it slow / broken / what now", or before listing options or advice.
- When an error, failure, slowdown, flaky or hanging test, or a failed command shows up while working.
- Before proposing a workaround or changing any system setting.

Search first, even when you think you know the answer.

## 1. Search

Run from the session's working directory (the project is detected from it):

```bash
bash "<scripts>/search.sh" <keyword> <keyword> ...
```

- `<scripts>` = the directory named "oh-my-knowledge scripts" in the session-start note (`scripts/` in the plugin folder, two levels above this SKILL.md). Run from the session's working directory; the script derives the project memory directory from it.
- 3–6 keywords: error message fragments, tool names, symptoms, and synonyms in English and in the user's language.
- Exit 2 naming `knowledge_dir` or "knowledge base not found": tell the user to run the `kb-setup` skill, then answer without the KB.
- Exit 2 naming a missing tool (e.g. `gawk`): show the exact install command from stderr and ask the user to run it, then answer without the KB.

Output sections, in order:

| Line | Meaning |
|---|---|
| `== knowledge base: <dir>` | the KB folder (`<knowledge_dir>`) |
| `== index hits` | `rel:line:text` from the `global/` index files (`index.md`, `index_*.md`); a migrated project's index files and the project-memory `MEMORY.md` are listed in their own sections below |
| `== topic hits (file:count)` | other `global/` pages, most hits first |
| `== project: <p>` or `== project: (not migrated)` | then hits in `projects/<p>/` when this repo is migrated (its project-memory `MEMORY.md` has a valid `(omk-project)` marker line) |
| `== auto memory: <dir>` or `== auto memory: (none)` | then hits in this project's project memory (stubs skipped; `MEMORY.md` lines shown like index hits) |
| `no hits` | nothing matched anywhere |

`rules/` is not searched (already loaded), nor `_retired/` and `lint/`. With 0 hits, retry once with other keywords.

## 2. Read and answer

- Read the full text of the 1–2 best hits (most hits, closest index line). Follow `[[g:…]]` / `[[k:…]]` links when the page points elsewhere.
- A page with a `> ⚠ UNVERIFIED (…)` line: treat its conclusion as uncertain and say so.
- In the reply, say in one sentence what the KB had (or "the knowledge base has nothing on this").

## 3. Write back (only these four)

Write-backs happen only in pages inside `<knowledge_dir>` (`global/`, `projects/<p>/`). A hit in the project memory — migrated project or not — is never edited by lookup: record it in `<knowledge_dir>/inbox.md` only (case 4 shape, with the project-memory file name).

| Case | Change | Commit message |
|---|---|---|
| 1. A test you ran confirms the page | set frontmatter `metadata.verified` (nested under `metadata:`) to today | `'verify: <slug>'` |
| 2. Test evidence (command + output) proves it wrong | rewrite in place, new conclusion first, one trailing sentence "once misjudged X (because Y)"; update `metadata.verified` and `description`; log entry (below) | `'fix: <slug>'` |
| 3. Only a suspicion | keep the conclusion; add at the top of the body `> ⚠ UNVERIFIED (YYYY-MM-DD): <symptom>; evidence: <command/output or not reproduced>`; add an `inbox.md` line pointing to the page | `'flag: <slug>'` |
| 4. Not in the KB, you solved it yourself | one `inbox.md` line: situation + conclusion + evidence | `'inbox: <topic>'` |

Case 2 also appends to `log.md`:

```
## [YYYY-MM-DD] fix | <slug>
- <what changed, with the evidence command>
```

- Evidence follows SCHEMA's path rule: no real-user home directories or local repo locations; use repo-relative paths, `~/…` for tool-standard locations, `<user>` as placeholder.
- Write knowledge in the user's language (match the existing page).

One commit per write-back, passing only the files you changed (KB-relative paths, exact on-disk case):

```bash
bash "<scripts>/commit.sh" 'fix: <slug>' global/<slug>.md log.md
```

- The message is single-quoted: never put a `'` inside it. No AI attribution, no session links.
- Exit 0 = committed; 3 = nothing to commit, counts as success (another session committed it along); 4 = lock still held: tell the user, retry later; 2 = bad path or usage (fix and rerun); 1 = other failure: report stderr.
