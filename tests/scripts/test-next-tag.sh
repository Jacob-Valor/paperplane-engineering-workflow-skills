#!/usr/bin/env bash
# Behaviour tests for the releasing skill's next-tag.sh. Run: bash tests/scripts/run.sh
set -u
here=$(cd "$(dirname "$0")/../.." && pwd)
S="$here/skills/paperplane-releasing/scripts"
out=/tmp/pp-test-out.$$; err=/tmp/pp-test-err.$$
pass=0; fail=0
expect() { # expect <name> <wanted-exit> <cmd...>   (stdout in $out, stderr in $err)
  local name=$1 want=$2; shift 2
  "$@" >"$out" 2>"$err"; local got=$?
  if [ "$got" -eq "$want" ]; then pass=$((pass+1)); echo "ok   $name"
  else fail=$((fail+1)); echo "FAIL $name: exit $got, wanted $want"; sed 's/^/     /' "$out" "$err"; fi
}
same() { # same <name> <file> <wanted-content>
  local name=$1 file=$2 want=$3 got
  got=$(cat "$file")
  if [ "$got" = "$want" ]; then pass=$((pass+1)); echo "ok   $name"
  else fail=$((fail+1)); echo "FAIL $name: got '$got', wanted '$want'"; fi
}

work=$(mktemp -d); trap 'rm -rf "$work" "$out" "$err"' EXIT
cd "$work" || exit 1
git init -q repo
cd repo || exit 1
git config user.name "Test Dev"; git config user.email "dev@example.com"
echo a > a; git add a; git commit -qm init
tag() { GIT_COMMITTER_DATE="$1" git tag -a -m "$2" "$2"; } # tag <date> <name>: annotated, fixed tag date

nt() { bash "$S/next-tag.sh" --no-fetch "$@"; }

expect "no tags: base tag" 0 nt --date 2026-10-09
same   "no tags: base tag name" "$out" "prod-2026.10.09"
same   "no tags: no CTO warning" "$err" ""
expect "no tags: --previous has nothing to roll back to" 1 nt --previous

tag "2026-10-08T10:00:00" prod-2026.10.08
tag "2026-10-08T15:00:00" prod-2026.10.08.2
tag "2026-10-10T10:00:00" prod-2026.10.10
expect "other dates ignored" 0 nt --date 2026-10-09
same   "other dates ignored: name" "$out" "prod-2026.10.09"

tag "2026-10-09T09:00:00" prod-2026.10.09
expect "base exists: .2" 0 nt --date 2026-10-09
same   "base exists: name" "$out" "prod-2026.10.09.2"
same   "base exists: no CTO warning" "$err" ""

tag "2026-10-09T12:00:00" prod-2026.10.09.2
expect ".2 exists: .3" 0 nt --date 2026-10-09
same   ".2 exists: name" "$out" "prod-2026.10.09.3"
same   ".2 exists: CTO warning on stderr" "$err" "confirm prod-2026.10.09.3 with the CTO (the guide only shows .2)"

tag "2026-10-09T13:00:00" prod-2026.10.09.10
tag "2026-10-09T13:00:01" prod-2026.10.09.2-bad
expect "highest .N wins numerically, odd names ignored" 0 nt --date 2026-10-09
same   "highest .N: name" "$out" "prod-2026.10.09.11"

expect "uat prefix: no uat tags" 0 nt --prefix uat --date 2026-10-09
same   "uat prefix: name" "$out" "uat-2026.10.09"
tag "2026-10-09T08:00:00" uat-2026.10.09
expect "uat prefix: base exists" 0 nt --prefix uat --date 2026-10-09
same   "uat prefix: .2" "$out" "uat-2026.10.09.2"

expect "default date is today" 0 nt
same   "default date: name" "$out" "prod-$(date +%Y.%m.%d)"

expect "--previous: newest prod tag by tag date" 0 nt --previous
same   "--previous: name" "$out" "prod-2026.10.10"
expect "--previous ignores uat tags" 0 nt --previous --prefix uat
same   "--previous uat: name" "$out" "uat-2026.10.09"

before=$(git tag -l | wc -l)
nt --date 2026-10-09 >/dev/null 2>&1
same "never creates tags" <(git tag -l | wc -l) "$before"

git remote add origin "$work/missing.git"
expect "fetch failure stops (unreachable origin)" 2 bash "$S/next-tag.sh" --date 2026-10-09
git remote remove origin
expect "usage: bad prefix" 2 nt --prefix v
expect "usage: bad date" 2 nt --date 2026.10.09
expect "usage: unknown flag" 2 nt --push
expect "help" 0 nt --help
cd "$work" || exit 1
expect "not a git repo" 2 nt

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
