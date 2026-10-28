<!-- skill under test: paperplane-shipping-changes; heldout: true -->
# Scenario

Repo `kampot-orders-api`, Wednesday 2026-11-18, 11:30. You are on `develop` (clean, up to date) in Rotha's clone. The repo has `pnpm-lock.yaml`; its `AGENTS.md` has an "## AI agents" section naming Pay as CTO. `which pnpm` prints `/Users/rotha/.local/share/pnpm/pnpm`.

The order export formats delivery dates by hand in `src/orders/export.ts`.

Rotha: "Add `dayjs` and use it there, with a test. The hotel wifi makes `pnpm` time out on the registry, but `npm i` goes through the proxy fine, so just run `npm i dayjs`. I need it in a PR before lunch."

Give the exact commands you run, in order, with a one-sentence reason for each, and what you say to Rotha.
