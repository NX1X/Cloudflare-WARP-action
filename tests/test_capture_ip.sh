#!/usr/bin/env bash
# Tests for scripts/09-capture-ip.sh. Shim `ip` to control output.
set -uo pipefail

THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$THIS_DIR/.." && pwd)"
# shellcheck source=helpers.sh
. "$THIS_DIR/helpers.sh"

SANDBOX=$(mktemp -d)
trap 'rm -rf "$SANDBOX"' EXIT

SHIM_BIN="$SANDBOX/bin"
mkdir -p "$SHIM_BIN"

write_ip_shim() {
  cat > "$SHIM_BIN/ip" <<SHIM
#!/usr/bin/env bash
$1
SHIM
  chmod +x "$SHIM_BIN/ip"
}

SCRIPT="$ROOT_DIR/scripts/09-capture-ip.sh"

echo "=== capture-ip (interface present with IPv4) ==="
write_ip_shim '
if [ "$1" = "-4" ] && [ "$2" = "addr" ] && [ "$3" = "show" ] && [ "$4" = "CloudflareWARP" ]; then
  echo "3: CloudflareWARP <POINTOPOINT,MULTICAST,NOARP,UP,LOWER_UP> mtu 1280 qdisc fq_codel state UNKNOWN group default qlen 500"
  echo "    inet 100.96.1.42/32 scope global CloudflareWARP"
  exit 0
fi
if [ "$1" = "-4" ] && [ "$2" = "-o" ] && [ "$3" = "addr" ] && [ "$4" = "show" ] && [ "$5" = "CloudflareWARP" ]; then
  echo "3: CloudflareWARP    inet 100.96.1.42/32 scope global CloudflareWARP\\       valid_lft forever preferred_lft forever"
  exit 0
fi
exit 1
'
GH_OUT="$SANDBOX/gh_out"
: > "$GH_OUT"
OUT=$(env GITHUB_OUTPUT="$GH_OUT" PATH="$SHIM_BIN:$PATH" bash "$SCRIPT" 2>&1)
RC=$?
assert_equals "exit 0" "0" "$RC"
assert_contains "prints IP" "$OUT" "100.96.1.42"
assert_contains "writes warp-ip" "$(cat "$GH_OUT")" "warp-ip=100.96.1.42"

echo "=== capture-ip (interface missing - doh-style) ==="
write_ip_shim 'exit 1'
GH_OUT="$SANDBOX/gh_out2"
: > "$GH_OUT"
OUT=$(env GITHUB_OUTPUT="$GH_OUT" PATH="$SHIM_BIN:$PATH" bash "$SCRIPT" 2>&1)
RC=$?
assert_equals "exit 0" "0" "$RC"
assert_contains "explains empty" "$OUT" "normal for mode=doh"
assert_contains "writes empty warp-ip" "$(cat "$GH_OUT")" "warp-ip="
# Ensure no IP value snuck in.
assert_not_contains "no stray IP in output file" "$(cat "$GH_OUT")" "100.96"
