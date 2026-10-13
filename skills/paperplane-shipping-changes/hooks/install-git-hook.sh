#!/usr/bin/env bash
# Installs (or removes) the paperplane git pre-push hook in the current repo.
# Usage: bash hooks/install-git-hook.sh [--uninstall]
# Respects core.hooksPath. An existing pre-push hook that is not ours moves to
# pre-push.local and keeps running first. Running it again updates the hook.
# --uninstall removes our hook and puts pre-push.local back as pre-push.
# Exit codes: 0 done · 1 could not install · 2 usage error or not in a git repo
set -uo pipefail

usage() { sed -n '2,7p' "$0" | sed 's/^# \{0,1\}//'; }
uninstall=0
for arg in "$@"; do
  case "$arg" in
    --uninstall) uninstall=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument: $arg"; usage; exit 2 ;;
  esac
done

marker='# paperplane-pre-push'
skill_dir=$(cd "$(dirname "$0")/.." && pwd)
src="$skill_dir/hooks/git-pre-push"

top=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "not inside a git work tree; cd into the repo first"; exit 2; }
cd "$top" || exit 2
hooks=$(git rev-parse --git-path hooks) || exit 2
case "$hooks" in /*) ;; *) hooks="$top/$hooks" ;; esac
hook="$hooks/pre-push"
chained="$hooks/pre-push.local"

ours() { [ -f "$1" ] && grep -qxF "$marker" "$1"; }

if [ "$uninstall" -eq 1 ]; then
  if ours "$hook"; then
    rm -f "$hook" && echo "removed $hook"
  elif [ -e "$hook" ]; then
    echo "$hook is not the paperplane hook; left it alone"
  else
    echo "no pre-push hook in $hooks"
  fi
  if [ -e "$chained" ] && [ ! -e "$hook" ]; then
    mv "$chained" "$hook" && echo "restored your previous hook to $hook"
  fi
  exit 0
fi

[ -f "$src" ] || { echo "missing $src; reinstall the skill"; exit 1; }
mkdir -p "$hooks" || { echo "cannot create $hooks"; exit 1; }

if [ -e "$hook" ] && ! ours "$hook"; then
  if [ -e "$chained" ]; then
    echo "both $hook and $chained exist and neither is ours; merge them by hand, then rerun"
    exit 1
  fi
  mv "$hook" "$chained" || { echo "cannot move $hook to $chained"; exit 1; }
  echo "moved your existing hook to $chained; it runs first on every push"
fi

tmp="$hook.tmp.$$"
written=0
while IFS= read -r line || [ -n "$line" ]; do
  printf '%s\n' "$line"
  if [ "$written" -eq 0 ] && [ "$line" = "set -uo pipefail" ]; then
    printf 'PAPERPLANE_SKILL_DIR=%q  # written by install-git-hook.sh\n' "$skill_dir"
    written=1
  fi
done <"$src" >"$tmp" || { rm -f "$tmp"; echo "cannot write $hook"; exit 1; }
chmod +x "$tmp" && mv "$tmp" "$hook" || { rm -f "$tmp"; echo "cannot write $hook"; exit 1; }
echo "installed $hook (skill: $skill_dir)"
