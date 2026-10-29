#!/usr/bin/env bash
# `/ready` on a draft PR: marks it ready for review after the same checks a human runs before `gh pr ready`.
# Called by .github/workflows/paperplane-ready.yml. Env: PR, COMMENT_BODY, COMMENTER, COMMENTER_TYPE,
# COMMENT_ASSOCIATION, GH_REPO, GH_TOKEN. Each refusal posts one PR comment with the reason and exits 1.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
CHECK_NAME="standard / checks"

body=$(printf '%s' "${COMMENT_BODY:-}" | tr -d '\r' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | sed -e '/^$/d')
[ "$body" = "/ready" ] || { echo "comment is not exactly /ready; nothing to do"; exit 0; }
: "${PR:?}" "${COMMENTER:?}" "${GH_REPO:?}"

say() { printf '%s\n' "$1" | gh pr comment "$PR" --body-file - >/dev/null || echo "could not comment on #$PR" >&2; echo "$1"; }
refuse() { say "\`/ready\` from @$COMMENTER refused: $1 The PR stays draft."; exit 1; }
lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

case "$(lower "$COMMENTER")" in *"[bot]") COMMENTER_TYPE=Bot ;; esac
[ "${COMMENTER_TYPE:-User}" != Bot ] || refuse "bots and agents cannot mark a PR ready; the author comments \`/ready\` after the human review."

pr=$(gh pr view "$PR" --json author,state,isDraft,headRefOid) || refuse "could not read PR #$PR."
author=$(printf '%s' "$pr" | jq -r '.author.login')
[ "$(lower "$author")" = "$(lower "$COMMENTER")" ] || refuse "only the PR author (@$author) can use \`/ready\`."
case "${COMMENT_ASSOCIATION:-NONE}" in
  OWNER|MEMBER|COLLABORATOR) ;;
  *) refuse "the author must be an org member or repo collaborator (association is ${COMMENT_ASSOCIATION:-NONE})." ;;
esac

state=$(printf '%s' "$pr" | jq -r '.state')
[ "$state" = OPEN ] || refuse "the PR is $(lower "$state"), not open."
if [ "$(printf '%s' "$pr" | jq -r '.isDraft')" != true ]; then
  say "\`/ready\` from @$COMMENTER: PR #$PR is already ready for review; nothing to do."
  exit 0
fi

tmp=$(mktemp "${TMPDIR:-/tmp}/pr-body.XXXXXX") || exit 1
trap 'rm -f "$tmp"' EXIT
gh pr view "$PR" --json body --jq .body > "$tmp" || refuse "could not read the PR body."
if ! result=$(bash "$here/check-pr-body.sh" "$tmp" 2>&1); then
  refuse "the PR body is incomplete:
\`\`\`
$result
\`\`\`
Fix the body, then comment \`/ready\` again."
fi

sha=$(printf '%s' "$pr" | jq -r '.headRefOid')
run=$(gh api "repos/$GH_REPO/commits/$sha/check-runs?per_page=100" \
  --jq "[.check_runs[] | select(.name == \"$CHECK_NAME\")] | sort_by(.started_at) | last | if . == null then \"missing\" else (.conclusion // .status) end") \
  || refuse "could not read the check runs of $sha."
[ "$run" = success ] || refuse "\`$CHECK_NAME\` on the head commit ${sha:0:7} is $run, not success. Wait for it to pass (push a fix if it failed), then comment \`/ready\` again."

gh pr ready "$PR" >/dev/null || refuse "\`gh pr ready\` failed; mark it ready by hand."
say "Marked ready for review by \`/ready\` from @$COMMENTER.

A bot marked it ready, and events made with \`GITHUB_TOKEN\` start no workflows, so \`$CHECK_NAME\` and the AI review do not re-run now. That is why this job checked the body and \`$CHECK_NAME\` on ${sha:0:7} first. The AI review runs on the next push or body edit."
