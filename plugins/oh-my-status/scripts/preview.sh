#!/bin/bash
# oh-my-status theme/layout preview
# Usage: bash preview.sh [themes|layouts|all]

# Installed copy: themes/ layouts/ lib/ sit next to this file. Repo checkout:
# this file lives in scripts/ and themes/ layouts/ sit one level up.
case ${BASH_SOURCE[0]} in */*) SCRIPT_DIR=${BASH_SOURCE[0]%/*} ;; *) SCRIPT_DIR=. ;; esac
if [ -z "${OMA_DIR:-}" ]; then
  if [ -d "$SCRIPT_DIR/themes" ]; then OMA_DIR=$SCRIPT_DIR; else OMA_DIR=$SCRIPT_DIR/..; fi
fi
OMA_HOME="${OMA_HOME:-$HOME/.gemini/oh-my-agy}"
OMA_CONF="${OMA_CONF:-$OMA_HOME/status.conf}"
RESET='\033[0m'
BOLD='\033[1m'
DIM='\033[2m'

# Current config
CUR_THEME="catppuccin"
CUR_LAYOUT="default"
[ -f "$OMA_CONF" ] && source "$OMA_CONF"
CUR_THEME="${THEME:-$CUR_THEME}"
CUR_LAYOUT="${LAYOUT:-$CUR_LAYOUT}"
# The preview always shows the extras (they are toggles in the real conf).
SHOW_MODE=true SHOW_COST=false SHOW_TASKS=true
ACCOUNT_SHOW_CONF="${ACCOUNT_SHOW:-true}"
QUOTA_FAMILY_CONF="${QUOTA_FAMILY:-all}"

# Sample data for demo
DEMO_MODEL="Gemini 4 Neon (High) [1M]"
DEMO_DIR="~/projects/my-app"
DEMO_BRANCH="feat/auth"
DEMO_ADD=3 DEMO_MOD=5 DEMO_DEL=1
DEMO_LADD=142 DEMO_LDEL=38
DEMO_CTX=42 DEMO_R5=18 DEMO_R7=6
DEMO_3P_R5=25 DEMO_3P_R7=10

source "$SCRIPT_DIR/lib/render-common.sh"

preview_theme() {
  local theme_file="$1"
  local theme_name label marker=""
  theme_name=$(basename "$theme_file" .sh)
  source "$theme_file"

  label=$(head -1 "$theme_file" | sed 's/^# *//')
  [ "$theme_name" = "$CUR_THEME" ] && marker=" ${DIM}(current)${RESET}"

  echo -e "${BOLD}${label}${RESET}${marker}  ${DIM}[${theme_name}]${RESET}"
  echo -en "  ${C_PRIMARY}Primary${RESET} "
  echo -en "${C_SECONDARY}Secondary${RESET} "
  echo -en "${C_ACCENT}Accent${RESET} "
  echo -en "${C_GREEN}Green${RESET} "
  echo -en "${C_YELLOW}Yellow${RESET} "
  echo -en "${C_RED}Red${RESET} "
  echo -en "${C_TEXT}Text${RESET} "
  echo -e  "${C_SUBTEXT}Subtext${RESET}"
  # Sample statusline
  echo -en "  ${C_PRIMARY}${DEMO_MODEL}${RESET} ${C_SECONDARY}${DEMO_DIR}${RESET}"
  echo -en " | ${C_ACCENT}${DEMO_BRANCH}${RESET}"
  echo -en " ${C_GREEN}+${DEMO_ADD}${RESET} ${C_YELLOW}~${DEMO_MOD}${RESET} ${C_RED}-${DEMO_DEL}${RESET}"
  echo ""
  echo ""
}

preview_layout() {
  local layout_file="$1"
  local layout_name label marker="" theme_file
  layout_name=$(basename "$layout_file" .sh)

  # Source current theme for layout preview
  theme_file="${OMA_DIR}/themes/${CUR_THEME}.sh"
  [ -f "$theme_file" ] && source "$theme_file"

  source "$layout_file"

  label=$(head -1 "$layout_file" | sed 's/^# *//')
  [ "$layout_name" = "$CUR_LAYOUT" ] && marker=" ${DIM}(current)${RESET}"

  echo -e "${BOLD}${label}${RESET}${marker}  ${DIM}[${layout_name}]${RESET}"

  # Set up demo variables for the render function
  MODEL="$DEMO_MODEL"
  DIR="$DEMO_DIR"
  BRANCH="$DEMO_BRANCH"
  ADD_FILES=$DEMO_ADD MOD_FILES=$DEMO_MOD DEL_FILES=$DEMO_DEL
  LINES_ADD=$DEMO_LADD LINES_DEL=$DEMO_LDEL
  CTX_PCT=$DEMO_CTX RATE5_PCT=$DEMO_R5 RATE7_PCT=$DEMO_R7
  RATE5_SUFFIX="" RATE7_SUFFIX=""
  if [ "$QUOTA_FAMILY_CONF" = all ]; then
    QUOTA_ALL=1 QUOTA_COUNT=2
    QUOTA_FAMILIES=(gemini 3p)
    QUOTA_5H_PCT=($DEMO_R5 $DEMO_3P_R5)
    QUOTA_7D_PCT=($DEMO_R7 $DEMO_3P_R7)
    QUOTA_5H_SUFFIX=("" "")
    QUOTA_7D_SUFFIX=("" "")
  else
    QUOTA_ALL=0 QUOTA_COUNT=0
    QUOTA_FAMILIES=() QUOTA_5H_PCT=() QUOTA_7D_PCT=() QUOTA_5H_SUFFIX=() QUOTA_7D_SUFFIX=()
  fi
  MODE="plan" COST="0.42" TASKS=1 AGENTS=0
  ACCOUNT_ICON="${ACCOUNT_ICON-$'\xef\x80\x87'}"
  ACCOUNT=""
  [ "$ACCOUNT_SHOW_CONF" = true ] && ACCOUNT="you"

  # Indent render output
  render | sed 's/^/  /'
  echo ""
}

ARG="${1:-all}"

case "$ARG" in
  theme|themes)
    echo -e "${BOLD}Available Themes${RESET}  ${DIM}(current: ${CUR_THEME})${RESET}"
    echo ""
    for f in "$OMA_DIR"/themes/*.sh; do preview_theme "$f"; done
    ;;
  layout|layouts)
    echo -e "${BOLD}Available Layouts${RESET}  ${DIM}(current: ${CUR_LAYOUT}, theme: ${CUR_THEME})${RESET}"
    echo ""
    for f in "$OMA_DIR"/layouts/*.sh; do preview_layout "$f"; done
    ;;
  *)
    echo -e "${BOLD}Available Themes${RESET}  ${DIM}(current: ${CUR_THEME})${RESET}"
    echo ""
    for f in "$OMA_DIR"/themes/*.sh; do preview_theme "$f"; done
    echo -e "${BOLD}Available Layouts${RESET}  ${DIM}(current: ${CUR_LAYOUT}, theme: ${CUR_THEME})${RESET}"
    echo ""
    for f in "$OMA_DIR"/layouts/*.sh; do preview_layout "$f"; done
    echo -e "${DIM}Switch with:  /status-theme <theme> <layout>${RESET}"
    ;;
esac
