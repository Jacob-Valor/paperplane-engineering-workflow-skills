#!/usr/bin/env bash
# Compares the skills in this repo with the live engineering guide
# (paperplanehq/paperplane-engineering, branch develop) through `gh api`.
# Usage: bash tests/drift/check.sh [-h|--help]
# Env:   SKILLS_DIR        skills directory (default: skills)
#        GH_TOKEN          token with read-only Contents on the guide repo (or a `gh auth login`)
#        DRIFT_ALLOW_SKIP  1 = exit 0 when the guide repo cannot be read
# Output: one line per check: `OK|DRIFT|SKIP  <check>  <detail>`
# Exit codes: 0 no drift · 1 drift found: update the skills (and their guide-version) ·
#             2 guide repo unreadable (without DRIFT_ALLOW_SKIP=1) or usage error
set -uo pipefail

usage() { sed -n '2,10s/^# \{0,1\}//p' "$0"; }
case "${1:-}" in
  -h|--help) usage; exit 0 ;;
  "") ;;
  *) usage; exit 2 ;;
esac

repo="paperplanehq/paperplane-engineering"
ref="develop"
skills="${SKILLS_DIR:-skills}"
drift=0
say() { printf '%-6s %-24s %s\n' "$1" "$2" "$3"; }
ok() { say OK "$1" "$2"; }
bad() { say DRIFT "$1" "$2"; drift=1; }

[ -d "$skills" ] || { echo "skills directory '$skills' not found; run from the repo root or set SKILLS_DIR"; exit 2; }

skip_access() {
  say SKIP access "$1"
  if [ "${DRIFT_ALLOW_SKIP:-}" = 1 ]; then exit 0; fi
  echo "set GH_TOKEN to a token with read-only Contents on $repo, or DRIFT_ALLOW_SKIP=1 to allow this"
  exit 2
}
command -v gh >/dev/null 2>&1 || skip_access "gh is not installed"
err=$(gh api "repos/$repo" --jq .full_name 2>&1 >/dev/null) ||
  skip_access "cannot read $repo: $(printf '%s' "$err" | head -1)"

raw() { gh api "repos/$repo/contents/$1?ref=$ref" -H 'Accept: application/vnd.github.raw'; }

# 1. Skills name every CI job exactly as GitHub shows it (`standard / <job>`), and no job that is gone.
if checks=$(raw .github/workflows/standard-checks.yml); then
  names=$(printf '%s\n' "$checks" | awk '/^jobs:/{j=1; next} j && /^    name:/{sub(/^    name:[ ]*/, ""); gsub(/^["'\'']|["'\'']$/, ""); print}')
  if [ -z "$names" ]; then
    bad "job names" "no job names found in standard-checks.yml; the file layout changed"
  else
    while IFS= read -r n; do
      if grep -qF -- "\`standard / $n\`" "$skills"/*/SKILL.md; then ok "job name" "$n"
      else bad "job name" "'standard / $n' is a CI job in standard-checks.yml but no SKILL.md names it as \`standard / $n\`"; fi
    done <<<"$names"
    while IFS= read -r n; do
      grep -qxF -- "$n" <<<"$names" || bad "job name" "a SKILL.md names 'standard / $n', which is not a job in standard-checks.yml"
    done < <(grep -ohE '`standard / [^`]+`' "$skills"/*/SKILL.md | sed -e 's/^`standard \/ //' -e 's/`$//' | sort -u)
  fi
else
  bad "job names" "could not fetch .github/workflows/standard-checks.yml"
fi

# 2. The PR template lines CI reads, and the checklist size the shipping skill quotes.
if tpl=$(raw templates/pull_request_template.md); then
  for line in '- Commands:' '- iOS:' '- Android:'; do
    if printf '%s\n' "$tpl" | grep -q "^$line"; then ok "PR template" "has '$line'"
    else bad "PR template" "line '$line' is gone from templates/pull_request_template.md"; fi
  done
  if printf '%s\n' "$tpl" | grep -q '^AI-assisted:'; then ok "PR template" "has 'AI-assisted:'"
  else bad "PR template" "line 'AI-assisted:' is gone from templates/pull_request_template.md"; fi
  boxes=$(printf '%s\n' "$tpl" | grep -c '^- \[ \]')
  ship="$skills/paperplane-shipping-changes/SKILL.md"
  want=$(grep -oE 'all [0-9]+ boxes' "$ship" 2>/dev/null | head -1 | grep -oE '[0-9]+')
  if [ -z "$want" ]; then bad "checklist boxes" "no 'all N boxes' phrase in $ship"
  elif [ "$boxes" -eq "$want" ]; then ok "checklist boxes" "$boxes boxes, skill says all $want"
  else bad "checklist boxes" "template has $boxes boxes; $ship says 'all $want boxes'"; fi
else
  bad "PR template" "could not fetch templates/pull_request_template.md"
fi

# 3. No guide change is newer than any skill's guide-version.
newest=""; newest_msg=""
for p in README.md templates .github/workflows/standard-checks.yml; do
  line=$(gh api "repos/$repo/commits?sha=$ref&path=$p&per_page=1" \
    --jq '.[0] | select(. != null) | .commit.committer.date + " " + (.commit.message | split("\n")[0])') ||
    { bad "guide commits" "could not list commits for $p"; continue; }
  [ -n "$line" ] || continue
  d=${line%% *}; d=${d%%T*}
  if [[ "$d" > "$newest" ]]; then newest=$d; newest_msg="${line#* } ($p)"; fi
done
if [ -n "$newest" ]; then
  for f in "$skills"/*/SKILL.md; do
    name=$(basename "$(dirname "$f")")
    gv=$(awk '/^---$/{n++; next} n==1 && /^[ ]+guide-version:/{sub(/^[ ]+guide-version:[ ]*/, ""); gsub(/"/, ""); print; exit}' "$f")
    if [ -z "$gv" ]; then bad "guide-version" "$name has no metadata.guide-version"
    elif [[ "$newest" > "$gv" ]]; then bad "guide-version" "$name is at $gv; guide changed $newest: $newest_msg"
    else ok "guide-version" "$name $gv >= newest guide commit $newest"; fi
  done
fi

# 4. A ready_for_review trigger in the template must be explained by the repo-setup skill.
if std=$(raw templates/standard.yml); then
  if printf '%s\n' "$std" | grep -q ready_for_review; then
    if grep -q ready_for_review "$skills/paperplane-repo-setup/SKILL.md" 2>/dev/null; then ok "ready_for_review" "template and repo-setup skill both have it"
    else bad "ready_for_review" "templates/standard.yml triggers on ready_for_review; paperplane-repo-setup does not mention it"; fi
  else
    ok "ready_for_review" "not in templates/standard.yml"
  fi
else
  bad "standard.yml" "could not fetch templates/standard.yml"
fi

exit "$drift"
