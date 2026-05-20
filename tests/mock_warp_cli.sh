#!/usr/bin/env bash
# Configurable mock warp-cli for tests. Behaviour is driven by env-like values
# in /tmp/mock-warp-config (overridable via MOCK_WARP_CONFIG) plus a small
# state file /tmp/mock-warp-state (overridable via MOCK_WARP_STATE) that
# tracks connection state across invocations.
#
# Recognised config keys (all optional):
#   DAEMON_READY_AFTER=<int>      seconds before status returns success
#   REGISTERED_AFTER=<int>        seconds before registration show succeeds
#   FAIL_TUNNEL_NEW_SYNTAX=1      `tunnel ip add` exits 1 (force legacy fallback)
#   FAIL_LEGACY_ROUTE=1           legacy add-*-route exits 1
#   CONNECT_FAILS_FIRST=<int>     status returns Disconnected this many times
#                                 before reporting Connected (after a connect call)
#   NEVER_CONNECTS=1              status never reports Connected
#   REGISTRATION_FAILS=1          registration delete returns 1 (causes
#                                 teams-unenroll fallback in cleanup.sh)
#
# State (managed automatically):
#   STATE=fresh|registered|connected   primary connection state
#   START_TS=<epoch>                   start of process (for time-gated checks)
#   STATUS_CALLS=<int>                 successful status calls so far
#
set -uo pipefail

MOCK_WARP_CONFIG="${MOCK_WARP_CONFIG:-/tmp/mock-warp-config}"
MOCK_WARP_STATE="${MOCK_WARP_STATE:-/tmp/mock-warp-state}"

# Load config (key=value lines). Default to empty.
DAEMON_READY_AFTER=0
REGISTERED_AFTER=0
FAIL_TUNNEL_NEW_SYNTAX=0
FAIL_LEGACY_ROUTE=0
CONNECT_FAILS_FIRST=0
NEVER_CONNECTS=0
REGISTRATION_FAILS=0
if [ -f "$MOCK_WARP_CONFIG" ]; then
  # shellcheck disable=SC1090
  . "$MOCK_WARP_CONFIG"
fi

# Initialise state file on first run.
if [ ! -f "$MOCK_WARP_STATE" ]; then
  cat > "$MOCK_WARP_STATE" <<EOF
STATE=fresh
START_TS=$(date +%s)
STATUS_CALLS=0
EOF
fi
# shellcheck disable=SC1090
. "$MOCK_WARP_STATE"

NOW=$(date +%s)
ELAPSED=$((NOW - START_TS))

save_state() {
  cat > "$MOCK_WARP_STATE" <<EOF
STATE=$STATE
START_TS=$START_TS
STATUS_CALLS=$STATUS_CALLS
EOF
}

# Strip --accept-tos
if [ "${1:-}" = "--accept-tos" ]; then shift; fi

case "${1:-}" in
  --version)
    echo "warp-cli 2024.6.415 (mock)"
    ;;
  status)
    if [ "$ELAPSED" -lt "$DAEMON_READY_AFTER" ]; then
      echo "warp-cli: daemon not ready" >&2
      exit 1
    fi
    STATUS_CALLS=$((STATUS_CALLS + 1))
    save_state
    if [ "$NEVER_CONNECTS" = "1" ]; then
      echo "Status update: Disconnected"
      exit 0
    fi
    if [ "$STATE" = "connected" ] && [ "$STATUS_CALLS" -gt "$CONNECT_FAILS_FIRST" ]; then
      echo "Status update: Connected"
    else
      echo "Status update: Disconnected"
    fi
    ;;
  registration)
    case "${2:-}" in
      show)
        if [ "$ELAPSED" -lt "$REGISTERED_AFTER" ]; then
          echo "Not registered" >&2
          exit 1
        fi
        if [ "$STATE" = "registered" ] || [ "$STATE" = "connected" ] || [ "$REGISTERED_AFTER" -gt 0 ]; then
          # If time-gated and elapsed, auto-promote to registered.
          if [ "$STATE" = "fresh" ]; then
            STATE=registered
            save_state
          fi
          echo "Device ID: mock-device-id-12345"
          echo "Account ID: mock-account-id-aaaa"
          echo "Public Key: mock-pubkey-aaaaaaaaaaaaaaaaaaaa"
          echo "Token: mock-token-aaaaaaaaaaaaaaaaaaaa"
          exit 0
        fi
        echo "Not registered" >&2
        exit 1
        ;;
      delete)
        if [ "$REGISTRATION_FAILS" = "1" ]; then
          echo "Could not delete" >&2
          exit 1
        fi
        STATE=fresh
        save_state
        echo "Registration deleted"
        ;;
      *) echo "mock-warp: registration $*" ;;
    esac
    ;;
  teams-unenroll)
    STATE=fresh
    save_state
    echo "Unenrolled via teams-unenroll"
    ;;
  connect)
    if [ "$STATE" = "fresh" ]; then STATE=registered; fi
    STATE=connected
    STATUS_CALLS=0
    save_state
    echo "Connecting..."
    ;;
  disconnect)
    if [ "$STATE" = "connected" ]; then STATE=registered; fi
    save_state
    echo "Disconnected"
    ;;
  tunnel)
    if [ "${2:-}" = "ip" ] && [ "${3:-}" = "add" ]; then
      if [ "$FAIL_TUNNEL_NEW_SYNTAX" = "1" ]; then
        echo "unknown subcommand: tunnel" >&2
        exit 1
      fi
      echo "Route added (new syntax): $*"
      exit 0
    fi
    echo "mock-warp: tunnel $*"
    ;;
  add-excluded-route|add-included-route)
    if [ "$FAIL_LEGACY_ROUTE" = "1" ]; then
      echo "legacy add route failed" >&2
      exit 1
    fi
    echo "Route added (legacy): $*"
    ;;
  *)
    echo "mock-warp: $*"
    ;;
esac
