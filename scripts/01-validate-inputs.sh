#!/usr/bin/env bash
# Validate action inputs. Reads MODE, RETRY_COUNT, RETRY_DELAY, EXCLUDE_ROUTES,
# INCLUDE_ROUTES, ORGANIZATION from the environment.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/validate.sh
. "$SCRIPT_DIR/lib/validate.sh"

: "${MODE:?MODE not set}"
: "${RETRY_COUNT:?RETRY_COUNT not set}"
: "${RETRY_DELAY:?RETRY_DELAY not set}"
: "${ORGANIZATION:?ORGANIZATION not set}"
EXCLUDE_ROUTES="${EXCLUDE_ROUTES:-}"
INCLUDE_ROUTES="${INCLUDE_ROUTES:-}"

if ! validate_mode "$MODE"; then
  echo "ERROR: Invalid mode '$MODE' - expected one of: warp, proxy, doh, warp+doh" >&2
  exit 1
fi

if ! validate_positive_int "$RETRY_COUNT"; then
  echo "ERROR: retry-count must be a positive integer, got '$RETRY_COUNT'" >&2
  exit 1
fi

if ! validate_positive_int "$RETRY_DELAY"; then
  echo "ERROR: retry-delay must be a positive integer, got '$RETRY_DELAY'" >&2
  exit 1
fi

if ! validate_org "$ORGANIZATION"; then
  echo "ERROR: organization '$ORGANIZATION' must be the team name (lowercase alphanumerics and hyphens, e.g. 'acme-corp'). Use the subdomain only, not the full URL." >&2
  exit 1
fi

if ! check_exclusivity "$EXCLUDE_ROUTES" "$INCLUDE_ROUTES"; then
  echo "ERROR: exclude-routes and include-routes are mutually exclusive. Pick one split-tunnel mode." >&2
  exit 1
fi

check_routes "exclude-routes" "$EXCLUDE_ROUTES" || exit 1
check_routes "include-routes" "$INCLUDE_ROUTES" || exit 1

echo "Inputs validated."
