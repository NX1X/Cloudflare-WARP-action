# shellcheck shell=bash
# Pure-function validators for cloudflare-warp-action inputs.
# No side effects, no exits - callers decide how to react.

validate_mode() {
  case "$1" in
    warp|proxy|doh|warp+doh) return 0 ;;
    *) return 1 ;;
  esac
}

validate_positive_int() {
  echo "$1" | grep -qE '^[1-9][0-9]*$'
}

validate_org() {
  echo "$1" | grep -qE '^[a-z0-9][a-z0-9-]{0,62}$'
}

validate_cidr() {
  if echo "$1" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+$'; then
    return 0
  fi
  if echo "$1" | grep -qE '^[0-9a-fA-F:]+/[0-9]+$'; then
    return 0
  fi
  return 1
}

check_routes() {
  local label="$1" routes="$2"
  [ -z "$routes" ] && return 0
  local cidr
  while IFS= read -r cidr; do
    cidr="$(echo "$cidr" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
    [ -z "$cidr" ] && continue
    if ! validate_cidr "$cidr"; then
      echo "ERROR: $label contains invalid CIDR '$cidr' (expected e.g. 192.168.0.0/16 or fd00::/8)" >&2
      return 1
    fi
  done <<< "$routes"
  return 0
}

check_exclusivity() {
  local exclude="$1" include="$2"
  if [ -n "$exclude" ] && [ -n "$include" ]; then
    return 1
  fi
  return 0
}
