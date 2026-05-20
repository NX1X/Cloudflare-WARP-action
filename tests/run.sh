#!/usr/bin/env bash
# Aggregate test runner. Executes every tests/test_*.sh in a clean shell and
# tallies their TESTS / FAILURES totals from the captured output.
set -uo pipefail

THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

TOTAL_TESTS=0
TOTAL_FAILS=0
FAILED_FILES=()

shopt -s nullglob
for f in "$THIS_DIR"/test_*.sh; do
  name=$(basename "$f")
  echo ""
  echo "##################################################"
  echo "## $name"
  echo "##################################################"

  # Run in its own bash so failures don't kill the runner. The test scripts
  # print one PASS/FAIL line per assertion; we count those.
  OUTPUT=$(bash "$f" 2>&1) || true
  echo "$OUTPUT"

  PASS_COUNT=$(echo "$OUTPUT" | grep -c "^  PASS:" || true)
  FAIL_COUNT=$(echo "$OUTPUT" | grep -c "^  FAIL:" || true)
  TOTAL_TESTS=$((TOTAL_TESTS + PASS_COUNT + FAIL_COUNT))
  TOTAL_FAILS=$((TOTAL_FAILS + FAIL_COUNT))
  if [ "$FAIL_COUNT" -gt 0 ]; then
    FAILED_FILES+=("$name ($FAIL_COUNT failures)")
  fi
  echo ""
  echo "## ${name}: ${PASS_COUNT} passed, ${FAIL_COUNT} failed"
done

echo ""
echo "=================================================="
echo "AGGREGATE: $TOTAL_TESTS assertions, $TOTAL_FAILS failed"
echo "=================================================="
if [ "${#FAILED_FILES[@]}" -gt 0 ]; then
  echo "Failing files:"
  for f in "${FAILED_FILES[@]}"; do
    echo "  - $f"
  done
  exit 1
fi
echo "All tests passed."
exit 0
