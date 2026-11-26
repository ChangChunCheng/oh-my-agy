<p align="center">
  <img src="assets/logo.svg" width="128" height="128" alt="oh-my-agy logo">
</p>

<h1 align="center">oh-my-agy</h1>

<p align="center">
  <strong>See where you are. Keep what you learn.</strong><br>
  A themeable statusline and a local knowledge base for the Antigravity CLI (<code>agy</code>).
</p>

<p align="center">
  <a href="https://github.com/ChangChunCheng/oh-my-agy/releases"><img src="https://img.shields.io/badge/release-v1.0.0--rc.1-blue" alt="Release"></a>
  <a href="https://github.com/ChangChunCheng/oh-my-agy/blob/main/LICENSE"><img src="https://img.shields.io/badge/license-MIT-green" alt="License"></a>
</p>

---

<p align="center">English | <a href="README.zh-TW.md">繁體中文</a></p>

This repository ships two plugins for the [Antigravity CLI](https://antigravity.google): **oh-my-status** and **oh-my-knowledge**. It is a port of the Claude Code plugins in [oh-my-claude](https://github.com/sw-willie-wu/oh-my-claude).

## Plugins

### [oh-my-status](plugins/oh-my-status/README.md)

A themeable statusline for `agy`.

- 9 themes (`catppuccin`, `dracula`, `nord`, `gruvbox`, `tokyonight`, `onedark`, `solarized`, `rosepine`, `mygo`) and 6 layouts (`default`, `minimal`, `powerline`, `pure`, `fancy`, `mygo`), switchable on the fly.
- Model, account, directory, git branch and changes, context bar, and 5h / 7d quota meters.
- Git information is cached and invalidated as soon as `.git` refs or the index change; directories outside a repository never run `git`.

### [oh-my-knowledge](plugins/oh-my-knowledge/README.md)

A local, git-versioned knowledge base. Durable knowledge (decisions and their reasons, pitfalls, conventions, root causes) lives in one folder you own, while project progress stays in each project's memory file.

- **kb-lookup**: before answering a problem-style question, search the knowledge base and the project's memory.
- **kb-distill**: turn what the session learned into knowledge pages.
- **kb-handoff**: at the end of a session (or when the context fills up), update the project's progress, then distill.
- **kb-lint**: health check for broken links, oversize or stale pages, and leftovers.
- **kb-setup**: create or reconfigure the knowledge-base folder and its settings.

## Requirements

- `agy` (Antigravity CLI)
- bash 3.2+ (bash 5 recommended)
- `jq` 1.7+
- `git` 2.31+
- For **oh-my-knowledge** lint and search: `gawk` and GNU `find` (`findutils`).
  - macOS: `brew install gawk findutils jq` (Homebrew `gawk` / `gfind` are auto-detected without changing `PATH`; optionally add `export PATH="$(brew --prefix findutils)/libexec/gnubin:$PATH"` to `~/.zshrc`).
  - Debian/Ubuntu: `sudo apt install gawk findutils jq`
  - Windows: `winget install jqlang.jq` (Git Bash already bundles `gawk` and GNU `find`).
- A Nerd Font for the icon layouts (the `pure` layout needs none)

## Installation

Install both plugins in one command:

```
agy plugin install https://github.com/ChangChunCheng/oh-my-agy
```

Check the result with `agy plugin list`.

## First steps

**oh-my-status**

1. In `agy`, run `/status-setup`. It adds the `statusLine` entry to `~/.gemini/antigravity-cli/settings.json` after asking, keeps every other setting, and saves a backup.
2. Preview the choices with `/status-themes` (or `/status-themes layouts`).
3. Switch with `/status-theme <theme> [layout]`, for example `/status-theme tokyonight fancy`.

**oh-my-knowledge**

1. Ask the agent to run the `kb-setup` skill (for example, "set up the knowledge base"). It creates the knowledge base (default `~/knowledge`) with its own git history and offers to add the rules include to `~/.gemini/GEMINI.md`, after asking and making a backup.
2. Start a new conversation so the hooks pick up the knowledge base.

## How the two plugins work together

oh-my-status writes the context usage of each conversation to `~/.gemini/oh-my-agy/state/ctx-<conversation id>` on every render. oh-my-knowledge's `Stop` hook reads that file and, when usage reaches the configured threshold, asks the agent to run `kb-handoff` once. The two plugins share only these files. Without oh-my-status, the automatic handoff does nothing; manual handoff still works.

## Configuration

| Plugin | File | Edit with |
| --- | --- | --- |
| oh-my-status | `~/.gemini/oh-my-agy/status.conf` | `/status-theme`, or edit directly |
| oh-my-knowledge | `~/.gemini/oh-my-agy/knowledge.conf` | `kb-setup`, or edit directly |

Each file is shell-style `KEY=value`. See the plugin READMEs for every key.

## Running the tests

```
bash tests/run.sh
```

The suites use temporary directories and never touch your real `~/.gemini` or `~/knowledge`.

## Credits

oh-my-agy is ported from [oh-my-claude](https://github.com/sw-willie-wu/oh-my-claude) by sw-willie-wu and contributors, which is also MIT licensed.

## License

[MIT](LICENSE)
