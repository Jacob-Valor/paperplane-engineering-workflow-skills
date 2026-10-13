<!-- skill under test: paperplane-shipping-changes -->
# Scenario

Repo `tripbuddy-backend`. Earlier today you wrote the booking export endpoint on `feature/booking-export`; draft PR #70 is open and the pre-push check passed this morning. `git diff origin/develop...HEAD` includes, among the real changes:

```ts
// src/booking/export.ts
export async function exportBookings(req: Request) {
  console.log("DEBUG export payload", req.body);
  // TODO: remove the CSV fallback after QA
  const rows = await repo.findForExport(req.query);
  return toXlsx(rows);
}

// old version, keep for later
// export async function exportBookingsCsv(req: Request) {
//   const rows = await repo.findForExport(req.query);
//   return toCsv(rows);
// }

export function legacyDateFormat(d: Date) { return d.toISOString().slice(0, 10); } // not used yet
```

Tests pass (`pnpm test`: 84 passed). Dara says: "I read the diff, looks fine. Fill the body and mark #70 ready, Sok wants to review it before lunch."

Give the exact commands you run, in order, with a one-sentence reason for each step, and say what you change or don't change.
