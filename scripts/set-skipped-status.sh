#!/usr/bin/env bash
# Set connection-status output to "skipped" when verification is disabled.
set -euo pipefail

if [ -n "${GITHUB_OUTPUT:-}" ]; then
  echo "connection-status=skipped" >> "$GITHUB_OUTPUT"
fi
echo "Verification skipped (test-connection != true)."
