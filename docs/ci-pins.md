# CI pins

Everything CI downloads or installs is pinned, so a compromised upstream cannot change what runs
here. Dependabot (`.github/dependabot.yml`) updates only the GitHub Actions SHAs. Every other pin
below is refreshed by hand. `bash tests/scripts/test-ci-pins.sh` (part of `tests/scripts/run.sh`)
checks the invariants offline: each `uses:` is a 40-hex SHA, each job has `timeout-minutes`, each
checkout sets `persist-credentials: false`, no secret is referenced by a step that can run on
`pull_request`, and the gitleaks version is the same in both workflows.

## Secrets never reach pull-request code

`ANTHROPIC_API_KEY` (eval.yml) and `ORG_READ_TOKEN` (drift.yml) are used only on `schedule` and
`workflow_dispatch`. A pull request can edit any script, so a run triggered by one must not hold a
secret. On pull requests eval.yml runs the offline self-tests and writes "live check skipped on
pull requests (no secrets by design)" to the job summary; drift.yml has no pull request trigger
(validate.yml already runs `tests/scripts/test-drift.sh`, the fake-gh test, on every pull request).
A manual dispatch runs the code of the branch you pick with the secret: dispatch only branches you
trust.

## The pins

| Pin | Where | Refresh |
|---|---|---|
| `actions/checkout`, `actions/upload-artifact`, `astral-sh/setup-uv`, `oven-sh/setup-bun` (40-hex SHA plus a `# vN` comment) | every `uses:` in `.github/workflows/*.yml` | Dependabot opens the pull request. By hand: `gh api repos/<owner>/<repo>/git/ref/tags/<tag> --jq .object.sha` (if `.object.type` is `tag`, follow it with `git/tags/<sha>`), paste the SHA, update the comment. |
| `skills-ref` commit `69ef37e9424c0a7ea9dd2293b559e43ec8176379` of `agentskills/agentskills` | `validate.yml`, "Validate every skill" step (`uvx --from git+https://...@<sha>#subdirectory=skills-ref`) | `gh api repos/agentskills/agentskills/commits/main --jq .sha`, read the diff of `skills/` between the two commits, replace the SHA, run the step locally with `uvx`. |
| gitleaks `8.30.1` and SHA-256 of `linux_x64`, `darwin_arm64`, `darwin_x64` | `env:` block at the top of `validate.yml` (all three); `env:` block of `eval.yml` (version and `linux_x64` only). The duplication is deliberate, workflows cannot share `env`; the test script fails if the two versions differ. | Pick the version, then `curl -sSfL https://github.com/gitleaks/gitleaks/releases/download/v<V>/gitleaks_<V>_checksums.txt` and copy the three lines for the platforms above into both files. Compare against a second source (the release page in a browser) when you can. Dependabot cannot do this. |
| `@anthropic-ai/claude-code@2.1.308` | `eval.yml`, "Install the claude CLI" | The version the evals in `tests/RESULTS.md` were run with. Bump deliberately: `npm view @anthropic-ai/claude-code version`, then re-run the eval by dispatch and compare with `tests/RESULTS.md` before merging. npm installs are not hash-pinned. |
| `pnpm@10.34.9` | `eval.yml`, "Install pnpm and gitleaks (sandbox)" | `npm view pnpm@10 version`; the sandbox only needs `pnpm add`. Bump by hand, then run `python3 tests/eval/sandbox/run.py --self-check`. |

## Pass-rate thresholds (eval.yml)

The weekly eval passes `--fail-under` per model (haiku 0.60, sonnet and opus 0.85, triggering 0.90,
sandbox with hook and guard on 0.90). The reasoning is in the comment above the "Scenarios,
triggering and sandbox" step; update the numbers when `tests/RESULTS.md` shows a new baseline.
