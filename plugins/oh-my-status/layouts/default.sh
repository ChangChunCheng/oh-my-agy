# Default layout - two lines with icons and progress bars
# Line 1: model @ dir | branch +A ~M -D | +lines -lines
# Line 2: [ctx bar] [5h bar] [7d bar]

RESET='\033[0m'

bar() {
  local pct=${1:-0} width=${2:-15}
  local filled=$(( pct * width / 100 ))
  [ "$filled" -gt "$width" ] && filled=$width
  local empty=$(( width - filled ))
  local color i
  if [ "$pct" -le 30 ]; then color="$C_GREEN"
  elif [ "$pct" -le 80 ]; then color="$C_YELLOW"
  else color="$C_RED"
  fi
  local bar_str=""
  for ((i=0; i<filled; i++)); do bar_str+="█"; done
  for ((i=0; i<empty; i++)); do bar_str+="░"; done
  printf -v REPLY "${color}${bar_str}${RESET} %d%%" "$pct"
}

render() {
  local FOLDER_ICON=$'\xef\x81\xbb'
  local BRANCH_ICON=$'\xee\x82\xa0'

  local LINE1="${C_PRIMARY}${MODEL}${RESET}"
  [ -n "$ACCOUNT" ] && LINE1+=" ${C_SUBTEXT}${ACCOUNT_ICON:+$ACCOUNT_ICON }${ACCOUNT}${RESET}"
  LINE1+=" ${C_SECONDARY}${FOLDER_ICON} ${DIR}${RESET}"

  if [ -n "$BRANCH" ]; then
    LINE1="${LINE1} | ${C_ACCENT}${BRANCH_ICON} ${BRANCH}${RESET}"

    local GIT_INFO=""
    [ "$ADD_FILES" -gt 0 ] 2>/dev/null && GIT_INFO+="${C_GREEN}+${ADD_FILES}${RESET} "
    [ "$MOD_FILES" -gt 0 ] 2>/dev/null && GIT_INFO+="${C_YELLOW}~${MOD_FILES}${RESET} "
    [ "$DEL_FILES" -gt 0 ] 2>/dev/null && GIT_INFO+="${C_RED}-${DEL_FILES}${RESET} "
    [ -n "$GIT_INFO" ] && LINE1="${LINE1} ${GIT_INFO}"

    local LINE_INFO=""
    [ "$LINES_ADD" -gt 0 ] 2>/dev/null && LINE_INFO+="${C_GREEN}+${LINES_ADD}${RESET} "
    [ "$LINES_DEL" -gt 0 ] 2>/dev/null && LINE_INFO+="${C_RED}-${LINES_DEL}${RESET}"
    [ -n "$LINE_INFO" ] && LINE1="${LINE1}| ${LINE_INFO}"
  fi

  bar "${CTX_PCT:-0}" 15; local LINE2=$REPLY
  local LINE3=""
  if [ "${QUOTA_ALL:-0}" = 1 ]; then
    LINE2="${C_SUBTEXT}ctx${RESET} ${LINE2}"
    local i qseg p5 p7 bw=15
    [ "${QUOTA_COUNT:-0}" -gt 1 ] && bw=8
    for ((i=0; i<${QUOTA_COUNT:-0}; i++)); do
      qseg="${C_SUBTEXT}${QUOTA_FAMILIES[i]}${RESET}"
      p5=${QUOTA_5H_PCT[i]}; p7=${QUOTA_7D_PCT[i]}
      if [ -n "$p5" ]; then bar "$p5" "$bw"; qseg+=" ${C_SUBTEXT}5h${RESET} ${REPLY}${QUOTA_5H_SUFFIX[i]}"; fi
      if [ -n "$p7" ]; then bar "$p7" "$bw"; qseg+=" ${C_SUBTEXT}7d${RESET} ${REPLY}${QUOTA_7D_SUFFIX[i]}"; fi
      LINE3="${LINE3:+${LINE3} ${C_SUBTEXT}|${RESET} }${qseg}"
    done
  else
    if [ -n "${RATE5_PCT:-}" ]; then bar "$RATE5_PCT" 15; LINE2+="  ${REPLY}${RATE5_SUFFIX}"; fi
    if [ -n "${RATE7_PCT:-}" ]; then bar "$RATE7_PCT" 15; LINE2+="  ${REPLY}${RATE7_SUFFIX}"; fi
  fi

  # Extras (cycle mode / cost / tasks), after the bars: they also use REPLY.
  oma_extras; [ -n "$REPLY" ] && LINE2+="  $REPLY"
  echo -e "$LINE1"
  echo -e "$LINE2"
  [ -n "$LINE3" ] && echo -e "$LINE3"
}
