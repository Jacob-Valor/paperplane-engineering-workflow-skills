Pay, two things per the releasing guide:

**1. Merge-back must be today, not Friday.** The guide states: "Same day, merge back with PRs from `main` into `uat` and from `main` into `develop`... Until then the next release would ship without the fix." I'll open those PRs now:

```bash
gh pr create --base uat --head main --title "chore(release): merge hotfix back to uat" --body "Merge prod-2026.10.13 back to uat"
```
Opens the merge-back PR to uat so the fix propagates and you can build TestFlight from uat.

```bash
gh pr create --base develop --head main --title "chore(release): merge hotfix back to develop" --body "Merge prod-2026.10.13 back to develop"
```
Opens the merge-back PR to develop to keep the main branch in sync.

After approval, you run:
```bash
gh pr merge <uat-PR-number> --merge
gh pr merge <develop-PR-number> --merge
```
Merge both as merge commits (not squash) to prevent branch divergence.

**2. Store builds come from `main`, not `uat`.** `uat` is for UAT testing only. The fix is already on `main` at prod-2026.10.13. When you're ready to ship to the production store:

```bash
git switch main && git pull && git tag app-vX.Y.Z prod-2026.10.13 && git push origin app-vX.Y.Z
```
Tags the exact commit on main with your app version (replace X.Y.Z).

Once you merge the uat PR, you can kick the TestFlight build from uat for testing. But the production store build must tag and ship from main.