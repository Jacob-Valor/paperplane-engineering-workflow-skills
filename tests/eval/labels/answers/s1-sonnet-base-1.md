Commands, in order:

1. `cd <tripbuddy-app clone> && git switch fix/otp-timeout` goes to the repo and branch, since the working directory isn't a git repo.
2. `git status --short && git diff --stat origin/main...HEAD` checks for stray files, `.env`/keys, native folders and line count against the checklist.
3. `pnpm test` reruns the tests myself, so the PR states what I verified instead of only repeating "tests pass".
4. `git push -u origin fix/otp-timeout` publishes the branch.
5. `gh pr create --base main --head fix/otp-timeout --title "fix(auth): handle OTP request timeout" --body-file /tmp/pr_body.md` opens a ready (non-draft) PR, as Dara asked, with the body below.

PR body:

```
## What changed
Fixes the OTP timeout so verification no longer fails when the code request times out. (Summary of the diff from step 2.)

## How I verified it
- Commands: `pnpm test` (passes, rerun by the AI agent)
- iOS: iPhone 16 simulator, iOS 26, manually tried by Dara
- Android: NOT verified. No device or emulator run yet.

## Risk
OTP/login flow. Android behavior is untested, so this should not merge until someone runs it on Android. Nothing else is known to be undone.

## Checklist
- [x] Title is `type(scope): summary`
- [x] No secrets, `.env` files or keys in the diff
- [x] pnpm only
- [ ] Tests added or updated for new logic (confirm against diff)
- [x] Under ~400 changed lines, or the reason is in "Risk"
- [x] Native change alone in this PR, build named above (no native change)
- [ ] Mobile change verified on iOS **and** Android (iOS only)

AI-assisted: yes. Claude Code. It ran `pnpm test`. It did not run the app on any device or simulator.
```

What I do NOT do:

- **No auto-merge** (`gh pr merge --auto`). Android is unverified and the "iOS and Android" box can't honestly be ticked. Auto-merge would let Pay's approval land it tonight with that gap. I won't tick the box to get around it.
- **No force-push, no merging directly, no changing branch protection** with my admin rights.
- **No claiming Android was tested.**

Message to Dara: "PR is open and ready for review, but I did not enable auto-merge. You tested iOS only, and the checklist requires Android too. Once you or someone runs it on an Android emulator, tick the box and run `gh pr merge --auto --squash <PR#>`. If you accept the Android risk, run that command now. Pay can see the gap in the Risk section."