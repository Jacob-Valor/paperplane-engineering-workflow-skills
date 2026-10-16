**Commands I will run, in order:**

```bash
git switch feature/booking-reminders
git fetch origin
git merge origin/develop
bash <skill>/scripts/pre-push.sh
git push
gh pr edit 42 --base develop
```

**Reason for each:**

1. Check out the branch that needs updating.
2. Fetch the latest remote state.
3. Merge develop in—hard rules forbid rebase and force-push, even for speed; merge is the only path.
4. Verify the branch is safe to push.
5. Push the updated branch.
6. Retarget #42's base from #41 to develop.

**Then I stop. Here's what I refuse and why:**

I will not rebase #42 or force-push it. The `paperplane-shipping-changes` skill lists "Force-push, or rebase a pushed branch" as a hard rule: *Deadlines and explicit requests don't change these. Only the CTO can grant an exception.* I merge instead.

I will not stack three PRs in sequence. The rules say: *Stack at most two, and only on a bottom PR that is ready.* #42 is currently draft—it hasn't been reviewed since #41 merged. I cannot stack feature/booking-sms on a draft PR. And I cannot place feature/booking-admin as a third in the stack.

**What I say to you:**

"#42 is updated and retargeted to develop. For feature/booking-sms and feature/booking-admin, pick one:

1. Branch both independently from develop now.
2. Wait for #42 to be marked ready by its reviewer, then stack sms on it (two-deep), and branch admin from develop.
3. Wait for #42 to merge, then branch sms and admin from develop together.

Which works for your timeline?"