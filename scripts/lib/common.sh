# shellcheck shell=bash
# Shared helpers for cloudflare-warp-action scripts.

trim() {
  echo "$1" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g'
}

# Redact <string>...</string> values in MDM XML on stdin/file.
redact_strings() {
  sed -E 's|(<string>)([^<]+)(</string>)|\1<REDACTED>\3|g'
}

# Redact sensitive fields from `warp-cli registration show` output.
redact_registration() {
  sed -E 's/(Device ID:|Account ID:|Public Key:|Token:)[[:space:]]*.*/\1 <REDACTED>/g'
}

# Wait for `warp-cli status` to succeed, polling once per second.
# Usage: wait_for_daemon <max_seconds>
wait_for_daemon() {
  local max="${1:-30}" i
  for i in $(seq 1 "$max"); do
    if warp-cli --accept-tos status > /dev/null 2>&1; then
      echo "warp-svc is ready (took ${i}s)."
      return 0
    fi
    sleep 1
  done
  return 1
}

# Wait for `warp-cli registration show` to succeed (i.e. MDM-driven enrollment
# has completed). Usage: wait_for_registration <max_seconds>
wait_for_registration() {
  local max="${1:-60}" i
  for i in $(seq 1 "$max"); do
    if warp-cli --accept-tos registration show > /dev/null 2>&1; then
      echo "Device registered (took ${i}s)."
      return 0
    fi
    sleep 1
  done
  return 1
}
