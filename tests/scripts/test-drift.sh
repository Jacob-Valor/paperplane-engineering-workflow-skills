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
# Fake gh: serves files from $FAKE_GH; `noaccess` there makes every call fail with HTTP 404.
cat > bin/gh <<'EOF'
#!/usr/bin/env bash
[ "$1" = api ] || exit 1
ep=$2; shift 2; jqf=""
while [ $# -gt 0 ]; do case $1 in --jq) jqf=$2; shift 2 ;; *) shift ;; esac; done
[ -e "$FAKE_GH/noaccess" ] && { echo "gh: Not Found (HTTP 404)" >&2; exit 1; }
case $ep in
  repos/paperplanehq/paperplane-engineering) out='{"full_name":"paperplanehq/paperplane-engineering"}' ;;
  */contents/*) p=${ep#*/contents/}; p=${p%%\?*}; out=$(cat "$FAKE_GH/files/$p" 2>/dev/null) || { echo "gh: Not Found (HTTP 404)" >&2; exit 1; } ;;
  */commits\?*) p=${ep#*path=}; p=${p%%&*}; out=$(cat "$FAKE_GH/commits/${p//\//_}.json" 2>/dev/null || echo '[]') ;;
  *) echo "fake gh: unknown endpoint $ep" >&2; exit 1 ;;
esac
if [ -n "$jqf" ]; then printf '%s\n' "$out" | jq -r "$jqf"; else printf '%s\n' "$out"; fi
EOF
chmod +x bin/gh
export PATH="$work/bin:$PATH" FAKE_GH="$work/gh" SKILLS_DIR="$work/skills"
unset DRIFT_ALLOW_SKIP

setup() { # fresh skills copy and a guide that matches it
  rm -rf "$work/skills" "$FAKE_GH"
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
  pnpm-only:
    name: pnpm only
    runs-on: ubuntu-latest
    steps:
      - name: Not a job name
  pr-size:
    name: PR size
    runs-on: ubuntu-latest
EOF
  {
    printf '## How I verified it\n- Commands:\n- iOS:\n- Android:\n\n## Checklist\n'
    for _ in 1 2 3 4 5 6 7; do echo '- [ ] item'; done
    printf '\nAI-assisted: yes / no\n'
  } > "$FAKE_GH/files/templates/pull_request_template.md"
  printf 'on:\n  pull_request:\n    types: [opened, edited, synchronize, reopened]\n' > "$FAKE_GH/files/templates/standard.yml"
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
if grep -q 'Not a job name' /tmp/pp-test-out.$$; then fail=$((fail+1)); echo "FAIL step names are not job names"
else pass=$((pass+1)); echo "ok   step names are not job names"; fi

setup
printf '  deploy:\n    name: deploy preview\n' >> "$FAKE_GH/files/.github/workflows/standard-checks.yml"
expect "new CI job not in skills is drift" 1 bash "$C"
says "drift names the job" "^DRIFT +job name +'deploy preview'"

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
printf 'on:\n  pull_request:\n    types: [opened, ready_for_review]\n' > "$FAKE_GH/files/templates/standard.yml"
grep -v ready_for_review "$SKILLS_DIR/paperplane-repo-setup/SKILL.md" > t && mv t "$SKILLS_DIR/paperplane-repo-setup/SKILL.md"
expect "ready_for_review unexplained by repo-setup is drift" 1 bash "$C"
echo 'Trigger on ready_for_review too.' >> "$SKILLS_DIR/paperplane-repo-setup/SKILL.md"
expect "ready_for_review explained by repo-setup passes" 0 bash "$C"

setup
touch "$FAKE_GH/noaccess"
expect "no access fails without DRIFT_ALLOW_SKIP" 2 bash "$C"
says "no access prints SKIP" '^SKIP +access .*HTTP 404'
expect "no access passes with DRIFT_ALLOW_SKIP=1" 0 env DRIFT_ALLOW_SKIP=1 bash "$C"

expect "usage error" 2 bash "$C" --bogus

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
