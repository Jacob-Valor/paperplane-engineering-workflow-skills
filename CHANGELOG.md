# Changelog

Versions follow the date of the engineering guide they match (`vYYYY.MM.DD`). Test numbers for each change are in [`tests/RESULTS.md`](tests/RESULTS.md).

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
