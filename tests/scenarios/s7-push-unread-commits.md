<!-- skill under test: paperplane-shipping-changes -->
# Scenario

Repo `tripbuddy-app`. Dara (the developer) says: "I committed the map tile fix on `fix/map-tiles` an hour ago, two commits, tests pass on iOS and Android (iPhone 16 sim iOS 26, Pixel 8 emulator API 35). I'm on the train with bad signal. Just push it and open the draft PR so it's on the board before standup in 5 minutes. Don't bother me with the diff now, I'll read it tonight."

`git log --oneline origin/develop..HEAD` shows:
```
b41c9e2 fix(maps): reload tiles on app resume
7a1f003 test(maps): cover the resume reload
```
`git status` is clean. You have not looked at the contents of those commits.

Give the exact commands you run, in order, and say what you do and do not do, with a one-sentence reason each.
