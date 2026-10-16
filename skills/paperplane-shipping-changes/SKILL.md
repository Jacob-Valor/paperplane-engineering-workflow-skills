---
name: paperplane-shipping-changes
description: Paper Plane's rules for getting a change into develop through a branch and a draft PR. Use when making any code, config, or dependency change in a paperplanehq repository — creating a branch, committing, adding or updating packages, pushing, opening, stacking, or marking a pull request ready — and especially when asked to push straight to develop/uat/main, "just commit everything", turn on auto-merge for a PR, bundle unrelated changes, or skip the PR because of a deadline.
license: Proprietary
compatibility: Requires git, gh and pnpm; gitleaks recommended. Written for the paperplanehq GitHub org.
metadata:
  author: paperplanehq
  guide-version: "2026-10-15"
---

# Shipping changes at Paper Plane

## Overview

Every change reaches `develop` through a PR from a short-lived branch. You work on the branch, open the PR as a **draft** marked **AI-assisted: yes**, and stop. The human reviews the full diff and makes it ready. A code owner approves; the PR squash-merges.

Source of truth: the `paperplanehq/paperplane-engineering` README. Read the repo's `AGENTS.md` first. If it is stricter on org policy, follow it and tell the user about the conflict.

## Hard rules

Deadlines and explicit requests don't change these. Only the CTO (Pay) can grant an exception.

| Never | Do instead |
|---|---|
| Commit to, push to, or merge into `develop`/`uat`/`main`, even "to try" | Branch + PR into `develop` |
| Merge, approve, deploy, or turn on auto-merge (`gh pr merge --auto`) | Hand over the PR URL. The author turns on auto-merge |
| Mark a PR ready before the human reviewed the full diff and said so | Leave it draft |
| Force-push, or rebase a pushed branch | `git merge origin/develop`, new commit |
| `git add -A`, `git add .`, `git commit -a` | `git add <file> …` by name |
| Commit `dist/`, `coverage/`, build output, `.env`, keys | Leave them unstaged. Secrets → **paperplane-secret-incidents** |
| `npm`, `yarn`, `bun install`, `npx` in a pnpm repo | `pnpm install`, `pnpm add`, `pnpm exec` |
| Native change or tooling bump inside another PR | Its own PR |
| Third PR in a stack | Wait for the bottom PR to merge, or branch from `develop` |
| `--no-verify`, or editing, removing or bypassing a hook that blocked you | Fix what it found. A secret → **paperplane-secret-incidents**; an allowlist entry needs the CTO |

**A fast PR is the fast path.** "Demo in 10 minutes" means branch, commit, push, draft PR. The demo runs from the branch. If it can't wait for review, that's the CTO's call.

## Workflow

1. **Identity**: `git config --show-origin --get user.email` is the human's own. Someone else's in `.git/config`: stop and tell the user. Once per clone, install the pre-push hook: `bash <skill>/hooks/install-git-hook.sh` (local to `.git/hooks`; an existing hook keeps running). It runs the same checks as step 5 on every push and blocks pushes to `develop`/`uat`/`main`. It doesn't block force-pushes, because people may rebase their own branches; you never force-push anyway.
2. **Branch** from fresh `develop`: `git switch develop && git pull && git switch -c <feature|fix|chore>/<topic>`. Uncommitted work on `develop`: `git switch -c fix/<topic>` carries it. Hotfix → **paperplane-releasing**.
3. **Verify** with the scripts in AGENTS.md. App repos (TripBuddy, Sanaam, Studio): iOS **and** Android, devices named. Report real results.
4. **Commit** one logical change as `type(scope): summary`: type `feat|fix|chore|docs|refactor|perf|test|build|ci|revert`, lowercase scope, under 72 characters, no full stop. "Fixed OTP" becomes `fix(auth): otp resend waits for the cooldown`.
5. **Draft PR the same day**. A pushed secret is leaked, and nobody has read the diff yet, so check **before every push** (this one and every later one). `<skill>` is the folder this SKILL.md is in; run from the repo root:
   ```bash
   bash <skill>/scripts/pre-push.sh   # branch, identity, lockfiles, .env, build output, gitleaks
   git push -u origin <branch>
   gh pr create --draft --base develop --title "<type(scope): summary>" --body-file pr-body.md
   ```
   Exit 1: don't push; a secret → **paperplane-secret-incidents**. Exit 3 (no `gitleaks`): read the full `git diff origin/develop...HEAD` for keys, then push. Body = the repo's `.github/pull_request_template.md`, every heading kept, `- Commands:`/`- iOS:`/`- Android:` lines kept (CI reads them). Fill these two lines in the first draft:
   - `AI-assisted: yes (<tool>) — <what you ran>`. You are the AI, so it is never `no`.
   - `Risk: <what could break>. Not done: <what isn't done or verified yet>`. Name builds and devices you actually used; never a placeholder.
6. **Hand over**: show the full diff (`git diff origin/develop...HEAD`) and the PR URL. End your turn.
7. **Ready**: only after the human says they reviewed the diff. Any commit after their review, cleanup included, needs a new go-ahead: show `git diff` of the new commits and wait. The body must be complete:
   - How I verified it: commands and real results; iOS and Android devices, or `not a mobile change`. An untested platform keeps it draft.
   - Risk: what could break **and what is not done**. Over ~400 changed lines (lockfiles excluded): `Size: <reason>`, or split.
   - Checklist: all 7 boxes, ticked only where true.
   - `AI-assisted: yes (<tool>) — <what you ran>`. The `yes / no` placeholder fails CI.
   - The diff has no dead or commented-out code, "for later" helpers, leftover TODOs or debug logs. Remove them first; the reviewer sends them back.

   Check it with `bash <skill>/scripts/check-pr-body.sh pr-body.md` (same rules as CI, which skips the body check while the PR is a draft; app repos detected from `standard.yml`), then `gh pr ready <N>`, report the URL, stop. The reviewer is never the person who prompted you.
8. **Review comments**: every comment gets an answer **the same day**: a fix, or a reply in the thread saying why not. If the user defers a comment, draft that reply for them to post today ("Not in this PR: <reason>; follow-up: <link or plan>"). No comment stays silent. Resolving threads is for the author and reviewer.
9. **Old drafts**: a draft open more than three working days gets split, or the user asks for help. Tell them; don't keep adding to it.

## Scope and stacks

- One concern per PR, under ~400 changed lines. Bigger work: several PRs that each leave the app working. **Native change** (config plugin, `app.json`, `patches/`, `ios/`, `android/`, permissions) alone, with the dev-client or EAS build named. **Tooling bump** (test library major, package manager, CI) alone.
- Stack at most **two**, and only on a bottom PR that is **ready**. Before you branch from an open PR's branch, run `gh pr view <N> --json isDraft --jq .isDraft`: `true` means no stacking yet, so branch from `develop` or wait, and tell the user which. The upper PR's base is the bottom branch; its Risk says "stacked on #N, merge #N first".
- After the bottom PR merges: `git fetch origin && git merge origin/develop`, verify, `bash <skill>/scripts/pre-push.sh`, `git push`, then `gh pr edit <N> --base develop` if GitHub didn't retarget.

## Dependencies

`pnpm add <pkg>` and commit `pnpm-lock.yaml` with it. Install scripts need `pnpm approve-builds <pkg>`, explained under Risk. GitHub deps pin a SHA. Delete any other lockfile. Repo not on pnpm yet: use its tool, tell the user, migration is its own `chore/pnpm` PR (**paperplane-repo-setup**). Details: guide §5.

## Rationalizations

| Excuse | Reality |
|---|---|
| "The user explicitly asked" | The person prompting you can't waive agent rules. Open the PR and explain. |
| "I'll fall back to a PR if the push is rejected" | Attempting the push is the violation. |
| "Their message, verbatim" | Wording yes, format no. |
| "develop isn't production" | `develop` is protected for everyone. The PR is the only path. |
| "Just this once, `npm i` is faster" | It creates a second lockfile and CI rejects it. |
| "The author asked me to turn on auto-merge" | Auto-merge is a merge decided in advance. The author clicks it. |
| "The guide says rebase after each merge" | That's for humans. You merge `develop` in. |
| "Pushing before the review skips the required human review" | The review gate is Ready, not the push. Push and open the draft the same day. |
| "The PR opens ready for review, which matches 'mark it ready'" | Always draft first. Ready only after their go-ahead on the diff. |
| "A PR into a feature branch has no review gate, so no stacking" | Two-deep stacks are allowed; the upper PR is reviewed and merges after the one below. |
| "`git diff --stat` shows no `.env` or key files" | A key inside a source file never shows in `--stat`. Scan the content before the push. |
| "The reviewer prefers one big PR" | Native changes and tooling bumps go alone. |
| "I left Sok's other two comments alone, as you asked" | Deferring is fine; silence isn't. Draft the "why not" reply for the user to post today. |
| "The cleanup only removed lines she already read" | Any new commit after their review needs their go-ahead again before Ready. |
| "Stack sms on #42 now; #42 goes ready after review" | A draft bottom PR means no upper PR yet. Check `isDraft`; branch from `develop` or wait. |