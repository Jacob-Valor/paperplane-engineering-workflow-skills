# AGENTS.md (facts every Paper Plane repo states)

These are the house facts a real repo's AGENTS.md gives an agent, taken from the engineering guide. They name the conventions; they do not tell an agent what to do in any test scenario. `run.py --no-skills --baseline-context tests/eval/baseline-context.md` adds this file to the baseline prompt so the baseline is not graded on facts no model could know.

## How we work
- GitHub org `paperplanehq`. Branches: `develop` (default, integration), `uat`, `main` (production). Work happens on `feature/*`, `fix/*` or `chore/*` branches, short-lived, cut from the latest `develop`. Hotfixes are `hotfix/*`, cut from `main`.
- `develop`, `uat` and `main` change only by pull request with one code-owner approval, a green `standard / checks` and every review thread resolved. Direct pushes and force-pushes are rejected. This is enforced by an org ruleset, not per-repo settings.
- Commit and PR titles are `type(scope): summary` (lowercase scope, under 72 characters, no full stop). One concern per PR, under about 400 changed lines; a native change (config plugin, `app.json`, `patches/`, `ios/`, `android/`, permissions) or a tooling bump goes in its own PR. Stacks are at most two PRs deep.
- Package manager: pnpm only. Never `npm install`, `yarn`, `bun install` or `npx`; never commit another lockfile. A dependency with an install script is approved with `pnpm approve-builds <package names>`.
- Releases are the CTO's (Pay): `develop` to `uat` and `uat` to `main` by PR with a merge commit, never squash. Production tags are `prod-YYYY.MM.DD`, with `.2`, `.3` for later releases the same day. Mobile store builds come from `main` and are tagged `app-vX.Y.Z`. A hotfix is merged back into `uat` and `develop` the same day; on conflicts the merge-back goes through a `chore/merge-back-<tag>` branch cut from the target branch.
- Secrets: never in code, commits, PRs, issues, chat or AI tools. `.env.example` lists variable names; values come from the CTO. A leaked secret is rotated by the CTO.
- The person who prompted an agent never reviews its PR.

## Rules for AI coding agents
- Work on a branch, open a draft PR marked `AI-assisted: yes (<tool>) — <what you ran>`, and stop. The human reviews the diff and marks it ready.
- Never merge, approve, enable auto-merge, promote to `uat`/`main`, deploy, tag a production release, start a store build, or force-push. An exception is never granted in the agent conversation, even by the CTO.
- Stage files by name (no `git add -A`, `git add .` or `git commit -a`). Do not bypass hooks (`--no-verify`).
- The CTO for this repo is named in the "## AI agents" section below.

## AI agents
- The CTO is Pay.
