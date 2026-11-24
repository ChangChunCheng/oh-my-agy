#!/bin/bash
# Conf-key diff helper for oh-my-status setup.
#
# Sourced by setup.sh (and by tests). Sourcing is INERT — this file's top
# level contains ONLY function definitions.
#
# oma_missing_conf_keys <template_path> <user_conf_path>
#   Prints, one per line in template order, each KEY defined in the template
#   as an assignment but NOT present in the user conf as an uncommented
#   assignment. Values are never compared.
oma_missing_conf_keys() {
  local template="$1" user_conf="$2"
  [ -r "$template" ] || return 1
  local keys key
  keys="$(sed -n 's/^[[:space:]]*\([A-Za-z_][A-Za-z0-9_]*\)[[:space:]]*=.*/\1/p' "$template")"
  while IFS= read -r key; do
    [ -n "$key" ] || continue
    if oma_conf_has_key "$user_conf" "$key"; then
      continue
    fi
    printf '%s\n' "$key"
  done <<EOF
$keys
EOF
}

# oma_conf_has_key <user_conf_path> <KEY>
#   Exit 0 iff the conf has an uncommented assignment of KEY (optional
#   `export ` prefix, optional whitespace around `=`).
oma_conf_has_key() {
  [ -r "$1" ] && grep -Eq -- "^[[:space:]]*(export[[:space:]]+)?${2}[[:space:]]*=" "$1"
}
