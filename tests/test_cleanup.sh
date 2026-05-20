#!/usr/bin/env bash
# Tests for cleanup/cleanup.sh.
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

# Shim systemctl and apt-get so REMOVE_WARP=true path is harmless.
cat > "$SHIM_BIN/systemctl" <<'SC'
#!/usr/bin/env bash
echo "mock systemctl $*"
exit 0
SC
chmod +x "$SHIM_BIN/systemctl"
cat > "$SHIM_BIN/apt-get" <<'AG'
#!/usr/bin/env bash
echo "mock apt-get $*"
exit 0
AG
chmod +x "$SHIM_BIN/apt-get"

SCRIPT="$ROOT_DIR/cleanup/cleanup.sh"

run_cleanup() {
  env STATE_FILE="$1" \
    REMOVE_WARP="${REMOVE_WARP:-false}" \
    SUDO="" \
    PATH="$SHIM_BIN:$PATH" \
    MOCK_WARP_CONFIG="$SANDBOX/config" \
    MOCK_WARP_STATE="$SANDBOX/mwstate" \
    bash "$SCRIPT" 2>&1
}

echo "=== cleanup (no state file) ==="
STATE="$SANDBOX/state-missing"
rm -f "$STATE"
OUT=$(run_cleanup "$STATE")
RC=$?
assert_equals "exit 0 with no state" "0" "$RC"
assert_contains "explains nothing to do" "$OUT" "nothing to clean up"

echo "=== cleanup (happy path) ==="
STATE="$SANDBOX/state-ok"
MDM_FILE="$SANDBOX/mdm.xml"
echo "fake mdm" > "$MDM_FILE"
cat > "$STATE" <<EOF
MDM_PATH=$MDM_FILE
REGISTERED=true
INSTALLED=true
EOF
: > "$SANDBOX/config"
rm -f "$SANDBOX/mwstate"
OUT=$(run_cleanup "$STATE")
RC=$?
assert_equals "exit 0" "0" "$RC"
assert_contains "disconnects" "$OUT" "Disconnecting WARP"
assert_contains "deletes registration" "$OUT" "Deleting device registration"
assert_contains "removes mdm file" "$OUT" "Removed MDM file"
assert_file_not_exists "MDM file gone" "$MDM_FILE"
assert_file_not_exists "state file gone" "$STATE"

echo "=== cleanup (warp-cli not on PATH) ==="
STATE="$SANDBOX/state-nowarp"
MDM_FILE="$SANDBOX/mdm-nowarp"
echo "fake" > "$MDM_FILE"
cat > "$STATE" <<EOF
MDM_PATH=$MDM_FILE
REGISTERED=true
INSTALLED=true
EOF
# Override PATH to one without warp-cli (no SHIM_BIN).
OUT=$(env STATE_FILE="$STATE" REMOVE_WARP=false SUDO="" PATH="/usr/bin:/bin" \
  bash "$SCRIPT" 2>&1)
RC=$?
assert_equals "exit 0 even without warp-cli" "0" "$RC"
assert_contains "explains warp-cli missing" "$OUT" "warp-cli not available"
assert_file_not_exists "MDM file still removed" "$MDM_FILE"

echo "=== cleanup (malformed state file - no MDM_PATH line) ==="
STATE="$SANDBOX/state-malformed"
cat > "$STATE" <<EOF
GARBAGE=line
NOT_THE_KEY=true
EOF
: > "$SANDBOX/config"
rm -f "$SANDBOX/mwstate"
OUT=$(run_cleanup "$STATE")
RC=$?
assert_equals "exit 0 on malformed state" "0" "$RC"
assert_contains "cleanup completes" "$OUT" "Cleanup complete"

echo "=== cleanup (registration delete fails - falls back to teams-unenroll) ==="
STATE="$SANDBOX/state-regfail"
MDM_FILE="$SANDBOX/mdm-regfail"
echo "fake" > "$MDM_FILE"
cat > "$STATE" <<EOF
MDM_PATH=$MDM_FILE
REGISTERED=true
INSTALLED=true
EOF
echo "REGISTRATION_FAILS=1" > "$SANDBOX/config"
rm -f "$SANDBOX/mwstate"
OUT=$(run_cleanup "$STATE")
RC=$?
assert_equals "exit 0 even when reg delete fails" "0" "$RC"
assert_contains "teams-unenroll fallback used" "$OUT" "Unenrolled via teams-unenroll"

echo "=== cleanup (remove-warp=true) ==="
STATE="$SANDBOX/state-rm"
MDM_FILE="$SANDBOX/mdm-rm"
echo "fake" > "$MDM_FILE"
cat > "$STATE" <<EOF
MDM_PATH=$MDM_FILE
REGISTERED=true
INSTALLED=true
EOF
: > "$SANDBOX/config"
rm -f "$SANDBOX/mwstate"
OUT=$(REMOVE_WARP=true run_cleanup "$STATE")
RC=$?
assert_equals "exit 0" "0" "$RC"
assert_contains "uninstall reported" "$OUT" "Uninstalling cloudflare-warp"
assert_contains "calls apt-get" "$OUT" "mock apt-get"
