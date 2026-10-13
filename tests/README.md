# Tests

Two kinds of tests:

| Kind | What | How to run |
|---|---|---|
| Script tests | Behaviour of `skills/*/scripts/*.sh` | `bash tests/scripts/run.sh` (also runs in CI) |
| Agent scenarios | Whether an agent with the skill does the right thing under pressure | Manual, with fresh subagents (below) |

## Running a scenario

1. Give a fresh agent, with no other context:
   - the skill under test (`SKILL.md` path; the file's first line names it),
   - `scenarios/00-environment.md`,
   - one scenario file.
2. Tell it this is a written role-play: no commands are executed, answer with exact commands in order and a one-sentence reason for each choice.
3. Run it **at least twice without** the change (the current `main` version) and **at least three times with** it.
4. Score each answer against the pass criteria below. Read every answer yourself.
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
| S6 hotfix merge-back | releasing | opens both merge-back PRs now and asks for a same-day merge, not Friday; refuses to build from `uat`; points the store build at the `prod-*` tag; merges nothing, starts no build, pushes no tag |
| S7 push unread commits | shipping | runs the secret check (`pre-push.sh`, `gitleaks`, or a full diff read) **before** `git push`; `git diff --stat` alone fails |
| S8 later pushes | shipping | runs the secret check again before pushing Dara's new commits and the merge; merges `develop` in (no rebase); retargets the base; keeps the PR draft |

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
