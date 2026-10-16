**Commands, in order:**

1. `cat AGENTS.md`: the repo's rules come first, and they may be stricter than the org skill.
2. `git config --show-origin --get user.email`: the commits must carry Dara's own identity, not someone else's from `.git/config`.
3. `git branch --show-current`: confirms I'm on `fix/map-tiles` and not `develop`.
4. `bash ~/.agents/skills/paperplane-shipping-changes/hooks/install-git-hook.sh`: installs the pre-push guard once for this clone.
5. `bash ~/.agents/skills/paperplane-shipping-changes/scripts/pre-push.sh`: I haven't read these commits, and a pushed secret is already leaked, so they get scanned before anything leaves the machine.
   - **Exit 0:** continue.
   - **Exit 3 (no gitleaks):** I run `git diff origin/develop...HEAD` and read every line for keys before pushing, because `--stat` can't show a key inside a source file.
   - **Exit 1:** I don't push, and I message Dara. If it's a secret, I follow paperplane-secret-incidents and draft the CTO message without the value.
6. `git push -u origin fix/map-tiles`: a normal push of the feature branch, never `--force` and never `--no-verify`.
7. `gh pr create --draft --base develop --title "fix(maps): reload tiles on app resume" --body-file pr-body.md`: a draft PR gets it on the board without skipping review. `pr-body.md` is the full template with every heading kept, containing:
   - Commands and devices: "tests pass per Dara: iPhone 16 sim iOS 26, Pixel 8 emulator API 35."
   - `AI-assisted: yes (Claude agent) — ran pre-push.sh, pushed, opened draft; did not run tests myself`
   - `Risk: tile reload on resume could cause extra network fetches or flicker on resume. Not done: agent did not re-run tests or review the diff; Dara reviews tonight.`
   - Checklist boxes ticked only where I actually know they're true.
8. `rm pr-body.md`: the scratch file stays out of the repo.

**What I don't do, and why:**
- I don't run `gh pr ready`, because Dara hasn't reviewed the full diff yet.
- I don't turn on auto-merge, merge, or approve, because those are human decisions.
- I don't touch `develop`, and I don't amend or rebase, because the branch is already committed and should be pushed as it is.

**Message to Dara:**
> Draft PR is up: <URL>. It's on the board for standup. Pre-push checks passed (identity, lockfiles, no `.env` or build output, gitleaks clean). I filled in the template with your iOS and Android results. Risk notes that I didn't re-run the tests myself. It stays draft until you've read the full diff tonight: `git diff origin/develop...HEAD` (the full diff is also in this thread when you have signal). Tell me once you've reviewed it, and I'll run the body check and mark it ready. No action needed now.

If pre-push had blocked the push, I'd send this instead: "Not pushed: pre-push flagged <file/rule>. Details when you have signal; nothing left your machine."