#!/usr/bin/env bash
# Behaviour tests for the merge-back workflow script, with real git repos and a fake `gh`. Run: bash tests/scripts/run.sh
set -u
here=$(cd "$(dirname "$0")/../.." && pwd)
A="$here/skills/paperplane-repo-setup/assets/.github"
S="$A/scripts/paperplane-merge-back.sh"
W="$A/workflows/paperplane-merge-back.yml"
C="$here/skills/paperplane-shipping-changes/scripts/check-pr-body.sh"
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

command -v jq >/dev/null 2>&1 || { echo "jq is required by the fake gh in this test"; exit 1; }

work=$(mktemp -d); trap 'rm -rf "$work" "$out"' EXIT
F="$work/gh-data"; mkdir -p "$work/bin"
export FAKE_GH="$F"
cat > "$work/bin/gh" <<'EOF'
#!/usr/bin/env bash
# Fake gh with state: `pr create` records an open PR per base in $FAKE_GH, `pr list` returns them.
echo "$*" >> "$FAKE_GH/calls"
jqf=""; args=()
while [ $# -gt 0 ]; do
  case "$1" in --jq) jqf=$2; shift ;; *) args+=("$1") ;; esac
  shift
done
set -- "${args[@]}"
arg_after() { local want=$1; shift; while [ $# -gt 1 ]; do [ "$1" = "$want" ] && { echo "$2"; return; }; shift; done; }
case "$1 $2" in
  "pr list")
    [ "$(arg_after --head "$@")" = main ] && [ "$(arg_after --state "$@")" = open ] || { echo "fake gh: unexpected list: $*" >&2; exit 99; }
    base=$(arg_after --base "$@")
    if [ -f "$FAKE_GH/open-$base" ]; then json="[{\"number\":$(cat "$FAKE_GH/open-$base")}]"; else json='[]'; fi
    if [ -n "$jqf" ]; then printf '%s' "$json" | jq -r "$jqf"; else printf '%s\n' "$json"; fi ;;
  "pr create")
    base=$(arg_after --base "$@"); n=$(( $(cat "$FAKE_GH/next" 2>/dev/null || echo 100) + 1 )); echo "$n" > "$FAKE_GH/next"
    echo "$n" > "$FAKE_GH/open-$base"
    arg_after --title "$@" > "$FAKE_GH/title-$base"
    cp "$(arg_after --body-file "$@")" "$FAKE_GH/body-$base.md"
    echo "https://github.com/paperplanehq/demo/pull/$n" ;;
  "pr comment")
    cp "$(arg_after --body-file "$@")" "$FAKE_GH/comment-${3##*/}.md" ;;
  *) echo "fake gh: unexpected call: $*" >&2; exit 99 ;;
esac
EOF
chmod +x "$work/bin/gh"
export PATH="$work/bin:$PATH"
[ "$(command -v gh)" = "$work/bin/gh" ] || { echo "fake gh is not first on PATH; refusing to call the real one"; exit 1; }

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=Test GIT_AUTHOR_EMAIL=t@x GIT_COMMITTER_NAME=Test GIT_COMMITTER_EMAIL=t@x
export GH_REPO=paperplanehq/demo GH_TOKEN=fake

# fresh <name>: a bare origin with main, uat, develop at one commit; $seed is a clone to build history in.
fresh() {
  rm -rf "$F"; mkdir -p "$F"
  origin="$work/$1.git"; seed="$work/$1-seed"; run="$work/$1-run"
  git init -q --bare "$origin"
  git init -q -b main "$seed"
  printf 'line one\nline two\n' > "$seed/app.txt"
  git -C "$seed" add app.txt && git -C "$seed" commit -qm "chore: init"
  git -C "$seed" branch uat && git -C "$seed" branch develop
  git -C "$seed" remote add origin "$origin"
}
publish() { # publish <tag>: tag main, push everything, clone like actions/checkout with fetch-depth 0
  git -C "$seed" tag "$1" main
  git -C "$seed" push -q origin main uat develop --tags
  rm -rf "$run"; git clone -q -b develop "$origin" "$run"
}
merge_back() { (cd "$run" && TAG=$1 bash "$S"); }
commit_on() { # commit_on <branch> <message> <sed expression on app.txt>
  git -C "$seed" switch -q "$1" && sed -i.bak "$3" "$seed/app.txt" && rm "$seed/app.txt.bak"
  git -C "$seed" commit -qam "$2"
}

fresh hotfix
commit_on main "fix(pay): stop double charge (#42)" 's/line two/line two fixed/'
publish prod-2026.10.29
expect "hotfix: script succeeds" 0 merge_back prod-2026.10.29
has    "hotfix: reports the uat PR" "opened https://github.com/paperplanehq/demo/pull/"
check  "hotfix: uat title" "$(cat "$F/title-uat" 2>/dev/null)" "chore(release): merge hotfix prod-2026.10.29 back into uat"
check  "hotfix: develop title" "$(cat "$F/title-develop" 2>/dev/null)" "chore(release): merge hotfix prod-2026.10.29 back into develop"
check  "hotfix: both are drafts from main" "$(grep -c -- '^pr create --draft --base [a-z]* --head main ' "$F/calls")" "2"
check  "hotfix: uat before develop" "$(sed -n 's/^pr create --draft --base \([a-z]*\).*/\1/p' "$F/calls" | tr '\n' ' ')" "uat develop "
check  "hotfix: no comment without conflicts" "$(grep -c '^pr comment' "$F/calls")" "0"
for b in uat develop; do
  expect "hotfix: $b body passes --no-mobile" 0 bash "$C" --no-mobile "$F/body-$b.md"
  lacks  "hotfix: $b body has no Risk warning" "WARNING"
  expect "hotfix: $b body passes --mobile" 0 bash "$C" --mobile "$F/body-$b.md"
done
expect "hotfix: body lists the hotfix commit" 0 grep -qE '^- fix\(pay\): stop double charge \(#42\) \([0-9a-f]+\)$' "$F/body-develop.md"
expect "hotfix: body names the verify command" 0 grep -qxF -- '- Commands: git log --no-merges origin/develop..prod-2026.10.29' "$F/body-develop.md"
expect "hotfix: body says who opened it" 0 grep -qxF 'AI-assisted: no (opened by the paperplane-merge-back workflow)' "$F/body-uat.md"

expect "rerun: script succeeds" 0 merge_back prod-2026.10.29
has    "rerun: skips uat" "open PR from main into uat already exists"
has    "rerun: skips develop" "open PR from main into develop already exists"
check  "rerun: no new PR" "$(grep -c '^pr create' "$F/calls")" "2"

fresh release
commit_on develop "feat(otp): add resend (#40)" 's/line one/line one with otp/'
git -C "$seed" switch -q uat && git -C "$seed" merge -q --no-ff -m "chore(release): develop into uat" develop
git -C "$seed" switch -q main && git -C "$seed" merge -q --no-ff -m "chore(release): uat into main" uat
publish prod-2026.10.30
expect "release: script succeeds" 0 merge_back prod-2026.10.30
has    "release: nothing missing from uat" "^no hotfix commits missing from uat$"
has    "release: nothing missing from develop" "^no hotfix commits missing from develop$"
check  "release: no gh call" "$(cat "$F/calls" 2>/dev/null)" ""

fresh existing
commit_on main "fix(pay): hotfix (#43)" 's/line two/line two fixed/'
publish prod-2026.10.31
echo 7 > "$F/open-uat"
expect "existing uat PR: script succeeds" 0 merge_back prod-2026.10.31
has    "existing uat PR: skipped" "open PR from main into uat already exists"
check  "existing uat PR: only develop created" "$(sed -n 's/^pr create --draft --base \([a-z]*\).*/\1/p' "$F/calls")" "develop"

fresh conflict
commit_on develop "feat(pay): rework (#41)" 's/line two/line two reworked/'
commit_on main "fix(pay): hotfix (#44)" 's/line two/line two fixed/'
publish prod-2026.11.01
expect "conflict: script succeeds" 0 merge_back prod-2026.11.01
has    "conflict: reported" "conflicts with develop: commented on"
check  "conflict: both drafts still opened" "$(grep -c '^pr create --draft' "$F/calls")" "2"
check  "conflict: one comment" "$(grep -c '^pr comment' "$F/calls")" "1"
cf=$(ls "$F"/comment-*.md 2>/dev/null)
dev_n=$(cat "$F/open-develop" 2>/dev/null)
check  "conflict: comment is on the develop PR" "$cf" "$F/comment-$dev_n.md"
expect "conflict: comment warns off the web editor" 0 grep -q 'Do not resolve the conflicts in the GitHub web editor' "$cf"
expect "conflict: comment names the merge-back branch" 0 grep -q 'chore/merge-back-prod-2026.11.01' "$cf"

expect "bad tag: refused" 2 env TAG='prod-x;rm' bash -c 'cd "$1" && bash "$2"' _ "$run" "$S"
expect "unknown tag: refused" 2 merge_back prod-1999.01.01
has    "unknown tag: says so" "tag prod-1999.01.01 not found"

runexpr=$(awk '
  /^[[:space:]]*(- )?run:/ { match($0, /^[[:space:]]*/); ind = RLENGTH; print; inrun = 1; next }
  inrun { match($0, /^[[:space:]]*/); if ($0 ~ /^[[:space:]]*$/ || RLENGTH > ind) { print; next }; inrun = 0 }
' "$W" | grep -F '${{')
check  "workflow: no \${{ }} in run blocks" "$runexpr" ""
expect "workflow: tag passed via env" 0 grep -qE '^ +TAG: \$\{\{ inputs\.tag \|\| github\.ref_name \}\}$' "$W"
expect "workflow: triggers on prod-* tags" 0 grep -qF "tags: ['prod-*']" "$W"
expect "workflow: least privilege" 0 grep -qE '^  pull-requests: write$' "$W"
expect "workflow: no credentials left in the clone" 0 grep -qE '^ +persist-credentials: false$' "$W"
expect "workflow: checks out the default branch, not the tag" 0 grep -qF 'ref: ${{ github.event.repository.default_branch }}' "$W"

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
