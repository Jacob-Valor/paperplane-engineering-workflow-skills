**Three branches and PRs** — native changes and tooling bumps must ship separately.

**PR 1: Bug fixes**

```bash
git switch develop && git pull
git switch -c fix/qa-bugs
# Fix date picker, avatar crop, empty state bugs
git add <files>
git commit -m "fix(ui): date picker, avatar crop, empty state bugs"
bash <skill>/scripts/pre-push.sh
git push -u origin fix/qa-bugs
gh pr create --draft --base develop --title "fix(ui): date picker, avatar crop, empty state" --body-file pr-body.md
```

Start fresh from develop; create feature branch; commit bug fixes; check for secrets; push; draft PR to develop.

Risk: "Three bugs verified on iOS device and Android device. Not in this PR: expo-camera config plugin, jest upgrade."

**PR 2: Camera plugin (stacked on PR 1)**

```bash
git fetch origin
git switch -c feat/camera-plugin origin/fix/qa-bugs
git add app.json
git commit -m "feat(config): add expo-camera plugin for scan feature"
bash <skill>/scripts/pre-push.sh origin/fix/qa-bugs
git push -u origin feat/camera-plugin
gh pr create --draft --base fix/qa-bugs --title "feat(config): expo-camera plugin" --body-file pr-body.md
```

Create branch from PR 1's branch, not develop, to stack them; native config change alone; check against PR 1; base the PR on PR 1.

Risk: "expo-camera plugin added to app.json, tested with [dev-client or EAS build name]. Native change alone. Stacked on #1; merge #1 first."

**PR 3: Jest upgrade (after PR 1 merges)**

```bash
git fetch origin && git switch develop && git pull
git switch -c chore/jest-upgrade
# Upgrade jest 29→30, update affected tests
git add package.json test-files
git commit -m "chore(test): upgrade jest from 29 to 30"
bash <skill>/scripts/pre-push.sh
git push -u origin chore/jest-upgrade
gh pr create --draft --base develop --title "chore(test): jest 29→30" --body-file pr-body.md
```

Wait for PR 1 to merge; fresh develop; create tooling branch; upgrade and test; check and push; draft to develop.

Risk: "jest 29→30 upgrade, tests verified. Tooling bump alone per policy."

**To the developer:**

"I'm creating three separate branches and PRs, not one. The hard policy requires native configuration changes and tooling bumps to ship alone, separate from each other and from bug fixes. PR 1 and 2 stack—PR 2 branches from PR 1's branch. PR 3 waits for PR 1 to merge, because stacks can't exceed two. All three start as drafts and move to Ready only after you review the full diff."