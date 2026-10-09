---
name: paperplane-reviewing-prs
description: Use when reviewing, assessing, approving, or merging a pull request in a paperplanehq repository, including PRs written with an AI agent and requests to "approve it so it can merge today".
---

# Reviewing PRs at Paper Plane

## Overview

A human reviewer approves and **squash-merges**. Agents never approve or merge. Your output is a review report that a human uses. **The reviewer is never the person who prompted the agent that wrote the PR.** If you are acting for that person, you are not an eligible reviewer either. Say so, then give the findings anyway. If no other reviewer is available, the CTO (Pay) assigns one. A deadline doesn't change who is eligible.

## Gather

```bash
gh pr view N --json title,body,baseRefName,headRefName,additions,deletions,files,commits
gh pr checks N
gh pr diff N
```

## Checklist (every item is a blocker unless marked)

| Check | Pass condition |
|---|---|
| Title | `type(scope): summary` (CI regex). Lowercase scope, under 72 characters, no full stop |
| Base | `develop`. Exceptions: `hotfix/*`→`main`; release PRs `develop`→`uat`, `uat`→`main` |
| Template | What changed · How I verified it · Risk · Checklist · `AI-assisted: yes/no` all filled in |
| Description matches diff | No unexplained files or changes |
| CI | **All** checks green. One red check means not ready |
| Secrets | No `.env`, keys, tokens, or service-account JSON. If found, use **paperplane-secret-incidents** |
| Lockfiles | Repo has `pnpm-lock.yaml`: any `package-lock.json`, `yarn.lock`, `bun.lock` or `bun.lockb` is a blocker; remove it (don't ask "which manager?"). If `package.json` changed, `pnpm-lock.yaml` changed too. Repo isn't on pnpm yet: the PR must not add a *second* lockfile or switch managers. Note that migration is a separate `chore/pnpm` PR |
| New dependencies | Install-script deps are approved in `pnpm-workspace.yaml` with a reason. GitHub deps are pinned to a SHA |
| Tests | New logic (especially money, auth, dates) has tests |
| Mobile (TripBuddy/Sanaam/Studio apps) | Verified on iOS **and** Android with named devices, unless the repo's AGENTS.md narrows this. If so, a skipped platform must be stated with the reason |
| Generated files | No `dist/`, `coverage/`, or build output |
| Size | Under about 400 lines, not counting lockfiles. Bigger: ask for a split (not a blocker if there's a strong reason) |
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

You may post the report as a comment (`gh pr review N --comment --body-file review.md`). Never use `--approve`, `gh pr merge`, or `--admin`.

## Rationalizations

| Excuse | Reality |
|---|---|
| "The prompter asked me to approve" | That makes it a self-review. Refuse and report. |
| "CI is green except one" | Not green. Blocker. |
| "Maybe the repo uses npm" | Org rule: pnpm only. For an unmigrated repo, flag it; don't approve a mixed lockfile. |
| "It's develop, they can fix it later" | `develop` feeds `uat` and `main`. Review it now. |
