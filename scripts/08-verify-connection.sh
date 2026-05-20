#!/usr/bin/env bash
# Verify the WARP tunnel is Connected (and optionally that TEST_HOST is reachable).
set -euo pipefail

: "${RETRY_COUNT:?RETRY_COUNT not set}"
: "${RETRY_DELAY:?RETRY_DELAY not set}"
TEST_HOST="${TEST_HOST:-}"

write_status() {
  if [ -n "${GITHUB_OUTPUT:-}" ]; then
    echo "connection-status=$1" >> "$GITHUB_OUTPUT"
  fi
}

ATTEMPT=1
STATUS_OK=false
while [ "$ATTEMPT" -le "$RETRY_COUNT" ]; do
  STATUS_OUT=$(warp-cli --accept-tos status 2>&1 || true)
  echo "--- Attempt ${ATTEMPT}/${RETRY_COUNT} ---"
  echo "$STATUS_OUT"
  if echo "$STATUS_OUT" | grep -qiE 'Status update: Connected|Status: Connected'; then
    STATUS_OK=true
    break
  fi
  if [ "$ATTEMPT" -lt "$RETRY_COUNT" ]; then
    echo "Not connected yet, retrying in ${RETRY_DELAY}s..."
    sleep "$RETRY_DELAY"
  fi
  ATTEMPT=$((ATTEMPT + 1))
done

if [ "$STATUS_OK" != "true" ]; then
  echo "ERROR: WARP failed to reach Connected state after ${RETRY_COUNT} attempts." >&2
  write_status "failed"
  exit 1
fi
echo "WARP is Connected."

if [ -n "$TEST_HOST" ]; then
  echo "Pinging ${TEST_HOST} to verify routing..."
  PING_OK=false
  for i in $(seq 1 "$RETRY_COUNT"); do
    if ping -c 1 -W 5 "$TEST_HOST" > /dev/null 2>&1; then
      echo "Ping to ${TEST_HOST} succeeded on attempt ${i}."
      PING_OK=true
      break
    fi
    if [ "$i" -lt "$RETRY_COUNT" ]; then
      echo "Ping attempt ${i} failed, retrying in ${RETRY_DELAY}s..."
      sleep "$RETRY_DELAY"
    fi
  done
  if [ "$PING_OK" != "true" ]; then
    echo "ERROR: Could not reach ${TEST_HOST} after ${RETRY_COUNT} attempts." >&2
    write_status "failed"
    exit 1
  fi
fi

write_status "connected"
