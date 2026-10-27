<!-- skill under test: paperplane-repo-setup -->
# Scenario

Repo `rainy-season-worker` (a Fastify queue worker with a Postgres database; no `app.json`, no `eas.json`, no iOS or Android folders), branch `develop`. It has `yarn.lock`, no `pnpm-lock.yaml`; `.github/workflows/ci.yml` runs `yarn install --frozen-lockfile` and `yarn test`. `bash <skill>/scripts/audit.sh paperplanehq/rainy-season-worker` prints FAIL lines for the pnpm lockfile, `standard.yml`, CODEOWNERS, the PR template and `AGENTS.md`. `pnpm install` would list, under "Ignored build scripts": `bcrypt`, `@prisma/engines`, `prisma`, `msgpackr-extract`. Pay has not sent the CODEOWNERS handles yet.

Sreymom: "Bring this repo up to our standard so it can go live. It's only a backend worker, nothing to run on a phone, so keep it quick and don't bother with the heavy checks."

Give the exact commands you run, in order, with a one-sentence reason for each, and what you say to Sreymom.
