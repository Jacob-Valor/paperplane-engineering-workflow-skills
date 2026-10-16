Commands, in order:

1. `git config --show-origin --get user.email`: confirms the commits go out under Dara's own identity.
2. `git fetch origin && git switch feature/booking-export && git merge --ff-only origin/feature/booking-export`: gets the current branch tip without rebasing or rewriting anything.
3. (Edit the export handler to validate `from`/`to`, return 400 on a missing or invalid value, and add a test.) Then `pnpm test`: proves the crash is fixed before committing, and I report the real results.
4. `git add src/routes/bookings/export.ts src/routes/bookings/export.test.ts`: stages files by name, never `-A`, `.` or `-a`. (Paths are illustrative; I stage the actual files I touched.)
5. `git commit -m "fix(export): validate from and to query params"`: one logical change, with a conventional title under 72 characters.
6. `bash ~/.agents/skills/paperplane-shipping-changes/scripts/pre-push.sh`: runs the secret, lockfile and identity checks that are required before every push. If it exits 3 (no gitleaks), I read the full `git diff origin/develop...HEAD` first.
7. `git push`: a normal push to the feature branch, never forced.
8. `gh pr view 70 --json isDraft`: confirms the PR state so I don't mark anything ready.
9. `gh pr edit 70 --body-file pr-body.md`: updates Risk to say "Not done: CSV vs xlsx question and the `findForExport` rename (Sok's comments 2 and 3), deferred" and keeps every template heading.
10. `git diff HEAD~1`: shows the new commit so Dara can review it.

**To Dara:**

"I've fixed the missing `to` crash (comment 1) and pushed it to `feature/booking-export`. Tests: `<real result>`. The diff of the new commit is above.

I'm not running `gh pr ready` or touching the PR's ready state. Because this commit came after Sok's review, it needs your go-ahead once you've read the new diff.

Comments 2 and 3 can wait, but they can't stay unanswered. Please post these in Sok's threads today:
- Comment 2: 'Not in this PR: CSV vs xlsx needs a decision with Ops, since they asked for CSV. Follow-up: <link or plan>.'
- Comment 3: 'Not in this PR: the rename to `findBookingsForExport` will be a separate change. Follow-up: <link or plan>.'

I'd also reply on comment 1 with 'Fixed in `<sha>`'. I won't resolve any threads; that's for you and Sok. Auto-merge is yours to decide too."