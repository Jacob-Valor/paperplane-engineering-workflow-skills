**3 branches, 3 PRs** — not one. I'd tell the developer:

---

"The three bugs go together in one PR, but the expo-camera config and jest bump must be separate. Native changes and tooling bumps are their own PRs — that's a hard rule. Three focused diffs for the reviewer:

1. **fix(bugs): date picker, avatar crop, empty state** — ~300 lines
2. **feat(camera): add expo-camera to app.json** — native change alone  
3. **chore(testing): upgrade jest 29 to 30** — tooling bump alone

I'll branch all three from fresh develop and open them as drafts the same day."

---

**Branch 1:** `fix/bugs-picker-avatar-empty`  
**Risk:** "Three bugs verified on iOS (iPhone 14) and Android (Pixel 6, API 33). Could break: date picker if field binding logic changed; avatar crop if canvas dimensions altered; empty state if list query changed. Not done: none."

---

**Branch 2:** `feat/camera-config`  
**Risk:** "Native change: expo-camera plugin added to app.json. Verified with dev-client on iOS (iPhone 14 simulator) and Android (Emulator, API 33). Could break: native module linking if Expo SDK version mismatch. Build: dev-client."

---

**Branch 3:** `chore/jest-29-to-30`  
**Risk:** "Tooling bump: jest major version (29 → 30). Test suite runs and passes. Could break: tests relying on jest 29 API (matchers, async handling). CI runs full suite."

---

All three as drafts same day, all three shown as full diffs before the reviewer marks any ready. Branch 2 and 3 don't depend on each other—branch from develop, not stacked.