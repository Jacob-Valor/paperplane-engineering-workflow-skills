---
name: paperplane-shipping-changes
description: Use when making any code, config, or dependency change in a paperplanehq repository — creating a branch, committing, adding or updating packages, pushing, opening, stacking, or marking a pull request ready — and especially when asked to push straight to develop/uat/main, "just commit everything", turn on auto-merge, bundle unrelated changes, or skip the PR because of a deadline.
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

**A fast PR is the fast path.** "Demo in 10 minutes" means branch, commit, push, draft PR. The demo runs from the branch. If it can't wait for review, that's the CTO's call.

## Workflow

1. **Identity**: `git config --show-origin --get user.email` is the human's own. Someone else's in `.git/config`: stop and tell the user.
2. **Branch** from fresh `develop`: `git switch develop && git pull && git switch -c <feature|fix|chore>/<topic>`. Uncommitted work on `develop`: `git switch -c fix/<topic>` carries it. Hotfix → **paperplane-releasing**.
3. **Verify** with the scripts in AGENTS.md. App repos (TripBuddy, Sanaam, Studio): iOS **and** Android, devices named. Report real results.
4. **Commit** one logical change as `type(scope): summary`: type `feat|fix|chore|docs|refactor|perf|test|build|ci|revert`, lowercase scope, under 72 characters, no full stop. "Fixed OTP" becomes `fix(auth): otp resend waits for the cooldown`.
5. **Draft PR the same day**. A pushed secret is leaked, and nobody has read the diff yet, so scan first:
   ```bash
   git fetch origin
   gitleaks git --no-banner --redact --log-opts="origin/develop..HEAD"   # exit 1: don't push → paperplane-secret-incidents
   git push -u origin <branch>
   gh pr create --draft --base develop --title "<type(scope): summary>" --body-file pr-body.md
   ```
   No `gitleaks` installed: read the full `git diff origin/develop...HEAD` for keys before pushing. Body = the repo's `.github/pull_request_template.md`, every heading kept, `- Commands:`/`- iOS:`/`- Android:` lines kept (CI reads them).
6. **Hand over**: show the full diff (`git diff origin/develop...HEAD`) and the PR URL. End your turn.
7. **Ready**: only after the human says they reviewed the diff, and only when the body is complete:
   - How I verified it: commands and real results; iOS and Android devices, or `not a mobile change`. An untested platform keeps it draft.
   - Risk: what could break **and what is not done**. Over ~400 changed lines (lockfiles excluded): `Size: <reason>`, or split.
   - `AI-assisted: yes (<tool>) — <what you ran>`. The `yes / no` placeholder fails CI.

   Then `gh pr ready <N>`, report the URL, stop. The reviewer is never the person who prompted you.

## Scope and stacks

- One concern per PR, under ~400 changed lines. **Native change** (config plugin, `app.json`, `patches/`, `ios/`, `android/`, permissions) alone, with the dev-client or EAS build named. **Tooling bump** (test library major, package manager, CI) alone.
- Stack at most **two**; the bottom PR is ready. The upper PR's base is the bottom branch; its Risk says "stacked on #N, merge #N first".
- After the bottom PR merges: `git fetch origin && git merge origin/develop`, verify, `git push`, then `gh pr edit <N> --base develop` if GitHub didn't retarget.

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