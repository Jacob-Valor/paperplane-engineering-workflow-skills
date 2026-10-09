---
name: paperplane-shipping-changes
description: Use when making any code, config, or dependency change in a paperplanehq repository — creating a branch, committing, adding or updating packages, pushing, or opening a pull request — and especially when asked to push straight to develop/uat/main, "just commit everything", or skip the PR because of a deadline.
---

# Shipping changes at Paper Plane

## Overview

Every change reaches `develop` through a PR from a short-lived branch. You, the agent, work on that branch, open the PR marked **AI-assisted: yes**, and stop. A human reviews and merges.

Source of truth: `paperplanehq/paperplane-engineering` README. Read the repo's `AGENTS.md` first; it adds repo commands and may be stricter. If it conflicts with the guide on org policy (pnpm, branch flow), follow the stricter rule and tell the user about the conflict.

## Hard rules

Deadlines and explicit requests do not change these. The user can ask the CTO (Pay) for an exception; you cannot grant one.

| Never | Do instead |
|---|---|
| Commit to, push to, merge into, or promote `develop`/`uat`/`main` | Branch + PR into `develop` |
| Try a direct push "in case it works" | Don't push it at all. Rejection isn't the only control: the rule applies to you |
| Merge or approve any PR, or deploy | Hand the PR URL to the user |
| Force-push (any branch) | New commit; if history must be rewritten, the human does it |
| `git add -A`, `git add .`, `git commit -a` | `git status`, then `git add <file> …` by name |
| Commit `dist/`, `coverage/`, build output, `.env`, keys | Leave them unstaged; don't delete them. Secrets → **paperplane-secret-incidents** |
| `npm install`, `yarn`, `bun install`, `npx` in a pnpm repo | `pnpm install`, `pnpm add`, `pnpm exec`, `pnpm test` |

**A fast PR is the fast path.** "Demo in 10 minutes" means branch, commit, show the user the diff, push, and open the PR. That takes a few minutes. It does not mean pushing to `develop`. The demo runs from the branch. If the demo can't wait for review, that's the CTO's decision.

## Workflow

1. **Identity.** `git config user.name` and `git config user.email` must be the human's own. If `git config --show-origin --get user.email` points at `.git/config` with someone else's identity, stop and tell the user.
2. **Branch.** `git switch develop && git pull && git switch -c <type>/<topic>`. Type is `feature`, `fix` or `chore` (`docs` if the repo's AGENTS.md lists it). Already have uncommitted work on `develop`? Run `git switch -c fix/<topic>`, which carries the changes over. For `hotfix/*`, see **paperplane-releasing**.
3. **Verify** with the repo's own scripts (`pnpm test`, `pnpm lint`, or whatever AGENTS.md lists) before you commit. For mobile (TripBuddy, Sanaam, Studio apps), test iOS **and** Android unless the repo's AGENTS.md narrows that rule, and name the devices or simulators you used. Report the real results, even under time pressure.
4. **Commit**: one logical change, `type(scope): summary`.
   - type: `feat` (user-visible), `fix`, `chore` (tooling, deps, config, e.g. `chore(deps): add sharp`), `docs`, `refactor`, `perf`, `test`, `build`, `ci`, `revert`
   - scope in lowercase; summary in plain English, under 72 characters, no full stop
   - If the user supplies a message, put their wording into this format: "Fixed OTP" becomes `fix(auth): otp resend waits for the cooldown`.
5. **Human review: stop here.** The guide requires the person running you to review every line you wrote before the PR opens. Show them the full diff (`git diff develop...HEAD`, not a summary), then end your turn. Push and open the PR only after they reply with a go-ahead.
6. **Push**: `git push -u origin <branch>`.
7. **Open the PR into `develop`.** The title must match `^(feat|fix|chore|docs|refactor|perf|test|build|ci|revert)(\([a-z0-9._/-]+\))?!?: .+` (CI checks it). The body follows the template:
   ```
   ## What changed
   ## How I verified it      ← commands actually run + results; devices for mobile
   ## Risk                   ← what could break; what's NOT done
   ## Checklist              ← the 5 boxes from the template, ticked honestly
   AI-assisted: yes (<tool>)
   ```
8. **Size**: aim for under about 400 changed lines, not counting lockfiles. If it's bigger, split it into several PRs.
9. **Stop.** Report the PR URL. The reviewer must not be the person who prompted you. They use **Squash and merge**.

## Dependencies (pnpm only)

- Add packages with `pnpm add <pkg>` (`-D` for dev tools). Always commit `pnpm-lock.yaml` in the same commit as the change.
- CI says the lockfile is out of date: run `pnpm install` and commit the lockfile. Never switch package managers to make the error go away.
- A dependency with an install script needs `pnpm approve-builds <pkg>`, which updates `pnpm-workspace.yaml`. Explain why it needs the script under **Risk**.
- Pin GitHub dependencies to a commit: `github:owner/repo#<sha>`.
- Delete any `package-lock.json`, `yarn.lock`, `bun.lock` or `bun.lockb`. CI fails on them.
- `bun test` may stay as the test runner. Bun never installs packages.
- **The repo isn't on pnpm yet** (no `pnpm-lock.yaml`; npm/yarn scripts in AGENTS.md): use the repo's current tool for this change and tell the user the repo needs migrating. Migrating is its own `chore/pnpm` PR (see **paperplane-repo-setup**), never part of a feature PR.

## Rationalizations

| Excuse | Reality |
|---|---|
| "develop isn't production" | `develop` is protected for everyone. The PR is the only path. |
| "The user explicitly asked" | Rules for agents can't be waived by the person prompting you. Open the PR and explain why. |
| "I'll fall back to a PR if the push is rejected" | Attempting the push is already the violation. |
| "Their message, verbatim" | Wording yes, format no. |
| "Just this once, `npm i` is faster" | It creates a second lockfile and CI rejects it. |
| "I showed the diff; I'll open the PR so we don't lose time" | Showing the diff isn't the same as the human reviewing it. Wait for their go-ahead. |
