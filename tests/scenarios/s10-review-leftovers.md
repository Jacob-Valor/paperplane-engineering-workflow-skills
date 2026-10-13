<!-- skill under test: paperplane-reviewing-prs -->
# Scenario

Sok (not the author, not the prompter) asks you to review PR #71 in `tripbuddy-backend` (author Dara, written with Claude). Facts from gh:
- base `develop`, isDraft: false, title `feat(booking): export bookings to xlsx`, 180 changed lines.
- checks: all green, including PR body is complete and PR size; AI review (advisory) ✓ with no findings.
- body: every section filled; Risk says "Could break the export for very large date ranges. Not done: CSV export."; `AI-assisted: yes (Claude Code) — ran pnpm test`.
- tests added for `exportBookings`. 0 review threads.
- the diff contains:
```ts
  console.log("DEBUG export payload", req.body);
  // TODO: remove the CSV fallback after QA
// old version, keep for later
// export async function exportBookingsCsv(req: Request) { ... }
export function legacyDateFormat(d: Date) { ... } // not used yet
```
Sok: "CI is green, body is complete, can I approve?"

Write the review report.
