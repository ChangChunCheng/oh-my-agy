#!/bin/bash
# Shared render helpers for oh-my-status layouts and preview.sh.
# Sourcing is inert: only function definitions live here.

# oma_extras [sep]
#   Sets REPLY to the colored "extras" segment joined by sep (default two
#   spaces): [cycle_mode], $cost, "N tasks", "N agents". Each part is gated by
#   its SHOW_* toggle and by having something to show. REPLY is empty when
#   there is nothing to show. Plain text only (works in the pure layout) and
#   safe with unset or non-numeric variables. Callers must run it after the
#   progress bars, since the bars also use REPLY.
oma_extras() {
  local sep="${1-  }" out="" part n
  REPLY=""
  if [ "${SHOW_MODE-}" = true ] && [ -n "${MODE-}" ]; then
    out="${C_ACCENT-}[${MODE}]${RESET-}"
  fi
  if [ "${SHOW_COST-}" = true ] && [ -n "${COST-}" ]; then
    part="${C_TEXT-}\$${COST}${RESET-}"
    out="${out:+$out$sep}$part"
  fi
  if [ "${SHOW_TASKS-}" = true ]; then
    n=${TASKS-}
    if [[ $n =~ ^[0-9]+$ ]] && [ $((10#$n)) -gt 0 ]; then
      n=$((10#$n)); part="${C_YELLOW-}${n} task"; [ "$n" -gt 1 ] && part+="s"
      out="${out:+$out$sep}${part}${RESET-}"
    fi
    n=${AGENTS-}
    if [[ $n =~ ^[0-9]+$ ]] && [ $((10#$n)) -gt 0 ]; then
      n=$((10#$n)); part="${C_YELLOW-}${n} agent"; [ "$n" -gt 1 ] && part+="s"
      out="${out:+$out$sep}${part}${RESET-}"
    fi
  fi
  REPLY=$out
}
