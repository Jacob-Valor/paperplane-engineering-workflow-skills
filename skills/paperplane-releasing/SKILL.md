---
name: paperplane-releasing
description: Paper Plane's release, hotfix, rollback and store-tag rules; the CTO runs releases. Use when asked to release, ship, or promote a paperplanehq repository to UAT or production, merge develop into uat or uat into main, tag a prod release, roll back, make a hotfix, or tag a mobile store build.
license: Proprietary
compatibility: Requires git and gh authenticated to the paperplanehq GitHub org.
metadata:
  author: paperplanehq
  guide-version: "2026-10-15"
---

# Releasing at Paper Plane

## Overview

Releases belong to the CTO (Pay). **Agents never merge, promote, tag production, deploy, start store builds, turn on auto-merge, or force-push.** That holds even when the CTO asks you directly or you have admin `gh` access. Your job is to prepare the release so the CTO only has to approve and run it. That means you:

- check readiness
- open the release PRs with the correct titles
- compute the tag name
- write out the exact commands for the CTO to run

The org ruleset `protect-develop-uat-main` requires a PR with 1 code-owner approval and every review thread resolved on `develop`, `uat` and `main`; a new push dismisses earlier approvals. It allows only squash and merge commits, and blocks force-pushes and branch deletion. The org ruleset `release-tags-owner-only` blocks creating, moving or deleting `prod-*` and `uat-*` tags for everyone but org admins.

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
gh pr create --base main --head uat     --title "chore(release): prod 2026-10-09" --body "<…> Rollback: deploy <tag from next-tag.sh --previous>"
```

**Tag name**: `bash <skill>/scripts/next-tag.sh` (`<skill>` = the folder this SKILL.md is in; it fetches tags first, prints the next name, never creates a tag). Add `--date YYYY-MM-DD` for another day, `--prefix uat` for UAT tags.

- No tags for today: `prod-2026.10.09`
- `prod-2026.10.09` exists: `prod-2026.10.09.2`
- `.2` exists too: `.3`. The guide only shows `.2`, so your handover tells the CTO to confirm `.3` before tagging. The script's warning alone isn't enough.

Never use `v…` prefixes, semver, or `gh release create`.

### CTO runs (write these out; don't execute them)

```bash
gh pr merge <uat-PR> --merge                     # after approval; then test on UAT
gh pr merge <main-PR> --merge
git switch main && git pull && git tag prod-2026.10.09.2 && git push origin prod-2026.10.09.2
# deploy that tag
```

If the repo's AGENTS.md tags UAT releases, add `uat-YYYY.MM.DD` on `uat` the same way.

**Rollback** means deploying the `prod-*` tag before the bad one: `bash <skill>/scripts/next-tag.sh --previous --before <bad tag>`. (`--previous` alone prints the newest tag, which is the one deployed now: right for a release PR's `Rollback:` line, wrong once the bad tag exists.) Never revert by force-pushing `main`.

## Hotfix

1. The CTO agrees it's a hotfix. Then: `git switch main && git pull && git switch -c hotfix/<topic>`.
2. Fix it, commit as `fix(scope): …`, push, and open a **draft** PR into **`main`** (`AI-assisted: yes`). It goes ready after the human reviews the diff, as in **paperplane-shipping-changes**. The CTO merges it and tags `prod-YYYY.MM.DD[.N]`.
3. **Same day**, merge back with PRs from `main` into `uat` and from `main` into `develop`, using **merge commits**. Open them right after the hotfix merges; the CTO merges them that day. Until then the next release would ship without the fix.

## Mobile store builds

Store builds always come from `main`, also after the merge-back; `uat` only gives UAT builds. Tag the exact commit submitted to the store `app-vX.Y.Z`. A hotfix that isn't merged back yet is only on `main`, which is one more reason the store build comes from `main`. The CTO or release owner starts the build and pushes the tag; you write out the commands.

## Rationalizations

| Excuse | Reality |
|---|---|
| "The CTO said 'Go', I have admin" | The guide the CTO wrote says agents never merge or deploy. Prepare, then hand over. |
| "Squash keeps history clean" | Release PRs need merge commits, or the branches diverge. |
| "`v2026.10.09.2` is conventional" | The format is `prod-YYYY.MM.DD[.N]` (existing tags: `prod-2026.10.01`, `prod-2026.10.01.2`). |
| "Hotfix is urgent, push to main" | It's still a PR. The ruleset rejects direct pushes. |
| "Merging is the step that can wait; merge them Friday" | Merge-back is same-day. Open the PRs now and ask the CTO to merge them today. |
| "Merge back into uat first, then build from uat" | Store builds come from `main` only. `uat` builds are for UAT testing. |
| "next-tag.sh handles the `.3`" | It prints the name. The CTO still confirms `.3`; say so in the handover. |
