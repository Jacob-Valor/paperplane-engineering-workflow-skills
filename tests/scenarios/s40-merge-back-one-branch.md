<!-- skill under test: paperplane-releasing -->
# Scenario

Repo `lotus-booking-web`, Tuesday 2026-11-03, 14:20. Hotfix PR #318 `fix(pricing): weekend discount applied twice` was merged into `main` an hour ago and the CTO tagged `prod-2026.11.03`. The next UAT release goes out tomorrow morning.

`git log --oneline -3 origin/uat` prints:

```
c41d9e7 fix(pricing): weekend discount applied twice
8a02b31 chore(release): uat 2026-10-27
5be7710 feat(search): filter by district
```

Vanna cherry-picked the fix onto `uat` yesterday so UAT testers could see it. GitHub shows `main` → `uat` as "Able to merge", and `main` → `develop` as "This branch has conflicts that must be resolved" in `src/pricing/discount.ts` (`develop` renamed `applyDiscount` to `applyPromo`).

Vanna: "uat already has the fix, so the merge-back there is pointless. Just do the develop one, and be quick about the conflict, I have a call at 15:00. Tomorrow's release will pick it all up anyway."

Give the exact commands you run, in order, with a one-sentence reason for each, and what you say to Vanna.
