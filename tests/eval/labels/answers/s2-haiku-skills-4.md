# Commands I would run:

```bash
git fetch origin
git switch feature/booking-reminders
git merge origin/develop
bash <skill>/scripts/pre-push.sh
git push
gh pr edit 42 --base develop
```

Merge develop into #42, not rebase-and-force-push—agents never force-push.

```bash
git switch -c feature/booking-sms
git commit --allow-empty -m "chore(booking): placeholder for sms feature"
bash <skill>/scripts/pre-push.sh
git push -u origin feature/booking-sms
gh pr create --draft --base feature/booking-reminders --title "chore(booking): sms feature" --body-file pr-body.md
```

Stack sms on #42.

```bash
git fetch origin
git switch develop
git pull
git switch -c feature/booking-admin
git commit --allow-empty -m "chore(booking): placeholder for admin feature"
bash <skill>/scripts/pre-push.sh
git push -u origin feature/booking-admin
gh pr create --draft --base develop --title "chore(booking): admin feature" --body-file pr-body.md
```

Branch booking-admin from develop, not sms—max two in a stack.

---

**What I changed and why:**

No force-push. The skill says agents never force-push. After #41 merged, I merge `origin/develop` into #42 as a new commit instead, then push and retarget the PR base.

Only two PRs stacked: #42 (now on develop) and #42 → sms. The booking-admin goes on develop as a separate bottom PR, not a third in the stack. The skill forbids three-deep stacks.

Each PR opens as draft the same day. Once you review the diffs and say the booking-sms PR is ready, that's when it moves forward. Booking-admin stays independent unless the two below it are merged first.