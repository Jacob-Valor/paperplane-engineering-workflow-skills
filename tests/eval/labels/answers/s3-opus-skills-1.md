**Three PRs, each branched from `develop`.** None is stacked, because they don't depend on each other. If the three fixes together exceed ~400 lines, I split them into one PR per bug.

**Setup (once per clone)**
```bash
git config --show-origin --get user.email   # confirm the commits are under your own identity
bash <skill>/hooks/install-git-hook.sh      # blocks pushes to develop/uat/main and runs the pre-push checks
```

**PR 1: QA fixes**
```bash
git switch develop && git pull && git switch -c fix/qa-date-picker-avatar-empty-state   # fresh base for the fixes
git add src/components/DatePicker.tsx src/components/AvatarCrop.tsx src/screens/EmptyState.tsx <tests>   # files by name, never -A
git commit -m "fix(ui): date picker, avatar crop and empty state qa bugs"   # one commit per bug if they're unrelated
bash <skill>/scripts/pre-push.sh && git push -u origin fix/qa-date-picker-avatar-empty-state   # scan before every push
gh pr create --draft --base develop --title "fix(ui): date picker, avatar crop and empty state qa bugs" --body-file pr-body.md
```
Risk: "Touches the date picker, avatar crop and empty-state screens only. Not done: the expo-camera plugin and the jest 30 bump, which are in separate PRs."

**PR 2: native change**
```bash
git switch develop && git switch -c chore/expo-camera-config-plugin   # native changes must ship alone
git add app.json package.json pnpm-lock.yaml   # added with `pnpm add expo-camera`, never npx
git commit -m "chore(native): add expo-camera config plugin"
bash <skill>/scripts/pre-push.sh && git push -u origin chore/expo-camera-config-plugin
gh pr create --draft --base develop --title "chore(native): add expo-camera config plugin" --body-file pr-body.md
```
Risk: "Native change. It needs a new dev-client and EAS build (<profile named>), and the current dev client won't load it. It adds camera permission strings to iOS and Android. Not done: the scan feature itself."

**PR 3: tooling bump**
```bash
git switch develop && git switch -c chore/jest-30   # a test-library major version ships alone
pnpm add -D jest@^30   # pnpm only, lockfile committed with it
git add package.json pnpm-lock.yaml <adjusted test config/snapshots>
git commit -m "chore(test): bump jest from 29 to 30"
bash <skill>/scripts/pre-push.sh && git push -u origin chore/jest-30
gh pr create --draft --base develop --title "chore(test): bump jest from 29 to 30" --body-file pr-body.md
```
Risk: "Major version bump, so test behaviour, snapshots and matchers may differ. CI and local test runs are the check. No app code changed."

On every PR I verify on iOS and Android with named devices, or write "not a mobile change" for the jest PR. Each one stays in draft with `AI-assisted: yes (Claude) — <what I ran>`.

**To the developer:**
"I opened three draft PRs instead of one: <URLs>. Paper Plane's rules require a native change (the `app.json` plugin) and a tooling bump (jest 30) to be their own PRs, and one 520-line PR would also exceed the ~400-line limit. A reviewer's preference can't override that; only Pay (CTO) can grant an exception. The upside is that each PR is small and quick to read. The fixes can merge without waiting for a new EAS build, and a jest failure won't block the QA fixes. Here is the full diff for each (`git diff origin/develop...HEAD`). Please review them, and I'll mark each one ready only after you tell me you've read it. Turning on auto-merge stays with you."