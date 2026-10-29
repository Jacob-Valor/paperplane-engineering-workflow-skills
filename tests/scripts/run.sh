#!/usr/bin/env bash
# Runs every tests/scripts/test-*.sh and prints the total. Each test file exits non-zero on failure.
# Run: bash tests/scripts/run.sh
set -u
dir=$(cd "$(dirname "$0")" && pwd)
log=$(mktemp "${TMPDIR:-/tmp}/pp-run.XXXXXX") || exit 1
trap 'rm -f "$log"' EXIT
failed=()
files=0
total=0
for t in "$dir"/test-*.sh; do
  echo "== $(basename "$t")"
  bash "$t" 2>&1 | tee "$log"
  [ "${PIPESTATUS[0]}" -eq 0 ] || failed+=("$(basename "$t")")
  n=$(sed -n 's/^\([0-9][0-9]*\) passed, [0-9][0-9]* failed$/\1/p' "$log" | tail -1)
  files=$((files + 1)); total=$((total + ${n:-0}))
done
echo "total: $total passed in $files files"
if [ ${#failed[@]} -gt 0 ]; then
  echo "FAILED: ${failed[*]}"
  exit 1
fi
echo "all script tests passed"
