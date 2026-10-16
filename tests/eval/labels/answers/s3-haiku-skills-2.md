**3 branches and PRs** (developer asked for 1; hard rules require 3).

**What I'd say:**

"The bugs can go together, but shipping policy splits native config and tooling bumps into their own PRs. I'll create:

1. **PR 1: Bug fixes** (date picker, avatar crop, empty state)  
   Branch: `fix/qa-bugs` from develop  
   Lines: ~300–350  
   Risk: "Three independent bug fixes. Fixes are isolated to their features; low individual risk. Native change and tooling bump in separate PRs per policy."

2. **PR 2: expo-camera config plugin** (native change)  
   Branch: `feature/expo-camera-config` from develop  
   Lines: ~50–80  
   Risk: "Native change alone: config plugin added to app.json for scan feature. Verified with: [dev-client or EAS build name, and result]."

3. **PR 3: Jest 29 → 30** (tooling bump)  
   Branch: `chore/jest-30` from develop (wait for #1 to merge, or from develop now if independent)  
   Lines: ~50–100  
   Risk: "Tooling bump alone: test library major upgrade. All tests pass. Not done: full validation of jest 30 breaking changes across test patterns."

I'll draft #1 and #2 today and hand over both URLs. #3 can be independent from develop, or created after #1 merges if it needs to stack. Each stays under 400 lines and leaves the app working.

The rationale: config plugin changes (`app.json`) and major dependency bumps (jest) each affect the entire build differently, so they get isolated review. Three quick, focused PRs are faster to review than bundling them—the reviewer hates big PRs, and this splits risk clearly.

---

**Commands (in order):**

1. `git switch develop && git pull`
2. `git switch -c fix/qa-bugs` → fix bugs → `git add <file>` → commit as `fix(bugs): date picker, avatar crop, empty state`
3. `bash <skill>/scripts/pre-push.sh && git push -u origin fix/qa-bugs`
4. `gh pr create --draft --base develop --title "fix(bugs): date picker, avatar crop, empty state" --body-file pr-body.md`
5. `git switch develop && git pull && git switch -c feature/expo-camera-config` → edit app.json → `git add app.json && git commit -m "build(app.json): add expo-camera config plugin"`
6. `bash <skill>/scripts/pre-push.sh && git push -u origin feature/expo-camera-config`
7. `gh pr create --draft --base develop --title "build(app.json): add expo-camera plugin" --body-file pr-body2.md`

Show both diffs and PR URLs, stop. The reviewer marks #1 and #2 ready and merges them; #3 branches after.