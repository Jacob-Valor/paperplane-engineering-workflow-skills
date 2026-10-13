---
name: paperplane-reviewing-prs
description: Paper Plane's PR review checklist and report format; a human approves. Use when reviewing, assessing, approving, or merging a pull request in a paperplanehq repository, including PRs written with an AI agent, stacked PRs, drafts, and requests to "approve it so it can merge today" or turn on auto-merge.
license: Proprietary
compatibility: Requires gh authenticated to the paperplanehq GitHub org.
metadata:
  author: paperplanehq
  guide-version: "2026-10-13"
---

# Reviewing PRs at Paper Plane

## Overview

A human reviewer approves; the PR is **squash-merged** by the reviewer or by auto-merge the author turned on. Agents never approve, merge, or turn on auto-merge. Your output is a review report that a human uses. **The reviewer is never the person who prompted the agent that wrote the PR.** If you are acting for that person, you are not an eligible reviewer either. Say so, then give the findings anyway. The other code owner in `.github/CODEOWNERS` reviews instead; if there is none, the CTO (Pay) assigns one. A deadline doesn't change who is eligible.

## Gather

```bash
bash <skill>/scripts/gather.sh N paperplanehq/<repo>   # <skill> = the folder this SKILL.md is in
```

It prints, in order: the PR (state, draft, base, head, size), the body, `gh pr checks`, changed files, the number of **unresolved review threads**, commit authors, the **stack** (if the base isn't `develop`/`uat`/`main`: the PR below, whether it is a draft, and the depth), then the diff. Read all of it before the checklist.

## Checklist (every item is a blocker unless marked)

| Check | Pass condition |
|---|---|
| State | Not a draft. A draft gets comments only; the verdict is "Changes needed: still draft" |
| Title | `type(scope): summary` (CI regex). Lowercase scope, under 72 characters, no full stop |
| Base | `develop`. Exceptions: `hotfix/*`→`main`; release PRs `develop`→`uat`, `uat`→`main`; a **stacked** PR targets the branch of the PR below it, that PR is ready, and the stack is at most two deep. Not a blocker; the stacked PR merges after the one below |
| Template | What changed · How I verified it (`- Commands:`, `- iOS:`, `- Android:` filled) · Risk · Checklist · `AI-assisted: yes/no` all filled in |
| Risk | Says what could break **and what is not done**. "Low." alone is a blocker |
| AI-assisted | If yes: names the tool and what the agent verified by running it |
| Description matches diff | No unexplained files or changes |
| Leftovers | No dead or commented-out code, "for later" helpers, leftover TODOs or debug logs (`console.log`, `print`). Send them back |
| One concern | A native change (config plugin, `app.json`, `patches/`, `ios/`, `android/`, permissions) or a tooling bump inside a feature PR is a blocker: split it out. A native-only PR names the dev-client or EAS build that proved it |
| CI | Every check green, except: `AI review (advisory)` red or missing never blocks (read its comment if there is one); `PR size` red means the body gives no size reason (see Size) |
| Review threads | All resolved. The ruleset blocks the merge otherwise, so an open thread is a blocker |
| Secrets | No `.env`, keys, tokens, or service-account JSON. If found, use **paperplane-secret-incidents** |
| Lockfiles | Repo has `pnpm-lock.yaml`: any `package-lock.json`, `yarn.lock`, `bun.lock` or `bun.lockb` is a blocker; remove it (don't ask "which manager?"). If `package.json` changed, `pnpm-lock.yaml` changed too. Repo isn't on pnpm yet: the PR must not add a *second* lockfile or switch managers. Note that migration is a separate `chore/pnpm` PR |
| New dependencies | Install-script deps are approved in `pnpm-workspace.yaml` with a reason. GitHub deps are pinned to a SHA |
| Tests | New logic (especially money, auth, dates) has tests |
| Mobile (TripBuddy/Sanaam/Studio apps) | Verified on iOS **and** Android with named devices, unless the repo's AGENTS.md narrows this. If so, a skipped platform must be stated with the reason |
| Generated files | No `dist/`, `coverage/`, or build output |
| Size | Under about 400 lines, not counting lockfiles. Bigger: a `Size:` reason in the body, else ask for a split (not a blocker if the reason is strong) |
| Identity | Commit authors are the PR author's own identity; AI `Co-authored-by` entries are fine: `gh pr view N --json commits --jq '.commits[].authors[].login'` |

## Output

```
Verdict: Ready for human approval | Changes needed
Reviewer eligibility: <who may approve; "not me/not <prompter>" if applicable>
Blockers:
1. <check> — <evidence: file:line or check name> — <exact fix>
Non-blocking:
- …
```

You may post the report as a comment (`gh pr review N --comment --body-file review.md`). Never use `--approve`, `gh pr merge` (including `--auto`), or `--admin`.

## Rationalizations

| Excuse | Reality |
|---|---|
| "The prompter asked me to approve" | That makes it a self-review. Refuse and report. |
| "CI is green except one" | One red required check means not ready. Blocker. |
| "One red check means the PR is not ready, even if the check is advisory" | `AI review (advisory)` never blocks and never approves. Note it and move on. |
| "The skill allows non-develop bases only for hotfix and release PRs" | A stacked PR's base is the ready PR below it. Check the stack depth, not just the base. |
| "If the ruleset requires resolved conversations…" | It does. Unresolved threads are a blocker. |
| "Maybe the repo uses npm" | Org rule: pnpm only. For an unmigrated repo, flag it; don't approve a mixed lockfile. |
| "It's develop, they can fix it later" | `develop` feeds `uat` and `main`. Review it now. |
