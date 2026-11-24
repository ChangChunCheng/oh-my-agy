# Oh My Status

A themeable statusline for Antigravity CLI (`agy`) with 9 color themes and 6 layouts. Port of the Claude Code plugin `oh-my-status`.

## Features

- **9 themes**: `catppuccin`, `dracula`, `nord`, `gruvbox`, `tokyonight`, `onedark`, `solarized`, `rosepine`, `mygo`
- **6 layouts**: `default`, `minimal`, `powerline`, `pure`, `fancy`, `mygo`
- **Fast git status**: model, directory, branch, file and line counts, cached and invalidated immediately when `.git` refs or the index change; non-repo directories never run `git`
- **Native Antigravity metrics**: model (with a `[1M]` tag for large context windows), account (email / plan tier), context bar, 5h and 7d quota bars with a reset countdown above 80%
- **Optional extras**: execution mode (`[plan]`), estimated cost, running background tasks and subagents
- **Cross-plugin integration**: writes context usage to `~/.gemini/oh-my-agy/state/ctx-<conversation_id>` for `oh-my-knowledge` auto-handoff

## Install

Install both plugins (oh-my-status and oh-my-knowledge) in one command:

```
agy plugin install https://github.com/ChangChunCheng/oh-my-agy
```

Then run:

```
/status-setup
```

The plugin's `SessionStart` hook copies the runtime to `~/.gemini/oh-my-agy/status/` and creates `~/.gemini/oh-my-agy/status.conf` on first run. `/status-setup` then adds this to `~/.gemini/antigravity-cli/settings.json` (after asking, keeping every other setting and saving a `settings.json.bak`):

```json
"statusLine": { "type": "command", "command": "bash ~/.gemini/oh-my-agy/status/statusline.sh" }
```

Changes apply on the next statusline refresh; no restart is needed.

## Skills

| Skill | What it does |
| --- | --- |
| `/status-setup` | Installs the `statusLine` setting and backfills new config options into `status.conf` |
| `/status-themes [themes\|layouts]` | Previews every theme and layout with real colors |
| `/status-theme <theme> [layout]` | Switches theme and/or layout (`/status-theme list` shows the options) |

## Configuration

`~/.gemini/oh-my-agy/status.conf` is a shell file; edit it directly or use the skills.

| Key | Default | Meaning |
| --- | --- | --- |
| `THEME` | `catppuccin` | One of the 9 themes |
| `LAYOUT` | `fancy` | One of the 6 layouts |
| `ACCOUNT_SHOW` | `true` | Show the account segment |
| `ACCOUNT_FORMAT` | `user` | `user` (part of the email before `@`), `email`, `tier`, `user+tier`, `email+tier` |
| `ACCOUNT_ICON` | (icon) | Uncomment to override; `""` hides the icon |
| `MODEL_CTX_TAG` | `true` | Append ` [1M]` to the model when the context window is 1M or larger |
| `MODEL_STRIP_EFFORT` | `false` | Strip a trailing ` (High)` effort suffix from the model name |
| `GIT_CACHE_TTL` | `10` | Seconds a git summary is reused; `0` disables the cache |
| `QUOTA_FAMILY` | `auto` | Quota buckets for the meters: `auto` follows the model, `gemini`, or `3p` |
| `SHOW_MODE` | `true` | Show the cycle mode (`auto`, `accept-edits`, `plan`) when active |
| `SHOW_COST` | `false` | Show the estimated session spend in USD |
| `SHOW_TASKS` | `true` | Show running background tasks and subagents when above 0 |

## Quota mapping

agy reports quota buckets such as `gemini-5h`, `gemini-weekly`, `3p-5h` and `3p-weekly`, each with a `remaining_fraction`. The meters show the **used** share (`1 - remaining_fraction`), labelled `5h` and `7d`:

- `QUOTA_FAMILY=auto`: Gemini models (model id or name contains "gemini") use the `gemini-*` buckets, any other model uses `3p-*`.
- A family without the bucket falls back to any `*-5h` / `*-weekly` bucket; a missing or `disabled` bucket hides its meter.
- Above 80% used, the meter shows the time until reset, for example `(2h53m)`.

## Requirements

- bash 3.2+ (bash 5 recommended: fewer processes per refresh)
- jq 1.7+ (the statusline prints an install hint when it is missing or too old)
- git
- A Nerd Font for the icon layouts; the `pure` layout needs none

## Files

- `scripts/`: `setup.sh` (installer and SessionStart hook), `statusline.sh`, `preview.sh`, `set-theme.sh`, `configure.sh`, `lib/`
- `themes/`, `layouts/`: the color palettes and the render functions
- `oh-my-status.conf`: the config template
- Tests: `tests/status/run.sh` at the repository root
