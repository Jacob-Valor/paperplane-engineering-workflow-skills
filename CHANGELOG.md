# Changelog

Versions follow the date of the engineering guide they match (`vYYYY.MM.DD`). Test numbers for each change are in [`tests/RESULTS.md`](tests/RESULTS.md).

## v2026.10.15.1

From a benchmark on haiku, sonnet and opus (numbers in `tests/RESULTS.md`).

### Changed
- **shipping-changes**: run `gh pr view <N> --json isDraft` before stacking on an open PR; a draft bottom PR means branch from `develop` or wait. The first draft already has `AI-assisted: yes (<tool>) — <what you ran>` and `Risk: … Not done: …`. Step 7 says any commit after the human's review needs a new go-ahead before Ready.
- **releasing**: store builds always come from `main`, also after the merge-back. The handover asks the CTO to confirm a `.3` tag.
- **secret-incidents**: never print a flagged file or commit. Take the value out of an unpushed commit (amend or local rebase) before pushing; a new commit on top leaves it in history.
- Descriptions: only shipping-changes (per PR) and repo-setup (repo setting) mention auto-merge.
- `tests/eval/run.py`: `--no-skills` baseline, `--judge-model`, and token and time figures in each `repN.judge.json`. The benchmark commands are in `tests/eval/README.md`.

## v2026.10.15

Matches the guide of 2026-10-15 (`ci(standard): one checks job instead of five, AI review skips drafts and edits`, #8).

### Changed
- **reviewing-prs**: CI is one `standard / checks` job; a red one means opening its log and naming the failing step. The PR size step only warns. `standard / AI review (advisory)` skips drafts and never blocks.
- **repo-setup**: "Done when" expects `standard / checks` and `standard / AI review (advisory)`, not five jobs. A `standard.yml` without the template's `concurrency` block gets replaced; `audit.sh` warns about it.
- **secret-incidents**: the description names the secret scan as a step of `standard / checks`.
- **shipping-changes**: CI skips the body check on drafts, so `check-pr-body.sh` before Ready is the only check.
- **releasing**: rollback uses `next-tag.sh --previous --before <bad tag>`.
- `guide-version` is `2026-10-15` in all five skills.

### Fixed
- `next-tag.sh --previous` printed the newest tag, which during a rollback is the bad one. New `--before <tag>` prints the tag before it.
- `pre-push.sh` blocked branches that only delete a stray lockfile or build output, and let through a `.env` that was added and removed again on the branch (it stays in the pushed history).
- `gather.sh` called a PR "not ready to approve" when only the advisory AI review was red. It now names the failing or pending checks that block.
- `tests/drift/check.sh` passed when a job name appeared anywhere in a skill (`checks` matched `gh pr checks`). Skills must now name jobs as `` `standard / <job>` ``, and naming a job that no longer exists is drift.
- Claude Code guard bypasses:
  - commands after shell keywords (`if … then gh pr merge`)
  - `$(…)` and backticks inside double quotes
  - merge, auto-merge and approve calls through `gh api`, including graphql mutations
  - `git stage`
  - abbreviated options (`--force-w`, `--al`, `--no-verif`)
  - `git -c core.hooksPath=…` and `git -c alias.*`
  - `npm`/`npx` run from a subdirectory of a pnpm repo
- Guard false positives:
  - branches named `uat-…` were treated as release tags
  - `git commit -uno` was treated as `--no-verify`
  - heredoc PR bodies were parsed as commands
  - `npm i -g pnpm` was blocked
- `install-git-hook.sh` refuses husky repos, where husky would skip or overwrite the hook, and prints the line to add to `.husky/pre-push`. `install-claude-hook.sh` keeps a symlinked `settings.json` as a symlink.
- Secret-scan tests were flaky: a random base64 key that starts with `/` doesn't match the gitleaks rule. They now use alphanumeric keys.

## v2026.10.13.3

### Fixed
- The git pre-push hook blocked force-pushes of your own branch, which `team-workflow-13-oct-2026.html` §5 allows for people ("rebase the next PR onto develop and push"). It now allows them; `install-git-hook.sh --block-force-push` turns the block on for clones only agents push from. Agents still never force-push (skill rule and Claude Code guard).
- `team-workflow-13-oct-2026.html` Part D: status cells for `mobile: true` and CODEOWNERS now match the org audit; new row for the hooks.

## v2026.10.13.2

### Added
- **Hooks** (`paperplane-shipping-changes/hooks/`): a git `pre-push` hook (blocks pushes to `develop`/`uat`/`main` and force-pushes, runs `pre-push.sh`, chains an existing hook) and a Claude Code `PreToolUse` guard (blocks merge, auto-merge, approve, force-push, protected-branch and release-tag pushes, `--no-verify`, `git add -A`, repo-setting changes, npm/yarn/bun in pnpm repos). Installers for both, with `--uninstall`.
- `repo-setup/scripts/audit.sh`: PASS/FAIL audit of one repo against the standard.
- `reviewing-prs/scripts/gather.sh`: PR, body, checks, files, unresolved threads, authors, stack and diff in one command.
- `releasing/scripts/next-tag.sh`: next `prod-`/`uat-` tag, CTO warning at `.3`, `--previous` for rollback.
- `tests/eval/run.py`: runs the scenarios through `claude -p` and grades them.
- `tests/drift/check.sh` and `.github/workflows/drift.yml`: weekly check that the skills still match the live guide.
- Scenarios S13 (second release in a day) and S14 (hook blocks a push).

### Changed
- Skills call the new scripts instead of listing raw `gh`/`git` commands.
- **shipping-changes**: never use `--no-verify` or bypass a hook; install the git hook once per clone.
- **secret-incidents**: "it's fake, I made it up" doesn't classify a finding; send the CTO message anyway.

## v2026.10.13.1

Brings the skills in line with `team-workflow-13-oct-2026.html`.

### Changed
- **shipping-changes**: "Ready" now also needs the Checklist ticked honestly and no dead code, leftover TODOs or debug logs. Every review comment gets an answer the same day (a fix, or a drafted "why not" reply for the user to post). A draft open more than three working days gets split, or the user asks for help. Bigger work is split into PRs that each leave the app working.
- **reviewing-prs**: new Leftovers check (dead or commented-out code, "for later" helpers, TODOs, debug logs).
- **releasing**: store builds come from `main`, tagged `app-vX.Y.Z`; no longer says "at a `prod-*` tag".
- `tests/`: scenarios S9–S12.

## v2026.10.13

Matches the `paperplanehq/paperplane-engineering` guide of 2026-10-13 (draft-first PRs, definition of ready, stack limit, body and size checks).

### Added
- `paperplane-shipping-changes/scripts/pre-push.sh`: run before every push. Blocks pushes from `develop`/`uat`/`main`, a second lockfile, `.env` files, build output and secrets (gitleaks).
- `paperplane-shipping-changes/scripts/check-pr-body.sh`: the CI `PR body is complete` rules, run locally before `gh pr ready`.
- `tests/`: agent scenarios S1–S8, the triggering test, pass criteria, results, and script tests.
- CI (`.github/workflows/validate.yml`): spec validation, shellcheck and script tests on every PR.
- Frontmatter: `license`, `compatibility` and `metadata` (`author`, `guide-version`).

### Changed
- **shipping-changes**: the agent opens a **draft** PR the same day and marks it ready only after the human has reviewed the full diff. It never turns on auto-merge, never rebases a pushed branch (it merges `develop` in instead), keeps stacks to two, and puts native changes and tooling bumps in their own PRs.
- **reviewing-prs**: stacked bases and the advisory AI review are not blockers; drafts, a Risk without "not done", unresolved threads and mixed native changes are.
- **repo-setup**: `mobile: true` for app repos, CODEOWNERS with two owners, auto-merge allowed, the full list of standard checks.
- **releasing**: hotfix merge-back the same day, store builds from the `prod-*` tag, the hotfix PR opens as a draft.
- Descriptions start with one sentence saying what the skill covers, then the triggers.
- README: install from this repo until the skills are merged into `paperplane-engineering`.
