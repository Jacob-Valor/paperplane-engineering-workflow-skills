#!/usr/bin/env bash
# Behaviour tests for tests/drift/check.sh against a fake `gh`. Run: bash tests/scripts/run.sh
set -u
here=$(cd "$(dirname "$0")/../.." && pwd)
C="$here/tests/drift/check.sh"
pass=0; fail=0
expect() { # expect <name> <wanted-exit> <cmd...>
  local name=$1 want=$2; shift 2
  "$@" >/tmp/pp-test-out.$$ 2>&1; local got=$?
  if [ "$got" -eq "$want" ]; then pass=$((pass+1)); echo "ok   $name"
  else fail=$((fail+1)); echo "FAIL $name: exit $got, wanted $want"; sed 's/^/     /' /tmp/pp-test-out.$$; fi
}
says() { # says <name> <regex>: the last expect's output matches
  if grep -qE -- "$2" /tmp/pp-test-out.$$; then pass=$((pass+1)); echo "ok   $1"
  else fail=$((fail+1)); echo "FAIL $1: output lacks /$2/"; sed 's/^/     /' /tmp/pp-test-out.$$; fi
}

if ! command -v jq >/dev/null 2>&1; then echo "jq not installed; the fake gh needs it to apply --jq"; echo "0 passed, 1 failed"; exit 1; fi

work=$(mktemp -d); trap 'rm -rf "$work" /tmp/pp-test-out.$$' EXIT
cd "$work" || exit 1
mkdir bin
# Fake gh: serves files from $FAKE_GH/files, or $FAKE_GH/refs/<ref>/ when that holds the file at the ref asked for;
# `noaccess` there makes every call fail with HTTP 404.
cat > bin/gh <<'EOF'
#!/usr/bin/env bash
[ "$1" = api ] || exit 1
ep=$2; shift 2; jqf=""
while [ $# -gt 0 ]; do case $1 in --jq) jqf=$2; shift 2 ;; *) shift ;; esac; done
[ -e "$FAKE_GH/noaccess" ] && { if [ -s "$FAKE_GH/noaccess" ]; then cat "$FAKE_GH/noaccess"; else echo "gh: Not Found (HTTP 404)"; fi >&2; exit 1; }
case $ep in
  repos/paperplanehq/paperplane-engineering) out='{"full_name":"paperplanehq/paperplane-engineering"}' ;;
  */contents/*) p=${ep#*/contents/}; r=${p#*\?ref=}; p=${p%%\?*}; f="$FAKE_GH/files/$p"; [ -f "$FAKE_GH/refs/$r/$p" ] && f="$FAKE_GH/refs/$r/$p"
    out=$(cat "$f" 2>/dev/null) || { echo "gh: Not Found (HTTP 404)" >&2; exit 1; } ;;
  */commits\?*) p=${ep#*path=}; p=${p%%&*}; out=$(cat "$FAKE_GH/commits/${p//\//_}.json" 2>/dev/null || echo '[]') ;;
  *) echo "fake gh: unknown endpoint $ep" >&2; exit 1 ;;
esac
if [ -n "$jqf" ]; then printf '%s\n' "$out" | jq -r "$jqf"; else printf '%s\n' "$out"; fi
EOF
chmod +x bin/gh
export PATH="$work/bin:$PATH" FAKE_GH="$work/gh" SKILLS_DIR="$work/skills"
unset DRIFT_ALLOW_SKIP GH_TOKEN

setup() { # fresh skills copy and a guide that matches it
  rm -rf "$work/skills" "$work/docs" "$FAKE_GH"
  cp -R "$here/skills" "$work/skills"
  for f in "$work"/skills/*/SKILL.md; do
    awk '/^[ ]+guide-version:/{sub(/guide-version:.*/, "guide-version: \"2026-10-13\"")} {print}' "$f" > "$f.new" && mv "$f.new" "$f"
  done
  mkdir -p "$FAKE_GH/files/.github/workflows" "$FAKE_GH/files/templates" "$FAKE_GH/commits"
  cat > "$FAKE_GH/files/.github/workflows/standard-checks.yml" <<'EOF'
name: standard-checks
on:
  workflow_call:
jobs:
  checks:
    name: checks
    runs-on: ubuntu-latest
    steps:
      - name: Not a job name
      - name: PR body is complete
        if: ${{ !cancelled() && github.event_name == 'pull_request' && github.event.pull_request.user.login != 'dependabot[bot]' }}
        env:
          BODY: ${{ github.event.pull_request.body }}
          MOBILE: ${{ inputs.mobile }}
          DRAFT: ${{ github.event.pull_request.draft }}
        run: |
          if [ "$DRAFT" = "true" ]; then echo "draft: not checked yet"; exit 0; fi
          fail=0
          section() { printf '%s' "$BODY" | awk -v h="## $1" 'index($0,h)==1{f=1;next} /^## /{f=0} f' | sed -e 's/<!--.*-->//g' -e '/^[[:space:]]*$/d'; }
          [ -n "$(section 'How I verified it' | grep -vE '^- (Commands|iOS|Android|Screenshots):[[:space:]]*$')" ] || { echo "::error::'How I verified it' is empty"; fail=1; }
          [ -n "$(section 'Risk')" ] || { echo "::error::'Risk' is empty"; fail=1; }
          printf '%s' "$BODY" | grep -Eq '^AI-assisted: *(yes|no)' && ! printf '%s' "$BODY" | grep -Eq '^AI-assisted: *yes */ *no' || { echo "::error::'AI-assisted: yes' or 'AI-assisted: no' line missing (the template placeholder does not count)"; fail=1; }
          if [ "$MOBILE" = "true" ]; then
            for p in iOS Android; do
              line=$(printf '%s' "$BODY" | grep -E "^- $p:" | head -1 | sed -e 's/<!--.*-->//' -e "s/^- $p:[[:space:]]*//")
              [ -n "$line" ] || { echo "::error::'- $p:' line is empty; name the device/simulator or write 'not a mobile change'"; fail=1; }
              # Ready means checked: a line that opens with "pending" is a draft (2026-11-13: 9 of 17 ready PRs said so).
              if printf '%s' "$line" | sed -e 's/^[*_`[:space:]]*//' | grep -Eqi '^(pending|todo|tbd|not (yet )?(verified|tested|checked|run|done))([^a-z]|$)'; then
                echo "::error::'- $p:' says the check is not done. Run it, or convert the PR back to draft until it is."; fail=1
              fi
              printf '%s' "$line" | grep -qi 'not a mobile change' || device=1
            done
            # Signal, not a gate yet: a device claim with nothing to look at cannot be reviewed.
            if [ "${device:-0}" = "1" ] && ! printf '%s' "$BODY" | grep -Eqi '!\[|<img |<video |user-attachments/'; then
              echo "::warning::A mobile change with no screenshot or recording in the body; attach one per platform under 'Screenshots'."
            fi
          fi
          exit $fail
  conformance:
    name: conformance
    runs-on: ubuntu-latest
  ai-review:
    name: AI review (advisory)
    runs-on: ubuntu-latest
EOF
  {
    printf '## How I verified it\n- Commands:\n- iOS:\n- Android:\n\n## Checklist\n'
    for _ in 1 2 3 4 5 6 7; do echo '- [ ] item'; done
    printf '\nAI-assisted: yes / no\n'
  } > "$FAKE_GH/files/templates/pull_request_template.md"
  printf 'on:\n  pull_request:\n    types: [opened, edited, synchronize, reopened]\njobs:\n  standard:\n    uses: paperplanehq/paperplane-engineering/.github/workflows/standard-checks.yml@v1\n' > "$FAKE_GH/files/templates/standard.yml"
  sed -i.bak 's/all [0-9]* boxes/all 7 boxes/' "$work/skills/paperplane-shipping-changes/SKILL.md"
  commit README.md 2026-10-12T09:00:00Z "docs: older change"
  commit templates 2026-10-13T05:39:07Z "docs(workflow): newest change"
}
commit() { # commit <path> <date> <message>
  jq -n --arg d "$2" --arg m "$3" '[{commit:{committer:{date:$d},message:$m}}]' > "$FAKE_GH/commits/${1//\//_}.json"
}

setup
expect "matching guide passes" 0 bash "$C"
says "matching guide reports OK lines" '^OK +checklist boxes +7 boxes'
says "matching guide: pinned CI same as develop" '^OK +pinned CI +@v1 runs the same checks as develop$'
says "matching guide: body step behaviour agrees" '^OK +body step behaviour +[0-9]+ bodies x 2 modes agree$'
if grep -q 'Not a job name' /tmp/pp-test-out.$$; then fail=$((fail+1)); echo "FAIL step names are not job names"
else pass=$((pass+1)); echo "ok   step names are not job names"; fi

setup
printf '  deploy:\n    name: deploy preview\n' >> "$FAKE_GH/files/.github/workflows/standard-checks.yml"
expect "new CI job not in skills is drift" 1 bash "$C"
says "drift names the job" "^DRIFT +job name +'standard / deploy preview'"

setup
printf '  deploy:\n    name: deploy preview\n' >> "$FAKE_GH/files/.github/workflows/standard-checks.yml"
echo 'Wait for the deploy preview.' >> "$SKILLS_DIR/paperplane-reviewing-prs/SKILL.md"
expect "job named without 'standard / ' is drift" 1 bash "$C"

setup
echo 'A red `standard / PR size` blocks.' >> "$SKILLS_DIR/paperplane-reviewing-prs/SKILL.md"
expect "skill naming a removed job is drift" 1 bash "$C"
says "drift names the removed job" "^DRIFT +job name +.*'standard / PR size'.*not a job"

setup
echo '- [ ] new item' >> "$FAKE_GH/files/templates/pull_request_template.md"
expect "changed checklist box count is drift" 1 bash "$C"
says "drift gives both counts" "template has 8 boxes; .*'all 7 boxes'"

setup
grep -v '^- Android:' "$FAKE_GH/files/templates/pull_request_template.md" > t && mv t "$FAKE_GH/files/templates/pull_request_template.md"
expect "missing Android line is drift" 1 bash "$C"

setup
commit .github/workflows/standard-checks.yml 2026-10-20T10:00:00Z $'ci: add deploy check\n\nlong body'
expect "guide commit newer than guide-version is drift" 1 bash "$C"
says "drift names the newer commit" '^DRIFT +guide-version +.*2026-10-20: ci: add deploy check'

setup
commit README.md 2026-10-13T23:00:00Z "docs: same day"
expect "same-day guide commit is not drift" 0 bash "$C"

setup
commit reviewing.md 2026-10-20T10:00:00Z "docs(reviewing): new rule"
expect "newer reviewing.md commit is drift" 1 bash "$C"
says "drift names reviewing.md" '^DRIFT +guide-version +.*2026-10-20: docs\(reviewing\): new rule \(reviewing\.md\)'

setup
commit reviewing.md 2026-10-01T10:00:00Z "docs(reviewing): old rule"
commit .github/actions/conformance/conformance.mjs 2026-10-02T10:00:00Z "feat(conformance): old check"
expect "older reviewing.md and conformance.mjs commits are not drift" 0 bash "$C"
says "guide-version OK against the newest watched commit" '^OK +guide-version +.* 2026-10-13 >= newest guide commit 2026-10-13'

setup
printf 'on:\n  pull_request:\n    types: [opened, ready_for_review]\njobs:\n  standard:\n    uses: paperplanehq/paperplane-engineering/.github/workflows/standard-checks.yml@v1\n' > "$FAKE_GH/files/templates/standard.yml"
grep -v ready_for_review "$SKILLS_DIR/paperplane-repo-setup/SKILL.md" > t && mv t "$SKILLS_DIR/paperplane-repo-setup/SKILL.md"
expect "ready_for_review unexplained by repo-setup is drift" 1 bash "$C"
echo 'Trigger on ready_for_review too.' >> "$SKILLS_DIR/paperplane-repo-setup/SKILL.md"
expect "ready_for_review explained by repo-setup passes" 0 bash "$C"

setup
expect "template pin accepted by audit.sh passes" 0 bash "$C"
says "pin OK line" '^OK +standard\.yml pin +template pins @v1; audit.sh accepts it'
says "pending regex OK line" '^OK +pending regex +check-pr-body\.sh matches standard-checks\.yml'
sed -i.bak 's/@v1$/@develop/' "$FAKE_GH/files/templates/standard.yml"
expect "template pin audit.sh rejects is drift" 1 bash "$C"
says "drift names the template pin" '^DRIFT +standard\.yml pin +templates/standard\.yml pins @develop; .*audit\.sh accepts only'
sed -i.bak 's/@develop$/@v3/' "$FAKE_GH/files/templates/standard.yml"
expect "a new major pin is still accepted" 0 bash "$C"

setup
sed -i.bak "s/^pin_re=.*/want_ref=develop/" "$SKILLS_DIR/paperplane-repo-setup/scripts/audit.sh"
expect "audit.sh without pin_re is drift" 1 bash "$C"
says "drift says pin_re is gone" "^DRIFT +standard\.yml pin +no pin_re="

setup
sed -i.bak 's/|tbd|/|tbd|wip|/' "$FAKE_GH/files/.github/workflows/standard-checks.yml"
expect "CI pending regex changed is drift" 1 bash "$C"
says "drift shows both regexes" "^DRIFT +pending regex +standard-checks\.yml has '.*\|wip\|.*'; .*check-pr-body\.sh has"

setup
grep -v 'grep -Eqi' "$FAKE_GH/files/.github/workflows/standard-checks.yml" > t && mv t "$FAKE_GH/files/.github/workflows/standard-checks.yml"
expect "CI pending check gone is drift" 1 bash "$C"
says "drift says the step changed" '^DRIFT +pending regex +no grep -Eqi'

# Behaviour: the real step text runs against tests/drift/bodies; a looser step is drift even when the regex matches.
setup
sed -i.bak 's/|Android|Screenshots)/|Android)/' "$FAKE_GH/files/.github/workflows/standard-checks.yml"
expect "CI step without the Screenshots exclusion is drift" 1 bash "$C"
says "Screenshots: the regex compare still agrees" '^OK +pending regex '
says "Screenshots: drift names the fixture and mode" "^DRIFT +body step behaviour +14-screenshots-only\.md --no-mobile: develop's 'PR body is complete' step passes; check-pr-body\.sh fails \(exit 1\)"
if grep -qE 'body step behaviour +14-screenshots-only\.md --mobile' /tmp/pp-test-out.$$; then fail=$((fail+1)); echo "FAIL Screenshots: --mobile still agrees (empty device lines fail both)"
else pass=$((pass+1)); echo "ok   Screenshots: --mobile still agrees (empty device lines fail both)"; fi

setup
sed -i.bak "s/grep -Eqi '^(pending[^']*'/false/" "$FAKE_GH/files/.github/workflows/standard-checks.yml"
expect "CI step without the pending check is drift" 1 bash "$C"
says "no pending check: drift names the pending fixture" "^DRIFT +body step behaviour +05-ios-pending\.md --mobile: develop's 'PR body is complete' step passes; check-pr-body\.sh fails"
if grep -q 'body step behaviour.*--no-mobile' /tmp/pp-test-out.$$; then fail=$((fail+1)); echo "FAIL no pending check: --no-mobile still agrees"
else pass=$((pass+1)); echo "ok   no pending check: --no-mobile still agrees"; fi

setup
sed -i.bak 's/name: PR body is complete/name: PR body present/' "$FAKE_GH/files/.github/workflows/standard-checks.yml"
expect "renamed CI step is drift" 1 bash "$C"
says "renamed step: drift says the step is gone" "^DRIFT +body step behaviour +no 'PR body is complete' step"

# Pinned CI: repos run standard-checks.yml at the template's pin; a gap with develop must be logged for the CTO.
setup
mkdir -p "$FAKE_GH/refs/v1/.github/workflows"
sed 's/|Android|Screenshots)/|Android)/' "$FAKE_GH/files/.github/workflows/standard-checks.yml" > "$FAKE_GH/refs/v1/.github/workflows/standard-checks.yml"
expect "pinned CI older than develop, not logged, is drift" 1 bash "$C"
says "undocumented gap: drift says log it" "^DRIFT +pinned CI +repos run standard-checks\.yml@v1, older than develop; log it in $work/docs/open-questions-for-cto\.md"
mkdir -p "$work/docs"
printf '| Pinned CI lags develop (pinned-ci-lags-develop) | ... |\n' > "$work/docs/open-questions-for-cto.md"
expect "pinned CI older than develop, logged, passes" 0 bash "$C"
says "documented gap: OK line" '^OK +pinned CI +repos run standard-checks\.yml@v1, older than develop; logged in .*open-questions-for-cto\.md \(pinned-ci-lags-develop\)'
mkdir -p elsewhere && mv "$work/docs/open-questions-for-cto.md" elsewhere/
expect "DOCS_DIR points at the log" 0 env DOCS_DIR=elsewhere bash "$C"
expect "log missing from the default docs dir is drift" 1 bash "$C"

setup
mkdir -p "$work/docs"
printf '| Pinned CI lags develop (pinned-ci-lags-develop) | ... |\n' > "$work/docs/open-questions-for-cto.md"
expect "pinned CI same as develop with a logged gap is drift" 1 bash "$C"
says "stale marker: drift says remove it" '^DRIFT +pinned CI +@v1 runs the same checks as develop, but .*open-questions-for-cto\.md still has the pinned-ci-lags-develop row; remove it'

setup
: > "$FAKE_GH/noaccess"
expect "no access fails without DRIFT_ALLOW_SKIP" 2 bash "$C"
says "no access prints SKIP" '^SKIP +access .*HTTP 404'
expect "no access passes with DRIFT_ALLOW_SKIP=1" 0 env DRIFT_ALLOW_SKIP=1 bash "$C"

# A token that was provided but is refused is a failure, never a skip: an expired secret must not turn the PR check green.
setup
printf 'gh: Bad credentials (HTTP 401)\n' > "$FAKE_GH/noaccess"
expect "provided token, 401: fails even with DRIFT_ALLOW_SKIP=1" 2 env GH_TOKEN=expired DRIFT_ALLOW_SKIP=1 bash "$C"
says "401 is reported as a rejected token" '^FAIL +access .*(401|rejected)'
expect "provided token, 401: fails without DRIFT_ALLOW_SKIP" 2 env GH_TOKEN=expired bash "$C"
printf 'gh: Resource not accessible by personal access token (HTTP 403)\n' > "$FAKE_GH/noaccess"
expect "provided token, 403: fails even with DRIFT_ALLOW_SKIP=1" 2 env GH_TOKEN=revoked DRIFT_ALLOW_SKIP=1 bash "$C"
expect "empty GH_TOKEN (secret not provided), 403: skip ok" 0 env DRIFT_ALLOW_SKIP=1 GH_TOKEN= bash "$C"
says "secret not provided prints SKIP" '^SKIP +access'
printf 'gh: Bad credentials (HTTP 401)\n' > "$FAKE_GH/noaccess"
expect "no token at all, 401 (stale gh login): skip ok" 0 env DRIFT_ALLOW_SKIP=1 bash "$C"
: > "$FAKE_GH/noaccess"
expect "provided token, 404 still follows DRIFT_ALLOW_SKIP" 0 env GH_TOKEN=x DRIFT_ALLOW_SKIP=1 bash "$C"

expect "usage error" 2 bash "$C" --bogus

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
