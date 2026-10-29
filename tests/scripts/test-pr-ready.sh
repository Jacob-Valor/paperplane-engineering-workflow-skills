#!/usr/bin/env bash
# Behaviour tests for repo-setup's /ready automation (paperplane-ready.sh and its workflow), against a fake `gh`.
# Run: bash tests/scripts/run.sh
set -u
here=$(cd "$(dirname "$0")/../.." && pwd)
A="$here/skills/paperplane-repo-setup/assets/.github"
out=/tmp/pp-test-out.$$
pass=0; fail=0
expect() { # expect <name> <wanted-exit> <cmd...>
  local name=$1 want=$2; shift 2
  "$@" >"$out" 2>&1; local got=$?
  if [ "$got" -eq "$want" ]; then pass=$((pass+1)); echo "ok   $name"
  else fail=$((fail+1)); echo "FAIL $name: exit $got, wanted $want"; sed 's/^/     /' "$out"; fi
}
check() { # check <name> <got> <wanted>
  if [ "$2" = "$3" ]; then pass=$((pass+1)); echo "ok   $1"
  else fail=$((fail+1)); echo "FAIL $1: got '$2', wanted '$3'"; fi
}
in_file() { # in_file <name> <file> <regex>
  if grep -qE -- "$3" "$2" 2>/dev/null; then pass=$((pass+1)); echo "ok   $1"
  else fail=$((fail+1)); echo "FAIL $1: no line of $(basename "$2") matches '$3'"; sed 's/^/     /' "$2" 2>/dev/null; fi
}

command -v jq >/dev/null 2>&1 || { echo "jq is required by the script and the fake gh"; exit 1; }

work=$(mktemp -d); trap 'rm -rf "$work" "$out"' EXIT
F="$work/gh-data"; mkdir -p "$F" "$work/bin" "$work/repo/.github"
cp -R "$A/." "$work/repo/.github/"
export FAKE_GH="$F"
cat > "$work/bin/gh" <<'EOF'
#!/usr/bin/env bash
# Fake gh: answers from canned files in $FAKE_GH, applies --jq like gh does, logs every call and comment body.
echo "$*" >> "$FAKE_GH/calls"
jqf=""; args=()
while [ $# -gt 0 ]; do
  case "$1" in --jq) jqf=$2; shift ;; *) args+=("$1") ;; esac
  shift
done
set -- "${args[@]}"
emit() { if [ -n "$jqf" ]; then jq -r "$jqf" "$1"; else cat "$1"; fi; }
case "$1 $2" in
  "pr view") emit "$FAKE_GH/pr.json" ;;
  "pr comment") { cat; echo "----"; } >> "$FAKE_GH/comments" ;;
  "pr ready") echo "$3" >> "$FAKE_GH/readied" ;;
  "api repos/paperplanehq/demo/commits/abc1234def/check-runs?per_page=100") emit "$FAKE_GH/runs.json" ;;
  *) echo "fake gh: unexpected call: $*" >&2; exit 99 ;;
esac
EOF
chmod +x "$work/bin/gh"
export PATH="$work/bin:$PATH"
[ "$(command -v gh)" = "$work/bin/gh" ] || { echo "fake gh is not first on PATH; refusing to call the real one"; exit 1; }

good_body=$'## How I verified it\n- Commands: pnpm test, 42 passed\n\n## Risk\nOTP flow. Not done: Android device.\n\nAI-assisted: yes (claude) - ran the suite'
pr_json() { # pr_json <draft> <state> <body>
  cat > "$F/pr.json" <<EOF
{"author":{"login":"Alice"},"state":"$2","isDraft":$1,"headRefOid":"abc1234def","body":$(printf '%s' "$3" | jq -Rs .)}
EOF
}
runs_json() { # runs_json <run objects, comma-separated>
  echo "{\"total_count\":0,\"check_runs\":[$1]}" > "$F/runs.json"
}
run() { # run <conclusion-or-null> <status> <started_at> [name]
  printf '{"name":"%s","status":"%s","conclusion":%s,"started_at":"%s"}' "${4:-standard / checks}" "$2" "$1" "$3"
}
reset() {
  rm -f "$F/calls" "$F/comments" "$F/readied"
  pr_json true OPEN "$good_body"
  runs_json "$(run '"failure"' completed 2026-10-01T10:00:00Z),$(run '"success"' completed 2026-10-01T11:00:00Z),$(run '"failure"' completed 2026-10-01T12:00:00Z 'standard / lint')"
}
ready() { # ready <commenter> <association> [type] [comment body]
  (cd "$work/repo" && env PR=7 COMMENTER="$1" COMMENT_ASSOCIATION="$2" COMMENTER_TYPE="${3:-User}" \
    COMMENT_BODY="${4:-/ready}" GH_REPO=paperplanehq/demo GH_TOKEN=x bash .github/scripts/paperplane-ready.sh)
}
readied() { cat "$F/readied" 2>/dev/null; }
n_comments() { grep -c '^----$' "$F/comments" 2>/dev/null || true; }

reset
expect "author and member: passes" 0 ready alice MEMBER
check  "author and member: gh pr ready 7 called" "$(readied)" 7
in_file "success comment names the commenter" "$F/comments" '^Marked ready for review by `/ready` from @alice\.'
in_file "success comment explains no re-run" "$F/comments" 'GITHUB_TOKEN.*start no workflows'
in_file "success comment: AI review on next push or body edit" "$F/comments" 'AI review runs on the next push or body edit'
check  "success: one comment" "$(n_comments)" 1
for assoc in OWNER COLLABORATOR; do
  reset; expect "author and $assoc: passes" 0 ready ALICE "$assoc"
  check "author and $assoc: readied" "$(readied)" 7
done

reset
expect "non-author refused" 1 ready bob MEMBER
check  "non-author: not readied" "$(readied)" ""
in_file "non-author: says only the author" "$F/comments" 'only the PR author \(@Alice\)'
check  "non-author: one comment" "$(n_comments)" 1
for assoc in NONE CONTRIBUTOR FIRST_TIME_CONTRIBUTOR; do
  reset; expect "author with $assoc refused" 1 ready alice "$assoc"
  check "author with $assoc: not readied" "$(readied)" ""
  in_file "author with $assoc: names the association" "$F/comments" "association is $assoc"
done

reset
expect "bot by [bot] suffix refused" 1 ready "paperplane-agent[bot]" MEMBER
check  "bot suffix: not readied" "$(readied)" ""
in_file "bot suffix: says bots cannot" "$F/comments" 'bots and agents cannot'
reset
pr_json true OPEN "$good_body"; sed -i.bak 's/"Alice"/"robo"/' "$F/pr.json"
expect "bot by user type refused, even as author" 1 ready robo MEMBER Bot
check  "bot type: not readied" "$(readied)" ""

reset; pr_json false OPEN "$good_body"
expect "already ready: no-op exit 0" 0 ready alice MEMBER
check  "already ready: not readied again" "$(readied)" ""
in_file "already ready: says so" "$F/comments" 'already ready for review'
reset; pr_json true CLOSED "$good_body"
expect "closed PR refused" 1 ready alice MEMBER
in_file "closed PR: says not open" "$F/comments" 'is closed, not open'

reset; pr_json true OPEN $'## How I verified it\n\n## Risk\n\nAI-assisted: yes / no'
expect "incomplete body refused" 1 ready alice MEMBER
check  "incomplete body: not readied" "$(readied)" ""
in_file "incomplete body: quotes the checker" "$F/comments" "MISSING: 'How I verified it' is empty"
check  "incomplete body: one comment" "$(n_comments)" 1
reset; printf '    with:\n      mobile: true\n' > "$work/repo/.github/workflows/standard.yml"
expect "app repo: body without iOS/Android refused" 1 ready alice MEMBER
in_file "app repo: mobile detected from standard.yml" "$F/comments" "'- iOS:' line is empty"
rm "$work/repo/.github/workflows/standard.yml"

reset; runs_json "$(run '"success"' completed 2026-10-01T10:00:00Z),$(run '"failure"' completed 2026-10-01T11:00:00Z)"
expect "latest checks failed: refused" 1 ready alice MEMBER
check  "checks failed: not readied" "$(readied)" ""
in_file "checks failed: names the check and result" "$F/comments" '`standard / checks` on the head commit abc1234 is failure'
reset; runs_json "$(run null in_progress 2026-10-01T10:00:00Z)"
expect "checks still running: refused" 1 ready alice MEMBER
in_file "checks running: says in_progress" "$F/comments" 'is in_progress, not success'
reset; runs_json "$(run '"success"' completed 2026-10-01T10:00:00Z 'checks')"
expect "checks missing: refused" 1 ready alice MEMBER
in_file "checks missing: says missing" "$F/comments" 'is missing, not success'

for b in $'  /ready  ' $'/ready\r\n' $'\n/ready\n'; do
  reset; expect "comment variant $(printf '%q' "$b") accepted" 0 ready alice MEMBER User "$b"
  check "comment variant $(printf '%q' "$b"): readied" "$(readied)" 7
done
for b in "/ready please" "not /ready" $'/ready\nlater' "/readyy"; do
  reset; expect "comment $(printf '%q' "$b") ignored" 0 ready alice MEMBER User "$b"
  check "comment $(printf '%q' "$b"): no gh call" "$(cat "$F/calls" 2>/dev/null)" ""
done

if cmp -s "$A/scripts/check-pr-body.sh" "$here/skills/paperplane-shipping-changes/scripts/check-pr-body.sh"; then
  pass=$((pass+1)); echo "ok   assets check-pr-body.sh is byte-identical to the shipping skill's"
else fail=$((fail+1)); echo "FAIL assets check-pr-body.sh differs from skills/paperplane-shipping-changes/scripts/check-pr-body.sh"; fi

W="$A/workflows/paperplane-ready.yml"
run_exprs=$(awk '/^[ ]*(- )?run:/{r=1; print; next} r && /^[ ]*(- )?[a-z_-]+:/{r=0} r{print}' "$W" | grep -F '${{' || true)
check "workflow: no \${{ }} inside run:" "$run_exprs" ""
check "workflow: checkout has no ref:" "$(grep -cE '^[ ]*ref:' "$W")" 0
in_file "workflow: checkout keeps no credentials" "$W" 'persist-credentials: false'
in_file "workflow: job if needs a PR comment mentioning /ready" "$W" "if: github.event.issue.pull_request && contains\(github.event.comment.body, '/ready'\)"
in_file "workflow: concurrency per PR" "$W" 'group: paperplane-ready-\$\{\{ github.event.issue.number \}\}'
for p in 'contents: write' 'pull-requests: write' 'issues: write' 'checks: read'; do
  in_file "workflow: permission $p" "$W" "^  $p$"
done
check "workflow: exactly four permissions" "$(awk '/^permissions:/{f=1;next} f&&/^[^ ]/{exit} f&&NF{n++} END{print n+0}' "$W")" 4

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
