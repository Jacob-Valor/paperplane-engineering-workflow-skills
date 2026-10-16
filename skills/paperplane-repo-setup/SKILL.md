---
name: paperplane-repo-setup
description: Paper Plane's standard files, CI and repo settings, applied by copying the engineering templates. Use when creating or onboarding a repository in the paperplanehq GitHub org, or when a paperplanehq repo lacks the standard CI workflow, PR template, CODEOWNERS, AGENTS.md/CLAUDE.md, .env.example, pnpm, the develop/uat/main branches, or a repo setting such as allowing auto-merge — "set it up to our engineering standard", "migrate to pnpm".
license: Proprietary
compatibility: Requires gh authenticated to the paperplanehq GitHub org; pnpm for migrations.
metadata:
  author: paperplanehq
  guide-version: "2026-10-15"
---

# Bringing a repo up to the Paper Plane standard

## Overview

The standard is applied by **copying** what `paperplanehq/paperplane-engineering` provides. Don't reinvent it. Branch protection comes from the org ruleset `protect-develop-uat-main`, which already covers every repo, so never create per-repo branch protection. File changes go in through a normal PR (see **paperplane-shipping-changes**). Repo **settings** changes are the CTO's: you check them and write out the commands.

## 1. Audit

```bash
bash <skill>/scripts/audit.sh paperplanehq/<repo>   # <skill> = the folder this SKILL.md is in; read-only
```

One `PASS|FAIL|WARN` line per check: default branch and `develop`/`uat`/`main`; merge settings (squash and merge commit on, rebase off, delete branch on merge, auto-merge allowed); the `protect-develop-uat-main` ruleset; `AGENTS.md`, `CLAUDE.md`, `.env.example`, PR template, `pnpm-lock.yaml` and no other lockfile; CODEOWNERS with two owners per line; `standard.yml` calling `standard-checks.yml@develop`, with `ready_for_review`, `concurrency` and, for app repos (`app.json`/`eas.json` found, or `--app`), `mobile: true`. Exit 1 means at least one FAIL. Every FAIL maps to a section below.

**Order** (the `pnpm only` step of `standard / checks` fails while another lockfile exists):

1. Settings and branches (§4, the CTO applies them)
2. If the repo has a non-pnpm lockfile: the `chore/pnpm` PR (§3), merged
3. The `chore/engineering-standard` PR (§2)

## 2. Files (one PR, `chore/engineering-standard` into `develop`)

| Path | Content |
|---|---|
| `.github/workflows/standard.yml` | Exact copy of `templates/standard.yml`. It calls the reusable `standard-checks.yml@develop`: one `standard / checks` job (pnpm only, PR title, PR body, PR size, secret scan) and `standard / AI review (advisory)`. **App repo** (TripBuddy app, Sanaam app, Studio app): uncomment `with: mobile: true`, or the iOS/Android lines are never checked. An existing file that differs from the template (missing `ready_for_review`, `concurrency` or `mobile: true`) gets replaced. Never write your own copies of these checks. Repo build/test CI goes in a separate `ci.yml`. |
| `.github/pull_request_template.md` | Exact copy of `templates/pull_request_template.md` |
| `.github/CODEOWNERS` | Copy of `templates/CODEOWNERS` with **two** owners on every line. Ask the CTO for the GitHub handles; never invent them. The PR stays draft until they are filled in |
| `AGENTS.md` | Copy the sections "How we work as a team", "Rules for AI coding agents" and "Rules for everyone" from a migrated sibling (e.g. `tripbuddy-backend`). Adjust the product intro line. Then write "## This repo": stack, layers, and the exact commands under **Verify before opening a PR**. |
| `CLAUDE.md` | `# CLAUDE.md`, a line saying to read and follow AGENTS.md, then a line with `@AGENTS.md` |
| `.env.example` | Every variable **name** with a placeholder value. No real values. |
| `.gitignore` | Ignores `.env`, `.env.*` and build output, with `!.env.example`. Must **not** ignore `pnpm-lock.yaml`. |

To copy a template or a sibling's AGENTS.md:
```bash
raw() { gh api -H "Accept: application/vnd.github.raw" "repos/paperplanehq/$1/contents/$2?ref=develop"; }
raw paperplane-engineering templates/standard.yml > .github/workflows/standard.yml
raw paperplane-engineering templates/pull_request_template.md > .github/pull_request_template.md
raw paperplane-engineering templates/CODEOWNERS > .github/CODEOWNERS               # then fill in the owners
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
- Merge methods: squash **and** merge commit (release PRs need merge commits), no rebase, delete branches after merge, auto-merge allowed (authors turn it on per PR):
  ```bash
  gh repo edit $R --default-branch develop --enable-squash-merge --enable-merge-commit \
    --enable-rebase-merge=false --delete-branch-on-merge --enable-auto-merge
  ```
- `protect-develop-uat-main` appears in `gh api repos/$R/rulesets`. If it's missing, tell the CTO. Don't add a repo-level ruleset as a substitute.

## Done when

The setup PR, once ready, shows `standard / checks` green in `gh pr checks`, and `standard / AI review (advisory)` has run (it never blocks and skips drafts). The audit in step 1 comes back clean.

## Common mistakes

| Mistake | Fix |
|---|---|
| Writing your own `ci.yml` checks in place of `standard.yml` | Copy the template. Add your own `ci.yml` only for build and test. |
| Exact template copy in an app repo | Uncomment `mobile: true`, or the iOS/Android lines aren't checked. |
| "Exact copy of the CODEOWNERS template" | The template has one placeholder owner. Two owners per line, names from the CTO. |
| "Auto-merge isn't part of the standard; it lets PRs land without a person" | It is part of it. It fires only after a code-owner approval and green checks. Write out `--enable-auto-merge`. |
| Protecting only `main`, or creating per-repo protection | The org ruleset already covers `develop`, `uat` and `main`. |
| Allowing squash merges only | Release PRs need merge commits. |
| Pointing the setup PR at `main` | PRs go into `develop`. |
| pnpm migration inside the setup PR or a feature PR | Use its own `chore/pnpm` PR. |
