#!/usr/bin/env bash
# Tests for scripts/02-install-warp.sh. Shims every external command the script
# touches (lsb_release, curl, gpg, sudo, tee, apt-get, warp-cli) so the install
# path can be exercised without network or root. Also verifies the warp-version
# output is written to $GITHUB_OUTPUT in the expected key=value format, and
# that set -e actually trips when an intermediate command (curl) fails.
set -uo pipefail

THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$THIS_DIR/.." && pwd)"
# shellcheck source=helpers.sh
. "$THIS_DIR/helpers.sh"

SCRIPT="$ROOT_DIR/scripts/02-install-warp.sh"
SANDBOX=$(mktemp -d)
trap 'rm -rf "$SANDBOX"' EXIT

SHIM_BIN="$SANDBOX/bin"
mkdir -p "$SHIM_BIN"
CALL_LOG="$SANDBOX/calls.log"

write_shims() {
  local curl_mode="${1:-ok}"

  cat > "$SHIM_BIN/lsb_release" <<'SHIM'
#!/usr/bin/env bash
echo "lsb_release $*" >> "$CALL_LOG"
case "$1" in
  -cs) echo "noble" ;;
  *) echo "no" ;;
esac
SHIM

  cat > "$SHIM_BIN/curl" <<SHIM
#!/usr/bin/env bash
echo "curl \$*" >> "\$CALL_LOG"
if [ "$curl_mode" = "fail" ]; then exit 22; fi
# Pretend pubkey bytes
printf 'FAKE_GPG_KEY_BYTES'
SHIM

  cat > "$SHIM_BIN/gpg" <<'SHIM'
#!/usr/bin/env bash
echo "gpg $*" >> "$CALL_LOG"
# Parse --output <path>; write whatever is on stdin there.
out=""
while [ $# -gt 0 ]; do
  case "$1" in
    --output) out="$2"; shift 2 ;;
    *) shift ;;
  esac
done
if [ -n "$out" ]; then
  mkdir -p "$(dirname "$out")"
  cat > "$out"
else
  cat > /dev/null
fi
SHIM

  # sudo: exec the rest of args. The script invokes `sudo gpg ...`, `sudo tee
  # ...`, `sudo apt-get ...`. We log + exec.
  cat > "$SHIM_BIN/sudo" <<'SHIM'
#!/usr/bin/env bash
echo "sudo $*" >> "$CALL_LOG"
exec "$@"
SHIM

  cat > "$SHIM_BIN/tee" <<'SHIM'
#!/usr/bin/env bash
# Capture both the args AND the stdin payload so tests can assert what was
# written through the pipeline (the apt source line lives in stdin, not argv).
dst="${@: -1:1}"
echo "tee $*" >> "$CALL_LOG"
mkdir -p "$(dirname "$dst")" 2>/dev/null || true
payload=$(cat)
printf '%s' "$payload" > "$dst" 2>/dev/null || true
echo "tee-stdin: $payload" >> "$CALL_LOG"
SHIM

  cat > "$SHIM_BIN/apt-get" <<'SHIM'
#!/usr/bin/env bash
echo "apt-get $*" >> "$CALL_LOG"
exit 0
SHIM

  cat > "$SHIM_BIN/warp-cli" <<'SHIM'
#!/usr/bin/env bash
echo "warp-cli $*" >> "$CALL_LOG"
case "$1" in
  --version) echo "warp-cli 2026.1.987 (mocked)" ;;
  *) ;;
esac
SHIM

  chmod +x "$SHIM_BIN"/*
}

run_install() {
  local gh_out="$1"
  : > "$CALL_LOG"
  env -i \
    HOME="$SANDBOX" \
    PATH="$SHIM_BIN:/usr/bin:/bin" \
    CALL_LOG="$CALL_LOG" \
    GITHUB_OUTPUT="$gh_out" \
    bash "$SCRIPT" 2>&1
}

echo "=== install (happy path) ==="
write_shims ok
GH_OUT="$SANDBOX/gh_out"
: > "$GH_OUT"
OUT=$(run_install "$GH_OUT")
RC=$?
assert_equals "exit 0" "0" "$RC"
CALLS=$(cat "$CALL_LOG")
assert_contains "lsb_release -cs was called" "$CALLS" "lsb_release -cs"
assert_contains "curl pulled the pubkey" "$CALLS" "https://pkg.cloudflareclient.com/pubkey.gpg"
assert_contains "gpg dearmored to keyring path" "$CALLS" "/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg"
assert_contains "gpg invoked with --dearmor" "$CALLS" "--dearmor"
assert_contains "apt source list written via tee" "$CALLS" "/etc/apt/sources.list.d/cloudflare-client.list"
assert_contains "apt-get update ran" "$CALLS" "apt-get update --assume-yes"
assert_contains "apt-get install ran for cloudflare-warp" "$CALLS" "apt-get install --assume-yes cloudflare-warp"
assert_contains "warp-cli --version was called" "$CALLS" "warp-cli --version"
assert_contains "sudo was used" "$CALLS" "sudo "

# Distro codename gets interpolated into the apt source line piped through tee.
# The tee shim captures stdin into the call log as `tee-stdin: ...`.
assert_contains "apt source line uses distro codename" "$CALLS" "tee-stdin:"
assert_contains "apt source mentions noble" "$CALLS" "noble"
assert_contains "apt source uses signed-by keyring path" "$CALLS" "signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg"
assert_contains "apt source points at Cloudflare repo" "$CALLS" "https://pkg.cloudflareclient.com/"

echo "=== install (GITHUB_OUTPUT format) ==="
GH_CONTENT=$(cat "$GH_OUT")
assert_contains "GITHUB_OUTPUT contains warp-version key" "$GH_CONTENT" "warp-version="
assert_contains "GITHUB_OUTPUT picks up mocked version" "$GH_CONTENT" "warp-version=2026.1.987"
# Format must be exactly one key=value line, no surrounding whitespace, no
# multi-line / heredoc framing (GH Actions parser requires this).
LINE_COUNT=$(grep -c . "$GH_OUT")
assert_equals "GITHUB_OUTPUT has exactly one non-empty line" "1" "$LINE_COUNT"
assert_matches "GITHUB_OUTPUT line matches ^key=value$" "$GH_CONTENT" '^warp-version=[A-Za-z0-9._+-]+$'
assert_not_contains "no heredoc delimiter in GITHUB_OUTPUT" "$GH_CONTENT" "<<"

echo "=== install (no GITHUB_OUTPUT - script still succeeds) ==="
: > "$CALL_LOG"
write_shims ok
OUT=$(env -i \
  HOME="$SANDBOX" \
  PATH="$SHIM_BIN:/usr/bin:/bin" \
  CALL_LOG="$CALL_LOG" \
  bash "$SCRIPT" 2>&1)
RC=$?
assert_equals "exit 0 without GITHUB_OUTPUT" "0" "$RC"
assert_contains "still ran warp-cli --version" "$OUT" "warp-cli 2026.1.987"

echo "=== install (lsb_release missing - hard fail with clear message) ==="
# Remove lsb_release from the shim PATH AND drop /usr/bin from PATH for this
# case - ubuntu-latest runners ship lsb_release pre-installed at
# /usr/bin/lsb_release, so leaving /usr/bin reachable masks the failure mode
# we are trying to exercise. The script only uses bash builtins (command -v,
# echo, exit, set) up to the bail point, so a shim-only PATH is sufficient.
# We invoke bash by absolute path so env -i can still locate the interpreter
# even though /usr/bin is no longer on the child PATH.
BASH_BIN=$(command -v bash)
rm -f "$SHIM_BIN/lsb_release"
: > "$CALL_LOG"
OUT=$(env -i \
  HOME="$SANDBOX" \
  PATH="$SHIM_BIN" \
  CALL_LOG="$CALL_LOG" \
  "$BASH_BIN" "$SCRIPT" 2>&1)
RC=$?
assert_not_equals "non-zero when lsb_release missing" "0" "$RC"
assert_contains "error mentions lsb_release" "$OUT" "lsb_release not found"
# Critical: nothing else should have been attempted.
assert_equals "no other commands ran" "" "$(cat "$CALL_LOG")"

echo "=== install (curl failure aborts via set -e + pipefail) ==="
write_shims fail   # curl exits non-zero
: > "$CALL_LOG"
GH_OUT2="$SANDBOX/gh_out_fail"
: > "$GH_OUT2"
OUT=$(env -i \
  HOME="$SANDBOX" \
  PATH="$SHIM_BIN:/usr/bin:/bin" \
  CALL_LOG="$CALL_LOG" \
  GITHUB_OUTPUT="$GH_OUT2" \
  bash "$SCRIPT" 2>&1)
RC=$?
assert_not_equals "non-zero when curl fails" "0" "$RC"
# apt-get must NOT have been reached - that's the whole point of pipefail+-e.
CALLS=$(cat "$CALL_LOG")
assert_not_contains "apt-get update was NOT called after curl failure" "$CALLS" "apt-get update"
assert_not_contains "apt-get install was NOT called after curl failure" "$CALLS" "apt-get install"
# And no warp-version output should have been emitted.
assert_not_contains "no warp-version emitted on failure" "$(cat "$GH_OUT2")" "warp-version="
