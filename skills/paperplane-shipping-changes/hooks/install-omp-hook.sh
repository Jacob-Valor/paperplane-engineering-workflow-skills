#!/usr/bin/env bash
# Installs (or removes) the paperplane guard for omp, in every repo on this machine.
# omp doesn't run Claude Code hooks, so this copies omp-guard.ts and the guard it calls into
# <omp agent dir>/hooks/pre/ (default ~/.omp/agent; PI_CODING_AGENT_DIR overrides it).
# Usage: bash hooks/install-omp-hook.sh [--uninstall]
# For a team repo, use install-claude-hook.sh --commit instead: it commits the omp adapter too.
# Exit codes: 0 done · 1 cannot write or remove · 2 usage error
set -uo pipefail

uninstall=0
for arg in "$@"; do
  case "$arg" in
    --uninstall) uninstall=1 ;;
    -h|--help) sed -n '2,7p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown argument: $arg"; exit 2 ;;
  esac
done

src="$(cd "$(dirname "$0")" && pwd)"
dir="${PI_CODING_AGENT_DIR:-$HOME/.omp/agent}/hooks/pre"

if [ "$uninstall" -eq 1 ]; then
  rm -f "$dir/paperplane-guard.ts" "$dir/paperplane-guard.sh" || { echo "cannot remove the guard from $dir"; exit 1; }
  echo "removed the paperplane guard from $dir"
  exit 0
fi

mkdir -p "$dir" || { echo "cannot create $dir"; exit 1; }
cat "$src/omp-guard.ts" >"$dir/paperplane-guard.ts" && cat "$src/claude-guard.sh" >"$dir/paperplane-guard.sh" \
  || { echo "cannot write to $dir"; exit 1; }
echo "installed the paperplane guard in $dir"
echo "restart omp so it loads the hook"
