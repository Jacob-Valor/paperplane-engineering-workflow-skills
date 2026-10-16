#!/usr/bin/env bash
# Prints the next release tag name for a date in the current repo. Never creates or pushes tags.
# Usage: bash scripts/next-tag.sh [--prefix prod|uat] [--date YYYY-MM-DD] [--previous [--before TAG]] [--no-fetch]
#   default: --prefix prod, --date today (local time); runs `git fetch --tags` first unless --no-fetch
#   --previous  print the newest existing <prefix>-* tag by tag date (what is deployed now)
#   --before TAG  with --previous: the newest tag older than TAG (the rollback target when TAG is bad)
# Exit codes: 0 tag printed · 1 --previous found no tag · 2 usage error, unknown --before tag, not a git repo, or fetch failed
set -uo pipefail

usage() { sed -n '2,7p' "$0"; }

prefix=prod
day=""
previous=false
before=""
fetch=true
while [ $# -gt 0 ]; do
  case "$1" in
    --prefix) prefix="${2:-}"; shift ;;
    --date) day="${2:-}"; shift ;;
    --previous) previous=true ;;
    --before) before="${2:-}"; shift ;;
    --no-fetch) fetch=false ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument '$1'"; usage; exit 2 ;;
  esac
  shift
done

case "$prefix" in
  prod|uat) ;;
  *) echo "--prefix must be prod or uat, got '$prefix'"; exit 2 ;;
esac
[ -z "$before" ] || $previous || { echo "--before needs --previous"; exit 2; }

if [ -z "$day" ]; then
  day=$(date +%Y-%m-%d)
elif ! printf '%s\n' "$day" | grep -qE '^[0-9]{4}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])$'; then
  echo "--date must be YYYY-MM-DD, got '$day'"; exit 2
fi

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "not a git repository; run this inside the repo you release"; exit 2; }

if $fetch && ! git fetch --tags --quiet; then
  echo "git fetch --tags failed, so local tags may be stale; fix remote access, or pass --no-fetch to use local tags only"
  exit 2
fi

if $previous; then
  tags=$(git for-each-ref --sort=-version:refname --sort=-creatordate --format='%(refname:short)' "refs/tags/$prefix-*" \
    | grep -E "^$prefix-[0-9]{4}\.[0-9]{2}\.[0-9]{2}(\.[0-9]+)?$")
  if [ -n "$before" ]; then
    printf '%s\n' "$tags" | grep -qxF -- "$before" || { echo "--before: no tag '$before' in this repo"; exit 2; }
    tags=$(printf '%s\n' "$tags" | awk -v b="$before" 'f; $0 == b {f=1}')
  fi
  tag=$(printf '%s\n' "$tags" | head -1)
  [ -n "$tag" ] || { echo "no $prefix-YYYY.MM.DD tag${before:+ older than $before} in this repo; there is nothing to roll back to"; exit 1; }
  echo "$tag"
  exit 0
fi

base="$prefix-${day//-/.}"
re="^${base//./\\.}(\\.([0-9]+))?$"
found=false
high=1
while IFS= read -r t; do
  [[ "$t" =~ $re ]] || continue
  found=true
  n="${BASH_REMATCH[2]}"
  [ -n "$n" ] && [ "$((10#$n))" -gt "$high" ] && high=$((10#$n))
done < <(git tag -l "$base" "$base.*")

if ! $found; then
  echo "$base"
  exit 0
fi
next="$base.$((high + 1))"
echo "$next"
[ "$((high + 1))" -ge 3 ] && echo "confirm $next with the CTO (the guide only shows .2)" >&2
exit 0
