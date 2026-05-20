#!/usr/bin/env bash
# Tests for wait_for_daemon helper. Uses the configurable mock warp-cli with
# DAEMON_READY_AFTER to gate readiness.
set -uo pipefail

THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$THIS_DIR/.." && pwd)"
# shellcheck source=helpers.sh
. "$THIS_DIR/helpers.sh"

SANDBOX=$(mktemp -d)
trap 'rm -rf "$SANDBOX"' EXIT

# Install mock warp-cli on PATH
SHIM_BIN="$SANDBOX/bin"
mkdir -p "$SHIM_BIN"
cp "$ROOT_DIR/tests/mock_warp_cli.sh" "$SHIM_BIN/warp-cli"
chmod +x "$SHIM_BIN/warp-cli"

export PATH="$SHIM_BIN:$PATH"
export MOCK_WARP_CONFIG="$SANDBOX/config"
export MOCK_WARP_STATE="$SANDBOX/state"

# shellcheck source=../scripts/lib/common.sh
. "$ROOT_DIR/scripts/lib/common.sh"

echo "=== wait_for_daemon (ready immediately) ==="
: > "$MOCK_WARP_CONFIG"
rm -f "$MOCK_WARP_STATE"
START=$(date +%s)
if wait_for_daemon 5 >/dev/null 2>&1; then RC=0; else RC=1; fi
END=$(date +%s)
ELAPSED=$((END - START))
assert_equals "ready=0 returns success" "0" "$RC"
if [ "$ELAPSED" -le 2 ]; then
  _pass "returned quickly (${ELAPSED}s)"
else
  _fail "took too long (${ELAPSED}s)"
fi
TESTS=$((TESTS + 1))

echo "=== wait_for_daemon (ready after 2s) ==="
echo "DAEMON_READY_AFTER=2" > "$MOCK_WARP_CONFIG"
rm -f "$MOCK_WARP_STATE"
START=$(date +%s)
wait_for_daemon 10 >/dev/null 2>&1
RC=$?
END=$(date +%s)
ELAPSED=$((END - START))
assert_equals "delayed-ready returns success" "0" "$RC"
if [ "$ELAPSED" -ge 1 ] && [ "$ELAPSED" -le 5 ]; then
  _pass "waited about 2s (actual: ${ELAPSED}s)"
else
  _fail "elapsed unexpected (${ELAPSED}s)"
fi
TESTS=$((TESTS + 1))

echo "=== wait_for_daemon (never ready) ==="
echo "DAEMON_READY_AFTER=999" > "$MOCK_WARP_CONFIG"
rm -f "$MOCK_WARP_STATE"
wait_for_daemon 2 >/dev/null 2>&1
RC=$?
assert_not_equals "timeout returns non-zero" "0" "$RC"

echo "=== 03-wait-daemon.sh script (timeout path) ==="
echo "DAEMON_READY_AFTER=999" > "$MOCK_WARP_CONFIG"
rm -f "$MOCK_WARP_STATE"
OUT=$(env DAEMON_WAIT_MAX=2 SUDO="echo skip-sudo" PATH="$SHIM_BIN:$PATH" \
  MOCK_WARP_CONFIG="$MOCK_WARP_CONFIG" MOCK_WARP_STATE="$MOCK_WARP_STATE" \
  bash "$ROOT_DIR/scripts/03-wait-daemon.sh" 2>&1)
RC=$?
assert_not_equals "script exits non-zero on timeout" "0" "$RC"
assert_contains "script reports timeout" "$OUT" "did not become ready"

echo "=== 03-wait-daemon.sh script (ready path) ==="
: > "$MOCK_WARP_CONFIG"
rm -f "$MOCK_WARP_STATE"
OUT=$(env DAEMON_WAIT_MAX=5 SUDO="echo skip-sudo" PATH="$SHIM_BIN:$PATH" \
  MOCK_WARP_CONFIG="$MOCK_WARP_CONFIG" MOCK_WARP_STATE="$MOCK_WARP_STATE" \
  bash "$ROOT_DIR/scripts/03-wait-daemon.sh" 2>&1)
RC=$?
assert_equals "script exits 0 when ready" "0" "$RC"
assert_contains "script reports ready" "$OUT" "warp-svc is ready"
