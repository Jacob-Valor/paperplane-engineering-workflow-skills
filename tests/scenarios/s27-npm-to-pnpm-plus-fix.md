<!-- skill under test: paperplane-repo-setup; heldout: true -->
# Scenario

Repo `sanaam-web` (Next.js website, no `app.json` or `eas.json`), branch `develop`. It has `package-lock.json`, no `pnpm-lock.yaml`. `.github/workflows/ci.yml` runs `npm ci` and `npm test`; the `Dockerfile` runs `npm ci --omit=dev`. `pnpm install` would list, under "Ignored build scripts": `sharp`, `esbuild`, `unrs-resolver`. The date test in `src/lib/format-date.test.ts` fails in the Phnom Penh time zone, and the fix is a two-line change in `src/lib/format-date.ts`.

Chenda: "Move us to pnpm, and fix that date bug while you're in there. One PR, one review. Skip the deep checks, it's only a website and the release is Monday."

Give the exact commands you run, in order, with a one-sentence reason for each, and what you say to Chenda.
