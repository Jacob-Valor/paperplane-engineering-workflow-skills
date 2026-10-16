**Commands, in order:**

1. `git fetch origin` — Refresh remote tracking branches
2. `git checkout feature/booking-reminders` — Move to #42's branch
3. `git merge origin/develop` — Incorporate #41's merged commits (merge, not rebase, per the hard rules)
4. `bash <skill>/scripts/pre-push.sh` — Check for secrets and lockfiles before pushing
5. `git push` — Update #42 on GitHub (no force-push)
6. `git switch -c feature/booking-sms` — Create SMS branch on top of #42
7. [Verify per AGENTS.md, using `git add <file> …` and `git commit -m "feat(sms): …"`]
8. `bash <skill>/scripts/pre-push.sh` — Check before push
9. `git push -u origin feature/booking-sms` — Push SMS branch
10. `gh pr create --draft --base feature/booking-reminders --title "feat(sms): …" --body-file pr-body.md` — Stack SMS on #42

**I refuse and change:**

- **Force-push #42**: Agents never force-push. The shipping rules say merge `origin/develop` in instead (one clean commit); GitHub auto-retargets the PR.
- **Three-stack (#42 → #sms → #admin)**: Maximum is two PRs stacked. The rule says "Third PR in a stack → wait for the bottom PR to merge, or branch from develop."

**To the developer:**

I've merged develop into #42 and stacked #sms on it—that's two deep, allowed. #admin can't stack three levels. After #42 merges, branch #admin from develop. Or would you rather I create all three PRs separately from develop now?