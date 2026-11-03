#!/usr/bin/env bash
# Opens the hotfix merge-back drafts (main -> uat, main -> develop) for a prod-* tag, as paperplane-releasing asks.
# Env: TAG (prod-*), GH_REPO, GH_TOKEN. Runs in a full clone with origin/main, origin/uat, origin/develop and the tags.
# Opens nothing for a target that has every non-merge commit of TAG, or that already has an open PR from this repo's
# main or from chore/merge-back-$TAG (the manual replacement for a conflicting draft). A chore/merge-back branch of
# another tag does not count: it lacks this tag's commits. Fork PRs are ignored.
set -uo pipefail

: "${TAG:?TAG is required}"
: "${GH_REPO:?GH_REPO is required}"
printf '%s' "$TAG" | grep -Eq '^prod-[A-Za-z0-9._-]+$' || { echo "TAG '$TAG' is not a prod-* tag"; exit 2; }
git rev-parse -q --verify "refs/tags/$TAG^{commit}" >/dev/null || { echo "tag $TAG not found in this clone"; exit 2; }
git rev-parse -q --verify refs/remotes/origin/main >/dev/null || { echo "origin/main not found in this clone"; exit 2; }

owner=${GH_REPO%%/*}

tmp=$(mktemp -d "${TMPDIR:-/tmp}/pp-merge-back.XXXXXX") || exit 1
trap 'rm -rf "$tmp"' EXIT
rc=0

for target in uat develop; do
  git rev-parse -q --verify "refs/remotes/origin/$target^{commit}" >/dev/null \
    || { echo "origin/$target not found in this clone"; rc=1; continue; }

  subjects=$(git log --no-merges --format='- %s (%h)' "origin/$target..$TAG")
  if [ -z "$subjects" ]; then
    echo "no hotfix commits missing from $target"
    continue
  fi

  heads=$(gh pr list --base "$target" --state open --limit 200 --json number,headRepositoryOwner,headRefName \
    --jq '.[] | "\(.headRepositoryOwner.login) \(.headRefName) \(.number)"') \
    || { echo "gh pr list for $target failed"; rc=1; continue; }
  existing=""
  while read -r pr_owner pr_head pr_num; do
    [ "$pr_owner" = "$owner" ] || continue
    case $pr_head in
      main) existing="an open PR from main into $target already exists (#$pr_num); skipping"; break ;;
      "chore/merge-back-$TAG") existing="an open PR from $pr_head into $target already exists (#$pr_num); skipping" ;;
    esac
  done <<< "$heads"
  if [ -n "$existing" ]; then
    echo "$existing"
    continue
  fi

  conflicts=no
  git merge-tree --write-tree "origin/$target" origin/main >/dev/null 2>&1
  case $? in
    0) ;;
    1) conflicts=yes ;;
    *) conflicts=unknown; echo "conflict check skipped: git merge-tree --write-tree needs git >= 2.38" ;;
  esac

  body="$tmp/body-$target.md"
  cat > "$body" <<EOF
## What changed
Merges \`main\` back into \`$target\` after hotfix \`$TAG\`. Hotfix commits missing from \`$target\`:
$subjects

## How I verified it
- Commands: git log --no-merges origin/$target..$TAG
- iOS: see the hotfix PR merged into main for $TAG
- Android: see the hotfix PR merged into main for $TAG

## Risk
May conflict with work already on \`$target\`. Not done: nothing merged; the CTO merges this with a merge commit (not squash) so \`$target\` gets \`main\`'s history.

## Checklist
- [x] Title is \`type(scope): summary\`
- [x] No secrets, \`.env\` files or keys in the diff (only commits already on \`main\`)

AI-assisted: no (opened by the paperplane-merge-back workflow)
EOF

  url=$(gh pr create --draft --base "$target" --head main \
    --title "chore(release): merge hotfix $TAG back into $target" --body-file "$body") \
    || { echo "gh pr create into $target failed"; rc=1; continue; }
  echo "opened $url"

  if [ "$conflicts" = yes ]; then
    cat > "$tmp/comment-$target.md" <<EOF
\`main\` conflicts with \`$target\`. Do not resolve the conflicts in the GitHub web editor: that commits to \`main\`.
Per paperplane-releasing: create \`chore/merge-back-$TAG\` from \`$target\`, merge \`main\` into it, resolve there, open the PR from that branch, and close this one.
\`\`\`
git fetch origin && git switch -c chore/merge-back-$TAG origin/$target && git merge origin/main
\`\`\`
EOF
    gh pr comment "$url" --body-file "$tmp/comment-$target.md" \
      || { echo "gh pr comment on $url failed"; rc=1; }
    echo "conflicts with $target: commented on $url"
  fi
done
exit "$rc"
