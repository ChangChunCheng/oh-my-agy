---
name: status-themes
description: Preview all oh-my-status statusline themes and layouts with real colors. Use when the user asks to see, list, browse or compare statusline themes or layouts (invoked as /status-themes).
---

# Preview oh-my-status themes and layouts

The preview script lives in the installed runtime at `~/.gemini/oh-my-agy/status/preview.sh`.

## Steps

1. If `~/.gemini/oh-my-agy/status/preview.sh` does not exist, the runtime is not installed yet. Run the plugin's setup script first: `bash <plugin>/scripts/setup.sh`, where `<plugin>` is the directory that contains this plugin's `plugin.json` (this skill's directory is `<plugin>/skills/status-themes/`, so the plugin directory is two levels up from this file). Setup also runs automatically at the start of every session once the plugin is installed.
2. Pick the mode from the user's arguments:
   - "themes" or "theme": `bash ~/.gemini/oh-my-agy/status/preview.sh themes`
   - "layouts" or "layout": `bash ~/.gemini/oh-my-agy/status/preview.sh layouts`
   - anything else, or no argument: `bash ~/.gemini/oh-my-agy/status/preview.sh all`
3. The output contains ANSI colors. Show it to the user; if the tool output is collapsed or the colors are not visible, tell them to expand the command output.
4. Finish by telling the user how to switch: `/status-theme <theme> <layout>` (changes apply on the next statusline refresh; no restart needed).
