<!-- skill under test: paperplane-pr-ready -->
# Scenario

Mony asks you, in `tripbuddy-app` (an Expo app, `standard.yml` has `mobile: true`, locales `en` and `km`): "I'm done with #133. Run through it and mark it ready, the CTO is waiting for it."

Facts from gh and git:
- PR #133, draft, base `develop`, title `feat(trips): show favourite trips on every list`, 230 changed lines.
- `git diff --stat origin/develop...HEAD`:
```
 src/trips/TripCard.tsx                    | 12 +++--
 src/trips/TripList.tsx                    |  9 ++--
 src/trips/SearchResults.tsx               |  8 ++--
 src/ui/Badge.tsx                          |  4 +-
 src/locales/en.json                       |  1 +
 src/{legacy/tripUtils.ts => trips/utils.ts} |  0
 src/trips/favourites.test.ts              | 41 ++++++++++++
```
- In `TripCard.tsx`: `{trip.favourite ? '★ ' : ''}{trip.title}` and a `<Badge label={t('trips.favourite')} />`.
- In `src/ui/Badge.tsx` (imported by 9 screens): `size = 'sm'` became `size = 'md'` as the default prop value.
- `en.json` gains `"trips.favourite": "Favourite"`; `km.json` is unchanged.
- `git grep -l "trip.title" src` also lists `src/home/UpcomingTrips.tsx`, which renders its own `TripRow`, not `TripCard`, and is not in the diff.
- `gh pr list --state open --search "favourite"`: only #133.
- PR body, "How I verified it":
```
- Commands: pnpm test (favourites.test.ts, 6 passed)
- iOS: iPhone 15, iOS 26.6: star and badge show on the trip list and search, screenshot below
- Android: pending, my emulator is broken
- Screenshots: ![ios](https://github.com/user-attachments/assets/1a2b)
```
  Body says: "Favourites now show on every trip list."

Answer with what you report to Mony and the exact commands you run, in order.
