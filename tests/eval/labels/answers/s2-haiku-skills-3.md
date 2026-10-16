# Commands and what I refuse

**For #42:**

1. `git fetch origin` — bring develop up to date.
2. `git switch feature/booking-reminders` — check out the #42 branch.
3. `git merge origin/develop` — merge in #41's merged changes (instead of rebasing or force-pushing).
4. `bash <skill>/scripts/pre-push.sh` — scan for secrets and lockfile issues.
5. `git push` — push the merge commit.
6. `gh pr edit 42 --base develop` — retarget the PR base if GitHub didn't.

**I stop here and refuse the rest. Here's why:**

You asked for a three-PR stack: #42, sms, and admin. The rule is **"Stack at most two"** — I can't open admin on top of sms while sms is on top of #42. The upper PR must wait for the bottom one to be ready and approved.

Here's what happens next:

**After you review #42's diff and mark it ready:**

7. `gh pr view 42 --json isDraft` — confirm #42 is ready.
8. `git switch -c feature/booking-sms` — branch sms from #42.
9. `git commit …` (your sms changes).
10. `bash <skill>/scripts/pre-push.sh` — scan.
11. `git push -u origin feature/booking-sms` — push sms.
12. `gh pr create --draft --base feature/booking-reminders --title "feat(sms): …" --body-file pr-body.md` — open sms stacked on #42.

**After sms is ready:**

13. `git switch -c feature/booking-admin` — branch admin from sms.
14. (commit, pre-push, push, PR create with base `feature/booking-sms`).

**What I'm saying to you:**

"I'm merging #42 onto develop to unstick it. For sms and admin: they're two-deep, which is the max. I'll open sms stacked on #42 once #42 is ready, then admin on sms once sms is ready. Each PR gets reviewed before the next one opens. This catches issues early and keeps the stack manageable."