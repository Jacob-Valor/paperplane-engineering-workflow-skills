#!/usr/bin/env bash
# Compares the skills in this repo with the live engineering guide
# (paperplanehq/paperplane-engineering, branch develop) through `gh api`.
# Usage: bash tests/drift/check.sh [-h|--help]
# Env:   SKILLS_DIR        skills directory (default: skills)
#        DOCS_DIR          docs directory holding open-questions-for-cto.md (default: docs next to SKILLS_DIR)
#        GH_TOKEN          token with read-only Contents on the guide repo (or a `gh auth login`)
#        DRIFT_ALLOW_SKIP  1 = exit 0 when the guide repo cannot be read, except that a GH_TOKEN
#                          which is set but refused (HTTP 401/403) is a FAIL: fix or rotate the secret
# Output: one line per check: `OK|DRIFT|SKIP|FAIL  <check>  <detail>`
# Exit codes: 0 no drift · 1 drift found: update the skills (and their guide-version) ·
#             2 guide repo unreadable (without DRIFT_ALLOW_SKIP=1) or usage error
set -uo pipefail

usage() { sed -n '2,13s/^# \{0,1\}//p' "$0"; }
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
if ! err=$(gh api "repos/$repo" --jq .full_name 2>&1 >/dev/null); then
  # "Secret not provided" (GH_TOKEN empty or unset) may skip; "provided but refused" must not.
  if [ -n "${GH_TOKEN:-}" ] && printf '%s' "$err" | grep -qE 'HTTP (401|403)|Bad credentials'; then
    say FAIL access "GH_TOKEN was provided but $repo refused it: $(printf '%s' "$err" | head -1); the token is expired, revoked or lacks read-only Contents. Rotate the secret"
    exit 2
  fi
  skip_access "cannot read $repo: $(printf '%s' "$err" | head -1)"
fi

raw() { gh api "repos/$repo/contents/$1?ref=${2:-$ref}" -H 'Accept: application/vnd.github.raw'; }

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
for p in README.md building.md reviewing.md CHANGELOG.md templates .github/workflows/standard-checks.yml \
  .github/workflows/unit-deploy.yml .github/actions/conformance/conformance.mjs; do
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

# 5. audit.sh accepts the standard-checks.yml ref the template pins (audit.sh's pin_re line).
audit="$skills/paperplane-repo-setup/scripts/audit.sh"
if [ -n "${std:-}" ]; then
  pin=$(printf '%s\n' "$std" | grep -oE 'standard-checks\.yml@[^"'\''[:space:]]+' | head -1); pin=${pin#*@}
  pin_re=$(sed -n "s/^pin_re='\(.*\)'.*/\1/p" "$audit" 2>/dev/null | head -1)
  if [ -z "$pin" ]; then bad "standard.yml pin" "templates/standard.yml does not call standard-checks.yml@<ref>"
  elif [ -z "$pin_re" ]; then bad "standard.yml pin" "no pin_re='...' line in $audit"
  elif [[ "$pin" =~ ^($pin_re)$ ]]; then ok "standard.yml pin" "template pins @$pin; audit.sh accepts it"
  else bad "standard.yml pin" "templates/standard.yml pins @$pin; $audit accepts only ^($pin_re)\$"; fi
fi

# 6. check-pr-body.sh rejects the same "pending" device lines as the CI step (literal regex compare).
body="$skills/paperplane-shipping-changes/scripts/check-pr-body.sh"
if [ -n "${checks:-}" ]; then
  ci_re=$(printf '%s\n' "$checks" | grep -F 'pending|' | sed -n "s/.*grep -Eqi '\([^']*\)'.*/\1/p" | head -1)
  local_re=$(sed -n "s/^pending_re='\(.*\)'.*/\1/p" "$body" 2>/dev/null | head -1)
  if [ -z "$ci_re" ]; then bad "pending regex" "no grep -Eqi '...pending|...' line in standard-checks.yml; the PR body step changed"
  elif [ -z "$local_re" ]; then bad "pending regex" "no pending_re='...' line in $body"
  elif [ "$ci_re" = "$local_re" ]; then ok "pending regex" "check-pr-body.sh matches standard-checks.yml"
  else bad "pending regex" "standard-checks.yml has '$ci_re'; $body has '$local_re'"; fi
fi

# 7. Repos run standard-checks.yml at the template's pin; the skills describe develop. A gap is logged for the CTO.
docs=${DOCS_DIR:-$(dirname "$skills")/docs}; docs=${docs#./}
gap_doc="$docs/open-questions-for-cto.md"
marker='pinned-ci-lags-develop'
if [ -n "${pin:-}" ] && [ -n "${checks:-}" ]; then
  if ! pinned=$(raw .github/workflows/standard-checks.yml "$pin"); then
    bad "pinned CI" "could not fetch .github/workflows/standard-checks.yml@$pin"
  else
    logged=false; grep -qF -- "$marker" "$gap_doc" 2>/dev/null && logged=true
    if [ "$pinned" = "$checks" ]; then
      if $logged; then bad "pinned CI" "@$pin runs the same checks as develop, but $gap_doc still has the $marker row; remove it"
      else ok "pinned CI" "@$pin runs the same checks as develop"; fi
    elif $logged; then ok "pinned CI" "repos run standard-checks.yml@$pin, older than develop; logged in $gap_doc ($marker)"
    else bad "pinned CI" "repos run standard-checks.yml@$pin, older than develop; log it in $gap_doc (a row with the marker $marker)"; fi
  fi
fi

# 8. check-pr-body.sh and develop's "PR body is complete" step pass and fail the same fixture bodies.
# The step is the org's own CI (it already runs in their Actions); it runs here with only BODY/MOBILE/DRAFT/PATH set.
fixtures="$(cd "$(dirname "$0")" && pwd)/bodies"
if [ -n "${checks:-}" ]; then
  step=$(printf '%s\n' "$checks" | awk '
    !s && /^[ ]*- name:[ ]*["'\'']?PR body is complete["'\'']?[ ]*$/ {s=1; match($0, /^ */); si=RLENGTH; next}
    s && !r { if ($0 !~ /^[ ]*$/) { match($0, /^ */); if (RLENGTH <= si) exit } }
    s && !r && /^[ ]*run:[ ]*\|[ ]*$/ {r=1; match($0, /^ */); ri=RLENGTH; next}
    r { if ($0 ~ /^[ ]*$/) { print ""; next }; match($0, /^ */); if (RLENGTH <= ri) exit; if (!bi) bi=RLENGTH; print substr($0, bi + 1) }')
  bodies=("$fixtures"/*.md)
  if [ -z "$step" ]; then bad "body step behaviour" "no 'PR body is complete' step with a 'run: |' block in standard-checks.yml"
  elif [ ! -f "$body" ]; then bad "body step behaviour" "$body not found"
  elif [ ! -e "${bodies[0]}" ]; then bad "body step behaviour" "no fixture bodies in $fixtures"
  else
    tmp=$(mktemp -d) || exit 2
    trap 'rm -rf "$tmp"' EXIT
    printf '%s\n' "$step" > "$tmp/ci-step.sh"
    differ=0
    for f in "${bodies[@]}"; do
      text=$(cat "$f")
      for m in true false; do
        (cd "$tmp" && env -i BODY="$text" MOBILE="$m" DRAFT=false PATH="$PATH" bash --noprofile --norc ci-step.sh) >/dev/null 2>&1; ci=$?
        if [ "$m" = true ]; then flag=--mobile; else flag=--no-mobile; fi
        bash "$body" "$flag" "$f" >/dev/null 2>&1; lc=$?
        if { [ "$ci" -eq 0 ] && [ "$lc" -eq 0 ]; } || { [ "$ci" -ne 0 ] && [ "$lc" -ne 0 ]; }; then continue; fi
        differ=1
        v_ci=passes; [ "$ci" -eq 0 ] || v_ci="fails (exit $ci)"
        v_lc=passes; [ "$lc" -eq 0 ] || v_lc="fails (exit $lc)"
        bad "body step behaviour" "$(basename "$f") $flag: develop's 'PR body is complete' step $v_ci; check-pr-body.sh $v_lc"
      done
    done
    [ "$differ" = 1 ] || ok "body step behaviour" "${#bodies[@]} bodies x 2 modes agree"
  fi
fi

exit "$drift"
