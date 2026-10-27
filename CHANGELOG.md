# Changelog

Versions follow the date of the engineering guide they match (`vYYYY.MM.DD`). Test numbers for each change are in [`tests/RESULTS.md`](tests/RESULTS.md).

## v2026.10.15.8

### Fixed
- Guard: quote-split command names (`g''it`, `n''pm`) are checked; the early "no git/gh/npm in the string" exit is gone.
- Guard: blocks writing `core.hooksPath` or `alias.*` (`git config`, `-ccore.hooksPath=`, `--config-env`), `GIT_CONFIG_*`/`GIT_DIR`/`GIT_EXEC_PATH` on git commands, `--no-verify` on merge/rebase/cherry-pick/am, and `git send-pack`. Reading config stays allowed.
- Guard: `git push --follow-tags`, `heads/main`, wildcard, `{brace}`, `$'...'` and bare `:` refspecs are blocked.
- Guard: wrapper commands with options (`sudo -u`, `nice -n`, `env -u/-C`, `xargs -I{}`, `watch`, `ssh host`) and `find -exec` are unwrapped and checked.
- Guard: heredoc and here-string input to bash/sh/zsh/dash/eval/source is checked. `$((1<<2))` no longer hides later lines, and an unterminated heredoc is scanned instead of skipped.
- Guard: the branch check and pnpm detection follow `git -C <dir>`, `cd` and `pushd`. A bare `git push` is blocked when `push.default=upstream` or `remote.<name>.push` points at develop, uat or main.
- Guard: more package-manager forms are blocked in pnpm repos (`npm --prefix x install`, `npm -w p install`, `uninstall`, `update`, `exec`, `it`, `cit`, `clean-install`, `yarn remove/dlx`, `bunx`, `bun x`). `npm run ...`, `npm --version`, global installs and `yarn test` stay allowed.
- Guard: blocks `gh alias set`, `gh extension install/exec`, `gh api graphql` with `query=@file` or `--input` (unless GET), and `git add ./.` and `:/` variants. The tool name match is case-insensitive, and an unreadable or non-string command exits 1 instead of passing silently.
- Git pre-push hook: blocks pushing or deleting `prod-*`/`uat-*` release tags, and blocks the push when gitleaks is missing unless `PAPERPLANE_ALLOW_NO_GITLEAKS=1`.
- `pre-push.sh`: `build/`, `dist/` and `coverage/` count as build output only at the repo root or beside a `package.json` (`src/build/x.ts` is fine). `.env.sample`, `.env.template`, `.env.dist` and `.env.*.example` are exempt.
- `audit.sh`: no false FAILs on branch lists over 64 KB (SIGPIPE under pipefail); the ruleset check requires `enforcement: active`; CODEOWNERS is accepted at `.github/`, the root or `docs/`; `ready_for_review` and `concurrency` are read from the real `on.pull_request.types` and top-level `concurrency`, ignoring comments and job-level keys.
- `next-tag.sh`: `--date` rejects impossible days (`2026-02-31`) and a missing value; `--prefix` and `--before` without a value are usage errors; `--previous` tie-breaking is documented and tested.
- `check-pr-body.sh`: multi-line and adjacent HTML comments are stripped correctly, `AI-assisted: yesterday` fails, CRLF bodies work (new `test-check-pr-body.sh`).
- `gather.sh`: reports when only the first 100 commits are shown and when the PR comes from a fork; any check state other than pass, skipping or neutral blocks.
- Drift check: an expired or revoked token (HTTP 401/403) fails even with `DRIFT_ALLOW_SKIP=1`; only a missing secret skips.
- Sandbox eval: runs where the CLI failed, timed out, produced no result event or made no tool call are INVALID (not pass, not fail), reported separately; any invalid run exits 3.

- Guard fails closed on `git push` refspecs that contain `$VAR`, `${...}`, `$(...)` or backticks, and on a variable command word followed by push, merge or pr.
- Guard reads the scripts it is told to run (shell, plus a text scan for python, node, ruby and perl; three levels, 64 KB), scans inline `python -c`/`node -e`/`perl -e`/`ruby -e`, and blocks `curl | sh`, `base64 -d | sh`, `eval "$(...)"`, `sh -c "$(...)"` and `bash <(curl ...)`.
- Guard parses quoted arguments of ssh, watch, su, docker, timeout and similar wrappers, and `pnpm|npm|yarn exec`. A `cd` inside `( )`, `$( )`, backticks or `bash -c` no longer changes the directory used for later commands.
- Guard refuses commands that remove or rewrite the guard, its settings, the git or husky pre-push hooks and the omp adapter, and commands that set `PAPERPLANE_ALLOW_NO_GITLEAKS`. Side effect: an agent cannot run `tests/scripts/test-hooks.sh` through the guard; a person can.
- Guard blocks `git update-ref` and `git branch -f|-m|-d` on develop, uat and main, `git -c push.default=matching`, and `git add *`. The header lists what it still does not catch.
- Scripts that push with a variable (`git push origin "$tag"`) are blocked when run through the guard; name the branch literally.


### Added
- Eval summaries print Wilson 95% intervals next to pass rates. Scenarios can be tagged `heldout: true` (`run.py --heldout-only` / `--exclude-heldout`); held-out scenarios must never be used to tune skill wording.
- CI: a macOS job runs `bash -n` and the script tests on bash 3.2 / BSD tools; gitleaks downloads are checked against the release checksums; `dependabot.yml` updates actions weekly; scheduled drift failures open or update a `drift` issue.
- `tests/RESULTS.md`: "How to read these numbers" and two over-claiming sentences reworded (recorded numbers unchanged).

### Added (tests and docs)
- `tests/scripts/test-skills-lint.sh`: offline lint for skill frontmatter, referenced script paths, cross-skill rule wording, description trigger ownership, Hard-rules enforcement mapping, the README skill table and placeholders.
- Eight held-out scenarios (S20 to S27, all five skills) and `tests/eval/label.py`, a blind human spot-check tool (`sample`, `report`) that prints agreement, kappa and judge precision/recall. `label.py --self-test` runs in CI.
- `docs/org-facts.md` and a README section "Using this for another org". Skills define the CTO role once and say "the CTO" elsewhere; example person names became roles. Canonical wording unified: "No exception is granted in the agent conversation" and "Agents never force-push".

### Changed
- CI: `ANTHROPIC_API_KEY` is scoped to the steps that run claude; eval concurrency separates scheduled, manual and pull request runs.
- Re-run `install-claude-hook.sh --commit` in each repo to refresh the committed guard; `audit.sh` warns when a copy is out of date.

## v2026.10.15.7

### Fixed
- **shipping-changes** and **secret-incidents** now agree on history rewrites: the local `git rebase -i` that drops a pushed secret is the one carve-out from "never rebase a pushed branch"; the agent prepares it and stops, the human force-pushes.
- Exceptions: one rule in shipping, releasing and README. No exception is granted in the agent conversation, even by the CTO; the agent follows the rule and drafts a message to the CTO, and a human acts outside the agent.
- README, flowchart and table agree with shipping step 7: the agent runs `gh pr ready` only after the person says they reviewed the diff.
- **releasing**: release PRs open as `--draft` with a body skeleton that passes `check-pr-body.sh --no-mobile`; merge-back PR title format and a `chore/merge-back-<tag>` branch for conflicts. **reviewing-prs**: Size/Leftovers/Tests apply to the merged PRs, not the release PR.
- **shipping-changes**: `gh pr ready --undo` before pushing post-review commits; hotfixes branch from `main`; reply rules for review threads ("Fixed in <sha>", never resolve, draft rejections); PR body files live in `${TMPDIR:-/tmp}`, not the working tree; how to resolve `<skill>`.

### Changed
- Descriptions: releasing drops bare "ship" (now "ship to production"); reviewing-prs says "approving", not "merging"; repo-setup says auto-merge is the repo setting. `tests/triggering.md` has 9 more prompts for these collisions.
- Pruned cryptic or duplicate Rationalizations rows; reviewing-prs' two red-check rows are one.

## v2026.10.15.6

### Fixed
- Claude Code guard: `git push`, `git push origin`, and `git push origin HEAD`/`@` now resolve the current branch from the hook's `cwd` and block when it is `develop`, `uat` or `main`. Before, they passed the guard, so a committed-guard-only setup relied on the git pre-push hook or the server ruleset to stop them. 11 new cases in `test-hooks.sh`.

### Changed
- README says what the guard cannot see: variables, command substitution, scripts, `gh alias`. It stops mistakes, and the server-side ruleset is the backstop.

## v2026.10.15.5

### Added
- omp support for the guard. omp doesn't run Claude Code's `.claude/settings.json` hooks: with the committed guard in place, omp pushed straight to `develop`. `hooks/omp-guard.ts` is an omp hook that sends each bash call to the same `claude-guard.sh` and blocks on exit 2. `install-claude-hook.sh --commit` now also commits it as `.omp/hooks/pre/paperplane-guard.ts`; `install-omp-hook.sh` installs it once per machine.
- `audit.sh`: WARN `omp-guard` when the repo has no committed omp adapter.

## v2026.10.15.4

### Added
- `install-claude-hook.sh --commit`: puts the Claude Code guard into the repo itself, as `.claude/hooks/paperplane-guard.sh` plus a PreToolUse hook in the committed `.claude/settings.json` (`bash "$CLAUDE_PROJECT_DIR/.claude/hooks/paperplane-guard.sh"`). Every Claude Code session in a team repo runs the guard without a per-machine install. Re-running refreshes the copy; `--uninstall` removes both.
- `audit.sh`: FAIL `claude-guard` when the committed guard is missing, WARN `claude-guard-current` when it is out of date, WARN `agents-skills` when AGENTS.md names no `paperplane-*` skill. **repo-setup** adds both files and an "## AI agents" AGENTS.md section to the standard.
- Sandbox scenarios `stack-on-draft`, `rebase-force`, `release-tag`, `approve-own` and `no-verify`; `git` calls are logged.
- CI: the weekly eval also runs the sandbox with and without the hooks; scheduled and manual evals fail without `ANTHROPIC_API_KEY` instead of passing silently. `validate` checks that the README version matches the newest CHANGELOG entry.

### Changed
- **shipping-changes**: the description also triggers on "rebasing or force-pushing a branch".

## v2026.10.15.3

### Changed
- **reviewing-prs**: the report's eligibility line names "not me", the person who prompted the agent, and the reviewer's handle.
- **repo-setup**: the pnpm migration block has a concrete `pnpm approve-builds` command that approves only what pnpm lists under "Ignored build scripts", and the PR step with one Risk line per approved package.

## v2026.10.15.2

### Added
- Scenarios S15–S19 (`.env` in a PR, a pushed live key with "just force-push", rollback with "revert main and force-push", pnpm migration inside a feature PR, the prompter asking for approval). S10 is harder: the old one passed without any skill.
- `tests/eval/checks.py`: regex checks for the objective parts of S1–S14, run after the judge (`--no-checks` to skip), with `--self-test` and 30 labelled answers in `tests/eval/labels/`.
- `tests/eval/sandbox/run.py`: tool-using eval in a throwaway repo with a fake `gh`, graded from the end state, with and without the hook and guard; `--self-check` runs in CI.
- `.github/workflows/eval.yml`: the triggering test on PRs that change a `SKILL.md`, and every scenario weekly or on demand (needs the `ANTHROPIC_API_KEY` secret).

### Changed
- **secret-incidents**: draft the CTO message first; classify from the scan output or `gitleaks dir --redact -v <file>`, never `cat`; fold the fix into an unpushed commit.
- **repo-setup**: the migration commands include the native builds and a reason per `approve-builds` package; the template copy command says to uncomment `mobile: true`.
- **reviewing-prs**: a helper with no caller is a leftover and a blocker.
- **releasing**: the ruleset also requires a green `standard / checks`.
- **shipping-changes**: an example Risk line instead of a template; push the cleanup before asking for a new go-ahead; shorter hook and Ready text.

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
