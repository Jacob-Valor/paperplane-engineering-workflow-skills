#!/usr/bin/env bash
# Runs the same rules as the "PR body is complete" step of the CI job `standard / checks`, before `gh pr ready`.
# Usage: bash scripts/check-pr-body.sh [--mobile|--no-mobile] <body-file | --pr N>
# Without a flag, the repo is treated as an app repo when .github/workflows/standard.yml sets `mobile: true`.
# Exit codes: 0 complete · 1 incomplete · 2 usage error
set -uo pipefail

mobile=""
src=""
pr=""
while [ $# -gt 0 ]; do
  case "$1" in
    --mobile) mobile=true ;;
    --no-mobile) mobile=false ;;
    --pr) pr="${2:-}"; shift ;;
    -h|--help) sed -n '2,5p' "$0"; exit 0 ;;
    *) src="$1" ;;
  esac
  shift
done

if [ -n "$pr" ]; then
  BODY=$(gh pr view "$pr" --json body --jq .body) || { echo "gh pr view $pr failed"; exit 2; }
elif [ -n "$src" ] && [ -f "$src" ]; then
  BODY=$(cat "$src")
else
  echo "usage: bash scripts/check-pr-body.sh [--mobile|--no-mobile] <body-file | --pr N>"; exit 2
fi

# Drop every <!-- ... --> comment, single- or multi-line, each one up to its own first -->.
# No CR stripping: every later check treats a trailing CR as [[:space:]], so CRLF bodies behave the same.
BODY=$(printf '%s\n' "$BODY" | awk '{
  line = $0; out = ""
  while (1) {
    if (inc) { i = index(line, "-->"); if (!i) { line = ""; break }; line = substr(line, i + 3); inc = 0 }
    i = index(line, "<!--"); if (!i) { out = out line; break }
    out = out substr(line, 1, i - 1); line = substr(line, i + 4); inc = 1
  }
  print out }')

if [ -z "$mobile" ]; then
  mobile=false
  grep -Eq '^[[:space:]]*mobile:[[:space:]]*true' .github/workflows/standard.yml 2>/dev/null && mobile=true
fi

fail=0
section() { printf '%s' "$BODY" | awk -v h="## $1" 'index($0,h)==1{f=1;next} /^## /{f=0} f' | sed -e '/^[[:space:]]*$/d'; }

[ -n "$(section 'How I verified it' | grep -vE '^- (Commands|iOS|Android):[[:space:]]*$')" ] \
  || { echo "MISSING: 'How I verified it' is empty"; fail=1; }
[ -n "$(section 'Risk')" ] || { echo "MISSING: 'Risk' is empty"; fail=1; }
printf '%s' "$BODY" | grep -Eq '^AI-assisted: *(yes|no)([[:space:]]|$)' && ! printf '%s' "$BODY" | grep -Eq '^AI-assisted: *(yes */ *no|no */ *yes)' \
  || { echo "MISSING: 'AI-assisted: yes' or 'AI-assisted: no' line (the template placeholder does not count)"; fail=1; }

if [ "$mobile" = "true" ]; then
  for p in iOS Android; do
    line=$(printf '%s' "$BODY" | grep -E "^- $p:" | head -1 | sed -e "s/^- $p:[[:space:]]*//" -e 's/[[:space:]]*$//')
    [ -n "$line" ] || { echo "MISSING: '- $p:' line is empty; name the device/simulator or write 'not a mobile change'"; fail=1; }
  done
fi

# Not checked by CI, but part of "ready" in the guide:
section 'Risk' | grep -qiE 'not done|not yet|no .* (yet|done)|n/a' \
  || echo "WARNING: Risk does not say what is not done"

[ "$fail" -eq 0 ] && echo "OK: body passes 'PR body is complete' (mobile=$mobile)"
exit "$fail"
