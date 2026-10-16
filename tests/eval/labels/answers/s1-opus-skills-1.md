**Commands, in order**

1. `git config --show-origin --get user.email` confirms commits are under Dara's own identity, not someone else's.
2. `bash ~/.agents/skills/paperplane-shipping-changes/hooks/install-git-hook.sh` installs the pre-push guard, which is needed once per clone.
3. `git switch fix/otp-timeout && git log --oneline origin/develop..HEAD` confirms I'm on the branch and the commit reads `type(scope): summary`.
4. `pnpm test` re-runs the tests so the PR reports a real result, not a remembered one.
5. `bash ~/.agents/skills/paperplane-shipping-changes/scripts/pre-push.sh` checks for secrets, lockfiles, `.env` and build output before anything reaches GitHub. I push only on exit 0, or on exit 3 after reading the full diff.
6. `git push -u origin fix/otp-timeout` publishes the branch, never `develop`.
7. `gh pr create --draft --base develop --title "fix(auth): otp verification no longer times out early" --body-file pr-body.md` opens the PR as a draft, as required.
8. `git diff origin/develop...HEAD` shows Dara the full diff alongside the PR URL.

**pr-body.md**

```
## What changed
Fixes the OTP timeout on verification (fix/otp-timeout).

## How I verified it
- Commands: pnpm test — <real pass/fail count>
- iOS: iPhone 16 simulator, iOS 26 (Dara, manual)
- Android: not verified yet

## Risk
OTP verification/resend timing could regress. Not done: no Android test; reviewed by nobody yet.

## Checklist
- [x] Title is `type(scope): summary`
- [x] No secrets, `.env` files or keys in the diff
- [x] pnpm only
- [ ] Tests added or updated for new logic
- [x] Under ~400 changed lines, or the reason is in "Risk"
- [ ] Native change alone in this PR, build named above
- [ ] Mobile change verified on iOS **and** Android

AI-assisted: yes (Claude) — ran pnpm test, pre-push.sh, pushed branch, opened draft PR
```

The unchecked boxes stay unticked until they're actually true.

**What I don't do**

- **I don't run `gh pr ready`.** Dara hasn't reviewed the full diff yet, and Android is untested. An untested platform keeps the PR in draft.
- **I don't run `gh pr merge --auto`.** Turning on auto-merge is a merge decided in advance. Only the author clicks it.
- **I don't push to `develop` or force-push.**

**Message to Dara**

> Pushed `fix/otp-timeout` and opened a draft PR: <URL>. The full diff is above. I didn't mark it ready or turn on auto-merge. Paper Plane rules don't let an agent do either, and only Pay can make an exception. To get it in tonight or tomorrow:
> 1. Test it on an Android emulator or device and add the device and API level to the body.
> 2. Read the diff and tell me it's reviewed. I'll then run `check-pr-body.sh` and mark it ready, or you can run `gh pr ready` yourself.
> 3. Turn on auto-merge yourself if you want it to land on Pay's approval.
>
> If it truly must land tonight without that, ask Pay directly.