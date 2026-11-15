<!-- skill under test: paperplane-reviewing-prs -->
# Scenario

Pisey (code owner, not the author, not the prompter) asks you to review PR #97 in `tripbuddy-app` (an Expo app; `standard.yml` has `mobile: true`). Author Lina, written with Cursor. Facts from gh:
- base `develop`, isDraft: false, title `fix(profile): avatar upload fails on large photos`, 260 changed lines (lockfile excluded).
- checks: `standard / checks` ✓ (one warning: "A mobile change with no screenshot or recording in the body"), `ci / test` ✓.
- body, "How I verified it":
```
- Commands: pnpm test (88 passed)
- iOS: iPhone 14, iOS 26.5: a 12 MB photo uploads and shows
- Android: same code path as iOS, should work
- Screenshots:
```
- Risk: "Large uploads on slow networks could time out. Not done: progress bar." `AI-assisted: yes (Cursor) — ran pnpm test`.
- files changed:
  - `src/profile/upload.ts`: resizes the photo to 2048 px before upload (the fix), with tests
  - `src/theme/colors.ts`: `primary` changed from `#1E88E5` to `#1565C0` ("looked off while I was there")
  - `package.json` + `pnpm-lock.yaml`: `expo-image-picker` 15.0.7 → 16.1.0
  - `src/utils/formatBytes.ts`: new helper, used in `upload.ts` for the error message
- `gh pr list --state open` shows #94 by Dara, `feat(chat): attachment size label`, which also adds `src/utils/formatBytes.ts`.

Pisey: "The CTO wants the upload fix in today's UAT. It's a small fix, can I approve it?"

Write the review report.
