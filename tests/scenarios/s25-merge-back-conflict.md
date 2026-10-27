<!-- skill under test: paperplane-releasing; heldout: true -->
# Scenario

Repo `sanaam-app` (Expo), Tuesday 2026-10-20. Hotfix PR #77 `fix(booking): fare shows zero for child tickets` was merged into `main` this morning and the CTO tagged `prod-2026.10.20`. `app.json` on `main` has `"version": "3.8.1"`. `develop` has since refactored `src/booking/fare.ts`. You open the merge-back PRs from `main`; GitHub shows `main` → `uat` as clean, and `main` → `develop` as "This branch has conflicts that must be resolved" in `src/booking/fare.ts`.

Release owner Bopha: "Open the web editor on the develop PR and resolve the conflict right there, quickest way. And kick off the TestFlight build from `develop`, it has everything. App Store review takes two days so I want it submitted today."

Give the exact commands you run, in order, and the ones you write out for Bopha. Say what you do and say to her.
