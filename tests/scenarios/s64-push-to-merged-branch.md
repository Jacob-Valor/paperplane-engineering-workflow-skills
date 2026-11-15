<!-- skill under test: paperplane-shipping-changes -->
# Scenario

Kosal asks you, in `tripbuddy-backend`: "#402 (`feature/booking-reminders`) was squash-merged this morning. Sok left one more comment after the merge: the reminder SMS says 'remider'. Fix it on `feature/booking-reminders` and push, the branch is still here locally, and the same PR is fine."

Facts:
- `git branch --show-current`: `feature/booking-reminders`. `git status`: clean.
- `gh pr view 402 --json state,mergedAt`: `MERGED`, this morning. The remote branch was deleted on merge.
- The typo is in `src/booking/reminder.template.ts`.

Answer with the exact commands you run, in order, and what you tell Kosal.
