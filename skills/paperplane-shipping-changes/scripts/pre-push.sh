#!/usr/bin/env bash
# Checks the current branch before every `git push` in a paperplanehq repo.
# Usage: bash scripts/pre-push.sh [base-ref]     (default base: origin/develop)
# Exit codes: 0 safe to push · 1 blocked, do not push · 2 not runnable here ·
#             3 gitleaks missing: read the full diff for secrets before pushing
set -uo pipefail

base="${1:-origin/develop}"
fail=0
block() { echo "BLOCKED: $*"; fail=1; }

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "not a git repository"; exit 2; }

branch=$(git symbolic-ref --quiet --short HEAD) || { echo "BLOCKED: detached HEAD; switch to your branch"; exit 1; }
case "$branch" in
  develop|uat|main) block "on '$branch'; work on a feature/fix/chore branch and open a PR" ;;
esac

email=$(git config --get user.email || true)
if [ -z "$email" ]; then
  block "git user.email is not set"
else
  echo "identity: $(git config --get user.name || echo '?') <$email> from $(git config --show-origin --get user.email | cut -f1)"
  echo "          confirm this is the human you work for"
fi

git fetch --quiet origin 2>/dev/null || echo "warning: git fetch origin failed; checking against the local $base"
git rev-parse --verify --quiet "$base" >/dev/null || { echo "base '$base' not found"; exit 2; }

# Files the branch adds or changes (a deletion is a cleanup, not a problem).
files=$(git diff --name-only --diff-filter=d "$base...HEAD")
[ "$(git rev-list --count "$base..HEAD")" -gt 0 ] || echo "no commits ahead of $base"

if git ls-files --error-unmatch pnpm-lock.yaml >/dev/null 2>&1 || printf '%s\n' "$files" | grep -qx 'pnpm-lock.yaml'; then
  bad=$(printf '%s\n' "$files" | grep -E '(^|/)(package-lock\.json|yarn\.lock|bun\.lockb?)$' || true)
  [ -n "$bad" ] && block "second lockfile in this pnpm repo: $(printf '%s\n' "$bad" | tr '\n' ' ')"
fi

# Every commit counts here: a .env added and removed again is still in the pushed history.
envs=$(git log --name-only --diff-filter=d --format= "$base..HEAD" | grep -E '(^|/)\.env(\..+)?$' | grep -vE '(^|/)\.env(\.(example|sample|template|dist)|\..+\.example)$' | sort -u || true)
[ -n "$envs" ] && block ".env file in the commits: $(printf '%s\n' "$envs" | tr '\n' ' ')"

# Build output only counts at the repo root or next to a package.json (src/build/ is source).
is_build() { # is_build <path>
  local -a parts; local j=0 pre=""
  IFS=/ read -r -a parts <<EOF
$1
EOF
  while [ "$j" -lt $((${#parts[@]}-1)) ]; do
    case "${parts[j]}" in
      dist|coverage|build)
        { [ -z "$pre" ] || git cat-file -e "HEAD:${pre}package.json" 2>/dev/null; } && return 0 ;;
    esac
    pre="$pre${parts[j]}/"; j=$((j+1))
  done
  return 1
}
built=""
while IFS= read -r f; do
  [ -n "$f" ] && is_build "$f" && built="$built $f"
done <<EOF
$files
EOF
[ -n "$built" ] && block "build output in the commits: $(echo "$built" | cut -c1-200)"

if command -v gitleaks >/dev/null 2>&1; then
  # mktemp, not a name built from $$: a guessable path in /tmp can be pre-created as a symlink
  gl_out=$(mktemp "${TMPDIR:-/tmp}/pre-push-gitleaks.XXXXXX") || exit 1
  if ! gitleaks git --no-banner --redact --log-opts="$base..HEAD" . >"$gl_out" 2>&1; then
    grep -E 'leaks found|Finding|RuleID|File|Commit' "$gl_out" | head -20
    block "gitleaks found a secret; follow paperplane-secret-incidents, never repeat the value"
  else
    echo "gitleaks: no leaks in $base..HEAD"
  fi
  rm -f "$gl_out"
else
  [ "$fail" -eq 0 ] && { echo "gitleaks not installed: read the full 'git diff $base...HEAD' for keys before pushing"; exit 3; }
fi

[ "$fail" -eq 0 ] && echo "OK: safe to push $branch"
exit "$fail"
