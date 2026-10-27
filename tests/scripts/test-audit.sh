#!/usr/bin/env bash
# Behaviour tests for the repo-setup skill's audit.sh. Run: bash tests/scripts/run.sh
# A fake `gh` on PATH serves canned API responses; no network is used.
set -u
here=$(cd "$(dirname "$0")/../.." && pwd)
A="$here/skills/paperplane-repo-setup/scripts/audit.sh"
pass=0; fail=0
out=/tmp/pp-test-out.$$
expect() { # expect <name> <wanted-exit> <cmd...>
  local name=$1 want=$2; shift 2
  "$@" >"$out" 2>&1; local got=$?
  if [ "$got" -eq "$want" ]; then pass=$((pass+1)); echo "ok   $name"
  else fail=$((fail+1)); echo "FAIL $name: exit $got, wanted $want"; sed 's/^/     /' "$out"; fi
}
says() { # says <name> <regex>: the last expect's output has a line matching regex
  if grep -qE -- "$2" "$out"; then pass=$((pass+1)); echo "ok   $1"
  else fail=$((fail+1)); echo "FAIL $1: no line matching '$2'"; sed 's/^/     /' "$out"; fi
}

work=$(mktemp -d); trap 'rm -rf "$work" "$out"' EXIT
mkdir -p "$work/bin" "$work/api"
cat > "$work/bin/gh" <<'EOF'
#!/usr/bin/env bash
# Fake gh: `gh api [flags] <path>` prints $FAKE_GH/<path with / ? = & as _>.
# --jq applies jq -r like gh does; a missing file is a 404.
[ "${1:-}" = api ] || { echo "fake gh: only 'api' is supported" >&2; exit 1; }
shift
path="" filter=""
while [ $# -gt 0 ]; do
  case "$1" in
    --jq|-q) filter=$2; shift ;;
    -H|--header|-X|--method|-f|-F) shift ;;
    -*) ;;
    *) path=$1 ;;
  esac
  shift
done
file="$FAKE_GH/$(printf '%s' "$path" | tr '/?=&' '____')"
[ -f "$file" ] || { echo "gh: Not Found (HTTP 404)" >&2; exit 1; }
if [ -n "$filter" ]; then jq -r "$filter" "$file"; else cat "$file"; fi
EOF
chmod +x "$work/bin/gh"
export FAKE_GH="$work/api" PATH="$work/bin:$PATH"
[ "$(command -v gh)" = "$work/bin/gh" ] || { echo "fake gh is not first on PATH; refusing to call the real gh"; exit 1; }

R=paperplanehq/demo-app
serve() { # serve <api path> <content>; content "" deletes the response (404)
  local f; f="$FAKE_GH/$(printf '%s' "$1" | tr '/?=&' '____')"
  if [ -n "$2" ]; then printf '%s\n' "$2" > "$f"; else rm -f "$f"; fi
}
names() { local n s=""; for n in "$@"; do s="$s${s:+,}{\"name\":\"$n\"}"; done; echo "[$s]"; }
rulesets() { local n s=""; for n in "$@"; do s="$s${s:+,}{\"name\":\"${n%%:*}\",\"enforcement\":\"${n#*:}\"}"; done; echo "[$s]"; } # rulesets name:enforcement...
settings() { # settings <auto_merge>
  echo "{\"default_branch\":\"develop\",\"allow_squash_merge\":true,\"allow_merge_commit\":true,\"allow_rebase_merge\":false,\"delete_branch_on_merge\":true,\"allow_auto_merge\":$1}"
}
WF=$(cat <<'EOF'
name: standard
on:
  pull_request:
    types: [opened, edited, synchronize, reopened, ready_for_review]
concurrency:
  group: standard-${{ github.event.pull_request.number || github.ref }}
  cancel-in-progress: true
jobs:
  standard:
    uses: paperplanehq/paperplane-engineering/.github/workflows/standard-checks.yml@develop
    with:
      mobile: true
EOF
)
ROOT=(AGENTS.md CLAUDE.md .env.example .github package.json pnpm-lock.yaml app.json src)
GUARD="$here/skills/paperplane-shipping-changes/hooks/claude-guard.sh"
CLAUDE_SETTINGS='{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"bash \"$CLAUDE_PROJECT_DIR/.claude/hooks/paperplane-guard.sh\""}]}]}}'
compliant() {
  rm -f "$FAKE_GH"/*
  serve "repos/$R" "$(settings true)"
  serve "repos/$R/branches?per_page=100" "$(names develop uat main feature/x)"
  serve "repos/$R/rulesets" "$(rulesets protect-develop-uat-main:active release-tags-owner-only:active)"
  serve "repos/$R/contents?ref=develop" "$(names "${ROOT[@]}")"
  serve "repos/$R/contents/.github?ref=develop" "$(names CODEOWNERS pull_request_template.md workflows)"
  serve "repos/$R/contents/.github/CODEOWNERS?ref=develop" "$(printf '# owners\n* @paperplanehq/leads @alice\n/ios/ @bob @carol # mobile\n')"
  serve "repos/$R/contents/.github/workflows/standard.yml?ref=develop" "$WF"
  serve "repos/$R/contents/.claude/settings.json?ref=develop" "$CLAUDE_SETTINGS"
  serve "repos/$R/contents/.claude/hooks/paperplane-guard.sh?ref=develop" "$(cat "$GUARD")"
  serve "repos/$R/contents/.omp/hooks/pre/paperplane-guard.ts?ref=develop" "$(cat "$here/skills/paperplane-shipping-changes/hooks/omp-guard.ts")"
  serve "repos/$R/contents/AGENTS.md?ref=develop" "$(printf '# AGENTS.md\n## AI agents\nLoad the paperplane-* skills before any git or gh work.\n')"
}

compliant
expect "audit: compliant app repo passes" 0 bash "$A" "$R"
says "audit: compliant repo has no FAIL or WARN" '^summary: .* app=yes  [0-9]+ pass, 0 fail, 0 warn$'
says "audit: app repo auto-detected from app.json" '^PASS  standard-mobile '

serve "repos/$R/contents/.github/workflows/standard.yml?ref=develop" "$(printf '%s\n' "$WF" | grep -v 'mobile: true')"
expect "audit: app repo without mobile: true fails" 1 bash "$A" "$R"
says "audit: names the mobile check" '^FAIL  standard-mobile '
expect "audit: --not-app skips the mobile check" 0 bash "$A" "$R" --not-app

compliant
serve "repos/$R/contents?ref=develop" "$(names AGENTS.md CLAUDE.md .env.example .github package.json pnpm-lock.yaml src)"
serve "repos/$R/contents/.github/workflows/standard.yml?ref=develop" "$(printf '%s\n' "$WF" | grep -v 'mobile: true')"
expect "audit: non-app repo needs no mobile: true" 0 bash "$A" "$R"
expect "audit: --app forces the mobile check" 1 bash "$A" "$R" --app

compliant
serve "repos/$R/contents/.github/CODEOWNERS?ref=develop" "$(printf '* @paperplanehq/leads @alice\n/api/ @bob\n')"
expect "audit: one-owner CODEOWNERS rule fails" 1 bash "$A" "$R"
says "audit: names the thin rule" '^FAIL  codeowners .*/api/'

compliant
serve "repos/$R/contents?ref=develop" "$(names "${ROOT[@]}" yarn.lock)"
expect "audit: yarn.lock fails" 1 bash "$A" "$R"
says "audit: names the extra lockfile" '^FAIL  pnpm-only .*yarn\.lock'

compliant
serve "repos/$R/contents?ref=develop" "$(names AGENTS.md CLAUDE.md .env.example .github package.json app.json)"
expect "audit: package.json without pnpm-lock.yaml fails" 1 bash "$A" "$R"
says "audit: names the missing lockfile" '^FAIL  file:pnpm-lock\.yaml '

compliant
serve "repos/$R" "$(settings false)"
expect "audit: auto-merge off fails" 1 bash "$A" "$R"
says "audit: names the auto-merge setting" '^FAIL  allow_auto_merge .*is false, want true'

compliant
serve "repos/$R/rulesets" "$(names release-tags-owner-only)"
expect "audit: missing ruleset fails" 1 bash "$A" "$R"
says "audit: names the ruleset check" '^FAIL  ruleset '

compliant
serve "repos/$R/branches?per_page=100" "$(names develop main)"
expect "audit: missing uat branch fails" 1 bash "$A" "$R"
says "audit: names the uat branch" '^FAIL  branch-uat '

compliant
serve "repos/$R/contents/.github?ref=develop" "$(names pull_request_template.md workflows)"
expect "audit: missing CODEOWNERS fails" 1 bash "$A" "$R"

compliant
serve "repos/$R/contents/.github/workflows/standard.yml?ref=develop" "$(printf '%s\n' "$WF" | sed 's/, ready_for_review//')"
expect "audit: missing ready_for_review is a WARN only" 0 bash "$A" "$R"
says "audit: names the ready_for_review warning" '^WARN  standard-ready_for_review '

compliant
serve "repos/$R/contents/.github/workflows/standard.yml?ref=develop" "$(printf '%s\n' "$WF" | grep -vE '^concurrency:|^  (group|cancel-in-progress):')"
expect "audit: missing concurrency is a WARN only" 0 bash "$A" "$R"
says "audit: names the concurrency warning" '^WARN  standard-concurrency '

compliant
serve "repos/$R/contents/.github/workflows/standard.yml?ref=develop" "$(printf '%s\n' "$WF" | sed 's/@develop/@main/')"
expect "audit: workflow pinned to another ref fails" 1 bash "$A" "$R"
says "audit: shows the wrong ref" '^FAIL  standard-workflow .*@main'

compliant
serve "repos/$R/contents/.claude/settings.json?ref=develop" '{"permissions":{"allow":["Bash(pnpm test)"]}}'
expect "audit: settings.json without the guard hook fails" 1 bash "$A" "$R"
says "audit: names the claude-guard check" '^FAIL  claude-guard .*settings\.json'

compliant
serve "repos/$R/contents/.claude/settings.json?ref=develop" ""
expect "audit: missing .claude/settings.json fails" 1 bash "$A" "$R"
says "audit: names the missing settings file" '^FAIL  claude-guard .*settings\.json'

compliant
serve "repos/$R/contents/.claude/hooks/paperplane-guard.sh?ref=develop" ""
expect "audit: missing vendored guard fails" 1 bash "$A" "$R"
says "audit: names the missing guard script" '^FAIL  claude-guard .*paperplane-guard\.sh'

compliant
serve "repos/$R/contents/.claude/hooks/paperplane-guard.sh?ref=develop" "$(sed 's/merge/MERGE/' "$GUARD")"
expect "audit: outdated vendored guard is a WARN only" 0 bash "$A" "$R"
says "audit: names the outdated guard" '^WARN  claude-guard-current .*install-claude-hook\.sh --commit'

compliant
serve "repos/$R/contents/.omp/hooks/pre/paperplane-guard.ts?ref=develop" ""
expect "audit: missing omp adapter is a WARN only" 0 bash "$A" "$R"
says "audit: names the missing omp adapter" '^WARN  omp-guard '

compliant
serve "repos/$R/contents/AGENTS.md?ref=develop" "$(printf '# AGENTS.md\nSee paperplanehq/paperplane-engineering.\n')"
expect "audit: AGENTS.md without the skills is a WARN only" 0 bash "$A" "$R"
says "audit: names the AGENTS.md skills warning" '^WARN  agents-skills '

compliant
serve "repos/$R/rulesets" "$(rulesets protect-develop-uat-main:disabled release-tags-owner-only:active)"
expect "audit: disabled ruleset fails" 1 bash "$A" "$R"
says "audit: says the ruleset is not active" '^FAIL  ruleset .*disabled'
serve "repos/$R/rulesets" "$(rulesets protect-develop-uat-main:evaluate)"
expect "audit: evaluate-only ruleset fails" 1 bash "$A" "$R"

compliant
serve "repos/$R/contents/.github?ref=develop" "$(names pull_request_template.md workflows)"
serve "repos/$R/contents?ref=develop" "$(names "${ROOT[@]}" CODEOWNERS)"
serve "repos/$R/contents/CODEOWNERS?ref=develop" "* @a @b"
expect "audit: root CODEOWNERS is accepted" 0 bash "$A" "$R"
says "audit: reports the root CODEOWNERS" '^PASS  codeowners .*CODEOWNERS'
serve "repos/$R/contents/CODEOWNERS?ref=develop" "* @a"
expect "audit: thin root CODEOWNERS fails" 1 bash "$A" "$R"
serve "repos/$R/contents?ref=develop" "$(names "${ROOT[@]}" docs)"
serve "repos/$R/contents/CODEOWNERS?ref=develop" ""
serve "repos/$R/contents/docs?ref=develop" "$(names CODEOWNERS)"
serve "repos/$R/contents/docs/CODEOWNERS?ref=develop" "* @a @b"
expect "audit: docs/CODEOWNERS is accepted" 0 bash "$A" "$R"
says "audit: reports docs/CODEOWNERS" '^PASS  codeowners .*docs/CODEOWNERS'

compliant
big=$(printf 'develop\nuat\nmain\n'; seq 1 20000 | sed s/^/branch-/)
BIGJSON=$(printf '%s\n' "$big" | jq -R . | jq -s 'map({name:.})')
serve "repos/$R/branches?per_page=100" "$BIGJSON"
expect "audit: 20000 branches (>64KB) do not cause false FAILs" 0 bash "$A" "$R"
says "audit: big branch list finds develop" '^PASS  branch-develop '

compliant
serve "repos/$R/contents/.github/workflows/standard.yml?ref=develop" "$(printf '%s\n' "$WF" | sed -e 's/, ready_for_review//' -e 's/^name: standard$/name: standard # ready_for_review/')"
expect "audit: ready_for_review only in a comment is a WARN" 0 bash "$A" "$R"
says "audit: comment does not satisfy ready_for_review" '^WARN  standard-ready_for_review '
serve "repos/$R/contents/.github/workflows/standard.yml?ref=develop" "$(printf '%s\n' "$WF" | sed -e 's/, ready_for_review//' -e 's/^    uses:/    if: github.event.action != '"'"'ready_for_review'"'"'\n    uses:/')"
expect "audit: ready_for_review only in a job if: is a WARN" 0 bash "$A" "$R"
says "audit: job if: does not satisfy ready_for_review" '^WARN  standard-ready_for_review '
serve "repos/$R/contents/.github/workflows/standard.yml?ref=develop" "$(printf '%s\n' "$WF" | sed -e 's/types: \[.*\]/types:\n      - opened\n      - ready_for_review/')"
expect "audit: block-list types with ready_for_review" 0 bash "$A" "$R"
says "audit: block-list types pass" '^PASS  standard-ready_for_review '

compliant
serve "repos/$R/contents/.github/workflows/standard.yml?ref=develop" "$(printf '%s\n' "$WF" | sed -e 's/^concurrency:/# concurrency:/')"
expect "audit: commented-out concurrency is a WARN" 0 bash "$A" "$R"
says "audit: commented concurrency warns" '^WARN  standard-concurrency '
serve "repos/$R/contents/.github/workflows/standard.yml?ref=develop" "$(printf '%s\n' "$WF" | grep -vE '^concurrency:|^  (group|cancel-in-progress):' | sed 's/^jobs:/jobs:\n  other:\n    concurrency:\n      group: x\n      cancel-in-progress: true/')"
expect "audit: job-level concurrency is not the top-level one" 0 bash "$A" "$R"
says "audit: job-level concurrency warns" '^WARN  standard-concurrency '
serve "repos/$R/contents/.github/workflows/standard.yml?ref=develop" "$(printf '%s\n' "$WF" | sed 's/cancel-in-progress: true/cancel-in-progress: false # true/')"
expect "audit: cancel-in-progress false with true in a comment" 0 bash "$A" "$R"
says "audit: cancel false warns" '^WARN  standard-concurrency '
serve "repos/$R/contents/.github/workflows/standard.yml?ref=develop" "$(printf '%s\n' "$WF" | sed -e '/^concurrency:/,/cancel-in-progress/d' -e 's/^jobs:/concurrency: { group: g, cancel-in-progress: true }\njobs:/')"
expect "audit: inline concurrency mapping passes" 0 bash "$A" "$R"
says "audit: inline concurrency passes" '^PASS  standard-concurrency '

compliant
serve "repos/$R/contents/.github/workflows/standard.yml?ref=develop" "$(printf '%s\n' "$WF" | sed 's/^  group: .*/  group: "a #b"/')"
expect "audit: # inside quotes is not a comment" 0 bash "$A" "$R"
says "audit: concurrency still passes after a quoted #" '^PASS  standard-concurrency '

compliant
serve "repos/$R" ""
expect "audit: unreadable repo exits 2" 2 bash "$A" "$R"
expect "audit: usage error without a repo" 2 bash "$A"
expect "audit: usage error on a bad repo name" 2 bash "$A" demo-app
expect "audit: --help exits 0" 0 bash "$A" --help

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
