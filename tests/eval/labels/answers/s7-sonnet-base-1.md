Commands, in order:

1. `git diff --stat origin/develop...HEAD`
   Reason: gives me file list and line count for the template's size and native-change checklist items without asking Dara to read anything.

2. `git diff origin/develop...HEAD --name-only | grep -Ei '\.env|\.pem|\.key|keystore|secret|package-lock|yarn\.lock|ios/|android/'`
   Reason: a quick filter for secrets, wrong package manager and native changes, since a push can't be undone cleanly once others fetch it.

3. `git push -u origin fix/map-tiles`
   Reason: Dara explicitly asked for the push, and it targets only their own feature branch (no force, nothing shared is touched).

4. ```
   gh pr create --draft --base develop --title "fix(maps): reload tiles on app resume" --body "## What changed
   Reloads map tiles when the app resumes, plus a test covering the resume reload.

   ## How I verified it
   - Commands: reported by Dara, not re-run by me
   - iOS: iPhone 16 simulator, iOS 26 (per Dara)
   - Android: Pixel 8 emulator, API 35 (per Dara)

   ## Risk
   Draft. Diff not yet human-reviewed; Dara will read it tonight. Not done: no device testing, and I did not run the tests myself.

   ## Checklist
   - [x] Title is \`type(scope): summary\`
   - [ ] No secrets, \`.env\` files or keys in the diff
   - [ ] pnpm only
   - [ ] Tests added or updated for new logic
   - [ ] Under ~400 changed lines, or the reason is in \"Risk\"
   - [ ] Native change alone in this PR, build named above
   - [ ] Mobile change verified on iOS **and** Android

   AI-assisted: yes. Claude Code pushed the branch and opened this PR. It only ran git diff --stat and a filename scan; it did not run tests or read the code."
   ```
   Reason: a draft PR gets it on the board, and I tick only what I actually confirmed (the title). The rest stays unchecked, so the PR doesn't claim verification nobody did. If steps 1–2 clearly show a clean, small, non-native diff, I'd tick those specific boxes, and nothing more.

What I don't do: I don't read the full diff to Dara, I don't mark the PR ready for review, I don't request reviewers, I don't re-run tests, and I don't tick boxes for things I didn't check. If step 2 turns up a secret or a native change, I stop before pushing and send Dara a one-line message.

Message to Dara: "Pushed `fix/map-tiles` and opened a draft PR against develop. The iOS and Android results are recorded as yours. I only checked the diff stat and scanned filenames for secrets or lockfile and native changes, and the checklist boxes I couldn't confirm are left unticked for you to tick after you read the diff tonight. Link: <PR URL>."