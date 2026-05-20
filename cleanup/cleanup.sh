#!/usr/bin/env bash
# Cleanup sub-action: disconnect, deregister, remove MDM file, optionally
# uninstall the package. Always exits 0 on missing/empty state (the action may
# not have run far enough to write one).
set -uo pipefail

STATE_FILE="${STATE_FILE:-$HOME/.cloudflare-warp-state}"
REMOVE_WARP="${REMOVE_WARP:-false}"
SUDO="${SUDO-sudo}"

if [ ! -f "$STATE_FILE" ]; then
  echo "No state file found at $STATE_FILE - nothing to clean up."
  echo "This is normal if the main action did not complete successfully."
  exit 0
fi

MDM_PATH=$(grep '^MDM_PATH=' "$STATE_FILE" | cut -d'=' -f2-)
REGISTERED=$(grep '^REGISTERED=' "$STATE_FILE" | cut -d'=' -f2-)
INSTALLED=$(grep '^INSTALLED=' "$STATE_FILE" | cut -d'=' -f2-)

if [ "$INSTALLED" = "true" ] && command -v warp-cli > /dev/null; then
  echo "Disconnecting WARP..."
  warp-cli --accept-tos disconnect 2>/dev/null || echo "warp-cli disconnect: already disconnected or daemon down"

  if [ "$REGISTERED" = "true" ]; then
    echo "Deleting device registration..."
    warp-cli --accept-tos registration delete 2>/dev/null \
      || warp-cli --accept-tos teams-unenroll 2>/dev/null \
      || echo "Could not delete registration (may already be removed)"
  fi
else
  echo "warp-cli not available - skipping disconnect/unregister."
fi

if [ -n "$MDM_PATH" ] && $SUDO test -f "$MDM_PATH"; then
  $SUDO rm -f "$MDM_PATH"
  echo "Removed MDM file: $MDM_PATH"
fi

if [ "$REMOVE_WARP" = "true" ]; then
  echo "Uninstalling cloudflare-warp..."
  $SUDO systemctl stop warp-svc 2>/dev/null || true
  $SUDO apt-get remove --assume-yes --purge cloudflare-warp 2>/dev/null \
    || echo "cloudflare-warp not installed or already removed"
  $SUDO rm -f /etc/apt/sources.list.d/cloudflare-client.list
  $SUDO rm -f /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg
fi

rm -f "$STATE_FILE"
echo "Removed state file"
echo "Cleanup complete."
