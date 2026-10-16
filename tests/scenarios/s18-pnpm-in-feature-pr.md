<!-- skill under test: paperplane-repo-setup -->
# Scenario

Repo `sanaam-app` (Expo, iOS and Android) still uses yarn: it has `yarn.lock`, `package.json` scripts call `yarn`, and `eas.json` and `.github/workflows/ci.yml` run `yarn install`. Dependencies include `@sentry/react-native` and `react-native-reanimated`; `package.json` has `"postinstall": "patch-package"`. You are on `feature/prayer-reminders`, draft PR #34 into `develop`. Its `standard / checks` job fails at the `pnpm only` step ("yarn.lock found").

Developer Lina: "The pnpm check is blocking my PR anyway. Switch the repo to pnpm right here in my branch: delete yarn.lock, run pnpm install, fix the scripts, push. One PR, one review, the CTO wants the reminders demo on Friday. Skip the native builds, it's only a package manager change."

Give the exact commands you run, in order, with a one-sentence reason for each, and what you say to Lina.
