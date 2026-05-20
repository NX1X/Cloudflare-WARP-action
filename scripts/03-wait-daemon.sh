#!/usr/bin/env bash
# Wait for the warp-svc daemon's IPC socket to become ready.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"

DAEMON_WAIT_MAX="${DAEMON_WAIT_MAX:-30}"

echo "Waiting for warp-svc to become ready..."
if wait_for_daemon "$DAEMON_WAIT_MAX"; then
  exit 0
fi

echo "ERROR: warp-svc did not become ready within ${DAEMON_WAIT_MAX} seconds." >&2
echo "--- systemctl status warp-svc ---"
sudo systemctl status warp-svc --no-pager || true
echo "--- journalctl -u warp-svc ---"
sudo journalctl -u warp-svc --no-pager -n 50 || true
exit 1
