#!/usr/bin/env bash
# Behaviour tests for the shipping skill's hooks. Run: bash tests/scripts/run.sh
set -u
here=$(cd "$(dirname "$0")/../.." && pwd)
H="$here/skills/paperplane-shipping-changes/hooks"
pass=0; fail=0
expect() { # expect <name> <wanted-exit> <cmd...>
  local name=$1 want=$2; shift 2
  "$@" >/tmp/pp-test-out.$$ 2>&1; local got=$?
  if [ "$got" -eq "$want" ]; then pass=$((pass+1)); echo "ok   $name"
  else fail=$((fail+1)); echo "FAIL $name: exit $got, wanted $want"; sed 's/^/     /' /tmp/pp-test-out.$$; fi
}
check() { # check <name> <test-expression...>
  local name=$1; shift
  if "$@"; then pass=$((pass+1)); echo "ok   $name"
  else fail=$((fail+1)); echo "FAIL $name"; fi
}
in_dir() { local d=$1; shift; (cd "$d" && "$@"); }

work=$(mktemp -d); trap 'rm -rf "$work" /tmp/pp-test-out.$$' EXIT
cd "$work" || exit 1

# Tools for the "no jq" runs: everything the scripts need except jq.
nojq="$work/nojq-bin"; mkdir "$nojq"
for c in python3 git mkdir mv cat rm dirname sed chmod; do ln -s "$(command -v "$c")" "$nojq/$c"; done

# ---------------------------------------------------------------- git hook
git init -q --bare origin.git
git clone -q origin.git repo 2>/dev/null
cd repo || exit 1
git config user.name "Test Dev"; git config user.email "dev@example.com"
git switch -qc develop
echo a > a; : > pnpm-lock.yaml; git add .; git commit -qm init; git push -q origin develop
git push -q origin develop:main

expect "git hook: install" 0 bash "$H/install-git-hook.sh"
check "git hook: installed with the skill dir" grep -q "PAPERPLANE_SKILL_DIR=.*paperplane-shipping-changes" .git/hooks/pre-push
expect "git hook: install twice" 0 bash "$H/install-git-hook.sh"
check "git hook: second install does not chain itself" test ! -e .git/hooks/pre-push.local

git switch -qc feature/x; echo b > b; git add b; git commit -qm "feat(x): b"
expect "git hook: feature push allowed" 0 git push -q -u origin feature/x
expect "git hook: push to develop blocked" 1 git push -q origin feature/x:develop
expect "git hook: push HEAD:main blocked" 1 git push -q origin HEAD:main
expect "git hook: delete of uat blocked" 1 git push -q origin :uat
expect "git hook: delete of main blocked" 1 git push -q origin --delete main

git commit -q --amend -m "feat(x): b2"
expect "git hook: force push of your own branch allowed by default (people may rebase)" 0 git push -q --force origin feature/x

expect "git hook: install --block-force-push" 0 bash "$H/install-git-hook.sh" --block-force-push
check "git hook: --block-force-push sets the clone option" test "$(git config --bool paperplane.blockForcePush)" = true
git commit -q --amend -m "feat(x): b3"
expect "git hook: force push blocked with --block-force-push" 1 git push -q --force origin feature/x
expect "git hook: +refspec blocked with --block-force-push" 1 git push -q origin +feature/x
git reset -q --hard origin/feature/x

git clone -q "$work/origin.git" "$work/other" 2>/dev/null
( cd "$work/other" && git config user.email o@example.com && git config user.name O &&
  git switch -q feature/x && echo c > c && git add c && git commit -qm "feat(x): c" && git push -q --no-verify origin feature/x )
echo d > d; git add d; git commit -qm "feat(x): d"
expect "git hook: force over unfetched commits blocked with --block-force-push" 1 git push -q --force origin feature/x
git fetch -q origin; git merge -q --no-edit origin/feature/x
expect "git hook: push after merge allowed" 0 git push -q origin feature/x

git tag prod-2026.10.13
expect "git hook: tag push allowed" 0 git push -q origin prod-2026.10.13

echo X=1 > .env.local; git add -f .env.local; git commit -qm env
expect "git hook: runs pre-push.sh on the current branch" 1 git push -q origin feature/x
git reset -q --hard HEAD~1

git switch -qc fix/other; echo e > e; git add e; git commit -qm "fix(o): e"; git switch -q feature/x
expect "git hook: other branch push allowed" 0 git push -q origin fix/other
if command -v gitleaks >/dev/null 2>&1; then
  git switch -qc fix/leak
  printf 'aws_secret_access_key = %s\n' "$(head -c 30 /dev/urandom | base64)" > k.ts
  git add k.ts; git commit -qm leak; git switch -q feature/x
  expect "git hook: secret on another branch blocked" 1 git push -q origin fix/leak
fi

# Chaining a foreign hook
expect "git hook: uninstall" 0 bash "$H/install-git-hook.sh" --uninstall
check "git hook: uninstall removes it" test ! -e .git/hooks/pre-push
check "git hook: uninstall unsets paperplane.blockForcePush" test -z "$(git config --get paperplane.blockForcePush)"
printf '#!/bin/sh\necho "foreign $1" >> "%s/foreign.log"; cat >> "%s/foreign.log"; exit "${FOREIGN_EXIT:-0}"\n' "$work" "$work" > .git/hooks/pre-push
chmod +x .git/hooks/pre-push
expect "git hook: install over a foreign hook" 0 bash "$H/install-git-hook.sh"
check "git hook: foreign hook moved to pre-push.local" grep -q foreign .git/hooks/pre-push.local
check "git hook: ours installed as pre-push" grep -qx '# paperplane-pre-push' .git/hooks/pre-push
expect "git hook: install again keeps the chain" 0 bash "$H/install-git-hook.sh"
check "git hook: chain intact after reinstall" grep -q foreign .git/hooks/pre-push.local
echo f > f; git add f; git commit -qm "feat(x): f"
expect "git hook: foreign hook failure blocks" 1 env FOREIGN_EXIT=1 git push -q origin feature/x
check "git hook: foreign hook got args and refs" grep -q "refs/heads/feature/x" "$work/foreign.log"
expect "git hook: foreign hook success allows" 0 git push -q origin feature/x
expect "git hook: uninstall with chain" 0 bash "$H/install-git-hook.sh" --uninstall
check "git hook: foreign hook restored" grep -q foreign .git/hooks/pre-push
check "git hook: pre-push.local gone" test ! -e .git/hooks/pre-push.local
rm -f .git/hooks/pre-push

git config core.hooksPath .githooks
expect "git hook: core.hooksPath install" 0 bash "$H/install-git-hook.sh"
check "git hook: written to core.hooksPath" grep -qx '# paperplane-pre-push' .githooks/pre-push
expect "git hook: core.hooksPath push to develop blocked" 1 git push -q origin feature/x:develop
git config --unset core.hooksPath
expect "git hook: install outside a repo" 2 in_dir "$work" bash "$H/install-git-hook.sh"

# ---------------------------------------------------------------- Claude guard
mkdir -p "$work/pnpm-repo" "$work/npm-repo"; : > "$work/pnpm-repo/pnpm-lock.yaml"
hook_json() { # hook_json <command> <cwd>
  local c=$1
  c=${c//\\/\\\\}; c=${c//\"/\\\"}
  printf '{"tool_name":"Bash","tool_input":{"command":"%s"},"cwd":"%s"}' "$c" "$2"
}
guard() { hook_json "$1" "$2" | bash "$H/claude-guard.sh"; }
guard_nojq() { hook_json "$1" "$2" | PATH="$nojq" "$BASH" "$H/claude-guard.sh"; }

blocked=(
  'gh pr merge 5'
  'gh pr merge 5 --squash --delete-branch'
  'gh pr merge --auto --squash 5'
  'gh pr review 5 --approve'
  'gh pr review 5 -a -b "lgtm"'
  'git push --force'
  'git push -f origin feature/x'
  'git push -uf origin feature/x'
  'git push --force-with-lease origin feature/x'
  'git push --force-with-lease=feature/x:abc origin feature/x'
  'git push --force-if-includes origin feature/x'
  'git push origin +feature/x'
  'git push origin develop'
  'git push origin HEAD:main'
  'git push origin :uat'
  'git push origin refs/heads/develop'
  'git push origin --delete main'
  'git push origin feature/x:refs/heads/uat'
  'git push origin prod-2026.10.13'
  'git push origin uat-2026.10.13'
  'git push origin refs/tags/prod-2026.10.13.2'
  'git push origin tag prod-2026.10.13'
  'git push --tags'
  'git push origin --tags'
  'gh release create prod-2026.10.13'
  'git push --no-verify'
  'git commit --no-verify -m "fix(x): y"'
  'git commit -nm "fix(x): y"'
  'git add -A'
  'git add --all'
  'git add .'
  'git commit -a -m "fix(x): y"'
  'git commit -am "fix(x): y"'
  'git commit --all -m "fix(x): y"'
  'gh repo edit --enable-auto-merge'
  'gh api -X PUT repos/paperplanehq/app/branches/main/protection'
  'gh api --method PATCH repos/paperplanehq/app'
  'gh api --method=delete repos/paperplanehq/app/rulesets/1'
  'gh api -XDELETE repos/paperplanehq/app/hooks/1'
  'pnpm test && git push origin develop'
  'git status; git push -f'
  'git log | tee x && git add -A'
  'cd app && git -C . push origin main'
  'GIT_TRACE=1 git push --force'
  'bash -c "git push origin main"'
  'echo $(gh pr merge 5)'
)
for c in "${blocked[@]}"; do expect "guard blocks: $c" 2 guard "$c" "$work/npm-repo"; done

allowed=(
  'gh pr create --draft --base develop'
  'gh pr ready 5'
  'git push -u origin feature/x'
  'git push'
  'git add src/a.ts'
  'git commit -m "fix(x): y"'
  'pnpm install'
  'git push origin fix/main-menu'
  'git push origin feature/develop-docs'
  'gh pr view 5 --json body'
  'git merge origin/develop'
  'git fetch origin develop'
  'git switch develop'
  'git commit -m "fix: stop using git add -A; never git push --force"'
  'gh pr review 5 --comment -b "looks good"'
  'gh api repos/paperplanehq/app/pulls/5'
  'gh api -X GET repos/paperplanehq/app'
  'git push origin feature/x 2>&1 | tail -5'
  'npm install'
  'npx prettier --check .'
  'yarn'
)
for c in "${allowed[@]}"; do expect "guard allows: $c" 0 guard "$c" "$work/npm-repo"; done

pnpm_blocked=('npm install' 'npm i lodash' 'npm ci' 'npm add zod' 'yarn' 'yarn add zod' 'yarn install' 'bun install' 'bun add zod' 'npx prettier --write src' 'pnpm build && npm install')
for c in "${pnpm_blocked[@]}"; do expect "guard blocks in pnpm repo: $c" 2 guard "$c" "$work/pnpm-repo"; done
pnpm_allowed=('pnpm install' 'pnpm add zod' 'pnpm dlx prettier --write src' 'npm run build' 'npm --version' 'yarn test' 'bun run dev')
for c in "${pnpm_allowed[@]}"; do expect "guard allows in pnpm repo: $c" 0 guard "$c" "$work/pnpm-repo"; done

expect "guard ignores other tools" 0 bash -c "printf '%s' '{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"git push --force\"}}' | bash '$H/claude-guard.sh'"
expect "guard reason on stderr" 0 bash -c "$(declare -f hook_json); hook_json 'gh pr merge 5' /tmp | bash '$H/claude-guard.sh' 2>&1 >/dev/null | grep -q '^paperplane guard: '"
expect "guard without jq blocks" 2 guard_nojq 'git push --force' "$work/npm-repo"
expect "guard without jq allows" 0 guard_nojq 'git push -u origin feature/x' "$work/npm-repo"
expect "guard without jq: pnpm rule" 2 guard_nojq 'npm install' "$work/pnpm-repo"
expect "guard: unreadable input is not a block" 1 bash -c "echo 'not json' | bash '$H/claude-guard.sh'"

# ---------------------------------------------------------------- Claude installer
home="$work/home"; mkdir -p "$home/.claude"
printf '{\n  "model": "opus",\n  "hooks": {\n    "PreToolUse": [\n      {"matcher": "Edit", "hooks": [{"type": "command", "command": "echo edit"}]}\n    ]\n  }\n}\n' > "$home/.claude/settings.json"
count() { grep -o 'claude-guard\.sh' "$1" 2>/dev/null | wc -l | tr -d ' '; }
expect "installer: --user" 0 env HOME="$home" bash "$H/install-claude-hook.sh" --user
expect "installer: --user again" 0 env HOME="$home" bash "$H/install-claude-hook.sh" --user
check "installer: one guard entry after two runs" test "$(count "$home/.claude/settings.json")" = 1
check "installer: other settings kept" grep -q '"model": "opus"' "$home/.claude/settings.json"
check "installer: other hooks kept" grep -q '"echo edit"' "$home/.claude/settings.json"
check "installer: entry matches Bash" grep -q '"matcher": "Bash"' "$home/.claude/settings.json"
expect "installer: installed command runs" 2 bash -c "$(declare -f hook_json); hook_json 'git push --force' /tmp | $(sed -n 's/.*"command": "\(bash .*claude-guard\.sh\)".*/\1/p' "$home/.claude/settings.json")"
expect "installer: --user --uninstall" 0 env HOME="$home" bash "$H/install-claude-hook.sh" --user --uninstall
check "installer: uninstall removes the guard" test "$(count "$home/.claude/settings.json")" = 0
check "installer: uninstall keeps other hooks" grep -q '"echo edit"' "$home/.claude/settings.json"
check "installer: uninstall keeps other settings" grep -q '"model": "opus"' "$home/.claude/settings.json"

proj="$work/repo"; cd "$proj" || exit 1
mkdir -p sub/dir .claude; printf '{"permissions": {"allow": ["Bash(pnpm test)"]}}\n' > .claude/settings.local.json
expect "installer: project default from a subdirectory" 0 in_dir sub/dir bash "$H/install-claude-hook.sh"
expect "installer: --project again" 0 bash "$H/install-claude-hook.sh" --project
check "installer: project one entry" test "$(count .claude/settings.local.json)" = 1
check "installer: project settings kept" grep -q 'Bash(pnpm test)' .claude/settings.local.json
expect "installer: project uninstall" 0 bash "$H/install-claude-hook.sh" --uninstall
check "installer: project entry removed" test "$(count .claude/settings.local.json)" = 0
check "installer: empty hooks dropped" test "$(grep -c '"hooks"' .claude/settings.local.json)" = 0

nh="$work/nojq-home"; mkdir -p "$nh"
expect "installer without jq: new file" 0 env HOME="$nh" PATH="$nojq" "$BASH" "$H/install-claude-hook.sh" --user
expect "installer without jq: again" 0 env HOME="$nh" PATH="$nojq" "$BASH" "$H/install-claude-hook.sh" --user
check "installer without jq: one entry" test "$(count "$nh/.claude/settings.json")" = 1
expect "installer without jq: uninstall" 0 env HOME="$nh" PATH="$nojq" "$BASH" "$H/install-claude-hook.sh" --user --uninstall
check "installer without jq: removed" test "$(count "$nh/.claude/settings.json")" = 0

echo '{ broken' > "$nh/.claude/settings.json"
expect "installer: broken JSON is left alone" 1 env HOME="$nh" bash "$H/install-claude-hook.sh" --user
check "installer: broken file unchanged" grep -qx '{ broken' "$nh/.claude/settings.json"
expect "installer: outside a repo without --user" 2 in_dir "$work" bash "$H/install-claude-hook.sh"
expect "installer: usage error" 2 bash "$H/install-claude-hook.sh" --bogus

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
