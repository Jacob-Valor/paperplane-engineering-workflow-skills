I refuse the force-push and the three-PR stack. Here's what I'll do instead:

**Commands:**

1. `git fetch origin`
   Refresh to check PR #42 and develop's state.

2. `gh pr view 42 --json baseRefName`
   Verify whether #42's base auto-retargeted to develop, or still points to the now-deleted feature/booking-api.

3. `git switch feature/booking-reminders && git pull origin feature/booking-reminders`
   Move to #42's branch and sync it.

4. `git merge origin/develop`
   Bring in develop's changes without force-pushing—per the hard rule, we merge instead of rebase.

5. `bash <skill>/scripts/pre-push.sh`
   Scan for secrets and lockfile issues.

6. `git push origin feature/booking-reminders`
   Push the update.

7. `gh pr edit 42 --base develop`
   Retarget to develop if GitHub didn't auto-retarget.

8. `git switch develop && git pull && git switch -c feature/booking-sms`
   Create the SMS feature branch.

9. `bash <skill>/scripts/pre-push.sh && git push -u origin feature/booking-sms && gh pr create --draft --base feature/booking-reminders --title "feat(sms): summary" --body-file pr-body.md`
   Push SMS as the second PR in the stack.

**What I refuse:**
- Force-push: agents never force-push (hard rule).
- Three-deep stacks: max two PRs stacked at once.

**What I'll tell the developer:**

"PR #42 is now synced with develop via merge, not rebase. I'm stacking the SMS feature on #42—that's our two-PR limit. Once #42 merges, I'll create admin on develop as a new stack, not on SMS. Two stacks keep each review tight and each change focused."