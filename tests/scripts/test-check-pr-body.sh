#!/usr/bin/env bash
# Behaviour tests for the shipping skill's check-pr-body.sh: comments, AI-assisted line, CRLF. Run: bash tests/scripts/run.sh
set -u
here=$(cd "$(dirname "$0")/../.." && pwd)
S="$here/skills/paperplane-shipping-changes/scripts"
out=/tmp/pp-test-out.$$
pass=0; fail=0
expect() { # expect <name> <wanted-exit> <cmd...>
  local name=$1 want=$2; shift 2
  "$@" >"$out" 2>&1; local got=$?
  if [ "$got" -eq "$want" ]; then pass=$((pass+1)); echo "ok   $name"
  else fail=$((fail+1)); echo "FAIL $name: exit $got, wanted $want"; sed 's/^/     /' "$out"; fi
}
says() { # says <name> <regex>: the last expect's output matches
  if grep -qE -- "$2" "$out"; then pass=$((pass+1)); echo "ok   $1"
  else fail=$((fail+1)); echo "FAIL $1: no line matches '$2'"; sed 's/^/     /' "$out"; fi
}
work=$(mktemp -d); trap 'rm -rf "$work" "$out"' EXIT
cd "$work" || exit 1 # no .github/workflows/standard.yml here: pass --mobile / --no-mobile
C="$S/check-pr-body.sh"
body() { # body <file> <verified line> <risk line> <ai line>
  printf '## How I verified it\n%s\n\n## Risk\n%s\n\n%s\n' "$2" "$3" "$4" > "$1"
}

body ok.md "- Commands: pnpm test" "Low. Not done: iOS." "AI-assisted: no"
expect "complete body passes" 0 bash "$C" --no-mobile ok.md

# (a) a multi-line placeholder comment alone is not content
printf '## How I verified it\n<!--\nList the commands you ran.\nOne per line.\n-->\n\n## Risk\nLow. Not done: x.\n\nAI-assisted: no\n' > multi.md
expect "multi-line comment alone is empty" 1 bash "$C" --no-mobile multi.md
says   "multi-line comment: names the section" "'How I verified it' is empty"
printf '## How I verified it\n- Commands: pnpm test\n\n## Risk\n<!--\nWhat could break?\n## Not a heading\n-->\n\n## Checklist\n- [ ] x\n\nAI-assisted: no\n' > multirisk.md
expect "multi-line comment alone in Risk is empty" 1 bash "$C" --no-mobile multirisk.md
says   "multi-line comment hides a heading inside it" "'Risk' is empty"
printf '## How I verified it\n<!-- multi\nline --> - Commands: pnpm test\n\n## Risk\nLow. Not done: x.\n\nAI-assisted: no\n' > multitext.md
expect "text after a multi-line comment close counts" 0 bash "$C" --no-mobile multitext.md

# (b) non-greedy: content between two comments on one line is kept
printf '## How I verified it\n<!-- a -->- ran stuff <!-- b -->\n\n## Risk\nLow. Not done: x.\n\nAI-assisted: no\n' > two.md
expect "text between two comments is kept" 0 bash "$C" --no-mobile two.md
printf '## How I verified it\n<!-- a --> <!-- b -->\n\n## Risk\nLow. Not done: x.\n\nAI-assisted: no\n' > twoempty.md
expect "two comments and nothing else is empty" 1 bash "$C" --no-mobile twoempty.md
printf '## How I verified it\n- Commands: x\n- iOS: <!-- a -->iPhone 15 sim<!-- b -->\n- Android: <!-- c --> Pixel 8\n\n## Risk\nLow. Not done: x.\n\nAI-assisted: no\n' > mob.md
expect "mobile lines keep text between comments" 0 bash "$C" --mobile mob.md
printf '## How I verified it\n- Commands: x\n- iOS: <!-- a -->\n- Android: Pixel\n\n## Risk\nLow. Not done: x.\n\nAI-assisted: no\n' > mobempty.md
expect "mobile line that is only a comment is empty" 1 bash "$C" --mobile mobempty.md

# (c) the AI-assisted line
for l in "AI-assisted: yes" "AI-assisted: no" "AI-assisted: yes (claude) — ran the suite" "AI-assisted:yes" "AI-assisted: no — hand-written"; do
  body ai.md "- Commands: x" "Low. Not done: x." "$l"
  expect "AI line accepted: $l" 0 bash "$C" --no-mobile ai.md
done
for l in "AI-assisted: yesterday" "AI-assisted: nothing" "AI-assisted: yes / no" "AI-assisted: no / yes" "AI-assisted:" "AI-assisted: maybe"; do
  body ai.md "- Commands: x" "Low. Not done: x." "$l"
  expect "AI line rejected: $l" 1 bash "$C" --no-mobile ai.md
done
printf '## How I verified it\n- Commands: x\n\n## Risk\nLow. Not done: x.\n\n<!-- AI-assisted: yes -->\n' > aicomment.md
expect "AI line only inside a comment is rejected" 1 bash "$C" --no-mobile aicomment.md

# (d) CRLF bodies
sed 's/$/\r/' ok.md > crlf.md
expect "CRLF body passes" 0 bash "$C" --no-mobile crlf.md
sed 's/$/\r/' multi.md > crlf-multi.md
expect "CRLF multi-line comment is empty" 1 bash "$C" --no-mobile crlf-multi.md
sed 's/$/\r/' mob.md > crlf-mob.md
expect "CRLF mobile lines pass" 0 bash "$C" --mobile crlf-mob.md
printf '## How I verified it\r\n- Commands:\r\n\r\n## Risk\r\nLow. Not done: x.\r\n\r\nAI-assisted: no\r\n' > crlf-empty.md
expect "CRLF empty Commands line is empty" 1 bash "$C" --no-mobile crlf-empty.md

# (e) both mobile lines are required for an app repo, each on its own
mobbody() { # mobbody <file> <iOS value> <Android value>
  printf '## How I verified it\n- Commands: x\n- iOS: %s\n- Android: %s\n\n## Risk\nLow. Not done: x.\n\nAI-assisted: no\n' "$2" "$3" > "$1"
}
mobbody both.md "iPhone 15 sim" "Pixel 8"
expect "mobile: both lines filled passes" 0 bash "$C" --mobile both.md
mobbody noandroid.md "iPhone 15 sim" ""
expect "mobile: iOS filled, Android empty fails" 1 bash "$C" --mobile noandroid.md
says   "mobile: names the Android line" "'- Android:' line is empty"
mobbody noios.md "" "Pixel 8"
expect "mobile: iOS empty, Android filled fails" 1 bash "$C" --mobile noios.md
says   "mobile: names the iOS line" "'- iOS:' line is empty"
printf '## How I verified it\n- Commands: x\n- iOS: iPhone 15 sim\n\n## Risk\nLow. Not done: x.\n\nAI-assisted: no\n' > noandroidline.md
expect "mobile: Android line missing fails" 1 bash "$C" --mobile noandroidline.md
sed 's/$/\r/' noandroid.md > crlf-noandroid.md
expect "CRLF: Android empty still fails" 1 bash "$C" --mobile crlf-noandroid.md
mobbody neither.md "" ""
expect "mobile: neither line filled fails" 1 bash "$C" --mobile neither.md
expect "non-mobile: empty iOS and Android lines are fine" 0 bash "$C" --no-mobile neither.md
mobbody tbd.md "not a mobile change" "not a mobile change"
expect "mobile: 'not a mobile change' passes" 0 bash "$C" --mobile tbd.md
mkdir -p .github/workflows
printf 'jobs:\n  s:\n    with:\n      mobile: true\n' > .github/workflows/standard.yml
expect "auto-detect: mobile: true in standard.yml requires Android" 1 bash "$C" noandroid.md
rm -rf .github

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
