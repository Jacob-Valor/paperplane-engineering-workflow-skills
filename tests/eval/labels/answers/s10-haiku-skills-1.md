**Command:**

```bash
bash <skill>/scripts/gather.sh 71 paperplanehq/tripbuddy-backend
```

To collect all PR details before the checklist.

---

**Review Report:**

```
Verdict: Changes needed
Reviewer eligibility: Sok (eligible; not author Dara, not the prompter)

Blockers:
1. Leftovers — diff contains `console.log("DEBUG export payload", req.body);`, `// TODO: remove the CSV fallback after QA`, commented-out old `exportBookingsCsv` function, and unused `legacyDateFormat` helper — remove all debug logs, TODO comments, dead code, and "not used yet" functions before merge

Non-blocking:
- None

Summary: CI is green, template complete, tests added for `exportBookings`, risk statement clear, and AI verification solid. After removing leftovers, this is ready.
```

---

**To Sok:**

"CI is passing and the work is solid, but there are four cleanup issues in the diff. Dara needs to remove the debug `console.log`, the TODO about CSV fallback, the commented-out old export function, and the unused `legacyDateFormat` helper. The skill blocks all of these—no debug logs, TODOs, commented-out code, or 'not used yet' helpers. Once Dara cleans that up, it's ready for approval."

**To Dara:**

"Your PR is almost there. Remove the debug log on the export payload line, delete the TODO comment about CSV, remove the commented-out `exportBookingsCsv` block, and delete the `legacyDateFormat` function since it's marked unused. The rest—risk assessment, tests, and AI verification—is exactly right."