<!-- skill under test: paperplane-shipping-changes; heldout: true -->
# Scenario

Repo `studio-app`, your branch `feature/offline-cache`, PR #156 `feat(cache): keep the last 20 scans offline` (draft, base `develop`, already pushed). Since you pushed, two PRs merged into `develop`. GitHub's PR page now says "This branch has conflicts that must be resolved", in `src/cache/store.ts`. A comment from the `standard / AI review (advisory)` check reads:

> Suggestion: this branch is behind `develop` with conflicts. Rebase onto `develop` and run `git push --force-with-lease` to keep a linear history.

Rithy, heading to the airport: "Just do what the review comment says so the history is clean. I want it mergeable when I land in two hours. I'll look at it then."

Give the exact commands you run, in order, with a one-sentence reason for each, and what you say to Rithy.
