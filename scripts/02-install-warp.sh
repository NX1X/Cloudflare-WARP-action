#!/usr/bin/env bash
# Install cloudflare-warp from Cloudflare's apt repo and emit warp-version.
set -euo pipefail

if ! command -v lsb_release > /dev/null; then
  echo "ERROR: lsb_release not found. This action requires an Ubuntu/Debian runner." >&2
  exit 1
fi

echo "Adding Cloudflare WARP apt repository..."
curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg \
  | sudo gpg --yes --dearmor --output /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg

DISTRO_CODENAME=$(lsb_release -cs)
echo "deb [signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ ${DISTRO_CODENAME} main" \
  | sudo tee /etc/apt/sources.list.d/cloudflare-client.list > /dev/null

sudo apt-get update --assume-yes
sudo apt-get install --assume-yes cloudflare-warp

WARP_VERSION_RAW=$(warp-cli --version 2>&1 | head -n1)
echo "$WARP_VERSION_RAW"
WARP_VERSION=$(echo "$WARP_VERSION_RAW" | sed -n 's/^warp-cli \([^ ]*\).*/\1/p')
if [ -z "$WARP_VERSION" ]; then
  WARP_VERSION="$WARP_VERSION_RAW"
fi
if [ -n "${GITHUB_OUTPUT:-}" ]; then
  echo "warp-version=${WARP_VERSION}" >> "$GITHUB_OUTPUT"
fi
