#!/usr/bin/env bash
# Capture the IPv4 address assigned to the CloudflareWARP tunnel interface.
# Empty string is the expected value when the interface is missing (mode=doh).
set -euo pipefail

WARP_IP=""
if ip -4 addr show CloudflareWARP > /dev/null 2>&1; then
  WARP_IP=$(ip -4 -o addr show CloudflareWARP | awk '{print $4}' | cut -d/ -f1 | head -n1)
fi
if [ -n "$WARP_IP" ]; then
  echo "WARP IPv4 address: ${WARP_IP}"
else
  echo "CloudflareWARP interface has no IPv4 address (this is normal for mode=doh)."
fi
if [ -n "${GITHUB_OUTPUT:-}" ]; then
  echo "warp-ip=${WARP_IP}" >> "$GITHUB_OUTPUT"
fi
