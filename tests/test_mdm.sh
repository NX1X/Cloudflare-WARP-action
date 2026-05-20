#!/usr/bin/env bash
# Tests for scripts/04-write-mdm.sh: actual file content, permissions,
# redaction, and verification that the script invokes `install` with the
# `-o root -g root` flags (we shim `install` to capture args).
set -uo pipefail

THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$THIS_DIR/.." && pwd)"
# shellcheck source=helpers.sh
. "$THIS_DIR/helpers.sh"

SCRIPT="$ROOT_DIR/scripts/04-write-mdm.sh"

SANDBOX=$(mktemp -d)
trap 'rm -rf "$SANDBOX"' EXIT

# Shim `install` so we can capture args and avoid root chown. We log args to
# $SANDBOX/install-args and emulate the file copy ourselves.
SHIM_BIN="$SANDBOX/bin"
mkdir -p "$SHIM_BIN"
cat > "$SHIM_BIN/install" <<'SHIM'
#!/usr/bin/env bash
echo "$@" > "$INSTALL_ARGS_FILE"
# Last two args are src and dst; copy and chmod accordingly.
src="${@: -2:1}"
dst="${@: -1:1}"
mkdir -p "$(dirname "$dst")"
cp "$src" "$dst"
# Parse -m mode if present
mode=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    -m) mode="$2"; shift 2 ;;
    *) shift ;;
  esac
done
[ -n "$mode" ] && chmod "$mode" "$dst"
SHIM
chmod +x "$SHIM_BIN/install"

MDM_PATH_FILE="$SANDBOX/mdm.xml"
INSTALL_ARGS_FILE="$SANDBOX/install-args"

OUT=$(env -i \
  PATH="$SHIM_BIN:$PATH" \
  INSTALL_ARGS_FILE="$INSTALL_ARGS_FILE" \
  ORGANIZATION="acme-corp" \
  AUTH_CLIENT_ID="id-12345.access" \
  AUTH_CLIENT_SECRET="super-secret-67890" \
  MODE="warp" \
  MDM_PATH="$MDM_PATH_FILE" \
  SUDO="" \
  bash "$SCRIPT" 2>&1)
RC=$?

echo "=== 04-write-mdm.sh ==="
assert_equals "script exits 0" "0" "$RC"
assert_file_exists "MDM file created" "$MDM_PATH_FILE"
assert_file_perms "MDM file is 600" "$MDM_PATH_FILE" "600"

CONTENT=$(cat "$MDM_PATH_FILE")
assert_contains "has <dict>" "$CONTENT" "<dict>"
assert_contains "has organization key" "$CONTENT" "<key>organization</key>"
assert_contains "has auth_client_id key" "$CONTENT" "<key>auth_client_id</key>"
assert_contains "has auth_client_secret key" "$CONTENT" "<key>auth_client_secret</key>"
assert_contains "has service_mode key" "$CONTENT" "<key>service_mode</key>"
assert_contains "has auto_connect" "$CONTENT" "<integer>1</integer>"
assert_contains "has onboarding false" "$CONTENT" "<false/>"
assert_contains "has switch_locked true" "$CONTENT" "<true/>"
assert_contains "org value present" "$CONTENT" "<string>acme-corp</string>"
assert_contains "client id present" "$CONTENT" "<string>id-12345.access</string>"
assert_contains "secret present (on disk only)" "$CONTENT" "<string>super-secret-67890</string>"
assert_contains "mode value present" "$CONTENT" "<string>warp</string>"

echo "=== install invoked with correct flags ==="
assert_file_exists "install-args captured" "$INSTALL_ARGS_FILE"
INSTALL_ARGS=$(cat "$INSTALL_ARGS_FILE")
assert_contains "-m 600 used" "$INSTALL_ARGS" "-m 600"
assert_contains "-o root used" "$INSTALL_ARGS" "-o root"
assert_contains "-g root used" "$INSTALL_ARGS" "-g root"
assert_contains "dest path used" "$INSTALL_ARGS" "$MDM_PATH_FILE"

echo "=== redacted output (the script's own printout) ==="
assert_contains "output mentions redacted heading" "$OUT" "credentials redacted"
assert_contains "output contains <REDACTED>" "$OUT" "<REDACTED>"
assert_not_contains "secret not in printed output" "$OUT" "super-secret-67890"
assert_not_contains "client id not in printed output" "$OUT" "id-12345.access"
# Key names should still be visible in the redacted output
assert_contains "key names visible in output" "$OUT" "<key>auth_client_secret</key>"

echo "=== XML injection safety (special chars in secret) ==="
rm -f "$MDM_PATH_FILE" "$INSTALL_ARGS_FILE"
DANGEROUS='value$(whoami)`id`; rm -rf /'
env -i \
  PATH="$SHIM_BIN:$PATH" \
  INSTALL_ARGS_FILE="$INSTALL_ARGS_FILE" \
  ORGANIZATION="acme-corp" \
  AUTH_CLIENT_ID="$DANGEROUS" \
  AUTH_CLIENT_SECRET="another\$dangerous\`value" \
  MODE="warp" \
  MDM_PATH="$MDM_PATH_FILE" \
  SUDO="" \
  bash "$SCRIPT" >/dev/null 2>&1
DANGEROUS_CONTENT=$(cat "$MDM_PATH_FILE")
assert_contains "dangerous value written verbatim" "$DANGEROUS_CONTENT" "$DANGEROUS"
assert_not_contains "command substitution did not run (no root id)" "$DANGEROUS_CONTENT" "uid=0"
