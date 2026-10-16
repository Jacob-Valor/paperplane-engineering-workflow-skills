#!/usr/bin/env bash
# Behaviour tests for the reviewing skill's gather.sh, against a fake `gh`. Run: bash tests/scripts/run.sh
set -u
here=$(cd "$(dirname "$0")/../.." && pwd)
S="$here/skills/paperplane-reviewing-prs/scripts"
out=/tmp/pp-test-out.$$
pass=0; fail=0
expect() { # expect <name> <wanted-exit> <cmd...>
  local name=$1 want=$2; shift 2
  "$@" >"$out" 2>&1; local got=$?
  if [ "$got" -eq "$want" ]; then pass=$((pass+1)); echo "ok   $name"
  else fail=$((fail+1)); echo "FAIL $name: exit $got, wanted $want"; sed 's/^/     /' "$out"; fi
}
has() { # has <name> <regex>: the last expect's output matches
  if grep -qE -- "$2" "$out"; then pass=$((pass+1)); echo "ok   $1"
  else fail=$((fail+1)); echo "FAIL $1: no line matches '$2'"; sed 's/^/     /' "$out"; fi
}
lacks() { # lacks <name> <regex>: the last expect's output does not match
  if ! grep -qE -- "$2" "$out"; then pass=$((pass+1)); echo "ok   $1"
  else fail=$((fail+1)); echo "FAIL $1: a line matches '$2'"; sed 's/^/     /' "$out"; fi
}
check() { # check <name> <got> <wanted>
  if [ "$2" = "$3" ]; then pass=$((pass+1)); echo "ok   $1"
  else fail=$((fail+1)); echo "FAIL $1: got '$2', wanted '$3'"; fi
}
under() { # under <name> <section> <wanted>: first line of a section in the last expect's output
  check "$1" "$(grep -A1 -x "== $2 ==" "$out" | sed -n 2p)" "$3"
}

command -v jq >/dev/null 2>&1 || { echo "jq is required by the fake gh in this test"; exit 1; }

work=$(mktemp -d); trap 'rm -rf "$work" "$out"' EXIT
F="$work/gh-data"; mkdir -p "$F" "$work/bin"
export FAKE_GH="$F"
cat > "$work/bin/gh" <<'EOF'
#!/usr/bin/env bash
# Fake gh: answers from canned files in $FAKE_GH, applies --jq like gh does, logs every call.
echo "$*" >> "$FAKE_GH/calls"
jqf=""; args=()
while [ $# -gt 0 ]; do
  case "$1" in --jq) jqf=$2; shift ;; *) args+=("$1") ;; esac
  shift
done
set -- "${args[@]}"
emit() { if [ -n "$jqf" ]; then jq -r "$jqf" "$1"; else cat "$1"; fi; }
arg_after() { local want=$1; shift; while [ $# -gt 1 ]; do [ "$1" = "$want" ] && { echo "$2"; return; }; shift; done; }
case "$1 $2" in
  "repo view")
    [ -f "$FAKE_GH/repo.json" ] || { echo "no git remotes found" >&2; exit 1; }
    emit "$FAKE_GH/repo.json" ;;
  "pr view")
    [ -f "$FAKE_GH/pr-$3.json" ] || { echo "GraphQL: Could not resolve to a PullRequest with the number of $3. (repository.pullRequest)" >&2; exit 1; }
    emit "$FAKE_GH/pr-$3.json" ;;
  "pr checks")
    cat "$FAKE_GH/checks-$3.txt"; exit "$(cat "$FAKE_GH/checks-$3.rc")" ;;
  "pr diff")
    case " $* " in *" --name-only "*) cat "$FAKE_GH/files-$3.txt" ;; *) cat "$FAKE_GH/diff-$3.txt" ;; esac ;;
  "pr list")
    head=$(arg_after --head "$@"); f="$FAKE_GH/head-${head//\//_}.json"
    if [ -f "$f" ]; then emit "$f"; else echo '[]' > "$FAKE_GH/empty.json"; emit "$FAKE_GH/empty.json"; fi ;;
  "api graphql")
    n=""; for a in "$@"; do case "$a" in number=*) n=${a#number=} ;; esac; done
    [ -f "$FAKE_GH/threads-$n.json" ] || { echo "HTTP 502: Bad Gateway" >&2; exit 1; }
    emit "$FAKE_GH/threads-$n.json" ;;
  *) echo "fake gh: unexpected call: $*" >&2; exit 99 ;;
esac
EOF
chmod +x "$work/bin/gh"
export PATH="$work/bin:$PATH"
[ "$(command -v gh)" = "$work/bin/gh" ] || { echo "fake gh is not first on PATH; refusing to call the real one"; exit 1; }

pr_json() { # pr_json <n> <draft> <base> <head> <body>
  cat > "$F/pr-$1.json" <<EOF
{"number":$1,"title":"feat(otp): pr $1","url":"https://github.com/paperplanehq/demo/pull/$1",
 "author":{"login":"alice"},"state":"OPEN","isDraft":$2,"baseRefName":"$3","headRefName":"$4",
 "additions":12,"deletions":3,"changedFiles":2,"body":$(printf '%s' "$5" | jq -Rs .),
 "commits":[{"authors":[{"login":"alice","name":"Alice","email":"a@x"}]},
            {"authors":[{"login":"","name":"Bot Box","email":"bot@x"},{"login":"alice","name":"Alice","email":"a@x"}]}]}
EOF
  printf 'src/otp.ts\nsrc/otp.test.ts\n' > "$F/files-$1.txt"
  printf 'diff --git a/src/otp.ts b/src/otp.ts\n+const TIMEOUT = 30\n' > "$F/diff-$1.txt"
  printf 'standard / lint\tpass\t12s\thttps://ci/1\n' > "$F/checks-$1.txt"; echo 0 > "$F/checks-$1.rc"
  echo '{"data":{"repository":{"pullRequest":{"reviewThreads":{"nodes":[{"isResolved":false},{"isResolved":true},{"isResolved":false}],"pageInfo":{"hasNextPage":false,"endCursor":null}}}}}}' > "$F/threads-$1.json"
}
body=$'## What changed\nFix OTP timeout.\n\n## Risk\nOTP flow.'
pr_json 10 false develop fix/otp "$body"
pr_json 11 false feature/a-base feature/b ""
pr_json 12 true develop feature/a-base "base"
pr_json 13 false feature/b feature/c ""
pr_json 14 false develop fix/lint "x"
printf 'standard / lint\tfail\t9s\thttps://ci/2\nstandard / test\tpending\t0\thttps://ci/3\n' > "$F/checks-14.txt"; echo 1 > "$F/checks-14.rc"
rm "$F/threads-14.json"
echo '[{"number":12,"title":"feat(a): base","isDraft":true,"baseRefName":"develop"}]' > "$F/head-feature_a-base.json"
echo '[{"number":11,"title":"feat(b): middle","isDraft":false,"baseRefName":"feature/a-base"}]' > "$F/head-feature_b.json"
echo '{"nameWithOwner":"paperplanehq/demo"}' > "$F/repo.json"

G="$S/gather.sh"

expect "normal PR" 0 bash "$G" 10 paperplanehq/demo
has    "normal: header" '^PR #10 in paperplanehq/demo$'
has    "normal: draft state and base" '^isDraft: false$'
has    "normal: size" '^size: \+12 -3 in 2 files$'
has    "normal: body verbatim" '^Fix OTP timeout\.$'
has    "normal: checks listed" 'standard / lint.*pass'
lacks  "normal: no failing-checks note" 'gh pr checks exit'
has    "normal: files" '^src/otp\.test\.ts$'
under  "normal: 2 unresolved threads" "Unresolved review threads" 2
has    "normal: commit author login" '^alice$'
has    "normal: author without login named" '^Bot Box <bot@x> \(no GitHub login\)$'
has    "normal: not stacked" '^not stacked: base is develop$'
has    "normal: diff included" '^\+const TIMEOUT = 30$'
check  "normal: diff is the last section" "$(grep '^== ' "$out" | tail -1)" "== Diff =="

expect "--no-diff" 0 bash "$G" 10 paperplanehq/demo --no-diff
lacks  "--no-diff: no diff section" '^== Diff ==$'
lacks  "--no-diff: no diff text" 'const TIMEOUT'
has    "--no-diff: other sections kept" '^== Commit authors ==$'

expect "stacked PR on a draft" 0 bash "$G" 11 paperplanehq/demo --no-diff
has    "stacked: base PR number" '^base PR: #12 feat\(a\): base$'
has    "stacked: base PR is a draft" '^  isDraft: true$'
has    "stacked: base PR's base" '^  base: develop$'
has    "stacked: depth 2" '^depth: 2 '
under  "stacked: empty body marked" "Body" "(empty)"

expect "stack deeper than 2" 0 bash "$G" 13 paperplanehq/demo --no-diff
has    "deep stack: depth 3 or more" '^depth: 3 or more'

expect "failing checks do not abort" 0 bash "$G" 14 paperplanehq/demo
has    "failing checks: listed" 'standard / lint.*fail'
has    "failing checks: noted" 'gh pr checks exit 1'
has    "failing checks: later sections still print" '^== Diff ==$'
printf 'standard / checks\tpass\t40s\thttps://ci/4\nstandard / AI review (advisory)\tfail\t1m\thttps://ci/5\n' > "$F/checks-14.txt"
expect "advisory-only red does not abort" 0 bash "$G" 14 paperplanehq/demo --no-diff
has    "advisory-only red: says it never blocks" 'only the advisory AI review.*never blocks'
lacks  "advisory-only red: not called unready" 'not ready to approve'
has    "unreadable section reported" '^unavailable: HTTP 502'

expect "repo from gh repo view" 0 bash "$G" 10 --no-diff
has    "repo from gh repo view: header" '^PR #10 in paperplanehq/demo$'

expect "unreadable PR" 2 bash "$G" 99 paperplanehq/demo
has    "unreadable PR: says why" 'cannot read PR #99 in paperplanehq/demo'
rm "$F/repo.json"
expect "no repo arg outside a GitHub repo" 2 bash "$G" 10
expect "usage: no PR number" 2 bash "$G"
expect "usage: not a number" 2 bash "$G" abc paperplanehq/demo
expect "usage: unknown flag" 2 bash "$G" 10 --approve
expect "help" 0 bash "$G" --help

if [ ! -s "$F/calls" ] || grep -qE '^(pr (merge|review|edit|ready|comment|close)|api .*-X|repo edit)' "$F/calls"; then
  fail=$((fail+1)); echo "FAIL read-only: gather.sh made a write call"; grep -E 'merge|review |edit|ready|comment|close' "$F/calls"
else pass=$((pass+1)); echo "ok   read-only: no write calls to gh"; fi

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
