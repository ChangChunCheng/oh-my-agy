# Pure layout - clean text, no icons, no special characters
# Designed for terminals without Nerd Font support

RESET='\033[0m'

pct_indicator() {
  local pct=${1:-0} label=$2
  local color i
  if [ "$pct" -le 30 ]; then color="$C_GREEN"
  elif [ "$pct" -le 80 ]; then color="$C_YELLOW"
  else color="$C_RED"
  fi
  printf -v REPLY "${color}%s:%d%%${RESET}" "$label" "$pct"
}

render() {
  local LINE="${C_PRIMARY}${MODEL}${RESET}"
  [ -n "$ACCOUNT" ] && LINE+="  ${C_SUBTEXT}${ACCOUNT}${RESET}"
  LINE+="  ${C_SECONDARY}${DIR}${RESET}"

  if [ -n "$BRANCH" ]; then
    LINE+="  ${C_ACCENT}(${BRANCH})${RESET}"

    local CHANGES=""
    [ "$ADD_FILES" -gt 0 ] 2>/dev/null && CHANGES+="${C_GREEN}+${ADD_FILES}${RESET} "
    [ "$MOD_FILES" -gt 0 ] 2>/dev/null && CHANGES+="${C_YELLOW}~${MOD_FILES}${RESET} "
    [ "$DEL_FILES" -gt 0 ] 2>/dev/null && CHANGES+="${C_RED}-${DEL_FILES}${RESET}"
    [ -n "$CHANGES" ] && LINE+=" ${CHANGES}"
  fi

  pct_indicator "${CTX_PCT:-0}" ctx; LINE+="  ${REPLY}"
  if [ "${QUOTA_ALL:-0}" = 1 ]; then
    local i qseg p5 p7
    for ((i=0; i<${QUOTA_COUNT:-0}; i++)); do
      qseg="${C_SUBTEXT}${QUOTA_FAMILIES[i]}${RESET}"
      p5=${QUOTA_5H_PCT[i]}; p7=${QUOTA_7D_PCT[i]}
      if [ -n "$p5" ]; then pct_indicator "$p5" 5h; qseg+=" ${REPLY}"; fi
      if [ -n "$p7" ]; then pct_indicator "$p7" 7d; qseg+=" ${REPLY}"; fi
      LINE+="  ${qseg}"
    done
  else
    if [ -n "${RATE5_PCT:-}" ]; then pct_indicator "$RATE5_PCT" 5h; LINE+="  ${REPLY}"; fi
    if [ -n "${RATE7_PCT:-}" ]; then pct_indicator "$RATE7_PCT" 7d; LINE+="  ${REPLY}"; fi
  fi

  # Extras (cycle mode / cost / tasks), after the bars: they also use REPLY.
  oma_extras; [ -n "$REPLY" ] && LINE+="  $REPLY"
  echo -e "$LINE"
}
