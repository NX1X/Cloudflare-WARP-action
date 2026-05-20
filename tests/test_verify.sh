#!/usr/bin/env bash
# Tests for scripts/08-verify-connection.sh and set-skipped-status.sh.
# Mock warp-cli simulates connected/disconnected, including retry-on-attempt-N
# via CONNECT_FAILS_FIRST.
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

# Shim ping so we can force success/failure deterministically.
cat > "$SHIM_BIN/ping" <<'PINGSHIM'
#!/usr/bin/env bash
if [ -f /tmp/mock-ping-fail ]; then exit 1; fi
echo "PING mock $@"
exit 0
PINGSHIM
chmod +x "$SHIM_BIN/ping"

export PATH="$SHIM_BIN:$PATH"
export MOCK_WARP_CONFIG="$SANDBOX/config"
export MOCK_WARP_STATE="$SANDBOX/state"

VERIFY="$ROOT_DIR/scripts/08-verify-connection.sh"
SKIP="$ROOT_DIR/scripts/set-skipped-status.sh"

mock_connected() {
  : > "$MOCK_WARP_CONFIG"
  rm -f "$MOCK_WARP_STATE"
  # Pre-set state to connected.
  cat > "$MOCK_WARP_STATE" <<EOF
STATE=connected
START_TS=$(date +%s)
STATUS_CALLS=99
EOF
}

mock_disconnected() {
  : > "$MOCK_WARP_CONFIG"
  rm -f "$MOCK_WARP_STATE"
  cat > "$MOCK_WARP_STATE" <<EOF
STATE=fresh
START_TS=$(date +%s)
STATUS_CALLS=0
EOF
}

mock_connects_on_attempt_2() {
  echo "CONNECT_FAILS_FIRST=1" > "$MOCK_WARP_CONFIG"
  cat > "$MOCK_WARP_STATE" <<EOF
STATE=connected
START_TS=$(date +%s)
STATUS_CALLS=0
EOF
}

mock_never_connects() {
  echo "NEVER_CONNECTS=1" > "$MOCK_WARP_CONFIG"
  cat > "$MOCK_WARP_STATE" <<EOF
STATE=connected
START_TS=$(date +%s)
STATUS_CALLS=0
EOF
}

run_verify() {
  local out
  GITHUB_OUTPUT_FILE="$SANDBOX/gh_output"
  : > "$GITHUB_OUTPUT_FILE"
  out=$(env GITHUB_OUTPUT="$GITHUB_OUTPUT_FILE" \
    RETRY_COUNT="${RETRY_COUNT:-3}" \
    RETRY_DELAY="${RETRY_DELAY:-1}" \
    TEST_HOST="${TEST_HOST:-}" \
    PATH="$SHIM_BIN:$PATH" \
    MOCK_WARP_CONFIG="$MOCK_WARP_CONFIG" \
    MOCK_WARP_STATE="$MOCK_WARP_STATE" \
    bash "$VERIFY" 2>&1)
  RC=$?
  printf '%s' "$out"
  return $RC
}

echo "=== verify (connected first try) ==="
mock_connected
rm -f /tmp/mock-ping-fail
OUT=$(run_verify); RC=$?
assert_equals "exit 0" "0" "$RC"
assert_contains "reports connected" "$OUT" "WARP is Connected"
assert_contains "writes connection-status=connected" "$(cat "$SANDBOX/gh_output")" "connection-status=connected"

echo "=== verify (connected on retry attempt 2) ==="
mock_connects_on_attempt_2
RETRY_DELAY=1 OUT=$(run_verify); RC=$?
assert_equals "exit 0" "0" "$RC"
assert_contains "reports connected eventually" "$OUT" "WARP is Connected"
# Should mention more than one attempt.
assert_contains "shows attempt 2" "$OUT" "Attempt 2/"

echo "=== verify (never connects timeout) ==="
mock_never_connects
RETRY_COUNT=2 RETRY_DELAY=1 OUT=$(run_verify); RC=$?
assert_not_equals "non-zero exit on never-connect" "0" "$RC"
assert_contains "failed message" "$OUT" "failed to reach Connected"
assert_contains "writes connection-status=failed" "$(cat "$SANDBOX/gh_output")" "connection-status=failed"

echo "=== verify (connected + ping success) ==="
mock_connected
rm -f /tmp/mock-ping-fail
RETRY_COUNT=2 RETRY_DELAY=1 TEST_HOST="10.0.0.1" OUT=$(run_verify); RC=$?
assert_equals "exit 0" "0" "$RC"
assert_contains "ping success reported" "$OUT" "Ping to 10.0.0.1 succeeded"
assert_contains "writes connection-status=connected" "$(cat "$SANDBOX/gh_output")" "connection-status=connected"

echo "=== verify (connected + ping fails) ==="
mock_connected
touch /tmp/mock-ping-fail
RETRY_COUNT=2 RETRY_DELAY=1 TEST_HOST="10.0.0.1" OUT=$(run_verify); RC=$?
rm -f /tmp/mock-ping-fail
assert_not_equals "non-zero on ping fail" "0" "$RC"
assert_contains "could not reach error" "$OUT" "Could not reach"
assert_contains "writes connection-status=failed" "$(cat "$SANDBOX/gh_output")" "connection-status=failed"

echo "=== set-skipped-status.sh ==="
GH_OUT="$SANDBOX/skipped_output"
: > "$GH_OUT"
OUT=$(env GITHUB_OUTPUT="$GH_OUT" bash "$SKIP" 2>&1); RC=$?
assert_equals "exit 0" "0" "$RC"
assert_contains "writes skipped" "$(cat "$GH_OUT")" "connection-status=skipped"
