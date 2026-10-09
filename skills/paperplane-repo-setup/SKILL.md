---
name: paperplane-repo-setup
description: Use when creating or onboarding a repository in the paperplanehq GitHub org, or when a paperplanehq repo lacks the standard CI workflow, PR template, AGENTS.md/CLAUDE.md, .env.example, pnpm, or the develop/uat/main branches — "set it up to our engineering standard", "migrate to pnpm".
---

# Bringing a repo up to the Paper Plane standard

## Overview

The standard is applied by **copying** what `paperplanehq/paperplane-engineering` provides. Don't reinvent it. Branch protection comes from the org ruleset `protect-develop-uat-main`, which already covers every repo, so never create per-repo branch protection. File changes go in through a normal PR (see **paperplane-shipping-changes**). Repo **settings** changes are the CTO's: you check them and write out the commands.

## 1. Audit

```bash
R=paperplanehq/<repo>
gh repo view $R --json defaultBranchRef,mergeCommitAllowed,squashMergeAllowed,rebaseMergeAllowed,deleteBranchOnMerge
gh api "repos/$R/branches" --jq '.[].name'                  # develop, uat, main present?
gh api "repos/$R/rulesets" --jq '.[].name'                  # expect protect-develop-uat-main
gh api "repos/$R/contents" --jq '.[].name'                  # default branch: AGENTS.md CLAUDE.md .env.example pnpm-lock.yaml …
gh api "repos/$R/contents/.github/workflows" --jq '.[].name' # standard.yml?
```

**Order** (the "pnpm only" check fails while another lockfile exists):

1. Settings and branches (§4, the CTO applies them)
2. If the repo has a non-pnpm lockfile: the `chore/pnpm` PR (§3), merged
3. The `chore/engineering-standard` PR (§2)

## 2. Files (one PR, `chore/engineering-standard` into `develop`)

| Path | Content |
|---|---|
| `.github/workflows/standard.yml` | Exact copy of `templates/standard.yml`. It calls the reusable `standard-checks.yml@develop` (pnpm-only, gitleaks, PR title). Never write your own copies of these checks. Repo build/test CI goes in a separate `ci.yml`. |
| `.github/pull_request_template.md` | Exact copy of `templates/pull_request_template.md` |
| `AGENTS.md` | Copy the sections "How we work as a team", "Rules for AI coding agents" and "Rules for everyone" from a migrated sibling (e.g. `tripbuddy-backend`). Adjust the product intro line. Then write "## This repo": stack, layers, and the exact commands under **Verify before opening a PR**. |
| `CLAUDE.md` | `# CLAUDE.md`, a line saying to read and follow AGENTS.md, then a line with `@AGENTS.md` |
| `.env.example` | Every variable **name** with a placeholder value. No real values. |
| `.gitignore` | Ignores `.env`, `.env.*` and build output, with `!.env.example`. Must **not** ignore `pnpm-lock.yaml`. |

To copy a template or a sibling's AGENTS.md:
```bash
raw() { gh api -H "Accept: application/vnd.github.raw" "repos/paperplanehq/$1/contents/$2?ref=develop"; }
raw paperplane-engineering templates/standard.yml > .github/workflows/standard.yml
raw paperplane-engineering templates/pull_request_template.md > .github/pull_request_template.md
raw tripbuddy-backend AGENTS.md > AGENTS.md   # then edit as above
```

## 3. pnpm migration (separate PR, `chore/pnpm`)

```bash
corepack enable && corepack use pnpm@latest    # writes "packageManager" to package.json
pnpm import                                    # converts package-lock/yarn.lock, keeping resolved versions
git rm --ignore-unmatch package-lock.json yarn.lock bun.lock bun.lockb
pnpm install && pnpm approve-builds <pkg> …    # name each package that needs its install script (no args = interactive prompt); explain each in the PR
```

Then switch every `npm`/`yarn`/`npx` use in scripts, CI, Dockerfiles, EAS config and AGENTS.md over to pnpm. Re-run the build and tests. For React Native/Expo, build on iOS **and** Android. If Metro can't resolve packages, add `node-linker=hoisted` to `.npmrc`.

## 4. Settings (the CTO applies them; you write the commands)

- Default branch `develop`. Branches `develop`, `uat` and `main` exist. Create any that are missing from the current tip of `main`:
  ```bash
  SHA=$(gh api repos/$R/git/ref/heads/main --jq .object.sha)
  gh api repos/$R/git/refs -f ref=refs/heads/develop -f sha=$SHA   # and uat
  ```
- Merge methods: squash **and** merge commit (release PRs need merge commits), no rebase, delete branches after merge:
  ```bash
  gh repo edit $R --default-branch develop --enable-squash-merge --enable-merge-commit \
    --enable-rebase-merge=false --delete-branch-on-merge
  ```
- `protect-develop-uat-main` appears in `gh api repos/$R/rulesets`. If it's missing, tell the CTO. Don't add a repo-level ruleset as a substitute.

## Done when

The setup PR shows the standard jobs in `gh pr checks`: "pnpm only", "secret scan (new commits)" and "PR title is type(scope) summary", all green. The audit in step 1 comes back clean.

## Common mistakes

| Mistake | Fix |
|---|---|
| Writing your own `ci.yml` checks in place of `standard.yml` | Copy the template. Add your own `ci.yml` only for build and test. |
| Protecting only `main`, or creating per-repo protection | The org ruleset already covers `develop`, `uat` and `main`. |
| Allowing squash merges only | Release PRs need merge commits. |
| Pointing the setup PR at `main` | PRs go into `develop`. |
| pnpm migration inside the setup PR or a feature PR | Use its own `chore/pnpm` PR. |
