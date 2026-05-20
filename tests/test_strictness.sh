#!/usr/bin/env bash
# Verifies every script under scripts/ and cleanup/ uses strict mode flags.
# All main scripts must enable -u and pipefail. Most also enable -e; the
# cleanup script intentionally omits -e so a partial failure in one stage
# does not skip subsequent best-effort teardown steps.
set -uo pipefail

THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$THIS_DIR/.." && pwd)"
# shellcheck source=helpers.sh
. "$THIS_DIR/helpers.sh"

# Scripts that MUST have -e (every main pipeline step). cleanup/cleanup.sh is
# the explicit exception.
STRICT_SCRIPTS=(
  scripts/01-validate-inputs.sh
  scripts/02-install-warp.sh
  scripts/03-wait-daemon.sh
  scripts/04-write-mdm.sh
  scripts/05-restart-and-register.sh
  scripts/06-split-tunnel.sh
  scripts/07-connect.sh
  scripts/08-verify-connection.sh
  scripts/09-capture-ip.sh
  scripts/10-write-state.sh
  scripts/set-skipped-status.sh
)

echo "=== strict mode flags on main scripts ==="
for s in "${STRICT_SCRIPTS[@]}"; do
  HEAD=$(head -10 "$ROOT_DIR/$s")
  # set -euo pipefail or any equivalent that contains both -e and -u and pipefail.
  if echo "$HEAD" | grep -qE '^set -[a-z]*e[a-z]*'; then
    _pass "$s sets -e"
  else
    _fail "$s missing -e"
  fi
  TESTS=$((TESTS + 1))

  if echo "$HEAD" | grep -qE '^set -[a-z]*u[a-z]*'; then
    _pass "$s sets -u"
  else
    _fail "$s missing -u"
  fi
  TESTS=$((TESTS + 1))

  if echo "$HEAD" | grep -q 'pipefail'; then
    _pass "$s sets pipefail"
  else
    _fail "$s missing pipefail"
  fi
  TESTS=$((TESTS + 1))
done

echo "=== cleanup intentionally allows partial failure (no -e, but keeps -u + pipefail) ==="
HEAD=$(head -10 "$ROOT_DIR/cleanup/cleanup.sh")
if echo "$HEAD" | grep -qE '^set -[a-z]+'; then
  _pass "cleanup has a set line"
  if echo "$HEAD" | grep -qE '^set -[a-z]*e[a-z]*'; then
    _fail "cleanup unexpectedly enables -e (would skip later teardown on first error)"
  else
    _pass "cleanup correctly omits -e"
  fi
  TESTS=$((TESTS + 2))
  if echo "$HEAD" | grep -qE '^set -[a-z]*u[a-z]*'; then
    _pass "cleanup sets -u"
  else
    _fail "cleanup missing -u"
  fi
  TESTS=$((TESTS + 1))
  if echo "$HEAD" | grep -q 'pipefail'; then
    _pass "cleanup sets pipefail"
  else
    _fail "cleanup missing pipefail"
  fi
  TESTS=$((TESTS + 1))
else
  _fail "cleanup has no set line at all"
  TESTS=$((TESTS + 1))
fi

echo "=== runtime check: -e + pipefail actually trip on intermediate failure ==="
# A canary that mirrors the action's pattern: if the first command in a pipe
# fails, the script must abort before the second-stage work. This guards
# against regressions where someone removes `pipefail` and the pipe-head error
# gets swallowed.
SANDBOX=$(mktemp -d)
trap 'rm -rf "$SANDBOX"' EXIT

cat > "$SANDBOX/canary.sh" <<'CANARY'
#!/usr/bin/env bash
set -euo pipefail
false | cat > /dev/null
echo REACHED_SECOND_STAGE
CANARY
chmod +x "$SANDBOX/canary.sh"
OUT=$(bash "$SANDBOX/canary.sh" 2>&1); RC=$?
assert_not_equals "canary exits non-zero on pipe-head failure" "0" "$RC"
assert_not_contains "second stage was NOT reached" "$OUT" "REACHED_SECOND_STAGE"

# Sanity-check the inverse: without pipefail, the same pipe is silently OK.
cat > "$SANDBOX/loose.sh" <<'LOOSE'
#!/usr/bin/env bash
set -eu
false | cat > /dev/null
echo REACHED_SECOND_STAGE
LOOSE
chmod +x "$SANDBOX/loose.sh"
OUT=$(bash "$SANDBOX/loose.sh" 2>&1); RC=$?
assert_equals "without pipefail, pipe-head failure is masked (sanity)" "0" "$RC"
assert_contains "second stage IS reached without pipefail (sanity)" "$OUT" "REACHED_SECOND_STAGE"
