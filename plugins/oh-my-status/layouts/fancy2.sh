# Fancy2 layout - fancy layout with primary quota on ctx row, secondary as circle meters, and a CLI-colored mode line
# Line 1: model and directory (always first)
# Line 2: git details with line stats (only if in repo)
# Line 3: ctx + primary 5h/7d bars (| secondary family circle meters when QUOTA_FAMILY=all)
# Line 4: cycle mode (robot icon + CLI colors + shift+tab hint) and extras

RESET='\033[0m'

meter() {
  local pct=${1:-0} label=$2 width=${3:-12}
  local filled=$(( pct * width / 100 ))
  [ "$filled" -gt "$width" ] && filled=$width
  local empty=$(( width - filled ))
  local color i
  if [ "$pct" -le 30 ]; then color="$C_GREEN"
  elif [ "$pct" -le 80 ]; then color="$C_YELLOW"
  else color="$C_RED"
  fi
  local bar_str=""
  for ((i=0; i<filled; i++)); do bar_str+="━"; done
  for ((i=0; i<empty; i++)); do bar_str+="╌"; done
  printf -v REPLY "${C_SUBTEXT}%s ${color}%s${RESET} %d%%" "$label" "$bar_str" "$pct"
}

circle_meter() {
  local pct=${1:-0} suffix=${2-}
  local color step
  if [ "$pct" -le 30 ]; then color="$C_GREEN"
  elif [ "$pct" -le 80 ]; then color="$C_YELLOW"
  else color="$C_RED"
  fi
  # 9-step Nerd Font v3 circle progress: nf-md-circle_outline + nf-md-circle_slice_1..8
  local -a icons=(
    $'\xf3\xb0\x84\xb0' # 0/8 U+F0130 nf-md-checkbox_blank_circle_outline
    $'\xf3\xb0\xaa\x9e' # 1/8 U+F0A9E nf-md-circle_slice_1
    $'\xf3\xb0\xaa\x9f' # 2/8 U+F0A9F nf-md-circle_slice_2
    $'\xf3\xb0\xaa\xa0' # 3/8 U+F0AA0 nf-md-circle_slice_3
    $'\xf3\xb0\xaa\xa1' # 4/8 U+F0AA1 nf-md-circle_slice_4
    $'\xf3\xb0\xaa\xa2' # 5/8 U+F0AA2 nf-md-circle_slice_5
    $'\xf3\xb0\xaa\xa3' # 6/8 U+F0AA3 nf-md-circle_slice_6
    $'\xf3\xb0\xaa\xa4' # 7/8 U+F0AA4 nf-md-circle_slice_7
    $'\xf3\xb0\xaa\xa5' # 8/8 U+F0AA5 nf-md-circle_slice_8
  )
  step=$(( (pct * 8 + 50) / 100 ))
  [ "$step" -lt 0 ] && step=0
  [ "$step" -gt 8 ] && step=8
  printf -v REPLY "${color}%s${RESET} %d%%%s" "${icons[step]}" "$pct" "$suffix"
}

render() {
  local FOLDER_ICON=$'\xef\x81\xbb'
  local BRANCH_ICON=$'\xee\x82\xa0'
  local DOT="·"

  # Line 1: model + dir
  local LINE1="${C_PRIMARY}${MODEL}${RESET}"
  [ -n "$ACCOUNT" ] && LINE1+=" ${C_SUBTEXT}${DOT}${RESET} ${C_SUBTEXT}${ACCOUNT_ICON:+$ACCOUNT_ICON }${ACCOUNT}${RESET}"
  LINE1+=" ${C_SUBTEXT}${DOT}${RESET} ${C_SECONDARY}${FOLDER_ICON} ${DIR}${RESET}"

  # Line 2: git info (only if in repo)
  local LINE2=""
  if [ -n "$BRANCH" ]; then
    LINE2="${C_ACCENT}${BRANCH_ICON} ${BRANCH}${RESET}"

    local FILE_STATS=""
    [ "$ADD_FILES" -gt 0 ] 2>/dev/null && FILE_STATS+=" ${C_GREEN}+${ADD_FILES} new${RESET}"
    [ "$MOD_FILES" -gt 0 ] 2>/dev/null && FILE_STATS+=" ${C_YELLOW}~${MOD_FILES} mod${RESET}"
    [ "$DEL_FILES" -gt 0 ] 2>/dev/null && FILE_STATS+=" ${C_RED}-${DEL_FILES} del${RESET}"
    [ -n "$FILE_STATS" ] && LINE2+=" ${C_SUBTEXT}│${RESET}${FILE_STATS}"

    local LINE_STATS=""
    [ "$LINES_ADD" -gt 0 ] 2>/dev/null && LINE_STATS+="${C_GREEN}+${LINES_ADD}${RESET}"
    [ "$LINES_DEL" -gt 0 ] 2>/dev/null && LINE_STATS+=" ${C_RED}-${LINES_DEL}${RESET}"
    [ -n "$LINE_STATS" ] && LINE2+=" ${C_SUBTEXT}│${RESET} ${LINE_STATS} ${C_SUBTEXT}lines${RESET}"
  fi

  # Line 3: ctx + active family's 5h/7d bars, followed by "│ <other> <5h circle> <7d circle>" when QUOTA_ALL=1
  local bw=12
  if [ "${QUOTA_ALL:-0}" = 1 ] && [ "${QUOTA_COUNT:-0}" -gt 1 ]; then bw=10; fi
  meter "${CTX_PCT:-0}" "ctx" "$bw"; local LINE3=$REPLY

  if [ "${QUOTA_ALL:-0}" = 1 ] && [ "${QUOTA_COUNT:-0}" -gt 0 ]; then
    local want_fam="3p" had_ncm=0
    shopt -q nocasematch && had_ncm=1
    shopt -s nocasematch
    if [ -z "${MODEL-}" ] || [[ "$MODEL" == *gemini* ]] || [[ "$MODEL" == *orchestrator* ]]; then
      want_fam="gemini"
    fi
    [ "$had_ncm" = 1 ] || shopt -u nocasematch

    local pri=-1 i p5 p7
    for ((i=0; i<${QUOTA_COUNT:-0}; i++)); do
      if [ "${QUOTA_FAMILIES[i]}" = "$want_fam" ]; then pri=$i; break; fi
    done
    [ "$pri" -lt 0 ] && pri=0

    # Primary family: 5h & 7d bars inline next to ctx (same layout as QUOTA_FAMILY=auto)
    p5=${QUOTA_5H_PCT[pri]}; p7=${QUOTA_7D_PCT[pri]}
    if [ -n "$p5" ]; then meter "$p5" "5h" "$bw"; LINE3+="  ${REPLY}${QUOTA_5H_SUFFIX[pri]}"; fi
    if [ -n "$p7" ]; then meter "$p7" "7d" "$bw"; LINE3+="  ${REPLY}${QUOTA_7D_SUFFIX[pri]}"; fi

    # Secondary families: │ <family> 5h <circle> <pct>% 7d <circle> <pct>%
    local oseg
    for ((i=0; i<${QUOTA_COUNT:-0}; i++)); do
      [ "$i" -eq "$pri" ] && continue
      p5=${QUOTA_5H_PCT[i]}; p7=${QUOTA_7D_PCT[i]}
      oseg="${C_SUBTEXT}${QUOTA_FAMILIES[i]}${RESET}"
      if [ -n "$p5" ]; then
        circle_meter "$p5" "${QUOTA_5H_SUFFIX[i]}"; oseg+=" ${C_SUBTEXT}5h${RESET} ${REPLY}"
      fi
      if [ -n "$p7" ]; then
        circle_meter "$p7" "${QUOTA_7D_SUFFIX[i]}"; oseg+=" ${C_SUBTEXT}7d${RESET} ${REPLY}"
      fi
      LINE3+="  ${C_SUBTEXT}│${RESET}  ${oseg}"
    done
  else
    if [ -n "${RATE5_PCT:-}" ]; then meter "$RATE5_PCT" " 5h" 12; LINE3+="  ${REPLY}${RATE5_SUFFIX}"; fi
    if [ -n "${RATE7_PCT:-}" ]; then meter "$RATE7_PCT" " 7d" 12; LINE3+="  ${REPLY}${RATE7_SUFFIX}"; fi
  fi

  # Line 4: cycle mode (with CLI-matched colors) and remaining extras below the meters.
  local show_mode="${SHOW_MODE-}" mode_seg="" LINE4=""
  if [ "$show_mode" = true ] && [ -n "${MODE-}" ]; then
    local mode_icon=$'\xf3\xb0\x9a\xa9' # nf-md-robot (U+F06A9)
    local mode_color
    case "$MODE" in
      auto)                   mode_color='\033[38;2;229;192;123m' ;; # #e5c07b
      plan)                   mode_color='\033[38;2;97;175;239m'  ;; # #61afef
      accept-edits)           mode_color='\033[38;2;152;195;121m' ;; # #98c379
      default|request-review) mode_color="${C_SUBTEXT-}" ;;
      *)                      mode_color="${C_ACCENT-}" ;;
    esac
    mode_seg="${mode_color}${mode_icon}  ${MODE} mode on${RESET-} ${C_SUBTEXT-}(shift+tab to cycle)${RESET-}"
  fi
  local SHOW_MODE=false
  oma_extras
  LINE4="$mode_seg"
  if [ -n "$REPLY" ]; then
    LINE4="${LINE4:+${LINE4}  }${REPLY}"
  fi
  echo -e "$LINE1"
  if [ -n "$LINE2" ]; then echo -e "$LINE2"; fi
  echo -e "$LINE3"
  if [ -n "$LINE4" ]; then echo -e "$LINE4"; fi
}
