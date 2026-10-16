**I won't rebase or force-push #42.** Agents never rewrite a pushed branch. Merging `develop` in gives the same result without force-pushing.

**Commands, in order**

1. `git config --show-origin --get user.email` confirms the commits will carry your identity.
2. `git switch feature/booking-reminders && git fetch origin` brings in the squash-merged #41.
3. `git merge origin/develop` brings #42 up to date with a new commit and no history rewrite. Because #41 was squash-merged, conflicts in the booking-api files are likely. I'd resolve them in favour of `develop`.
4. `pnpm install --frozen-lockfile && pnpm lint && pnpm test`, or whatever scripts the repo's `AGENTS.md` lists. This checks the merged result works, and I report the real results.
5. `bash <skill>/scripts/pre-push.sh` runs the required scan before every push.
6. `git push` is a normal push with no `--force`.
7. `gh pr view 42 --json baseRefName`, then `gh pr edit 42 --base develop` if GitHub didn't retarget it. The bottom PR now targets `develop`.
8. `git diff origin/develop...HEAD` shows you #42's full diff to review.

**booking-sms (allowed, as the second PR in a two-PR stack)**

9. `git switch -c feature/booking-sms` from `feature/booking-reminders` stacks it on #42. A stack of two is allowed, but only once #42 is ready, i.e. after you've reviewed its diff.
10. `git add <files by name>`, then `git commit -m "feat(booking): send sms booking reminders"`, `bash <skill>/scripts/pre-push.sh`, and `git push -u origin feature/booking-sms`.
11. `gh pr create --draft --base feature/booking-reminders --title "feat(booking): send sms booking reminders" --body-file pr-body.md` opens the draft. Its Risk section says "stacked on #42, merge #42 first" and the body includes `AI-assisted: yes (Claude)`.

**booking-admin: not stacked on sms**

Stacking it on sms would make a third PR in the stack, which isn't allowed. I'll do one of these instead:
- If admin doesn't depend on sms or reminders: `git switch develop && git pull && git switch -c feature/booking-admin` and open a separate draft PR into `develop` now.
- If it does depend on them: wait until #42 merges, then branch it from the sms branch, which will then be a two-PR stack again.

**What I'd tell you**

> "#42 is updated by merging `develop` into it, with no rebase or force-push. Agents never rewrite pushed branches, and the PR squash-merges anyway, so history ends up identical. The PR URL is below; please review the full diff. Once you say it's good, I'll mark #42 ready.
>
> booking-sms is a draft stacked on #42, and its Risk section says to merge #42 first.
>
> I didn't stack booking-admin on sms because that would be three deep, which our rules don't allow. Does admin depend on sms? If not, I'll branch it from `develop` now. If it does, I'll start it once #42 merges. Only Pay can make an exception to the stack limit.
>
> All PRs stay draft. Merging and auto-merge are yours to do."