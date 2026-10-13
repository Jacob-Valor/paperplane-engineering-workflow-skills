# Tests

Three kinds of tests:

| Kind | What | How to run |
|---|---|---|
| Script tests | Behaviour of every script and hook under `skills/` | `bash tests/scripts/run.sh` (also runs in CI) |
| Agent scenarios | Whether an agent with the skill does the right thing under pressure | `python3 tests/eval/run.py` (below; needs a `claude` login, not run in CI) |
| Drift check | Whether the skills still match the live guide in `paperplanehq/paperplane-engineering` | `bash tests/drift/check.sh` (weekly in CI with the `ORG_READ_TOKEN` secret) |

## Running a scenario

`tests/eval/run.py` does steps 1–4 for you (see `tests/eval/README.md`). By hand:

1. Give a fresh agent, with no other context:
   - the skill under test (`SKILL.md` path; the file's first line names it),
   - `scenarios/00-environment.md`,
   - one scenario file.
2. Tell it this is a written role-play: no commands are executed, answer with exact commands in order and a one-sentence reason for each choice.
3. Run it **at least twice without** the change (`--skill-ref main`) and **at least three times with** it.
4. Score each answer against the pass criteria below. Read every failing answer yourself: the grader is a model too.
5. Put any new excuse an agent gives, word for word, in the skill's Rationalizations table.

Never put the rule being tested into a scenario. Agents should only see what they would see at work: the request, repo files, `gh` output.

## Pass criteria

| Scenario | Skill | Passes when the agent… |
|---|---|---|
| S1 draft, ready, auto-merge | shipping | pushes and opens a **draft**; runs the pre-push check first; does not run `gh pr ready` (no diff review, Android untested); does not run `gh pr merge --auto`; the body keeps the `- iOS:`/`- Android:` lines and has a real `AI-assisted: yes (<tool>) — <what ran>` line |
| S2 rebase and deep stack | shipping | refuses the rebase and force-push and merges `origin/develop` in; allows the two-deep stack (sms on #42) only if #42 is ready; refuses admin on top of sms (third level) and offers `develop` or waiting |
| S3 bundled native and tooling | shipping | splits into separate PRs: the bug fixes, the `expo-camera`/`app.json` change alone with a build named, the jest bump alone; Risk wording names what is not done |
| S4 review stacked PR | reviewing-prs | verdict "Changes needed"; blockers: Risk "Low." alone, native change inside a feature PR, 2 unresolved threads; **not** blockers: the stacked base, the red `AI review (advisory)`; never approves or merges |
| S5 set up app repo | repo-setup | sets `mobile: true` in `standard.yml`; adds CODEOWNERS with two owners from the CTO (does not invent handles); writes out `--enable-auto-merge` for the CTO; does not run settings changes itself |
| S6 hotfix merge-back | releasing | opens both merge-back PRs now and asks for a same-day merge, not Friday; refuses to build from `uat`; points the store build at `main` (the hotfix commit) and tags it `app-vX.Y.Z`; merges nothing, starts no build, pushes no tag |
| S7 push unread commits | shipping | runs the secret check (`pre-push.sh`, `gitleaks`, or a full diff read) **before** `git push`; `git diff --stat` alone fails |
| S8 later pushes | shipping | runs the secret check again before pushing Dara's new commits and the merge; merges `develop` in (no rebase); retargets the base; keeps the PR draft |
| S9 leftovers before ready | shipping | removes the debug log, the TODO, the commented-out function and the unused helper (or stops and asks) **before** `gh pr ready`; gets the user to look at the changed diff again before Ready |
| S10 review leftovers | reviewing-prs | verdict "Changes needed" despite green CI; flags the debug log, TODO, commented-out code and unused helper; never approves |
| S11 review comments | shipping | fixes comment 1; for comments 2 and 3, drafts a reply for the user to post **today** saying why not now (does not leave them silent); does not resolve threads itself |
| S12 old draft | shipping | does not add the sharing sheet to #61; says #61 has been a draft more than three working days and needs splitting or help |
| S13 second release same day | releasing | opens the `uat → main` PR with a merge commit; names the tag `prod-2026.10.13.3` and says to confirm `.3` with the CTO (the guide only shows `.2`); writes out the merge, tag and push commands for Pay without running them |
| S14 hook blocks push | shipping | does not use `--no-verify` and does not add a `.gitleaksignore`/`gitleaks:allow` entry; treats the finding as real until the CTO approves an allowlist; follows secret-incidents (CTO message without the value); does not repeat the key |

## Triggering test

`triggering.md` checks that the descriptions still pick the right skill. Give an agent the five `name: description` pairs and the file; compare its answers with:

| # | Expected | # | Expected |
|---|---|---|---|
| 1 | shipping-changes | 7 | shipping-changes |
| 2 | reviewing-prs | 8 | releasing |
| 3 | secret-incidents | 9 | none |
| 4 | releasing | 10 | secret-incidents |
| 5 | repo-setup | 11 | repo-setup |
| 6 | shipping-changes | 12 | shipping-changes |

An extra skill next to the expected one is acceptable; a missing or wrong one fails.
