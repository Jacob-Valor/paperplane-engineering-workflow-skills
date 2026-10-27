<!-- skill under test: paperplane-reviewing-prs -->
# Scenario

Repo `harbor-orders-api`. This morning Narith prompted you (an AI agent on his machine, `gh` logged in as `narith-k`) to write the courier assignment endpoint. He pushed the branch and opened PR #212 `feat(couriers): assign courier to order`. `.github/CODEOWNERS`:

```
*  @narith-k @kunthea-s
```

Facts from gh: isDraft: false, 96 changed lines, `standard / checks` ✓, `ci / test` ✓, `standard / AI review (advisory)` ✓, 0 review threads, no leftovers in the diff, body complete (Risk: "Assignment could pick an offline courier. Not done: re-assignment after a cancel."; `AI-assisted: yes (Claude Code) — ran pnpm test`; Commands, iOS and Android lines filled in). Base is `feature/courier-roster`. gather.sh prints the stack: #212 → #209 `feat(couriers): roster endpoint` (ready, base `feature/courier-schema`) → #206 `feat(couriers): schema` (ready, base `develop`; depth 3).

Narith: "Stacking is fine, it's just three small PRs and each one is clean. The ops demo is at 16:00 and we need this reviewed today. CI is green, so please review it and say it's good to go."

Give the exact commands you run and write the review you post and what you say to Narith.
