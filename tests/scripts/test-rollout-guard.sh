#!/usr/bin/env bash
# Behaviour tests for the repo-setup skill's rollout-guard.sh. Run: bash tests/scripts/run.sh
# No network: a git config maps https://github.com/ to local bare repos, and a fake `gh` on PATH logs its calls.
set -u
here=$(cd "$(dirname "$0")/../.." && pwd)
RG="$here/skills/paperplane-repo-setup/scripts/rollout-guard.sh"
INSTALLER="$here/skills/paperplane-shipping-changes/hooks/install-claude-hook.sh"
SKILL="$here/skills/paperplane-repo-setup/SKILL.md"
out=/tmp/pp-test-out.$$
pass=0; fail=0
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
lacks() { # lacks <name> <regex>
  if ! grep -qE -- "$2" "$out"; then pass=$((pass+1)); echo "ok   $1"
  else fail=$((fail+1)); echo "FAIL $1: a line matches '$2'"; sed 's/^/     /' "$out"; fi
}
check() { # check <name> <got> <wanted>
  if [ "$2" = "$3" ]; then pass=$((pass+1)); echo "ok   $1"
  else fail=$((fail+1)); echo "FAIL $1: got '$2', wanted '$3'"; fi
}
callhas() { # callhas <name> <fragment>: the logged gh call contains the fragment as whole words
  case " $call " in *" $2 "*) pass=$((pass+1)); echo "ok   $1" ;; *) fail=$((fail+1)); echo "FAIL $1: no '$2' in: $call" ;; esac
}

command -v jq >/dev/null 2>&1 || { echo "jq is required by install-claude-hook.sh"; exit 1; }
work=$(mktemp -d); trap 'rm -rf "$work" "$out"' EXIT
mkdir -p "$work/bin" "$work/remotes/paperplanehq" "$work/tmp"
export TMPDIR="$work/tmp"

# git: https://github.com/ is served from $work/remotes; fixed identity; nothing from the real user config.
cat > "$work/gitconfig" <<CFG
[user]
	name = Test
	email = test@example.com
[init]
	defaultBranch = develop
[url "file://$work/remotes/"]
	insteadOf = https://github.com/
CFG
export GIT_CONFIG_GLOBAL="$work/gitconfig" GIT_CONFIG_NOSYSTEM=1 GIT_TERMINAL_PROMPT=0

# gh: logs every call; `repo clone` fails (so a missing repo cannot be reached that way); `pr create` succeeds.
cat > "$work/bin/gh" <<'FAKE'
#!/usr/bin/env bash
echo "$*" >> "$FAKE_GH_CALLS"
case "$1 $2" in
  "pr create") echo "https://github.com/fake/pull/1"; exit 0 ;;
  "repo clone") echo "gh: could not clone" >&2; exit 1 ;;
  *) echo "fake gh: unexpected call: $*" >&2; exit 99 ;;
esac
FAKE
chmod +x "$work/bin/gh"
export FAKE_GH_CALLS="$work/gh-calls" PATH="$work/bin:$PATH"
[ "$(command -v gh)" = "$work/bin/gh" ] || { echo "fake gh is not first on PATH; refusing to call the real gh"; exit 1; }

section=$(awk '/^```markdown$/{f=1; next} f && /^```$/{exit} f' "$SKILL")
case "$section" in "## AI agents"*) ;; *) echo "cannot read the AI agents section from SKILL.md"; exit 1 ;; esac

mkrepo() { # mkrepo <name> <agents: none|plain|section> <guard: yes|no>: bare repo with a develop branch
  local name=$1 agents=$2 guard=$3 seed="$work/seed-$1"
  git init -q "$seed"
  ( cd "$seed" || exit 1
    echo "# $name" > README.md
    case "$agents" in
      plain) printf '# AGENTS.md\nBe careful.\n' > AGENTS.md ;;
      section) printf '# AGENTS.md\n\n%s\n' "$section" > AGENTS.md ;;
    esac
    [ "$guard" = yes ] && bash "$INSTALLER" --commit >/dev/null
    git add -A && git commit -qm seed )
  git clone -q --bare "$seed" "$work/remotes/paperplanehq/$name.git"
}
mkrepo plain plain no          # AGENTS.md without the section, no guard
mkrepo noagents none no        # no AGENTS.md
mkrepo finished section yes        # guard and section already there
mkrepo guardless section no    # section there, guard missing
# default branch is main; develop has an extra file. The guard must be built on develop.
git init -q -b main "$work/seed-twobranch"
( cd "$work/seed-twobranch" || exit 1
  echo main > README.md; git add -A; git commit -qm main
  git switch -qc develop; echo marker > ON_DEVELOP; git add -A; git commit -qm develop )
git clone -q --bare "$work/seed-twobranch" "$work/remotes/paperplanehq/twobranch.git"
git -C "$work/remotes/paperplanehq/twobranch.git" symbolic-ref HEAD refs/heads/main
remote_has_branch() { git -C "$work/remotes/paperplanehq/$1.git" rev-parse --verify -q refs/heads/chore/agent-guard >/dev/null; }

# (6) usage errors
expect "no repos is a usage error" 2 bash "$RG"
says   "no repos: says what is needed" 'need at least one owner/repo'
expect "unknown flag is a usage error" 2 bash "$RG" --force paperplanehq/plain
says   "unknown flag: named" 'unknown argument: --force'
expect "bare name without owner is a usage error" 2 bash "$RG" plain
expect "--help exits 0" 0 bash "$RG" --help
: > "$FAKE_GH_CALLS"

# (1) dry run: commit made in a temp clone, nothing pushed, no PR
expect "dry run on a repo with AGENTS.md succeeds" 0 bash "$RG" paperplanehq/plain
says   "dry run: names the repo" '^== paperplanehq/plain$'
says   "dry run: diff lists .claude/settings.json" '\.claude/settings\.json'
says   "dry run: diff lists the Claude guard" '\.claude/hooks/paperplane-guard\.sh'
says   "dry run: diff lists the omp guard" '\.omp/hooks/pre/paperplane-guard\.ts'
says   "dry run: diff lists AGENTS.md" 'AGENTS\.md'
says   "dry run: 4 files changed" '4 files? changed'
says   "dry run: says nothing was pushed" 'dry run: nothing pushed'
if remote_has_branch plain; then fail=$((fail+1)); echo "FAIL dry run: branch chore/agent-guard reached the remote"
else pass=$((pass+1)); echo "ok   dry run: nothing pushed to the remote"; fi
check  "dry run: gh was not called" "$(wc -l < "$FAKE_GH_CALLS" | tr -d ' ')" 0

# (5) AGENTS.md absent / present without the section / section present but guard missing
expect "no AGENTS.md: not created, 3 files" 0 bash "$RG" paperplanehq/noagents
says   "no AGENTS.md: 3 files changed" '3 files? changed'
lacks  "no AGENTS.md: AGENTS.md not in the diff" 'AGENTS\.md'
expect "section already present, guard missing: 3 files" 0 bash "$RG" paperplanehq/guardless
says   "section present: 3 files changed" '3 files? changed'
lacks  "section present: AGENTS.md left alone" 'AGENTS\.md'

# (3) already done: skipped, even with --apply
expect "repo with guard and section is skipped" 0 bash "$RG" --apply paperplanehq/finished
says   "skip: says so" 'already has the guard and section; skipped'
if remote_has_branch finished; then fail=$((fail+1)); echo "FAIL skip: a branch was pushed"
else pass=$((pass+1)); echo "ok   skip: nothing pushed"; fi
check  "skip: no PR opened" "$(grep -c '^pr create' "$FAKE_GH_CALLS")" 0

# (2) --apply: pushes chore/agent-guard, opens a draft PR into develop.
# -R and --head are required: the clone is single-branch, so gh cannot find the branch without them.
: > "$FAKE_GH_CALLS"
expect "--apply succeeds" 0 bash "$RG" --apply paperplanehq/plain
if remote_has_branch plain; then pass=$((pass+1)); echo "ok   --apply: branch chore/agent-guard pushed"
else fail=$((fail+1)); echo "FAIL --apply: branch chore/agent-guard not on the remote"; fi
check  "--apply: the pushed branch holds the guard commit" \
  "$(git -C "$work/remotes/paperplanehq/plain.git" ls-tree -r --name-only chore/agent-guard | grep -c -E '^(\.claude/settings\.json|\.claude/hooks/paperplane-guard\.sh|\.omp/hooks/pre/paperplane-guard\.ts|AGENTS\.md)$')" 4
check  "--apply: develop is untouched" \
  "$(git -C "$work/remotes/paperplanehq/plain.git" ls-tree -r --name-only develop | grep -c '^\.claude/')" 0
call=$(grep '^pr create' "$FAKE_GH_CALLS")
check  "--apply: exactly one gh pr create" "$(grep -c '^pr create' "$FAKE_GH_CALLS")" 1
callhas "--apply: gh pr create -R <repo>" "-R paperplanehq/plain"
callhas "--apply: gh pr create --head chore/agent-guard" "--head chore/agent-guard"
callhas "--apply: gh pr create --draft" "--draft"
callhas "--apply: gh pr create --base develop" "--base develop"

# the clone is of develop, not the remote default branch
expect "--apply on a repo whose default branch is main" 0 bash "$RG" --apply paperplanehq/twobranch
check  "--apply: branch is built on develop" \
  "$(git -C "$work/remotes/paperplanehq/twobranch.git" ls-tree -r --name-only chore/agent-guard | grep -c '^ON_DEVELOP$')" 1

# re-run after the branch was pushed: say the branch exists, not "write access?"
: > "$FAKE_GH_CALLS"
expect "--apply when chore/agent-guard is already on the remote exits 1" 1 bash "$RG" --apply paperplanehq/plain
says   "existing branch: says so" 'branch chore/agent-guard already exists on paperplanehq/plain'
lacks  "existing branch: no write-access guess" 'write access'
check  "existing branch: no PR opened" "$(grep -c '^pr create' "$FAKE_GH_CALLS")" 0

# (4) a repo that cannot be cloned: exit 1, the others still run
: > "$FAKE_GH_CALLS"
expect "unclonable repo exits 1" 1 bash "$RG" paperplanehq/missing paperplanehq/noagents
says   "unclonable: names the repo" 'cannot clone paperplanehq/missing \(develop\)'
says   "unclonable: next repo still runs" '^== paperplanehq/noagents$'
says   "unclonable: next repo still gets its diff" '3 files? changed'
expect "unclonable repo last also exits 1" 1 bash "$RG" paperplanehq/noagents paperplanehq/missing
says   "unclonable last: earlier repo was done" '3 files? changed'
check  "temp clones are removed" "$(find "$work/tmp" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')" 0

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
