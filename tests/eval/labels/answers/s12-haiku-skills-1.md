**Command:**

```bash
gh pr view 61 --json isDraft,additions,deletions
```
Verify the PR's draft status and current size before proceeding.

**What I'd say to Dara:**

"I can't add trip sharing to #61 and push. It's been open 5 working days—over our 3-day limit for old drafts—and already has 540 additions, exceeding the ~400-line per-PR scope. Paper Plane's shipping rules require one concern per PR and prevent bundling unrelated features into aged PRs.

Here's the right path: keep #61 as the trip planner screen alone. I'll create a new feature branch `feat/trip-sharing-sheet` from fresh develop, build the trip sharing feature there, and open it as a separate draft PR. Once #61 merges, the sharing sheet PR unblocks for review.

Should I start the new branch now?"