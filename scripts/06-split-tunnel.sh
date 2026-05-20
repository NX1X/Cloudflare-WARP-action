#!/usr/bin/env bash
# Configure split-tunnel exclude/include routes. Tries the modern
# `tunnel ip add` form first, falls back to add-excluded-route/add-included-route.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"

EXCLUDE_ROUTES="${EXCLUDE_ROUTES:-}"
INCLUDE_ROUTES="${INCLUDE_ROUTES:-}"

add_route() {
  local cidr="$1" mode="$2"
  if warp-cli --accept-tos tunnel ip add "$cidr" "$mode" 2>/dev/null; then
    echo "Added route ($mode): $cidr"
    return 0
  fi
  if [ "$mode" = "exclude" ]; then
    warp-cli --accept-tos add-excluded-route "$cidr"
  else
    warp-cli --accept-tos add-included-route "$cidr"
  fi
  echo "Added route via legacy command ($mode): $cidr"
}

apply_routes() {
  local routes="$1" mode="$2" cidr
  [ -z "$routes" ] && return 0
  while IFS= read -r cidr; do
    cidr="$(trim "$cidr")"
    [ -z "$cidr" ] && continue
    add_route "$cidr" "$mode"
  done <<< "$routes"
}

apply_routes "$EXCLUDE_ROUTES" "exclude"
apply_routes "$INCLUDE_ROUTES" "include"
