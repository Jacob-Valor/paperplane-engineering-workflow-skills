#!/usr/bin/env bash
# Behaviour tests for the shipping skill's scripts. Run: bash tests/scripts/run.sh
set -u
here=$(cd "$(dirname "$0")/../.." && pwd)
S="$here/skills/paperplane-shipping-changes/scripts"
pass=0; fail=0
expect() { # expect <name> <wanted-exit> <cmd...>
  local name=$1 want=$2; shift 2
  "$@" >/tmp/pp-test-out.$$ 2>&1; local got=$?
  if [ "$got" -eq "$want" ]; then pass=$((pass+1)); echo "ok   $name"
  else fail=$((fail+1)); echo "FAIL $name: exit $got, wanted $want"; sed 's/^/     /' /tmp/pp-test-out.$$; fi
}

work=$(mktemp -d); trap 'rm -rf "$work" /tmp/pp-test-out.$$' EXIT
cd "$work" || exit 1
git init -q --bare origin.git
git clone -q origin.git repo 2>/dev/null
cd repo || exit 1
git config user.name "Test Dev"; git config user.email "dev@example.com"
git switch -qc develop
echo a > a; : > pnpm-lock.yaml; git add .; git commit -qm init; git push -q origin develop

if command -v gitleaks >/dev/null 2>&1; then clean=0; else clean=3; fi

# pre-push.sh
expect "pre-push blocks on develop" 1 bash "$S/pre-push.sh"
git switch -qc fix/x; echo b > b; git add b; git commit -qm "fix(x): b"
expect "pre-push passes a clean branch" "$clean" bash "$S/pre-push.sh"
echo '{}' > package-lock.json; git add package-lock.json; git commit -qm lock
expect "pre-push blocks a second lockfile" 1 bash "$S/pre-push.sh"
git reset -q --hard HEAD~1
echo X=1 > .env.local; git add -f .env.local; git commit -qm env
expect "pre-push blocks a .env file" 1 bash "$S/pre-push.sh"
git reset -q --hard HEAD~1
echo X= > .env.example; git add .env.example; git commit -qm example
expect "pre-push allows .env.example" "$clean" bash "$S/pre-push.sh"
mkdir dist; echo x > dist/a.js; git add -f dist; git commit -qm dist
expect "pre-push blocks build output" 1 bash "$S/pre-push.sh"
git reset -q --hard HEAD~1
echo X=1 > .env; git add -f .env; git commit -qm env; git rm -q .env; git commit -qm "rm env"
expect "pre-push blocks a .env added then removed" 1 bash "$S/pre-push.sh"
git reset -q --hard HEAD~2
git switch -q develop; mkdir dist; echo x > dist/old.js; echo '{}' > package-lock.json
git add -f dist package-lock.json; git commit -qm "old junk"; git push -q origin develop
git switch -qc chore/cleanup; git rm -rq dist package-lock.json; git commit -qm "chore(repo): remove junk"
expect "pre-push allows deleting a lockfile and build output" "$clean" bash "$S/pre-push.sh"
git switch -q fix/x
if command -v gitleaks >/dev/null 2>&1; then
  printf 'aws_secret_access_key = %s\n' "$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 40)" > k.ts
  git add k.ts; git commit -qm leak
  expect "pre-push blocks a secret" 1 bash "$S/pre-push.sh"
  git reset -q --hard HEAD~1
fi
expect "pre-push exits 3 without gitleaks" 3 env PATH=/usr/bin:/bin bash "$S/pre-push.sh"

# check-pr-body.sh
cat > good.md <<'EOF'
## What changed
Fix OTP timeout.

## How I verified it
- Commands: pnpm test (42 passed)
- iOS: iPhone 16 sim, iOS 26
- Android: Pixel 8 emulator, API 35

## Risk
OTP flow on slow networks. Not done: resend copy.

## Checklist
- [x] Title is `type(scope): summary`

AI-assisted: yes (Claude Code) — ran pnpm test
EOF
sed -e 's/^- Android: .*/- Android:/' good.md > no-android.md
sed -e 's/^AI-assisted: .*/AI-assisted: yes \/ no/' good.md > placeholder.md
awk '/^## Risk/{print; getline; print ""; next} {print}' good.md > no-risk.md
expect "body: complete, app repo" 0 bash "$S/check-pr-body.sh" --mobile good.md
expect "body: empty Android line, app repo" 1 bash "$S/check-pr-body.sh" --mobile no-android.md
expect "body: empty Android line, backend repo" 0 bash "$S/check-pr-body.sh" --no-mobile no-android.md
expect "body: AI-assisted placeholder" 1 bash "$S/check-pr-body.sh" --no-mobile placeholder.md
expect "body: empty Risk" 1 bash "$S/check-pr-body.sh" --no-mobile no-risk.md
mkdir -p .github/workflows; printf 'jobs:\n  standard:\n    with:\n      mobile: true\n' > .github/workflows/standard.yml
expect "body: app repo detected from standard.yml" 1 bash "$S/check-pr-body.sh" no-android.md
expect "body: usage error" 2 bash "$S/check-pr-body.sh"

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
