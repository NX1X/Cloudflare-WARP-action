#!/usr/bin/env bash
# Tests for the registration-wait logic and redaction of registration-show output.
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

# Shim sudo / systemctl / journalctl so 05-restart-and-register.sh works
# without root.
cat > "$SHIM_BIN/sudo" <<'SUDOSHIM'
#!/usr/bin/env bash
exec "$@"
SUDOSHIM
chmod +x "$SHIM_BIN/sudo"
cat > "$SHIM_BIN/systemctl" <<'SCSHIM'
#!/usr/bin/env bash
echo "mock systemctl $*"
exit 0
SCSHIM
chmod +x "$SHIM_BIN/systemctl"
cat > "$SHIM_BIN/journalctl" <<'JCSHIM'
#!/usr/bin/env bash
echo "mock journalctl $*"
JCSHIM
chmod +x "$SHIM_BIN/journalctl"

export PATH="$SHIM_BIN:$PATH"
export MOCK_WARP_CONFIG="$SANDBOX/config"
export MOCK_WARP_STATE="$SANDBOX/state"

# shellcheck source=../scripts/lib/common.sh
. "$ROOT_DIR/scripts/lib/common.sh"

echo "=== wait_for_registration (ready immediately, fresh state) ==="
: > "$MOCK_WARP_CONFIG"
rm -f "$MOCK_WARP_STATE"
# In fresh state without REGISTERED_AFTER, registration show fails.
if wait_for_registration 2 >/dev/null 2>&1; then RC=0; else RC=1; fi
assert_not_equals "fresh-not-registered fails" "0" "$RC"

echo "=== wait_for_registration (mdm-driven registration after 2s) ==="
echo "REGISTERED_AFTER=2" > "$MOCK_WARP_CONFIG"
rm -f "$MOCK_WARP_STATE"
START=$(date +%s)
wait_for_registration 10 >/dev/null 2>&1
RC=$?
ELAPSED=$(( $(date +%s) - START ))
assert_equals "delayed-register succeeds" "0" "$RC"
if [ "$ELAPSED" -ge 1 ] && [ "$ELAPSED" -le 5 ]; then
  _pass "waited about 2s (actual: ${ELAPSED}s)"
else
  _fail "elapsed unexpected (${ELAPSED}s)"
fi
TESTS=$((TESTS + 1))

echo "=== redact_registration ==="
RAW='Device ID: abc-123-secret
Account ID: acct-456-private
Public Key: pubkey-9999AAAA
Token: tok-xxxxxxxx
Some other line: visible'
REDACTED=$(echo "$RAW" | redact_registration)
assert_not_contains "device id hidden" "$REDACTED" "abc-123-secret"
assert_not_contains "account id hidden" "$REDACTED" "acct-456-private"
assert_not_contains "public key hidden" "$REDACTED" "pubkey-9999AAAA"
assert_not_contains "token hidden" "$REDACTED" "tok-xxxxxxxx"
assert_contains "device id label kept" "$REDACTED" "Device ID:"
assert_contains "account id label kept" "$REDACTED" "Account ID:"
assert_contains "public key label kept" "$REDACTED" "Public Key:"
assert_contains "token label kept" "$REDACTED" "Token:"
assert_contains "other lines pass through" "$REDACTED" "Some other line: visible"
assert_contains "REDACTED placeholder present" "$REDACTED" "<REDACTED>"

echo "=== 05-restart-and-register.sh (success path) ==="
echo "REGISTERED_AFTER=1" > "$MOCK_WARP_CONFIG"
rm -f "$MOCK_WARP_STATE"
OUT=$(env DAEMON_WAIT_MAX=5 REGISTRATION_WAIT_MAX=5 \
  PATH="$SHIM_BIN:$PATH" \
  MOCK_WARP_CONFIG="$MOCK_WARP_CONFIG" MOCK_WARP_STATE="$MOCK_WARP_STATE" \
  bash "$ROOT_DIR/scripts/05-restart-and-register.sh" 2>&1)
RC=$?
assert_equals "exits 0 on registration success" "0" "$RC"
assert_contains "reports restart" "$OUT" "Restarting warp-svc"
assert_contains "reports registered" "$OUT" "Device registered"
# Real values should be redacted from the script's output.
assert_not_contains "device id redacted in script output" "$OUT" "mock-device-id-12345"
assert_not_contains "account id redacted" "$OUT" "mock-account-id-aaaa"
assert_not_contains "pubkey redacted" "$OUT" "mock-pubkey-aaaaaaaaaaaaaaaaaaaa"
assert_not_contains "token redacted" "$OUT" "mock-token-aaaaaaaaaaaaaaaaaaaa"

echo "=== 05-restart-and-register.sh (registration timeout) ==="
echo "REGISTERED_AFTER=999" > "$MOCK_WARP_CONFIG"
rm -f "$MOCK_WARP_STATE"
OUT=$(env DAEMON_WAIT_MAX=5 REGISTRATION_WAIT_MAX=2 \
  PATH="$SHIM_BIN:$PATH" \
  MOCK_WARP_CONFIG="$MOCK_WARP_CONFIG" MOCK_WARP_STATE="$MOCK_WARP_STATE" \
  bash "$ROOT_DIR/scripts/05-restart-and-register.sh" 2>&1)
RC=$?
assert_not_equals "exits non-zero on reg timeout" "0" "$RC"
assert_contains "reports registration timeout" "$OUT" "Device registration did not complete"

echo "=== 05-restart-and-register.sh (daemon never returns after restart) ==="
echo "DAEMON_READY_AFTER=999" > "$MOCK_WARP_CONFIG"
rm -f "$MOCK_WARP_STATE"
OUT=$(env DAEMON_WAIT_MAX=2 REGISTRATION_WAIT_MAX=2 \
  PATH="$SHIM_BIN:$PATH" \
  MOCK_WARP_CONFIG="$MOCK_WARP_CONFIG" MOCK_WARP_STATE="$MOCK_WARP_STATE" \
  bash "$ROOT_DIR/scripts/05-restart-and-register.sh" 2>&1)
RC=$?
assert_not_equals "exits non-zero on daemon timeout" "0" "$RC"
assert_contains "reports daemon restart failure" "$OUT" "did not restart"
