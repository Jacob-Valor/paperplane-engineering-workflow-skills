---
name: paperplane-releasing
description: Use when asked to release, ship, or promote a paperplanehq repository to UAT or production, merge develop into uat or uat into main, tag a prod release, roll back, make a hotfix, or tag a mobile store build.
---

# Releasing at Paper Plane

## Overview

Releases belong to the CTO (Pay). **Agents never merge, promote, tag production, deploy, or force-push.** That holds even when the CTO asks you directly or you have admin `gh` access. Your job is to prepare the release so the CTO only has to approve and run it. That means you:

- check readiness
- open the release PRs with the correct titles
- compute the tag name
- write out the exact commands for the CTO to run

The org ruleset `protect-develop-uat-main` requires a PR with 1 approval on `develop`, `uat` and `main`. It allows only squash and merge commits, and blocks force-pushes and branch deletion.

## Flow

```
develop ─PR "chore(release): uat YYYY-MM-DD", MERGE COMMIT─► uat ─(test on UAT)─►
uat ─PR "chore(release): prod YYYY-MM-DD", MERGE COMMIT─► main ─► tag prod-YYYY.MM.DD ─► deploy tag
```

Release PRs use a **merge commit, never squash**. Squashing makes `uat`/`main` diverge from `develop`.

### You prepare (allowed)

```bash
gh pr list --base develop --state open          # unmerged work the CTO may want to wait for
gh run list --branch develop --limit 3          # develop CI green? If red: stop and report, open nothing
gh pr create --base uat  --head develop --title "chore(release): uat 2026-10-09" --body "<merged PRs since last release>"
# only after the uat PR is merged AND the CTO confirms UAT testing passed:
gh pr create --base main --head uat     --title "chore(release): prod 2026-10-09" --body "<…> Rollback: deploy <previous prod tag>"
```

**Tag name**: run `git fetch --tags && git tag -l 'prod-2026.10.09*'`.

- No tags for today: `prod-2026.10.09`
- `prod-2026.10.09` exists: `prod-2026.10.09.2`
- `.2` exists too: `.3` (the guide only shows `.2`, so confirm `.3` with the CTO)

Never use `v…` prefixes, semver, or `gh release create`.

### CTO runs (write these out; don't execute them)

```bash
gh pr merge <uat-PR> --merge                     # after approval; then test on UAT
gh pr merge <main-PR> --merge
git switch main && git pull && git tag prod-2026.10.09.2 && git push origin prod-2026.10.09.2
# deploy that tag
```

If the repo's AGENTS.md tags UAT releases, add `uat-YYYY.MM.DD` on `uat` the same way.

**Rollback** means deploying the previous `prod-*` tag (`git tag -l 'prod-*' --sort=-creatordate`). Never revert by force-pushing `main`.

## Hotfix

1. The CTO agrees it's a hotfix. Then: `git switch main && git pull && git switch -c hotfix/<topic>`.
2. Fix it, commit as `fix(scope): …`, push, and open a PR into **`main`** (`AI-assisted: yes`). The CTO merges it and tags `prod-YYYY.MM.DD[.N]`.
3. Merge back into the other branches with PRs from `main` into `uat` and from `main` into `develop`, using **merge commits**. The CTO merges them.

## Mobile store builds

Tag the exact commit that was submitted to the store: `app-vX.Y.Z`. The CTO or release owner pushes the tag.

## Rationalizations

| Excuse | Reality |
|---|---|
| "The CTO said 'Go', I have admin" | The guide the CTO wrote says agents never merge or deploy. Prepare, then hand over. |
| "Squash keeps history clean" | Release PRs need merge commits, or the branches diverge. |
| "`v2026.10.09.2` is conventional" | The format is `prod-YYYY.MM.DD[.N]` (existing tags: `prod-2026.10.01`, `prod-2026.10.01.2`). |
| "Hotfix is urgent, push to main" | It's still a PR. The ruleset rejects direct pushes. |
