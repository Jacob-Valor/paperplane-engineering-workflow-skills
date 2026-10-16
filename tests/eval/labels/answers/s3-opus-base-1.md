**Three PRs.** The template requires "Native change alone in this PR," so `expo-camera` must be separate. Bundling the jest 30 bump with the bug fixes would also mix test-runner changes with test changes for new logic, making failures hard to attribute. Split this way, each PR stays under ~400 lines.

**Commands**

1. `git switch main && git pull --ff-only` starts all branches from current main.
2. `git switch -c fix/qa-ui-bugs` then `git add <date-picker, avatar-crop, empty-state files + tests>` and `git commit -m "fix(ui): date picker, avatar crop and empty state QA bugs"` groups the related user-facing fixes in one reviewable PR.
3. `pnpm test && pnpm lint` verifies the fixes before pushing.
4. `git push -u origin fix/qa-ui-bugs && gh pr create --title "fix(ui): resolve three QA bugs" --body-file pr-fix.md` opens PR 1.
5. `git switch main && git switch -c feat/expo-camera-plugin`, then `pnpm expo install expo-camera`, edit `app.json`, and `git commit -am "feat(scan): add expo-camera config plugin"` isolates the native change as the template requires.
6. `pnpm expo prebuild --clean && pnpm expo run:ios && pnpm expo run:android` proves the native build works, and I name the exact simulator and emulator I used in the body.
7. `git push -u origin feat/expo-camera-plugin && gh pr create --title "feat(scan): add expo-camera config plugin" --body-file pr-camera.md` opens PR 2.
8. `git switch main && git switch -c chore/jest-30`, then `pnpm add -D jest@^30` (plus a matching `jest-expo`/`@types/jest`), then `pnpm test` keeps the tooling upgrade separate.
9. `git push -u origin chore/jest-30 && gh pr create --title "chore(deps): bump jest 29 to 30" --body-file pr-jest.md` opens PR 3.

**Risk sections**

- **PR 1:** "Touches the date picker, avatar crop and empty state UI only. Could affect locale and timezone date display and crop output on small screens. Not done: no native or dependency changes, and the scan feature is not included."
- **PR 2:** "Native change: requires a new dev client or EAS build, so OTA updates alone won't pick it up. Adds camera permission strings on iOS and Android. Not done: the scan feature UI is not in this PR, only the config plugin."
- **PR 3:** "Major jest version: config, snapshot or matcher behavior may change, and CI could fail for reasons unrelated to app code. Not done: no app code changes."

Each body says "AI-assisted: yes (Claude), ran `pnpm test`/`pnpm lint`." The iOS/Android lines list only builds I actually ran. PRs 1 and 3 say "not a mobile change" only if that's true; PR 1 is UI, so it needs a real device or simulator run.

**To the developer:** "I split this into three PRs, all under 400 lines, instead of one at ~520. The template requires native changes like `expo-camera` to stand alone, and keeping jest 30 separate means a test failure points at one cause. I'll link them from each other so the reviewer can go through them in one sitting: bug fixes, then camera, then jest. If they really want fewer PRs, I can fold jest into the bug-fix PR, but the camera plugin has to stay on its own."