# shellcheck shell=bash
# Test assertion helpers. Sourced by each test_*.sh and by run.sh.
# Counts are kept in TESTS / FAILURES which run.sh aggregates.

TESTS="${TESTS:-0}"
FAILURES="${FAILURES:-0}"
CURRENT_TEST_FILE="${CURRENT_TEST_FILE:-unknown}"

_pass() { echo "  PASS: $1"; }
_fail() { echo "  FAIL: $1" >&2; FAILURES=$((FAILURES + 1)); }

assert_equals() {
  local label="$1" expected="$2" actual="$3"
  TESTS=$((TESTS + 1))
  if [ "$expected" = "$actual" ]; then
    _pass "$label"
  else
    _fail "$label (expected='$expected', actual='$actual')"
  fi
}

assert_not_equals() {
  local label="$1" left="$2" right="$3"
  TESTS=$((TESTS + 1))
  if [ "$left" != "$right" ]; then
    _pass "$label"
  else
    _fail "$label (both='$left')"
  fi
}

assert_contains() {
  local label="$1" haystack="$2" needle="$3"
  TESTS=$((TESTS + 1))
  if echo "$haystack" | grep -qF -- "$needle"; then
    _pass "$label"
  else
    _fail "$label (expected to contain '$needle')"
  fi
}

assert_not_contains() {
  local label="$1" haystack="$2" needle="$3"
  TESTS=$((TESTS + 1))
  if echo "$haystack" | grep -qF -- "$needle"; then
    _fail "$label (should NOT contain '$needle')"
  else
    _pass "$label"
  fi
}

assert_matches() {
  local label="$1" haystack="$2" pattern="$3"
  TESTS=$((TESTS + 1))
  if echo "$haystack" | grep -qE -- "$pattern"; then
    _pass "$label"
  else
    _fail "$label (expected to match /$pattern/)"
  fi
}

assert_file_exists() {
  local label="$1" path="$2"
  TESTS=$((TESTS + 1))
  if [ -f "$path" ]; then
    _pass "$label"
  else
    _fail "$label (file '$path' does not exist)"
  fi
}

assert_file_not_exists() {
  local label="$1" path="$2"
  TESTS=$((TESTS + 1))
  if [ ! -e "$path" ]; then
    _pass "$label"
  else
    _fail "$label (file '$path' should not exist)"
  fi
}

assert_file_perms() {
  local label="$1" path="$2" expected="$3"
  local actual
  actual=$(stat -c '%a' "$path" 2>/dev/null || stat -f '%Lp' "$path" 2>/dev/null)
  assert_equals "$label" "$expected" "$actual"
}

assert_command_succeeds() {
  local label="$1"
  shift
  TESTS=$((TESTS + 1))
  if "$@" >/dev/null 2>&1; then
    _pass "$label"
  else
    _fail "$label (expected '$*' to succeed)"
  fi
}

assert_command_fails() {
  local label="$1"
  shift
  TESTS=$((TESTS + 1))
  if "$@" >/dev/null 2>&1; then
    _fail "$label (expected '$*' to fail but it succeeded)"
  else
    _pass "$label"
  fi
}

assert_exit_code() {
  local label="$1" expected="$2"
  shift 2
  TESTS=$((TESTS + 1))
  local actual=0
  "$@" >/dev/null 2>&1 || actual=$?
  if [ "$actual" = "$expected" ]; then
    _pass "$label"
  else
    _fail "$label (expected exit=$expected, got $actual)"
  fi
}
