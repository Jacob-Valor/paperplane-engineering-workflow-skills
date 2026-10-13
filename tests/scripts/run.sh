#!/usr/bin/env bash
# Runs every tests/scripts/test-*.sh. Each test file exits non-zero on failure.
# Run: bash tests/scripts/run.sh
set -u
dir=$(cd "$(dirname "$0")" && pwd)
failed=()
for t in "$dir"/test-*.sh; do
  echo "== $(basename "$t")"
  bash "$t" || failed+=("$(basename "$t")")
done
if [ ${#failed[@]} -gt 0 ]; then
  echo "FAILED: ${failed[*]}"
  exit 1
fi
echo "all script tests passed"
