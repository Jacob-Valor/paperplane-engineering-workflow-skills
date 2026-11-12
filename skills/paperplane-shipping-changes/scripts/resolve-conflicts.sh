#!/usr/bin/env bash
# Helps resolve merge conflicts on your own PR the Paper Plane way: merge (never rebase), in the clone (never the web
# editor), lockfiles rebuilt by pnpm, every real decision left to a person. It never commits, pushes, merges a PR or
# marks it Ready: you commit and push with the shipping skill's normal steps once --check passes. Run from the repo root.
# Usage: bash scripts/resolve-conflicts.sh [--base <branch>]   start: draft again, merge, rebuild lockfiles, list the rest
#        bash scripts/resolve-conflicts.sh --check             after you resolved the rest: is it safe to commit?
#   --base  the branch to merge in (default: the PR's base from gh, else develop)
# Start takes a Ready PR back to draft, runs `git merge --no-commit origin/<base>`, rebuilds each conflicting
#   pnpm-lock.yaml with `pnpm install --lockfile-only` in its folder (in --check when a package.json or
#   pnpm-workspace.yaml conflicts too), and prints every other conflict with the commits that touched it on both sides.
# Check works only on the merge the start began on this branch. It rebuilds lockfiles still waiting, then refuses
#   while a conflicted file has a new conflict marker, is unstaged, or cannot be read. On success it prints the
#   commands to commit and push, and for an approved PR a message for the reviewer.
# Exit codes: start 0 merged, nothing left to decide, run --check · 3 already up to date, nothing to do ·
#             4 conflicts need a decision · check 0 safe to commit · both 1 blocked: do what it printed ·
#             2 refused: do what it printed
set -uo pipefail

check=false base=""
while [ $# -gt 0 ]; do
  case "$1" in
    --check) check=true ;;
    --base) [ $# -ge 2 ] || { echo "--base needs a branch name"; exit 2; }; base=$2; shift ;;
    --base=*) base=${1#--base=} ;;
    -h|--help) sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown argument '$1'"; exit 2 ;;
  esac
  shift
done
$check && [ -n "$base" ] && { echo "--base is for the start; --check uses the base the start recorded"; exit 2; }

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "not a git repository"; exit 2; }
[ -z "$(git rev-parse --show-prefix)" ] || { echo "run it from the repo root"; exit 2; }
branch=$(git symbolic-ref --quiet --short HEAD) || { echo "detached HEAD; switch to your PR's branch"; exit 2; }
case "$branch" in
  develop|uat|main) echo "on '$branch': conflicts are resolved on your PR's branch, never on a protected branch"; exit 2 ;;
esac

# One flat state file per branch: branch, base, PR, review decision, merged commit, then the conflicted files.
state=$(git rev-parse --git-path "paperplane-conflicts.$(printf '%s' "$branch" | tr '/' '%')")
# A conflict marker line: 7 or more < > or | (conflict-marker-size can make them longer), then a space or the end.
MARK='^(<{7,}|>{7,}|\|{7,})( |$|'$'\r'')'
# File names unquoted (café.md, not "caf\303\251.md"), one per line: core.quotePath=false.
unmerged() { git -c core.quotePath=false diff --name-only --diff-filter=U; }
in_list() { printf '%s\n' "$1" | grep -qxF -- "$2"; }
locks() { printf '%s\n' "$1" | grep -E '(^|/)pnpm-lock\.yaml$'; }
manifests_under() { # manifests_under <dir> <list>: package.json / pnpm-workspace.yaml in the list, inside <dir>
  local d=$1; [ "$d" = . ] && d=""
  printf '%s\n' "$2" | grep -E "^${d:+$d/}(.*/)?package\.json$|^${d:+$d/}pnpm-workspace\.yaml$"
}
rebuildable() { # the lock exists on both sides; otherwise it is a deleted-file conflict for the person
  git cat-file -e "origin/$base:$1" 2>/dev/null && git cat-file -e "HEAD:$1" 2>/dev/null
}
rebuild_lock() { # rebuild_lock <lockfile>: the base's copy plus this branch's manifests, by pnpm, never by hand
  local dir; dir=$(dirname "$1")
  echo "$1: rebuilding from origin/$base's copy with pnpm"
  git restore --source="origin/$base" --staged --worktree -- "$1" || return 1
  command -v pnpm >/dev/null 2>&1 || { echo "pnpm is not installed; install it, then run --check (it rebuilds the lockfile)"; return 1; }
  ( cd "$dir" && pnpm install --lockfile-only ) || { echo "pnpm install --lockfile-only failed in $dir (see above); fix it, then run --check"; return 1; }
  git add -- "$1"
}
kind() { # kind <file>: what sort of conflict git recorded
  if git --literal-pathspecs ls-files -s -- "$1" | grep -q '^120000'; then echo "symlink changed on both sides"; return; fi
  case "$(git --literal-pathspecs status --porcelain=v1 -- "$1" | cut -c1-2)" in
    UU|AA) if git --literal-pathspecs diff -- "$1" | grep -q '^Binary files'; then echo "binary file changed on both sides"; else echo text; fi ;;
    UD) echo "changed here, deleted on the base" ;;
    DU) echo "deleted here, changed on the base" ;;
    *) echo "conflict" ;;
  esac
}
new_markers() { # new_markers <file>: the staged copy has a marker line neither parent had, or cannot be read
  local staged rc
  git --literal-pathspecs ls-files --error-unmatch -- "$1" >/dev/null 2>&1 || return 1   # staged as deleted
  # git grep reports an unreadable file as "no match", so read the staged copy first: if that fails, block.
  git cat-file -p ":0:$1" >/dev/null 2>&1 || return 0
  staged=$(git --literal-pathspecs grep --cached -h -E "$MARK" -- "$1"); rc=$?
  [ "$rc" -eq 1 ] && return 1     # no marker lines
  [ "$rc" -eq 0 ] || return 0     # could not read it: block
  # Marker-like lines already in a parent (a doc that shows an example) are not new.
  [ -n "$(comm -23 <(printf '%s\n' "$staged" | sort -u) \
      <({ git cat-file -p "HEAD:$1"; git cat-file -p "MERGE_HEAD:$1"; } 2>/dev/null | grep -E "$MARK" | sort -u))" ]
}
staged_vs_both() { # staged files that differ from both parents: every place a resolution was written
  comm -12 <(git -c core.quotePath=false diff --cached --no-renames --name-only HEAD | sort) \
           <(git -c core.quotePath=false diff --cached --no-renames --name-only MERGE_HEAD | sort)
}
quoted() { local f out=""; while IFS= read -r f; do [ -n "$f" ] && out="$out $(printf '%q' "$f")"; done <<<"$1"; printf '%s' "$out"; }

if ! $check; then
  if git rev-parse -q --verify MERGE_HEAD >/dev/null; then
    echo "a merge is already in progress. If this script started it: resolve it, then run with --check."
    echo "If you started it by hand: 'git merge --abort', then run this script."
    exit 2
  fi
  rm -f "$state"
  [ -z "$(git status --porcelain --untracked-files=no)" ] || { echo "uncommitted changes: commit or stash them first"; exit 2; }

  # The PR, through gh: stdout and stderr apart, so a gh warning never reads as data. "No PR" is fine; anything
  # else gh cannot answer stops here, so a Ready PR never skips the draft step.
  command -v gh >/dev/null 2>&1 || { echo "gh is not installed; install it and run 'gh auth login' (the draft step needs it)"; exit 2; }
  ghe=$(mktemp "${TMPDIR:-/tmp}/rc-gh.XXXXXX") || exit 2
  trap 'rm -f "$ghe"' EXIT
  pr="" ready=false review=""
  if info=$(gh pr view --json number,isDraft,baseRefName,reviewDecision \
      --jq '"\(.number) \(.isDraft) \(.baseRefName) \(.reviewDecision // "")"' 2>"$ghe"); then
    read -r pr draft prbase review <<<"$info"
    if ! [[ "$pr" =~ ^[0-9]+$ ]] || { [ "$draft" != true ] && [ "$draft" != false ]; } || [ -z "$prbase" ]; then
      echo "gh gave an answer this script cannot read: '$info'"; exit 2
    fi
    [ "$draft" = false ] && ready=true
    [ -n "$base" ] || base=$prbase
  elif grep -qi 'no pull requests found' "$ghe"; then
    echo "no PR for $branch yet; merging without the draft step"
  else
    tail -3 "$ghe"
    echo "gh could not read the PR (see above); fix gh (gh auth status), then run this script again"; exit 2
  fi
  [ -n "$base" ] || base=develop

  git fetch --quiet origin || { echo "git fetch origin failed"; exit 2; }
  git rev-parse -q --verify "origin/$base" >/dev/null || { echo "origin/$base not found"; exit 2; }
  if git merge-base --is-ancestor "origin/$base" HEAD; then
    echo "already up to date with origin/$base; nothing to merge, nothing to check"; exit 3
  fi
  if $ready; then
    echo "PR #$pr is Ready: back to draft first, the resolution is new code nobody reviewed"
    gh pr ready "$pr" --undo || { echo "gh pr ready $pr --undo failed; fix gh, then run this script again"; exit 2; }
  fi
  out=$(git merge --no-ff --no-commit "origin/$base" 2>&1)
  if ! git rev-parse -q --verify MERGE_HEAD >/dev/null; then
    printf '%s\n' "$out" | tail -8
    echo "git refused the merge (see above; often an untracked file in the way). Fix that, then run this script again."
    $ready && echo "PR #$pr is now a draft; it stays one until the person running you says go."
    exit 2
  fi
  files=$(unmerged)
  printf '%s\n' "$branch" "$base" "$pr" "$review" "$(git rev-parse MERGE_HEAD)" "$files" > "$state" \
    || { echo "cannot write $state"; git merge --abort; exit 2; }

  handled=""
  while IFS= read -r l; do
    [ -n "$l" ] && rebuildable "$l" || continue
    handled="$handled$l"$'\n'
    waiting=$(manifests_under "$(dirname "$l")" "$files")
    if [ -n "$waiting" ]; then echo "$l: rebuilt by --check once $(printf '%s' "$waiting" | paste -sd, -) is resolved"
    else rebuild_lock "$l" || exit 1; fi
  done <<<"$(locks "$files")"
  left=$(printf '%s\n' "$files" | grep -vxF -f <(printf '%s' "$handled"; echo /dev/null/none))
  if [ -z "$left" ]; then
    echo "merged origin/$base with nothing left to decide. Run the repo's checks, then: bash $0 --check"; exit 0
  fi
  echo
  echo "These conflicts need a decision. For each: if both changes fit together, keep both;"
  echo "if they change behaviour differently, stop and ask the person which wins. Never take one side of a whole file."
  while IFS= read -r f; do
    k=$(kind "$f")
    echo; echo "== $f"
    case "$f" in *pnpm-lock.yaml) echo "-- a lockfile pnpm cannot rebuild here (deleted on one side): ask the person; never edit it by hand." ;; esac
    echo "-- commits that touched it, on both sides:"
    git --literal-pathspecs log --merge --format='   %h %s (%an)' -- "$f"
    if [ "$k" = text ]; then
      echo "-- conflict:"
      git --literal-pathspecs diff -- "$f" | sed -n '/^@@/,$p' | head -80
    else
      echo "-- $k: no text to merge. Ask the person which version stays (or that it is deleted); do not pick one yourself."
    fi
  done <<<"$left"
  echo; echo "Edit the files above, run the repo's checks, stage each by name (git add -- <file>), then: bash $0 --check"
  exit 4
fi

# --check
owner="" merged="" files=""
if [ -f "$state" ]; then
  { read -r owner; read -r base; read -r pr; read -r review; read -r merged; files=$(cat); } < "$state"
fi
if ! git rev-parse -q --verify MERGE_HEAD >/dev/null; then
  echo "no merge in progress on $branch. If you already committed it, push with the skill's step 5;"
  echo "otherwise run this script without --check to start."
  exit 2
fi
if [ "$owner" != "$branch" ] || [ "$(git rev-parse MERGE_HEAD)" != "$merged" ]; then
  echo "the merge in progress was not started by this script on $branch. 'git merge --abort', then run the script."
  exit 2
fi

left=$(unmerged)
while IFS= read -r l; do
  [ -n "$l" ] && rebuildable "$l" || continue
  pending=$(manifests_under "$(dirname "$l")" "$left")
  if [ -z "$pending" ]; then
    while IFS= read -r m; do [ -n "$m" ] && new_markers "$m" && pending="$pending$m"$'\n'; done \
      <<<"$(manifests_under "$(dirname "$l")" "$files")"
  fi
  [ -z "$pending" ] || { echo "BLOCKED: resolve and stage$(quoted "$pending") first; $l is rebuilt from it"; exit 1; }
  rebuild_lock "$l" || exit 1
done <<<"$(locks "$files")"
left=$(unmerged)
if [ -n "$left" ]; then
  marked="" plain=""
  while IFS= read -r f; do
    if [ -f "$f" ] && grep -qE "$MARK" -- "$f"; then marked="$marked$f"$'\n'; else plain="$plain$f"$'\n'; fi
  done <<<"$left"
  [ -z "$marked" ] || { echo "BLOCKED: conflict markers are still in:"; printf '%s' "$marked" | sed 's/^/  /'; exit 1; }
  echo "BLOCKED: no markers left, but not staged. A binary, symlink or deleted-file conflict has no markers: check that"
  echo "the person chose its version. Then stage each by name and run --check again:"
  echo "  git add --$(quoted "$plain")"
  exit 1
fi
marked=""
while IFS= read -r f; do
  [ -n "$f" ] && new_markers "$f" && marked="$marked$f"$'\n'
done <<<"$(printf '%s\n%s\n' "$files" "$(staged_vs_both)" | grep -v '^$' | sort -u)"
[ -z "$marked" ] || { echo "BLOCKED: conflict markers (or a file it cannot read) are staged in:"; printf '%s' "$marked" | sed 's/^/  /'; exit 1; }

echo "OK: the merge of origin/$base is resolved and staged. Commit and push it now, with nothing else in between:"
echo "  git commit --no-edit"
echo "  bash <skill>/scripts/pre-push.sh origin/$base"
echo "  git push origin $branch"
echo "Then show the person the resolution: git show --remerge-diff HEAD"
if [ "$review" = APPROVED ] && [ -n "$files" ]; then
  echo; echo "== Message for the reviewer (the person you work for posts it):"
  echo "After your approval, #$pr conflicted with origin/$base. I merged it in (no rebase) and resolved:"
  printf '%s\n' "$files" | sed 's/^/- /; s/^- \(.*pnpm-lock\.yaml\)$/- \1: rebuilt with pnpm from both sides'"'"' manifests/'
  echo "The resolution is in the merge commit (git show --remerge-diff). Could you look again before it merges?"
fi
echo; echo "Stop after the push. Mark the PR Ready again only after the person says go."
