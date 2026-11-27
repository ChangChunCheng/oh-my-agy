---
name: status-theme
description: Switch the oh-my-status statusline theme and/or layout, or list the available ones. Use when the user wants to change, set or show the statusline theme or layout (invoked as /status-theme <theme> <layout>).
---

# Switch oh-my-status theme and layout

The helper lives in the installed runtime at `~/.gemini/oh-my-agy/status/set-theme.sh`. It validates the names against the installed themes and layouts and rewrites only the `THEME=` / `LAYOUT=` lines of `~/.gemini/oh-my-agy/status.conf`.

## Steps

1. If `~/.gemini/oh-my-agy/status/set-theme.sh` does not exist, the runtime is not installed yet. Run `bash <plugin>/scripts/setup.sh` first, where `<plugin>` is the directory that contains this plugin's `plugin.json` (this skill's directory is `<plugin>/skills/status-theme/`, so the plugin directory is two levels up from this file).
2. Always start by showing the current settings and the options:
   `bash ~/.gemini/oh-my-agy/status/set-theme.sh list`
3. Apply the user's arguments:
   - no arguments or `list`: stop after step 2 and describe the layouts below.
   - one argument that is a theme name: `bash ~/.gemini/oh-my-agy/status/set-theme.sh <theme>`
   - one argument that is a layout name: `bash ~/.gemini/oh-my-agy/status/set-theme.sh <layout>`
   - two arguments: the first is the theme, the second the layout: `bash ~/.gemini/oh-my-agy/status/set-theme.sh <theme> <layout>`
   - `mygo` is both a theme and a layout; given alone it sets both.
   - `preview`: run `bash ~/.gemini/oh-my-agy/status/preview.sh layouts` instead.
   If the script reports an unknown name, show its list of valid names and ask the user which they meant.
4. Confirm what was set, using the script's output. Tell the user the change applies on the next statusline refresh; no restart is needed.

## Layouts

- `default`: two lines with icons and progress bars
- `minimal`: single compact line
- `powerline`: arrow separators (needs a Nerd Font)
- `pure`: plain text, no icons, no Nerd Font needed
- `fancy`: three lines, detailed
- `fancy2`: fancy layout with a dedicated CLI-colored mode line below the meters
- `mygo`: band-inspired, musical separators

Themes: catppuccin, dracula, nord, gruvbox, tokyonight, onedark, solarized, rosepine, mygo.
