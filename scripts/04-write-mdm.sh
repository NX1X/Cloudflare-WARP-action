#!/usr/bin/env bash
# Write the MDM XML file used for headless service-token enrollment.
# Reads ORGANIZATION, AUTH_CLIENT_ID, AUTH_CLIENT_SECRET, MODE from env.
# MDM_PATH (default /var/lib/cloudflare-warp/mdm.xml) and SUDO (default "sudo")
# are overridable so tests can drive the script without root.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"

: "${ORGANIZATION:?ORGANIZATION not set}"
: "${AUTH_CLIENT_ID:?AUTH_CLIENT_ID not set}"
: "${AUTH_CLIENT_SECRET:?AUTH_CLIENT_SECRET not set}"
: "${MODE:?MODE not set}"
MDM_PATH="${MDM_PATH:-/var/lib/cloudflare-warp/mdm.xml}"
SUDO="${SUDO-sudo}"

$SUDO mkdir -p "$(dirname "$MDM_PATH")"

TMP_MDM=$(mktemp)
{
  printf '<dict>\n'
  printf '    <key>organization</key>\n'
  printf '    <string>%s</string>\n' "$ORGANIZATION"
  printf '    <key>auth_client_id</key>\n'
  printf '    <string>%s</string>\n' "$AUTH_CLIENT_ID"
  printf '    <key>auth_client_secret</key>\n'
  printf '    <string>%s</string>\n' "$AUTH_CLIENT_SECRET"
  printf '    <key>service_mode</key>\n'
  printf '    <string>%s</string>\n' "$MODE"
  printf '    <key>auto_connect</key>\n'
  printf '    <integer>1</integer>\n'
  printf '    <key>onboarding</key>\n'
  printf '    <false/>\n'
  printf '    <key>switch_locked</key>\n'
  printf '    <true/>\n'
  printf '</dict>\n'
} > "$TMP_MDM"

$SUDO install -m 600 -o root -g root "$TMP_MDM" "$MDM_PATH"
rm -f "$TMP_MDM"

echo "MDM file written (credentials redacted):"
$SUDO cat "$MDM_PATH" | redact_strings
