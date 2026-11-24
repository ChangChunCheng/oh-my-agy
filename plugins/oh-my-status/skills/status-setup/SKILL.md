---
name: status-setup
description: Install and configure the oh-my-status statusline in the Antigravity CLI settings, and add newly introduced config options to the user's status.conf. Use when the user wants to set up, enable, repair or update the oh-my-status statusline (invoked as /status-setup).
---

# Set up oh-my-status

All steps use the deterministic helper `~/.gemini/oh-my-agy/status/configure.sh`. Do not edit `~/.gemini/antigravity-cli/settings.json` or `status.conf` by hand. When asking the user a yes/no question, use the `ask_question` tool if it is available (options Yes / No); otherwise ask in plain chat text.

## Steps

1. Make sure the runtime is installed. If `~/.gemini/oh-my-agy/status/configure.sh` does not exist, run `bash <plugin>/scripts/setup.sh`, where `<plugin>` is the directory that contains this plugin's `plugin.json` (this skill's directory is `<plugin>/skills/status-setup/`, so the plugin directory is two levels up from this file). This copies the runtime to `~/.gemini/oh-my-agy/status/` and creates `~/.gemini/oh-my-agy/status.conf` from the template. Also run it when the user reports a broken or outdated install: it is idempotent and refreshes the copied files.
2. Check the current statusline setting: `bash ~/.gemini/oh-my-agy/status/configure.sh status`. The first output line is `none`, `ours` or `other`; the second is the current `statusLine` JSON (or `null`). If it exits non-zero (for example `jq` is missing or settings.json is not valid JSON), report the error to the user and stop.
   - `none`: ask "No statusLine configured. Add the oh-my-status statusline to your Antigravity CLI settings?" If yes, run `bash ~/.gemini/oh-my-agy/status/configure.sh install`.
   - `ours`: do not modify anything. Tell the user oh-my-status is already configured.
   - `other`: show the user the current `statusLine` JSON and ask "You already have a statusLine configured. Replace it with oh-my-status?" Only if they confirm, run the `install` subcommand (it keeps every other setting and saves the previous file as `settings.json.bak`).
   Step 3 runs in every case, whatever the answer.
3. Backfill config options added in newer plugin versions: run `bash ~/.gemini/oh-my-agy/status/configure.sh missing-keys`.
   - Empty output: tell the user their `status.conf` is already up to date and change nothing.
   - Otherwise show the missing keys and ask "Your status.conf is missing N new option(s): <keys>. Add them with their default values? Existing values are preserved." If yes, run `bash ~/.gemini/oh-my-agy/status/configure.sh backfill` and tell the user which keys were added. If no, leave the file unchanged.
4. Finish by telling the user:
   - The statusline appears on the next refresh; no restart is needed.
   - `/status-themes` previews the themes and layouts, and `/status-theme <theme> <layout>` switches them.
   - Options (quota family, account format, mode/cost/task indicators, model tag) live in `~/.gemini/oh-my-agy/status.conf`.
