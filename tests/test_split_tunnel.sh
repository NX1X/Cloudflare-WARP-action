#!/usr/bin/env bash
# Tests for scripts/06-split-tunnel.sh: new syntax success, legacy fallback,
# empty no-op.
set -uo pipefail

THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$THIS_DIR/.." && pwd)"
# shellcheck source=helpers.sh
. "$THIS_DIR/helpers.sh"

SANDBOX=$(mktemp -d)
trap 'rm -rf "$SANDBOX"' EXIT

SHIM_BIN="$SANDBOX/bin"
mkdir -p "$SHIM_BIN"
cp "$ROOT_DIR/tests/mock_warp_cli.sh" "$SHIM_BIN/warp-cli"
chmod +x "$SHIM_BIN/warp-cli"

export PATH="$SHIM_BIN:$PATH"
export MOCK_WARP_CONFIG="$SANDBOX/config"
export MOCK_WARP_STATE="$SANDBOX/state"

SCRIPT="$ROOT_DIR/scripts/06-split-tunnel.sh"

echo "=== 06-split-tunnel.sh (no routes - no-op) ==="
: > "$MOCK_WARP_CONFIG"
rm -f "$MOCK_WARP_STATE"
OUT=$(env EXCLUDE_ROUTES="" INCLUDE_ROUTES="" \
  MOCK_WARP_CONFIG="$MOCK_WARP_CONFIG" MOCK_WARP_STATE="$MOCK_WARP_STATE" \
  PATH="$SHIM_BIN:$PATH" \
  bash "$SCRIPT" 2>&1)
RC=$?
assert_equals "exit 0 with no routes" "0" "$RC"
assert_not_contains "no 'Added route' line" "$OUT" "Added route"

echo "=== 06-split-tunnel.sh (exclude with modern syntax) ==="
: > "$MOCK_WARP_CONFIG"
rm -f "$MOCK_WARP_STATE"
OUT=$(env EXCLUDE_ROUTES="$(printf '10.0.0.0/8\n192.168.0.0/16\n')" INCLUDE_ROUTES="" \
  MOCK_WARP_CONFIG="$MOCK_WARP_CONFIG" MOCK_WARP_STATE="$MOCK_WARP_STATE" \
  PATH="$SHIM_BIN:$PATH" \
  bash "$SCRIPT" 2>&1)
RC=$?
assert_equals "exit 0" "0" "$RC"
assert_contains "first route added" "$OUT" "10.0.0.0/8"
assert_contains "second route added" "$OUT" "192.168.0.0/16"
assert_not_contains "no legacy fallback used" "$OUT" "legacy"

echo "=== 06-split-tunnel.sh (include via legacy fallback) ==="
echo "FAIL_TUNNEL_NEW_SYNTAX=1" > "$MOCK_WARP_CONFIG"
rm -f "$MOCK_WARP_STATE"
OUT=$(env EXCLUDE_ROUTES="" INCLUDE_ROUTES="10.0.0.0/8" \
  MOCK_WARP_CONFIG="$MOCK_WARP_CONFIG" MOCK_WARP_STATE="$MOCK_WARP_STATE" \
  PATH="$SHIM_BIN:$PATH" \
  bash "$SCRIPT" 2>&1)
RC=$?
assert_equals "exit 0 with legacy fallback" "0" "$RC"
assert_contains "legacy command used" "$OUT" "legacy"
assert_contains "include CIDR mentioned" "$OUT" "10.0.0.0/8"

echo "=== 06-split-tunnel.sh (whitespace + blank lines tolerated) ==="
: > "$MOCK_WARP_CONFIG"
rm -f "$MOCK_WARP_STATE"
OUT=$(env EXCLUDE_ROUTES="$(printf '  10.0.0.0/8  \n\n192.168.0.0/16\n')" INCLUDE_ROUTES="" \
  MOCK_WARP_CONFIG="$MOCK_WARP_CONFIG" MOCK_WARP_STATE="$MOCK_WARP_STATE" \
  PATH="$SHIM_BIN:$PATH" \
  bash "$SCRIPT" 2>&1)
RC=$?
assert_equals "exit 0" "0" "$RC"
ROUTE_LINES=$(echo "$OUT" | grep -c "Added route" || true)
assert_equals "exactly 2 routes added" "2" "$ROUTE_LINES"
