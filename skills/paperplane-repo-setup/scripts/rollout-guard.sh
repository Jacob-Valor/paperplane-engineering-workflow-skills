#!/usr/bin/env bash
# Prepares the committed guard and the AGENTS.md "## AI agents" section for paperplanehq repos.
# Usage: bash scripts/rollout-guard.sh [--apply] <owner/repo>...
#   default  dry run: clones develop into a temp dir, makes the commit, prints the diff; pushes nothing
#   --apply  also pushes branch chore/agent-guard and opens a DRAFT PR into develop (needs write access)
# A repo that already has the guard and the section is skipped. A human reviews and merges each PR.
# Exit codes: 0 done · 1 a repo failed · 2 usage error
set -uo pipefail

apply=false
repos=()
for arg in "$@"; do
  case "$arg" in
    --apply) apply=true ;;
    -h|--help) sed -n '2,7p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    */*) repos+=("$arg") ;;
    *) echo "unknown argument: $arg"; exit 2 ;;
  esac
done
[ ${#repos[@]} -gt 0 ] || { echo "need at least one owner/repo"; exit 2; }

here="$(cd "$(dirname "$0")" && pwd)"
installer="$here/../../paperplane-shipping-changes/hooks/install-claude-hook.sh"
# The section text lives once, in the repo-setup SKILL.md.
section=$(awk '/^```markdown$/{f=1; next} f && /^```$/{exit} f' "$here/../SKILL.md")
case "$section" in "## AI agents"*) ;; *) echo "cannot find the AI agents section in SKILL.md"; exit 2 ;; esac

branch=chore/agent-guard
failed=0
for repo in "${repos[@]}"; do
  echo "== $repo"
  dir=$(mktemp -d)
  if ! git clone -q --branch develop --depth 1 "https://github.com/$repo.git" "$dir" 2>/dev/null \
     && ! gh repo clone "$repo" "$dir" -- -q --branch develop --depth 1 2>/dev/null; then
    echo "cannot clone $repo (develop)"; failed=1; continue
  fi
  (
    cd "$dir" || exit 1
    git switch -qc "$branch"
    bash "$installer" --commit >/dev/null || { echo "install-claude-hook.sh --commit failed"; exit 1; }
    if [ -f AGENTS.md ] && ! grep -q '^## AI agents' AGENTS.md; then
      printf '\n%s\n' "$section" >> AGENTS.md
    fi
    git add .claude/settings.json .claude/hooks/paperplane-guard.sh .omp/hooks/pre/paperplane-guard.ts
    [ -f AGENTS.md ] && git add AGENTS.md
    if git diff --cached --quiet; then echo "already has the guard and section; skipped"; exit 0; fi
    git commit -qm "chore(agents): commit the paperplane guard for Claude Code and omp" || exit 1
    git show --stat --format='%s' HEAD | sed 's/^/  /'
    $apply || { echo "  dry run: nothing pushed ($dir)"; exit 0; }
    git push -qu origin "$branch" || { echo "push failed (write access?)"; exit 1; }
    gh pr create --draft --base develop --title "chore(agents): commit the paperplane guard for Claude Code and omp" --body \
"## What changed
Commits the paperplane guard so every Claude Code and omp session in this repo blocks merges, approvals, pushes to develop/uat/main, force-pushes, release tags and \`--no-verify\`, with nothing to install. Adds the \"## AI agents\" section to AGENTS.md.

## How I verified it
- Commands: generated with \`install-claude-hook.sh --commit\` from paperplane-engineering-workflow-skills; the guard has its own test suite there.
- iOS: not a mobile change
- Android: not a mobile change

## Risk
A guarded command an agent used to run now fails with a \"paperplane guard:\" message. Not done: per-clone git pre-push hook (each developer installs it).

AI-assisted: yes (rollout-guard.sh) — generated the files; a human reviews and merges"
  ) || failed=1
done
exit "$failed"
