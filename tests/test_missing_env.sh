#!/usr/bin/env bash
# Verifies scripts that declare required env vars via : "${VAR:?msg}" exit
# non-zero and surface the variable name when invoked without that var set.
# Each missing var is exercised individually so a partial config doesn't slip
# through.
set -uo pipefail

THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$THIS_DIR/.." && pwd)"
# shellcheck source=helpers.sh
. "$THIS_DIR/helpers.sh"

# Drop one entry from a key=value list, return the rest.
without_key() {
  local drop="$1"; shift
  for kv in "$@"; do
    [ "${kv%%=*}" = "$drop" ] && continue
    printf '%s\n' "$kv"
  done
}

run_without() {
  # $1 = script path (relative to ROOT_DIR)
  # $2 = required var to drop
  # remaining = full env (var=value pairs)
  local script="$1" drop="$2"; shift 2
  local cmd=(env -i HOME="/tmp" PATH="/usr/bin:/bin")
  while IFS= read -r kv; do
    [ -z "$kv" ] && continue
    cmd+=("$kv")
  done < <(without_key "$drop" "$@")
  "${cmd[@]}" bash "$ROOT_DIR/$script" 2>&1
  return $?
}

run_with_all() {
  local script="$1"; shift
  local cmd=(env -i HOME="/tmp" PATH="/usr/bin:/bin")
  for kv in "$@"; do cmd+=("$kv"); done
  "${cmd[@]}" bash "$ROOT_DIR/$script" 2>&1
  return $?
}

# -------------------------------------------------------------------------
# 01-validate-inputs.sh requires: MODE, RETRY_COUNT, RETRY_DELAY, ORGANIZATION
# -------------------------------------------------------------------------
echo "=== 01-validate-inputs missing-env ==="
VALIDATE_ENV=(
  MODE=warp
  RETRY_COUNT=3
  RETRY_DELAY=5
  ORGANIZATION=acme
  EXCLUDE_ROUTES=
  INCLUDE_ROUTES=
)

# Sanity: with all required vars set, the script exits 0.
OUT=$(run_with_all scripts/01-validate-inputs.sh "${VALIDATE_ENV[@]}"); RC=$?
assert_equals "01 happy path exits 0" "0" "$RC"
assert_contains "01 reports inputs validated" "$OUT" "Inputs validated"

for req in MODE RETRY_COUNT RETRY_DELAY ORGANIZATION; do
  OUT=$(run_without scripts/01-validate-inputs.sh "$req" "${VALIDATE_ENV[@]}"); RC=$?
  assert_not_equals "01 fails without $req" "0" "$RC"
  assert_contains "01 error names $req" "$OUT" "$req"
  assert_contains "01 error says 'not set' for $req" "$OUT" "not set"
done

# -------------------------------------------------------------------------
# 04-write-mdm.sh requires: ORGANIZATION, AUTH_CLIENT_ID, AUTH_CLIENT_SECRET, MODE
# Use a sandboxed MDM_PATH and SUDO="" so the script doesn't need root.
# -------------------------------------------------------------------------
echo "=== 04-write-mdm missing-env ==="
MDM_SANDBOX=$(mktemp -d)
trap 'rm -rf "$MDM_SANDBOX"' EXIT
MDM_ENV=(
  ORGANIZATION=acme
  AUTH_CLIENT_ID=id-1.access
  AUTH_CLIENT_SECRET=secret-2
  MODE=warp
  "MDM_PATH=$MDM_SANDBOX/mdm.xml"
  SUDO=
)

# Critical security property: when a required var is missing, the script must
# bail BEFORE writing the MDM file. Otherwise a half-baked MDM with empty
# credentials could land on disk.
for req in ORGANIZATION AUTH_CLIENT_ID AUTH_CLIENT_SECRET MODE; do
  rm -f "$MDM_SANDBOX/mdm.xml"
  OUT=$(run_without scripts/04-write-mdm.sh "$req" "${MDM_ENV[@]}"); RC=$?
  assert_not_equals "04 fails without $req" "0" "$RC"
  assert_contains "04 error names $req" "$OUT" "$req"
  assert_file_not_exists "04 did NOT write MDM file when $req missing" "$MDM_SANDBOX/mdm.xml"
done

# -------------------------------------------------------------------------
# 08-verify-connection.sh requires: RETRY_COUNT, RETRY_DELAY
# (warp-cli is invoked, but the script bails on missing env before that.)
# -------------------------------------------------------------------------
echo "=== 08-verify-connection missing-env ==="
VERIFY_ENV=(
  RETRY_COUNT=1
  RETRY_DELAY=1
  TEST_HOST=
)
for req in RETRY_COUNT RETRY_DELAY; do
  OUT=$(run_without scripts/08-verify-connection.sh "$req" "${VERIFY_ENV[@]}"); RC=$?
  assert_not_equals "08 fails without $req" "0" "$RC"
  assert_contains "08 error names $req" "$OUT" "$req"
done
