#!/usr/bin/env bash
# Restart warp-svc to pick up the MDM file, then wait for auto-registration.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"

DAEMON_WAIT_MAX="${DAEMON_WAIT_MAX:-30}"
REGISTRATION_WAIT_MAX="${REGISTRATION_WAIT_MAX:-60}"
SUDO="${SUDO-sudo}"

echo "Restarting warp-svc to apply MDM configuration..."
$SUDO systemctl restart warp-svc

if ! wait_for_daemon "$DAEMON_WAIT_MAX"; then
  echo "ERROR: warp-svc did not restart within ${DAEMON_WAIT_MAX} seconds." >&2
  $SUDO systemctl status warp-svc --no-pager || true
  exit 1
fi

echo "Waiting for registration..."
if wait_for_registration "$REGISTRATION_WAIT_MAX"; then
  warp-cli --accept-tos registration show 2>&1 | redact_registration
  exit 0
fi

echo "ERROR: Device registration did not complete within ${REGISTRATION_WAIT_MAX} seconds." >&2
echo "--- warp-cli status ---"
warp-cli --accept-tos status || true
echo "--- journalctl -u warp-svc ---"
$SUDO journalctl -u warp-svc --no-pager -n 80 || true
exit 1
