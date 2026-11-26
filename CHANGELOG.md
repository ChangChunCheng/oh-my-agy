# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [1.0.0-rc.1] - 2026-11-26

### Added

- **oh-my-knowledge**: `scripts/check-deps.sh` prerequisite checker (run as step 0 of `kb-setup`) and shared dependency helpers (`omk_install_hint`, `omk_resolve_gawk`, `omk_resolve_gnu_find`, `omk_resolve_jq`) with unit tests (`tests/knowledge/test-deps.sh`).
- **macOS Homebrew auto-detection**: `oh-my-knowledge` scripts and hooks automatically detect `gfind` and Homebrew-installed `gawk`, `findutils`, and `jq` under `/opt/homebrew` and `/usr/local` even when `gnubin` is not prepended to `PATH`.

### Changed

- **Explicit install prompts for missing tools**:
  - `oh-my-knowledge` (`check-deps.sh`, `lint.sh`, `search.sh`, `check-move.sh`, `init.sh`, and `kb-setup` / `kb-lookup` / `kb-lint` skills) now detect missing `gawk`, GNU `find`, `jq`, or `git` and print the exact platform install command (`brew`, `apt`, `dnf`, `pacman`, `zypper`, `apk`, or `winget`).
  - `oh-my-status` (`configure.sh` and `status-setup` skill) now checks for `jq 1.7+` (`--raw-output0`) and prints the exact platform install or upgrade command.
- **Documentation**: expanded platform install instructions in `README.md`, `README.zh-TW.md`, and plugin READMEs.

### Fixed

- **README badges on GitHub web**: replaced dynamic `img.shields.io/github/*` badges (which intermittently returned HTTP 504 via GitHub Camo) with reliable static badges.

## [1.0.0-rc.0] - 2026-11-25

First release candidate: the Antigravity CLI (`agy`) port of the Claude Code plugins in [oh-my-claude](https://github.com/sw-willie-wu/oh-my-claude).

### Added

- **oh-my-status**: a themeable statusline with 9 themes (`catppuccin`, `dracula`, `nord`, `gruvbox`, `tokyonight`, `onedark`, `solarized`, `rosepine`, `mygo`) and 6 layouts (`default`, `minimal`, `powerline`, `pure`, `fancy`, `mygo`).
  - Reads the agy statusLine JSON: model with a `[1M]` tag for large context windows, account (email or plan tier), and a context meter.
  - Quota meters for the `gemini` and `3p` families (5h and weekly buckets), with a reset countdown above 80% used.
  - Optional extras: execution mode, estimated cost, and running background tasks and subagents.
  - Cached git information, invalidated when `.git` refs or the index change.
  - Skills: `status-setup`, `status-theme`, `status-themes`.
  - A `SessionStart` hook that copies the runtime and creates `status.conf` on first run.
- **oh-my-knowledge**: a local, git-versioned knowledge base.
  - Skills: `kb-setup`, `kb-lookup`, `kb-distill`, `kb-handoff`, `kb-lint`.
  - Hooks: `SessionStart` (injects the knowledge-base location and project memory), `PreInvocation` (reminds the agent to run `kb-lookup` on problem-style prompts), and `Stop` (automatic handoff).
  - Project memory kept under `~/.gemini/oh-my-agy/projects/`.
  - Settings in `~/.gemini/oh-my-agy/knowledge.conf`.
- **Cross-plugin auto-handoff**: oh-my-status writes context usage to `~/.gemini/oh-my-agy/state/ctx-<conversation id>`, which the oh-my-knowledge `Stop` hook reads to trigger `kb-handoff`.
- **Installation** in one command from the GitHub URL, which installs both plugins: `agy plugin install https://github.com/ChangChunCheng/oh-my-agy`.
- **Test suite** under `tests/`, run with `bash tests/run.sh`.
- MIT license.

### Known limitations

- No third-party marketplace manifest: agy documents none, so this repository is not published as a marketplace.
- Per-plugin subfolder install URLs are not supported; the repository URL installs both plugins.
- The `/clear` command in the TUI has not been tested live.
