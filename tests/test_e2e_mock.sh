#!/usr/bin/env bash
# End-to-end pipeline run against the mock warp-cli. Exercises:
# 01-validate-inputs -> 04-write-mdm -> 05-restart-and-register
#   -> 06-split-tunnel -> 07-connect -> 08-verify-connection
#   -> 09-capture-ip -> 10-write-state -> cleanup.sh
# Steps 02 (apt install) and 03 (real systemctl) are skipped since they are
# host-level and already covered by their own tests.
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

# Shims for sudo, systemctl, journalctl, install, ip, ping.
cat > "$SHIM_BIN/sudo" <<'SH'
#!/usr/bin/env bash
exec "$@"
SH
chmod +x "$SHIM_BIN/sudo"
cat > "$SHIM_BIN/systemctl" <<'SH'
#!/usr/bin/env bash
echo "mock systemctl $*"
SH
chmod +x "$SHIM_BIN/systemctl"
cat > "$SHIM_BIN/journalctl" <<'SH'
#!/usr/bin/env bash
echo "mock journalctl $*"
SH
chmod +x "$SHIM_BIN/journalctl"
cat > "$SHIM_BIN/install" <<'SH'
#!/usr/bin/env bash
# Drop -o/-g (chown without root) but honour -m
mode=""
src=""
dst=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    -m) mode="$2"; shift 2 ;;
    -o|-g) shift 2 ;;
    *)
      if [ -z "$src" ]; then src="$1"
      elif [ -z "$dst" ]; then dst="$1"
      fi
      shift ;;
  esac
done
mkdir -p "$(dirname "$dst")"
cp "$src" "$dst"
[ -n "$mode" ] && chmod "$mode" "$dst"
SH
chmod +x "$SHIM_BIN/install"
cat > "$SHIM_BIN/ip" <<'SH'
#!/usr/bin/env bash
# Mimic CloudflareWARP interface present.
if [ "$1" = "-4" ] && [ "$2" = "addr" ] && [ "$4" = "CloudflareWARP" ]; then
  echo "    inet 100.96.1.42/32 scope global CloudflareWARP"
  exit 0
fi
if [ "$1" = "-4" ] && [ "$2" = "-o" ] && [ "$5" = "CloudflareWARP" ]; then
  echo "3: CloudflareWARP    inet 100.96.1.42/32 scope global CloudflareWARP"
  exit 0
fi
exit 1
SH
chmod +x "$SHIM_BIN/ip"
cat > "$SHIM_BIN/ping" <<'SH'
#!/usr/bin/env bash
echo "PING mock $*"
SH
chmod +x "$SHIM_BIN/ping"

export PATH="$SHIM_BIN:$PATH"
export MOCK_WARP_CONFIG="$SANDBOX/config"
export MOCK_WARP_STATE="$SANDBOX/mwstate"
# Simulate MDM-driven registration completing within 1s of daemon startup.
echo "REGISTERED_AFTER=1" > "$MOCK_WARP_CONFIG"
rm -f "$MOCK_WARP_STATE"

MDM_FILE="$SANDBOX/mdm.xml"
STATE_FILE="$SANDBOX/.cloudflare-warp-state"
GH_OUT="$SANDBOX/gh_output"
: > "$GH_OUT"

echo "=== e2e: validate inputs ==="
OUT=$(env MODE="warp" RETRY_COUNT="2" RETRY_DELAY="1" \
  ORGANIZATION="acme-corp" EXCLUDE_ROUTES="" INCLUDE_ROUTES="10.0.0.0/8" \
  bash "$ROOT_DIR/scripts/01-validate-inputs.sh" 2>&1)
RC=$?
assert_equals "validate-inputs OK" "0" "$RC"
assert_contains "prints success" "$OUT" "Inputs validated"

echo "=== e2e: write MDM ==="
OUT=$(env ORGANIZATION="acme-corp" \
  AUTH_CLIENT_ID="client-id.access" \
  AUTH_CLIENT_SECRET="super-secret" \
  MODE="warp" \
  MDM_PATH="$MDM_FILE" \
  SUDO="" \
  bash "$ROOT_DIR/scripts/04-write-mdm.sh" 2>&1)
RC=$?
assert_equals "write-mdm OK" "0" "$RC"
assert_file_exists "MDM file" "$MDM_FILE"
assert_file_perms "MDM file 600" "$MDM_FILE" "600"

echo "=== e2e: restart and register ==="
OUT=$(env DAEMON_WAIT_MAX=5 REGISTRATION_WAIT_MAX=5 SUDO="" \
  bash "$ROOT_DIR/scripts/05-restart-and-register.sh" 2>&1)
RC=$?
assert_equals "restart-register OK" "0" "$RC"
assert_contains "registration completed" "$OUT" "Device registered"

echo "=== e2e: split tunnel (include) ==="
OUT=$(env EXCLUDE_ROUTES="" INCLUDE_ROUTES="10.0.0.0/8" \
  bash "$ROOT_DIR/scripts/06-split-tunnel.sh" 2>&1)
RC=$?
assert_equals "split-tunnel OK" "0" "$RC"
assert_contains "route added" "$OUT" "10.0.0.0/8"

echo "=== e2e: connect ==="
OUT=$(bash "$ROOT_DIR/scripts/07-connect.sh" 2>&1)
RC=$?
assert_equals "connect OK" "0" "$RC"

echo "=== e2e: verify connection ==="
OUT=$(env GITHUB_OUTPUT="$GH_OUT" RETRY_COUNT=3 RETRY_DELAY=1 TEST_HOST="10.0.0.1" \
  bash "$ROOT_DIR/scripts/08-verify-connection.sh" 2>&1)
RC=$?
assert_equals "verify OK" "0" "$RC"
assert_contains "writes connected" "$(cat "$GH_OUT")" "connection-status=connected"

echo "=== e2e: capture IP ==="
OUT=$(env GITHUB_OUTPUT="$GH_OUT" bash "$ROOT_DIR/scripts/09-capture-ip.sh" 2>&1)
RC=$?
assert_equals "capture-ip OK" "0" "$RC"
assert_contains "writes warp-ip" "$(cat "$GH_OUT")" "warp-ip=100.96.1.42"

echo "=== e2e: write state ==="
OUT=$(env STATE_FILE="$STATE_FILE" MDM_PATH="$MDM_FILE" \
  bash "$ROOT_DIR/scripts/10-write-state.sh" 2>&1)
RC=$?
assert_equals "write-state OK" "0" "$RC"
assert_file_exists "state file written" "$STATE_FILE"

echo "=== e2e: cleanup ==="
OUT=$(env STATE_FILE="$STATE_FILE" REMOVE_WARP=false SUDO="" \
  bash "$ROOT_DIR/cleanup/cleanup.sh" 2>&1)
RC=$?
assert_equals "cleanup OK" "0" "$RC"
assert_file_not_exists "MDM removed" "$MDM_FILE"
assert_file_not_exists "state removed" "$STATE_FILE"
