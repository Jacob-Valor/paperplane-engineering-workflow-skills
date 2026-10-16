#!/usr/bin/env bash
# Read-only audit of one paperplanehq repo against the Paper Plane standard.
# Usage: bash scripts/audit.sh <owner/repo> [--app|--not-app]
#   --app       treat as an app repo (standard.yml must pass `mobile: true`)
#   --not-app   treat as a non-app repo, even if app.json or eas.json exists
#   default     app repo when app.json or eas.json is at the root of develop
# Prints one line per check: PASS|FAIL|WARN  <check>  <detail>, then a summary.
# Uses `gh api` GET requests only; it never changes anything on GitHub.
# Exit codes: 0 no FAIL (WARN lines may need a look) · 1 at least one FAIL ·
#             2 usage error, gh missing, or the repo cannot be read
set -uo pipefail

usage() { sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; }

repo="" app=auto
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --app) app=yes ;;
    --not-app) app=no ;;
    -*) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
    *) [ -z "$repo" ] || { echo "only one repo, got '$repo' and '$1'" >&2; exit 2; }; repo=$1 ;;
  esac
  shift
done
[[ "$repo" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || { echo "need <owner/repo>, e.g. paperplanehq/tripbuddy-app" >&2; usage >&2; exit 2; }
command -v gh >/dev/null 2>&1 || { echo "gh is not installed; install it and run 'gh auth login'" >&2; exit 2; }

npass=0 nfail=0 nwarn=0
report() { # report PASS|FAIL|WARN <check> <detail>
  printf '%s  %-36s  %s\n' "$1" "$2" "$3"
  case "$1" in PASS) npass=$((npass+1)) ;; FAIL) nfail=$((nfail+1)) ;; WARN) nwarn=$((nwarn+1)) ;; esac
}
err=$(mktemp); trap 'rm -f "$err"' EXIT
api() { gh api "$@" 2>"$err"; }
lasterr() { grep -m1 . "$err" | cut -c1-160; }
raw() { api -H 'Accept: application/vnd.github.raw' "repos/$repo/contents/$1?ref=$ref"; }
has() { printf '%s\n' "$1" | grep -qxF -- "$2"; }
nocomments() { sed -e 's/^[[:space:]]*#.*//' -e 's/[[:space:]]#.*//'; }

# Repo settings and default branch. An unreadable repo stops the audit.
settings=$(api "repos/$repo" --jq '[.default_branch, .allow_squash_merge, .allow_merge_commit, .allow_rebase_merge, .delete_branch_on_merge, .allow_auto_merge] | map(tostring) | join(" ")') \
  || { echo "cannot read $repo: $(lasterr)" >&2; echo "check the name and that 'gh auth status' has read access to it" >&2; exit 2; }
read -r default squash merge rebase delete_on_merge auto_merge <<<"$settings"

echo "audit: $repo"
if [ "$default" = develop ]; then report PASS default-branch "develop"
else report FAIL default-branch "is '$default', want develop"; fi

if branches=$(api --paginate "repos/$repo/branches?per_page=100" --jq '.[].name'); then
  for b in develop uat main; do
    if has "$branches" "$b"; then report PASS "branch-$b" "exists"
    else report FAIL "branch-$b" "missing"; fi
  done
else
  report FAIL branches "cannot list branches: $(lasterr)"
fi

setting() { # setting <name> <value> <want>
  if [ "$2" = "$3" ]; then report PASS "$1" "$2"
  elif [ "$2" = null ]; then report WARN "$1" "hidden from this token (needs push access); want $3"
  else report FAIL "$1" "is $2, want $3"; fi
}
setting allow_squash_merge "$squash" true
setting allow_merge_commit "$merge" true
setting allow_rebase_merge "$rebase" false
setting delete_branch_on_merge "$delete_on_merge" true
setting allow_auto_merge "$auto_merge" true

if rulesets=$(api "repos/$repo/rulesets" --jq '.[].name'); then
  if has "$rulesets" protect-develop-uat-main; then report PASS ruleset "protect-develop-uat-main"
  else report FAIL ruleset "protect-develop-uat-main not found (have: $(echo "${rulesets:-none}" | paste -sd, -))"; fi
else
  report WARN ruleset "cannot list rulesets: $(lasterr)"
fi

# Files. Checked on develop; on the default branch only when develop is missing.
ref=develop
if [ -n "${branches:-}" ] && ! has "$branches" develop; then ref=$default; fi
on="on $ref"
root=$(api "repos/$repo/contents?ref=$ref" --jq '.[].name') || { report FAIL files "cannot list the root $on: $(lasterr)"; root=""; }
dotgithub=$(api "repos/$repo/contents/.github?ref=$ref" --jq '.[].name') || dotgithub=""

if [ "$app" = auto ]; then
  if has "$root" app.json || has "$root" eas.json; then app=yes; why="auto: app.json or eas.json at root"
  else app=no; why="auto: no app.json or eas.json at root"; fi
else why="set by --$( [ "$app" = yes ] && echo app || echo not-app )"; fi
echo "app repo: $app ($why); files checked $on"

for f in AGENTS.md CLAUDE.md .env.example; do
  if has "$root" "$f"; then report PASS "file:$f" "present $on"
  else report FAIL "file:$f" "missing $on"; fi
done
if printf '%s\n' "$dotgithub" | grep -qix 'pull_request_template.md'; then
  report PASS file:.github/pull_request_template.md "present $on"
else report FAIL file:.github/pull_request_template.md "missing $on"; fi

if has "$root" package.json; then
  if has "$root" pnpm-lock.yaml; then report PASS file:pnpm-lock.yaml "present $on"
  else report FAIL file:pnpm-lock.yaml "package.json without pnpm-lock.yaml $on; run pnpm install"; fi
fi
other=$(printf '%s\n' "$root" | grep -xE 'package-lock\.json|yarn\.lock|bun\.lockb?' | paste -sd' ' -)
if [ -z "$other" ]; then report PASS pnpm-only "no npm/yarn/bun lockfile $on"
else report FAIL pnpm-only "remove $other $on (pnpm only)"; fi

# CODEOWNERS: every rule names at least two @owners.
if ! has "$dotgithub" CODEOWNERS; then
  report FAIL codeowners "missing .github/CODEOWNERS $on"
elif ! owners=$(raw .github/CODEOWNERS); then
  report FAIL codeowners "cannot read .github/CODEOWNERS: $(lasterr)"
else
  rules=0 thin=""
  while read -r pattern rest; do
    [ -n "$pattern" ] || continue
    rules=$((rules+1))
    n=$(printf '%s\n' "$rest" | tr -s ' \t' '\n\n' | grep -c '^@')
    [ "$n" -ge 2 ] || thin="$thin $pattern"
  done < <(printf '%s\n' "$owners" | nocomments)
  if [ "$rules" -eq 0 ]; then report FAIL codeowners "no rules in .github/CODEOWNERS"
  elif [ -n "$thin" ]; then report FAIL codeowners "fewer than two @owners for:$thin"
  else report PASS codeowners "$rules rule(s), each with two or more @owners"; fi
fi

# Standard CI workflow.
want=paperplanehq/paperplane-engineering/.github/workflows/standard-checks.yml@develop
if ! wf=$(raw .github/workflows/standard.yml); then
  if grep -q 'HTTP 404' "$err"; then report FAIL standard-workflow "missing .github/workflows/standard.yml $on"
  else report FAIL standard-workflow "cannot read .github/workflows/standard.yml $on: $(lasterr)"; fi
else
  wf=$(printf '%s\n' "$wf" | nocomments)
  uses=$(printf '%s\n' "$wf" | grep -oE 'uses:[[:space:]]*["'\'']?[^"'\''[:space:]]*standard-checks\.yml[^"'\''[:space:]]*' | sed -E 's/uses:[[:space:]]*["'\'']?//' | head -1)
  if [ "$uses" = "$want" ]; then report PASS standard-workflow "calls $want"
  elif [ -n "$uses" ]; then report FAIL standard-workflow "calls $uses, want $want"
  else report FAIL standard-workflow "does not call $want"; fi
  if printf '%s\n' "$wf" | grep -qw ready_for_review; then report PASS standard-ready_for_review "pull_request types include ready_for_review"
  else report WARN standard-ready_for_review "pull_request types lack ready_for_review; draft PRs marked ready skip CI (template change pending)"; fi
  if printf '%s\n' "$wf" | grep -qE '^concurrency:' && printf '%s\n' "$wf" | grep -qE 'cancel-in-progress:[[:space:]]*true'; then report PASS standard-concurrency "cancels the previous run of the same PR"
  else report WARN standard-concurrency "no 'concurrency' with cancel-in-progress: true; every push bills a full run (replace with the template)"; fi
  if [ "$app" = yes ]; then
    if printf '%s\n' "$wf" | grep -qE '^[[:space:]]*mobile:[[:space:]]*true([[:space:]]|$)'; then report PASS standard-mobile "mobile: true"
    else report FAIL standard-mobile "app repo, but standard.yml does not pass 'with: mobile: true'"; fi
  fi
fi

# Committed Claude Code guard (install-claude-hook.sh --commit) and AGENTS.md pointing at the skills.
fix="run: bash <skills>/paperplane-shipping-changes/hooks/install-claude-hook.sh --commit"
local_guard="$(cd "$(dirname "$0")" && pwd)/../../paperplane-shipping-changes/hooks/claude-guard.sh"
if ! cs=$(raw .claude/settings.json); then
  report FAIL claude-guard "no .claude/settings.json $on; $fix"
elif ! printf '%s\n' "$cs" | grep -q '\.claude/hooks/paperplane-guard\.sh'; then
  report FAIL claude-guard ".claude/settings.json $on has no paperplane guard hook; $fix"
elif ! vg=$(raw .claude/hooks/paperplane-guard.sh); then
  report FAIL claude-guard "no .claude/hooks/paperplane-guard.sh $on; $fix"
else
  report PASS claude-guard "committed in .claude/settings.json and .claude/hooks/paperplane-guard.sh"
  if [ ! -f "$local_guard" ]; then report WARN claude-guard-current "cannot compare: no $local_guard"
  elif [ "$vg" = "$(cat "$local_guard")" ]; then report PASS claude-guard-current "same as the installed skills"
  else report WARN claude-guard-current "differs from the installed skills' guard; $fix"; fi
fi
if raw .omp/hooks/pre/paperplane-guard.ts >/dev/null; then report PASS omp-guard "committed in .omp/hooks/pre/paperplane-guard.ts"
else report WARN omp-guard "no .omp/hooks/pre/paperplane-guard.ts $on (omp ignores Claude Code hooks); $fix"; fi
if has "$root" AGENTS.md && agents=$(raw AGENTS.md); then
  if printf '%s\n' "$agents" | grep -qE 'paperplane-(\*|shipping-changes|reviewing-prs|releasing|repo-setup|secret-incidents)'; then
    report PASS agents-skills "AGENTS.md names the paperplane-* skills"
  else report WARN agents-skills "AGENTS.md does not mention the paperplane-* skills; add the \"## AI agents\" section"; fi
fi

echo "summary: $repo app=$app  $npass pass, $nfail fail, $nwarn warn"
[ "$nfail" -eq 0 ]
