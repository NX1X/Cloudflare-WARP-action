#!/usr/bin/env bash
# Issue an explicit warp-cli connect. auto_connect=1 in the MDM should already
# trigger connection - this is belt-and-braces and a no-op if already connected.
set -euo pipefail

echo "Issuing warp-cli connect..."
warp-cli --accept-tos connect || true
