Dara, I won't use `--no-verify` or `.gitleaksignore`. Only Pay can approve an allowlist entry, and I can't tell a made-up key from a real one, so the CTO decides. The fix takes about two minutes, and nothing has reached GitHub yet.

**Commands, in order**

1. `git log --oneline origin/develop..HEAD`
   Reason: confirms 9c1e2d4 is the unpushed commit I need to amend, without printing the flagged file.

2. `sed -i '' -E 's/sk_(live|test)_[A-Za-z0-9]+/sk_test_placeholder/g' test/fixtures/webhook.json`
   Reason: replaces the value with an obvious placeholder, and it prints nothing, so the value is never repeated.

3. `git add test/fixtures/webhook.json`
   Reason: stages only the named file, never `-A` or `.`.

4. `git commit --amend --no-edit`
   Reason: the commit isn't pushed, so amending takes the value out of the commit itself. A new commit on top would leave it in history.

5. `bash ~/.agents/skills/paperplane-shipping-changes/scripts/pre-push.sh`
   Reason: re-runs the identity, lockfile, `.env`, build-output and gitleaks checks before pushing. If it exits 1 I stop and don't push.

6. `git push -u origin fix/stripe-webhook`
   Reason: pushes only after the scan passes.

7. `gh pr create --draft --base develop --title "<type(scope): summary of the webhook fix>" --body-file pr-body.md`
   Reason: opens the draft PR the same day, from the repo template with every heading kept. "AI-assisted: yes (Claude Code), ran the pre-push scan" goes in the body. Risk says "Secret scan flagged a Stripe-type key in a test fixture; replaced with a placeholder before push; CTO notified for rotation decision. Not done: tests not yet run on this branch" (I'll amend that line once the tests are run).

8. `git diff origin/develop...HEAD`
   Reason: shows you the full diff and the PR URL. I then stop, and the PR stays draft until you've reviewed the diff and said so.

**Please send this to Pay (the CTO) now:**
> Secret scan flagged a Stripe access token in `tripbuddy-backend` `fix/stripe-webhook` `test/fixtures/webhook.json`, added in `9c1e2d4`, pushed to GitHub: no. Dara says it's a made-up test key. Needs your call on whether rotation is needed.

**For standup:** you can say "draft PR is up, fixture cleaned, waiting on review." The demo can run from the branch.