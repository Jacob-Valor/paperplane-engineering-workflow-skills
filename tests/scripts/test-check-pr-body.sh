#!/usr/bin/env bash
# Behaviour tests for the shipping skill's check-pr-body.sh: comments, AI-assisted line, CRLF, pending mobile lines, screenshots. Run: bash tests/scripts/run.sh
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

# (a) as in CI, a multi-line comment is not removed: its lines count as content
printf '## How I verified it\n<!--\nList the commands you ran.\nOne per line.\n-->\n\n## Risk\nLow. Not done: x.\n\nAI-assisted: no\n' > multi.md
expect "multi-line comment counts as content, as in CI" 0 bash "$C" --no-mobile multi.md
printf '## How I verified it\n- Commands: pnpm test\n\n## Risk\n<!--\nWhat could break?\n## Not a heading\n-->\n\n## Checklist\n- [ ] x\n\nAI-assisted: no\n' > multirisk.md
expect "multi-line comment in Risk counts, a ## inside it ends the section, as in CI" 0 bash "$C" --no-mobile multirisk.md
printf '## How I verified it\n<!-- multi\nline --> - Commands: pnpm test\n\n## Risk\nLow. Not done: x.\n\nAI-assisted: no\n' > multitext.md
expect "text after a multi-line comment close counts" 0 bash "$C" --no-mobile multitext.md
# The device line is the first '- iOS:' line of the raw body, even inside a multi-line comment (CI fails this one)
printf '## How I verified it\n<!--\n- iOS: pending\n-->\n- Commands: x\n- iOS: iPhone 15, iOS 26.6: ok\n- Android: not a mobile change\n\n## Risk\nLow. Not done: x.\n\nAI-assisted: no\n' > blockios.md
expect "device line inside a multi-line comment is read first, as in CI" 1 bash "$C" --mobile blockios.md
says   "commented pending line is NOT DONE" "^NOT DONE: '- iOS:' says the check is not done"

# (b) as in CI, same-line comments are dropped greedily: text between two comments on one line goes too
printf '## How I verified it\n<!-- a -->- ran stuff <!-- b -->\n\n## Risk\nLow. Not done: x.\n\nAI-assisted: no\n' > two.md
expect "text between two comments on one line is dropped, as in CI" 1 bash "$C" --no-mobile two.md
says   "two comments: names the section" "'How I verified it' is empty"
printf '## How I verified it\n<!-- a --> <!-- b -->\n\n## Risk\nLow. Not done: x.\n\nAI-assisted: no\n' > twoempty.md
expect "two comments and nothing else is empty" 1 bash "$C" --no-mobile twoempty.md
printf '## How I verified it\n- Commands: x\n- iOS: <!-- pending --> iPhone 15, iOS 26.6: ok\n- Android: <!-- c --> Pixel 8\n\n## Risk\nLow. Not done: x.\n\nAI-assisted: no\n' > mob.md
expect "mobile lines keep text after a same-line comment" 0 bash "$C" --mobile mob.md
printf '## How I verified it\n- Commands: x\n- iOS: <!-- a -->iPhone 15 sim<!-- b -->\n- Android: Pixel 8\n\n## Risk\nLow. Not done: x.\n\nAI-assisted: no\n' > mobtwo.md
expect "mobile line between two comments is empty, as in CI" 1 bash "$C" --mobile mobtwo.md
says   "mobile line between two comments: names the iOS line" "'- iOS:' line is empty"
printf '## How I verified it\n- Commands: x\n- iOS: <!-- a -->\n- Android: Pixel\n\n## Risk\nLow. Not done: x.\n\nAI-assisted: no\n' > mobempty.md
expect "mobile line that is only a comment is empty" 1 bash "$C" --mobile mobempty.md

# (c) the AI-assisted line, read as CI reads it: it starts with yes or no and is not the 'yes / no' placeholder
for l in "AI-assisted: yes" "AI-assisted: no" "AI-assisted: yes (claude) — ran the suite" "AI-assisted:yes" "AI-assisted: no — hand-written" "AI-assisted: yesterday" "AI-assisted: no / yes"; do
  body ai.md "- Commands: x" "Low. Not done: x." "$l"
  expect "AI line accepted, as in CI: $l" 0 bash "$C" --no-mobile ai.md
done
for l in "AI-assisted: yes / no" "AI-assisted: yes/no <!-- if yes, which tool -->" "AI-assisted:" "AI-assisted: maybe"; do
  body ai.md "- Commands: x" "Low. Not done: x." "$l"
  expect "AI line rejected: $l" 1 bash "$C" --no-mobile ai.md
done
printf '## How I verified it\n- Commands: x\n\n## Risk\nLow. Not done: x.\n\n<!-- AI-assisted: yes -->\n' > aicomment.md
expect "AI line only inside a same-line comment is rejected" 1 bash "$C" --no-mobile aicomment.md
printf '## How I verified it\n- Commands: x\n\n## Risk\nLow. Not done: x.\n\n<!--\nAI-assisted: yes\n-->\n' > aiblock.md
expect "AI line inside a multi-line comment counts, as in CI" 0 bash "$C" --no-mobile aiblock.md

# (d) CRLF bodies
sed 's/$/\r/' ok.md > crlf.md
expect "CRLF body passes" 0 bash "$C" --no-mobile crlf.md
sed 's/$/\r/' blockios.md > crlf-blockios.md
expect "CRLF commented device line still fails" 1 bash "$C" --mobile crlf-blockios.md
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

# (f) ready means checked: a mobile line that opens with "pending" fails, as in CI (guide standard-checks.body.test.mjs)
shots() { # shots <file> <iOS value> <Android value> [screenshots value]
  printf '## How I verified it\n- Commands: pnpm test\n- iOS: %s\n- Android: %s\n- Screenshots: %s\n\n## Risk\nLow. Not done: x.\n\nAI-assisted: no\n' "$2" "$3" "${4:-}" > "$1"
}
DONE_IOS="iPhone 15, iOS 26.6: list loads"
for l in 'pending, physical iPhone dev build' 'pending — needs a run' '**pending, not yet verified**' 'Not yet verified' 'not tested' 'TBD'; do
  shots p.md "$DONE_IOS" "$l"
  expect "pending: '$l' fails" 1 bash "$C" --mobile p.md
  says   "pending: '$l' names the Android line" "^NOT DONE: '- Android:' says the check is not done"
done
for l in 'todo' '`not run` yet' '_not done_' 'not checked'; do
  shots p.md "$l" "Pixel 8 emulator, API 36: list loads"
  expect "pending: '$l' on iOS fails" 1 bash "$C" --mobile p.md
done
shots p.md "pending" "Pixel 8"
sed 's/$/\r/' p.md > crlf-p.md
expect "pending: CRLF body still fails" 1 bash "$C" --mobile crlf-p.md
for l in 'iPhone 15, iOS 26.6: pending badge now clears' 'iPhone 15, iOS 26.6; dark mode not tested' 'not a mobile change' 'pendingfix build on iPhone 15' 'Notes: not tested on iPad'; do
  shots p.md "$l" "not a mobile change" "![ios](https://github.com/user-attachments/assets/x)"
  expect "pending: '$l' passes" 0 bash "$C" --mobile p.md
done
shots p.md "pending" "not verified"
expect "pending: non-mobile run ignores pending" 0 bash "$C" --no-mobile p.md

# (g) screenshot signal: a device claim with nothing attached warns, exit unchanged
noshotwarn() { # noshotwarn <name>: the last expect printed no screenshot warning
  if grep -q 'no screenshot' "$out"; then fail=$((fail+1)); echo "FAIL $1"; sed 's/^/     /' "$out"; else pass=$((pass+1)); echo "ok   $1"; fi
}
shots s.md "$DONE_IOS" "Pixel 8 emulator, API 36: list loads"
expect "screenshot: device check with no attachment still passes" 0 bash "$C" --mobile s.md
says   "screenshot: warns when nothing is attached" "^WARNING: a mobile change with no screenshot"
for a in '![ios](x.png)' '<img src="x.png">' '<VIDEO src="x.mp4">' 'https://github.com/user-attachments/assets/abc'; do
  shots s.md "$DONE_IOS" "not a mobile change" "$a"
  expect "screenshot: '$a' attached passes" 0 bash "$C" --mobile s.md
  noshotwarn "screenshot: '$a' does not warn"
done
shots s.md "not a mobile change" "Not a mobile change"
expect "screenshot: 'not a mobile change' on both passes" 0 bash "$C" --mobile s.md
noshotwarn "screenshot: no warning on 'not a mobile change'"
shots s.md "$DONE_IOS" "Pixel 8"
expect "screenshot: non-mobile run passes" 0 bash "$C" --no-mobile s.md
noshotwarn "screenshot: non-mobile run does not warn"
printf '## How I verified it\n- Commands:\n- iOS:\n- Android:\n- Screenshots:\n\n## Risk\nLow. Not done: x.\n\nAI-assisted: no\n' > emptyshots.md
expect "an empty Screenshots line is not content" 1 bash "$C" --no-mobile emptyshots.md

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
