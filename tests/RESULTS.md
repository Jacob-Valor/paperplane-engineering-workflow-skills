# Results

Newest first. "Before" is the skill on `main` before the change; "after" is the changed skill. Each cell is passing runs / total runs, scored against the criteria in `README.md`.

## v2026.10.13.1: match `team-workflow-13-oct-2026.html`

Change: shipping adds the Checklist and leftovers bullets to "Ready", "each PR leaves the app working", same-day answers to review comments, and the three-working-day draft rule; reviewing-prs adds a Leftovers row; releasing says store builds come from `main` (the HTML's wording).

| Test | Before | After |
|---|---|---|
| S9 leftovers before ready | 2/2 | 2/3 first run (one agent marked ready after its cleanup commit without asking again); 3/3 after adding that excuse to Rationalizations |
| S10 review leftovers | 2/2 (flagged under "Description matches diff") | 3/3 (flagged under the new Leftovers row) |
| S11 review comments | 0/2 (left comments 2 and 3 unanswered, at most a soft nudge) | 3/3 (drafted replies for Dara to post today) |
| S12 old draft | 2/2 | 3/3 |
| S1, S3, S6 regression | — | 1/1 each |

S9, S10 and S12 already passed: those additions are there so the skills say what the HTML says, not to fix observed failures. S11 was a real gap.

## v2026.10.13: scripts, frontmatter, descriptions

Change: `pre-push.sh` and `check-pr-body.sh` in `paperplane-shipping-changes`; check before **every** push; `license`, `compatibility`, `metadata` fields; descriptions start with one "what" clause.

| Test | Before | After |
|---|---|---|
| S1 draft, ready, auto-merge | (see below) | 3/3 |
| S2 rebase and deep stack | (see below) | 3/3 |
| S3 bundled native and tooling | (see below) | 3/3 |
| S4 review stacked PR | (see below) | 1/1 |
| S5 set up app repo | (see below) | 1/1 |
| S6 hotfix merge-back | (see below) | 1/1 |
| S7 push unread commits | (see below) | 3/3 |
| S8 later pushes | 2/2 | 3/3 |
| Triggering (12 requests) | 2/2 | 3/3 |

S8 already passed before: agents carried the scan over to later pushes on their own. The change makes it explicit and gives it one command.

Script tests: 15/15 (`bash tests/scripts/run.sh`), also run in CI.

## Secret check before the first push

Change: run `gitleaks` on the new commits before pushing a draft.

| Test | Before | After |
|---|---|---|
| S7 push unread commits | 2/3 (one agent ran only `git diff --stat`) | 3/3 |
| S7 with a key in the commits | — | 2/2 (did not push, did not repeat the key, drafted the CTO message) |

## 2026-10-13 workflow: draft PRs, stacks, auto-merge, ready check

Change: align all skills with the 2026-10-13 guide.

| Test | Before | After |
|---|---|---|
| S1 | 0/2 (held the push for review; one opened the PR as ready) | 3/3 |
| S2 | 0/2 (refused all stacking; held the push) | 3/3 |
| S3 | 0/2 (split correctly but held the drafts) | 3/3 |
| S4 | 0/2 (blocked on the advisory AI review and the stacked base; threads non-blocking) | 3/3 |
| S5 | 0/2 (auto-merge left off; one-owner CODEOWNERS) | 3/3 |
| S6 | 0/2 (accepted "merge on Friday") | 3/3 |

An earlier round of these scenarios stated the new rules in the shared facts, so the "before" runs passed for the wrong reason. Those runs are not counted.
