#!/usr/bin/env bash
# Offline lint of .github/workflows/*.yml: pinned actions, timeouts, no persisted credentials,
# no secrets reachable from pull requests. awk and grep only. Run: bash tests/scripts/test-ci-pins.sh
set -u
here=$(cd "$(dirname "$0")/../.." && pwd)
cd "$here" || exit 1
pass=0; fail=0
check() { # check <name> <test-expression...>
  local name=$1; shift
  if "$@"; then pass=$((pass+1)); echo "ok   $name"
  else fail=$((fail+1)); echo "FAIL $name"; fi
}
bad() { echo "     $*"; }

workflows=$(ls .github/workflows/*.yml)
[ -n "$workflows" ] || { echo "no workflows found"; exit 1; }

# job_info <file>: one line per job, "job|has_timeout|runs_on_pr|has_secret", from the 2-space-indented
# keys under `jobs:`. runs_on_pr is 1 unless the job (or the whole workflow) cannot run on pull_request:
# the job `if:` mentions github.event_name != 'pull_request' or == 'schedule'.
trigger_pr() { awk '/^on:/{f=1;next} f&&/^[^ #]/{exit} f&&/^  pull_request/{print 1;exit}' "$1"; }

jobs_report() { # jobs_report <file>
  awk -v pr="$(trigger_pr "$1")" '
    function flush() {
      if (job != "") print job "|" timeout "|" (guarded ? 0 : (pr == 1 ? 1 : 0)) "|" secret
    }
    /^jobs:/ {injobs=1; next}
    injobs && /^[^ #]/ {flush(); job=""; injobs=0}
    injobs && /^  [A-Za-z0-9_-]+:[ ]*$/ {flush(); job=$1; sub(/:$/, "", job); timeout=0; guarded=0; secret=0; next}
    job != "" && /^    timeout-minutes:/ {timeout=1}
    job != "" && /^    if:/ && (/event_name != .pull_request./ || /event_name == .(schedule|workflow_dispatch)./) {guarded=1}
    job != "" && /secrets\.[A-Za-z_]/ && !/^[ ]*#/ {secret=1}
    END {flush()}' "$1"
}

pinned_actions() {
  local f rc=0 line
  for f in $workflows; do
    while IFS= read -r line; do
      case "$line" in *"uses: ./"*) continue ;; esac
      echo "$line" | grep -qE 'uses:[ ]+[A-Za-z0-9_.-]+/[A-Za-z0-9_./-]+@[0-9a-f]{40}([ ]|$)' || { bad "$f: not pinned to a 40-hex SHA: $line"; rc=1; }
    done <<EOF2
$(grep -E '^[ ]*(- )?uses:' "$f")
EOF2
  done
  return $rc
}
check "every workflow 'uses:' is a 40-hex SHA" pinned_actions

timeouts() {
  local f rc=0 job t
  for f in $workflows; do
    while IFS='|' read -r job t _ _; do
      [ -n "$job" ] || continue
      [ "$t" = 1 ] || { bad "$f: job '$job' has no timeout-minutes"; rc=1; }
    done <<EOF2
$(jobs_report "$f")
EOF2
  done
  return $rc
}
check "every job has timeout-minutes" timeouts

checkout_creds() { # each `uses: actions/checkout` must be followed by a with: block holding persist-credentials: false
  local f rc=0
  for f in $workflows; do
    awk -v f="$f" '
      function end_step() { if (open && !ok) { print "     " f ":" line ": checkout without persist-credentials: false"; bad=1 } open=0 }
      /^      - / || /^    [a-z-]+:/ { end_step() }
      /uses:[ ]+actions\/checkout@/ { open=1; ok=0; line=NR }
      open && /persist-credentials:[ ]+false/ { ok=1 }
      END { end_step(); exit bad }' "$f" || rc=1
  done
  return $rc
}
check "every actions/checkout sets persist-credentials: false" checkout_creds

no_pr_secrets() {
  local f rc=0 job t pr s
  for f in $workflows; do
    while IFS='|' read -r job t pr s; do
      [ -n "$job" ] || continue
      if [ "$pr" = 1 ] && [ "$s" = 1 ]; then bad "$f: job '$job' can run on pull_request and references secrets.*"; rc=1; fi
    done <<EOF2
$(jobs_report "$f")
EOF2
  done
  return $rc
}
check "no secret is referenced by a job that can run on pull_request" no_pr_secrets

no_pr_secrets_workflow_env() { # workflow-level env: must not hold secrets either
  local f rc=0
  for f in $workflows; do
    awk '/^jobs:/{exit} /secrets\./ && !/^[ ]*#/ {print; bad=1} END{exit bad}' "$f" >/dev/null || { bad "$f: secret referenced outside a job"; rc=1; }
  done
  return $rc
}
check "no secret is referenced at workflow level" no_pr_secrets_workflow_env

gitleaks_versions_agree() {
  local v
  v=$(grep -hE '^[ ]*GITLEAKS_VERSION:' .github/workflows/*.yml | awk '{print $2}' | sort -u)
  [ "$(echo "$v" | wc -l | tr -d ' ')" = 1 ] && [ -n "$v" ] || { bad "GITLEAKS_VERSION differs between workflows: $(echo $v)"; return 1; }
  grep -hoE 'GITLEAKS_SHA256_[A-Z0-9_]+: [0-9a-f]{64}$' .github/workflows/*.yml | grep -q . || { bad "no 64-hex gitleaks hash"; return 1; }
  ! grep -rn 'brew install' .github/workflows >/dev/null || { bad "unpinned brew install in a workflow"; return 1; }
}
check "gitleaks version is the same in every workflow, hashes pinned, no brew install" gitleaks_versions_agree

# The detector itself: a fixture that breaks every rule must be caught.
self_test() {
  local tmp rc=0
  tmp=$(mktemp -d)
  mkdir -p "$tmp/.github/workflows" "$tmp/tests/scripts"
  cat > "$tmp/.github/workflows/bad.yml" <<'EOF2'
name: bad
on:
  pull_request:
jobs:
  live:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: echo
        env:
          K: ${{ secrets.KEY }}
EOF2
  cp "$0" "$tmp/tests/scripts/test-ci-pins.sh"
  if (cd "$tmp" && CI_PINS_NO_SELF_TEST=1 bash tests/scripts/test-ci-pins.sh >/dev/null 2>&1); then rc=1; fi
  rm -rf "$tmp"
  return $rc
}
[ "${CI_PINS_NO_SELF_TEST:-}" = 1 ] || check "the checks reject a workflow that breaks every rule" self_test

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
