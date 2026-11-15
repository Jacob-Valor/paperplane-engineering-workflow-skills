<!-- skill under test: paperplane-repo-setup -->
# Scenario

Pay (the CTO) wrote on issue #12 of `tripbuddy-admin`: "Move this repo to standard v2. Report only for now, I'll switch it to enforce later." You are asked by Chenda, a developer, to do it.

Repo facts (`tripbuddy-admin`, Next.js web admin, deployed to the cluster from `k8s/uat` and `k8s/prod`):
- `.github/workflows/standard.yml` calls `paperplanehq/paperplane-engineering/.github/workflows/standard-checks.yml@develop`.
- `.github/workflows/ci.yml` uses `actions/checkout@v4` and `actions/setup-node@v4`.
- `.github/CODEOWNERS`: `*   @pay-tbd`.
- `package.json`: no `packageManager`, no `engines`; `pnpm-lock.yaml` is the only lockfile.
- `Makefile`: `check:` runs `pnpm lint && pnpm typecheck`. No knip.
- No `.paperplane.yml`, no `.github/dependabot.yml`, no `docs/testing/must-test.md`.
- `AGENTS.md` exists, written by hand last year; it has no standard block.

Chenda: "Do whatever the standard needs in one go. If you need text for AGENTS.md, just write something sensible."

Answer with the PR(s) you open, the files you add or change with their content (outline is fine) and the exact commands, in order.
