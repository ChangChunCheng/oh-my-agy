# Minimal layout - single compact line
# model | dir | branch | ctx% 5h% 7d%

RESET='\033[0m'

pct_color() {
  local pct=${1:-0}
  if [ "$pct" -le 30 ]; then REPLY=$C_GREEN
  elif [ "$pct" -le 80 ]; then REPLY=$C_YELLOW
  else REPLY=$C_RED
  fi
}

render() {
  local LINE="${C_PRIMARY}${MODEL}${RESET}"
  [ -n "$ACCOUNT" ] && LINE+=" ${C_SUBTEXT}|${RESET} ${C_SUBTEXT}${ACCOUNT}${RESET}"
  LINE+=" ${C_SUBTEXT}|${RESET} ${C_SECONDARY}${DIR}${RESET}"

  if [ -n "$BRANCH" ]; then
    LINE+=" ${C_SUBTEXT}|${RESET} ${C_ACCENT}${BRANCH}${RESET}"

    local CHANGES=""
    [ "$ADD_FILES" -gt 0 ] 2>/dev/null && CHANGES+="+${ADD_FILES} "
    [ "$MOD_FILES" -gt 0 ] 2>/dev/null && CHANGES+="~${MOD_FILES} "
    [ "$DEL_FILES" -gt 0 ] 2>/dev/null && CHANGES+="-${DEL_FILES}"
    [ -n "$CHANGES" ] && LINE+=" ${C_YELLOW}${CHANGES}${RESET}"
  fi

  LINE+=" ${C_SUBTEXT}|${RESET}"
  pct_color "${CTX_PCT:-0}"; LINE+=" ${REPLY}${CTX_PCT:-0}%${RESET}"
  if [ "${QUOTA_ALL:-0}" = 1 ]; then
    local i p5 p7 qseg
    for ((i=0; i<${QUOTA_COUNT:-0}; i++)); do
      p5=${QUOTA_5H_PCT[i]}; p7=${QUOTA_7D_PCT[i]}
      qseg="${C_SUBTEXT}${QUOTA_FAMILIES[i]}${RESET}"
      if [ -n "$p5" ] && [ -n "$p7" ]; then
        pct_color "$p5"; qseg+=" ${REPLY}${p5}%${RESET}"
        pct_color "$p7"; qseg+="${C_SUBTEXT}/${RESET}${REPLY}${p7}%${RESET}"
      elif [ -n "$p5" ]; then
        pct_color "$p5"; qseg+=" ${REPLY}5h:${p5}%${RESET}"
      elif [ -n "$p7" ]; then
        pct_color "$p7"; qseg+=" ${REPLY}7d:${p7}%${RESET}"
      fi
      LINE+=" ${C_SUBTEXT}|${RESET} ${qseg}"
    done
  else
    if [ -n "${RATE5_PCT:-}" ]; then pct_color "$RATE5_PCT"; LINE+=" ${REPLY}${RATE5_PCT}%${RESET}"; fi
    if [ -n "${RATE7_PCT:-}" ]; then pct_color "$RATE7_PCT"; LINE+=" ${REPLY}${RATE7_PCT}%${RESET}"; fi
  fi

  # Extras (cycle mode / cost / tasks), after the bars: they also use REPLY.
  oma_extras; [ -n "$REPLY" ] && LINE+="  $REPLY"
  echo -e "$LINE"
}
