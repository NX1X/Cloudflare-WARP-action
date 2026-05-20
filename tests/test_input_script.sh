#!/usr/bin/env bash
# Tests for scripts/01-validate-inputs.sh - runs the real script with env vars
# and asserts pass/fail behaviour and the error message it prints.
set -uo pipefail

THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$THIS_DIR/.." && pwd)"
# shellcheck source=helpers.sh
. "$THIS_DIR/helpers.sh"

SCRIPT="$ROOT_DIR/scripts/01-validate-inputs.sh"

run_with() {
  env -i \
    PATH="$PATH" \
    MODE="${MODE_OVERRIDE:-warp}" \
    RETRY_COUNT="${RETRY_COUNT_OVERRIDE:-3}" \
    RETRY_DELAY="${RETRY_DELAY_OVERRIDE:-5}" \
    ORGANIZATION="${ORG_OVERRIDE:-acme-corp}" \
    EXCLUDE_ROUTES="${EXCLUDE_ROUTES_OVERRIDE:-}" \
    INCLUDE_ROUTES="${INCLUDE_ROUTES_OVERRIDE:-}" \
    bash "$SCRIPT"
}

echo "=== 01-validate-inputs.sh (happy path) ==="
OUT=$(run_with 2>&1)
RC=$?
assert_equals "exits 0 on valid inputs" "0" "$RC"
assert_contains "prints success message" "$OUT" "Inputs validated."

echo "=== 01-validate-inputs.sh (bad mode) ==="
OUT=$(MODE_OVERRIDE="bogus" run_with 2>&1); RC=$?
assert_not_equals "non-zero exit" "0" "$RC"
assert_contains "mode error message" "$OUT" "Invalid mode"

echo "=== 01-validate-inputs.sh (bad retry-count) ==="
OUT=$(RETRY_COUNT_OVERRIDE="0" run_with 2>&1); RC=$?
assert_not_equals "non-zero exit" "0" "$RC"
assert_contains "retry-count error" "$OUT" "retry-count must be a positive integer"

echo "=== 01-validate-inputs.sh (bad retry-delay) ==="
OUT=$(RETRY_DELAY_OVERRIDE="abc" run_with 2>&1); RC=$?
assert_not_equals "non-zero exit" "0" "$RC"
assert_contains "retry-delay error" "$OUT" "retry-delay must be a positive integer"

echo "=== 01-validate-inputs.sh (bad org) ==="
OUT=$(ORG_OVERRIDE="https://acme.cloudflareaccess.com" run_with 2>&1); RC=$?
assert_not_equals "non-zero exit" "0" "$RC"
assert_contains "org error" "$OUT" "must be the team name"

echo "=== 01-validate-inputs.sh (both routes set) ==="
OUT=$(EXCLUDE_ROUTES_OVERRIDE="10.0.0.0/8" INCLUDE_ROUTES_OVERRIDE="192.168.0.0/16" run_with 2>&1); RC=$?
assert_not_equals "non-zero exit" "0" "$RC"
assert_contains "exclusivity error" "$OUT" "mutually exclusive"

echo "=== 01-validate-inputs.sh (bad CIDR in include) ==="
OUT=$(INCLUDE_ROUTES_OVERRIDE="not-a-cidr" run_with 2>&1); RC=$?
assert_not_equals "non-zero exit" "0" "$RC"
assert_contains "cidr error" "$OUT" "invalid CIDR"
