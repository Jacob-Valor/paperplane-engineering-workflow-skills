**Commands, in order**

1. `bash ~/.agents/skills/paperplane-reviewing-prs/scripts/gather.sh 58 paperplanehq/tripbuddy-app`
   This collects the state, body, checks, files, unresolved threads, stack and diff in one read-only pass.

2. `gh pr view 58 --repo paperplanehq/tripbuddy-app --json commits --jq '.commits[].authors[].login'`
   This confirms the commits are Dara's own, with only AI `Co-authored-by` entries.

3. `gh pr view 58 --repo paperplanehq/tripbuddy-app --comments`
   This shows what the two unresolved AI-comment threads actually say, so the report can address them.

4. `gh pr review 58 --repo paperplanehq/tripbuddy-app --comment --body-file review.md`
   This posts the report as a comment only, never an approval or merge.

**review.md**

```
Verdict: Changes needed
Reviewer eligibility: Sok may approve (not the author, not the prompter). Not me.
Blockers:
1. One concern — app.json adds the expo-notifications config plugin inside a
   feature PR — Move the app.json/plugin change into its own native PR that names
   the dev-client or EAS build that proved it. Stack this screen on top of it.
2. Risk — body says only "Low." — State what could break (e.g. notification
   permission prompt, scheduling on Android 13+) and what is NOT done.
3. Review threads — 2 unresolved threads from the AI review comment — Address
   each one, then resolve it. The ruleset blocks merge until both are resolved.
Non-blocking:
- Base feature/booking-api is fine: stacked on #57 (ready, base develop),
  depth 2. Merge #58 only after #57 lands.
- standard / AI review (advisory) is red with "OpenRouter 502". This is an
  infrastructure failure and never blocks; its existing comment was read.
- standard / checks and ci / check are green. 310 lines is under the size limit.
- iOS (iPhone 16 sim, iOS 26) and Android (Pixel 8 emulator, API 35) are named.
- AI-assisted names the tool (Claude Code) and what it ran (pnpm test). It would
  help to also say whether the agent ran pnpm check.
```

**To Sok:**
"Review is posted on #58. The verdict is Changes needed, with three blockers: the `app.json` notifications plugin needs its own native PR, Risk needs real content, and two review threads are still open. The red AI review is an OpenRouter 502 and doesn't count. You're an eligible approver once Dara fixes these, and #58 should merge after #57."

**To Dara:**
"Thanks, the screen itself looks clean. Please split the `expo-notifications` plugin and `app.json` change into a separate native PR with the build that proved it. Then expand Risk to cover what could break and what isn't done, and resolve the two AI review threads. After that, Sok can take another look."