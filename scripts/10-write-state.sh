#!/usr/bin/env bash
# Write cleanup-state file. Paths and flags only - no credentials.
set -euo pipefail

STATE_FILE="${STATE_FILE:-$HOME/.cloudflare-warp-state}"
MDM_PATH="${MDM_PATH:-/var/lib/cloudflare-warp/mdm.xml}"

{
  echo "MDM_PATH=$MDM_PATH"
  echo "REGISTERED=true"
  echo "INSTALLED=true"
} > "$STATE_FILE"
echo "State file written to $STATE_FILE"
