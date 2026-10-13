#!/usr/bin/env bash
# Prints everything a reviewer needs for one PR, in headed sections. Read-only: it never comments,
# reviews, approves, merges or edits anything.
# Usage: bash scripts/gather.sh <N> [owner/repo] [--no-diff]
#   owner/repo defaults to the current repo (`gh repo view`). The diff comes last unless --no-diff.
#   A section that cannot be read says "unavailable: <reason>"; the other sections still print.
# Exit codes: 0 gathered · 2 usage error, or the PR cannot be read
set -uo pipefail

usage() { sed -n '2,7p' "$0"; }

pr=""
repo=""
diff=true
while [ $# -gt 0 ]; do
  case "$1" in
    --no-diff) diff=false ;;
    -h|--help) usage; exit 0 ;;
    -*) echo "unknown flag '$1'"; usage; exit 2 ;;
    */*) repo="$1" ;;
    *) [ -z "$pr" ] || { echo "two PR numbers given: '$pr' and '$1'"; exit 2; }; pr="$1" ;;
  esac
  shift
done

case "$pr" in
  ''|*[!0-9]*) echo "PR number required, got '${pr}'"; usage; exit 2 ;;
esac
command -v gh >/dev/null 2>&1 || { echo "gh is not installed; install it and run 'gh auth login'"; exit 2; }

if [ -z "$repo" ]; then
  repo=$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>&1) || {
    echo "cannot find the GitHub repo here ($repo); pass owner/repo"; exit 2; }
fi
printf '%s\n' "$repo" | grep -qE '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$' || { echo "owner/repo must look like paperplanehq/name, got '$repo'"; exit 2; }

section() { printf '\n== %s ==\n' "$1"; }
unavailable() { echo "unavailable: $(printf '%s' "$1" | tr '\n' ' ' | cut -c1-300)"; }

meta=$(gh pr view "$pr" -R "$repo" --json number,title,url,author,state,isDraft,baseRefName,headRefName,additions,deletions,changedFiles --jq '
  "PR #\(.number) in '"$repo"'",
  "title: \(.title)",
  "url: \(.url)",
  "author: \(.author.login)",
  "state: \(.state)",
  "isDraft: \(.isDraft)",
  "base: \(.baseRefName)",
  "head: \(.headRefName)",
  "size: +\(.additions) -\(.deletions) in \(.changedFiles) files"' 2>&1) || {
  echo "cannot read PR #$pr in $repo: $(printf '%s' "$meta" | tr '\n' ' ')"
  echo "check the number, the repo, and 'gh auth status'"
  exit 2
}
base=$(printf '%s\n' "$meta" | sed -n 's/^base: //p')
owner=${repo%%/*}
name=${repo#*/}

section PR
printf '%s\n' "$meta"

section Body
if body=$(gh pr view "$pr" -R "$repo" --json body --jq .body 2>&1); then
  if [ -n "$body" ]; then printf '%s\n' "$body"; else echo "(empty)"; fi
else unavailable "$body"; fi

section Checks
checks=$(gh pr checks "$pr" -R "$repo" 2>&1); rc=$?
printf '%s\n' "$checks"
[ "$rc" -eq 0 ] || echo "(gh pr checks exit $rc: a check failed, is pending, or none ran; not ready to approve)"

section "Files changed"
if files=$(gh pr diff "$pr" -R "$repo" --name-only 2>&1); then printf '%s\n' "$files"
else unavailable "$files"; fi

section "Unresolved review threads"
# shellcheck disable=SC2016 # GraphQL variables, not shell
query='query($owner:String!,$name:String!,$number:Int!,$endCursor:String){repository(owner:$owner,name:$name){pullRequest(number:$number){reviewThreads(first:100,after:$endCursor){nodes{isResolved} pageInfo{hasNextPage endCursor}}}}}'
if counts=$(gh api graphql --paginate -f query="$query" -F owner="$owner" -F name="$name" -F number="$pr" \
    --jq '[.data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved | not)] | length' 2>&1); then
  printf '%s\n' "$counts" | awk '{n += $1} END {print n + 0}'
else unavailable "$counts"; fi

section "Commit authors"
if authors=$(gh pr view "$pr" -R "$repo" --json commits --jq '
    [.commits[].authors[] | if (.login // "") != "" then .login else "\(.name) <\(.email)> (no GitHub login)" end] | unique | .[]' 2>&1); then
  printf '%s\n' "$authors"
else unavailable "$authors"; fi

section Stack
case "$base" in
  develop|uat|main) echo "not stacked: base is $base" ;;
  *)
    if parent=$(gh pr list -R "$repo" --head "$base" --state open --json number,title,isDraft,baseRefName --jq '
        .[] | "base PR: #\(.number) \(.title)", "  isDraft: \(.isDraft)", "  base: \(.baseRefName)"' 2>&1); then
      if [ -z "$parent" ]; then
        echo "base '$base' is not develop/uat/main and no open PR has it as head; ask the author what this PR targets"
      else
        printf '%s\n' "$parent"
        pbase=$(printf '%s\n' "$parent" | sed -n 's/^  base: //p' | head -1)
        case "$pbase" in
          develop|uat|main) echo "depth: 2 (this PR on #$(printf '%s\n' "$parent" | sed -n 's/^base PR: #\([0-9]*\).*/\1/p' | head -1), which targets $pbase)" ;;
          *) echo "depth: 3 or more (the base PR targets '$pbase', not develop/uat/main)" ;;
        esac
      fi
    else unavailable "$parent"; fi
    ;;
esac

if $diff; then
  section Diff
  if d=$(gh pr diff "$pr" -R "$repo" 2>&1); then printf '%s\n' "$d"
  else unavailable "$d"; fi
fi
exit 0
