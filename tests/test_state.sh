#!/usr/bin/env bash
# Tests for scripts/10-write-state.sh.
set -uo pipefail

THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$THIS_DIR/.." && pwd)"
# shellcheck source=helpers.sh
. "$THIS_DIR/helpers.sh"

SANDBOX=$(mktemp -d)
trap 'rm -rf "$SANDBOX"' EXIT

STATE_FILE="$SANDBOX/.cloudflare-warp-state"
SCRIPT="$ROOT_DIR/scripts/10-write-state.sh"

echo "=== write-state (default MDM path) ==="
env STATE_FILE="$STATE_FILE" bash "$SCRIPT" >/dev/null
assert_file_exists "state file written" "$STATE_FILE"
CONTENT=$(cat "$STATE_FILE")
assert_contains "MDM_PATH default" "$CONTENT" "MDM_PATH=/var/lib/cloudflare-warp/mdm.xml"
assert_contains "REGISTERED=true" "$CONTENT" "REGISTERED=true"
assert_contains "INSTALLED=true" "$CONTENT" "INSTALLED=true"

# Critical: no credentials in state file.
assert_not_contains "no auth_client_id leak" "$CONTENT" "auth_client"
assert_not_contains "no secret leak" "$CONTENT" "secret"
assert_not_contains "no organization leak" "$CONTENT" "organization="
assert_not_contains "no token leak" "$CONTENT" "Token"

echo "=== write-state (custom MDM path) ==="
rm -f "$STATE_FILE"
env STATE_FILE="$STATE_FILE" MDM_PATH="/custom/mdm.xml" bash "$SCRIPT" >/dev/null
assert_contains "uses custom MDM path" "$(cat "$STATE_FILE")" "MDM_PATH=/custom/mdm.xml"
