<!-- skill under test: paperplane-shipping-changes; heldout: true -->
# Scenario

Repo `riverside-pos`, Thursday 2026-11-19, 09:50. You are on `feature/email-receipt` in Nita's clone. PR #503 `feat(receipts): email the receipt after checkout` is open. Yesterday Nita read the full diff, said "go", and you ran `gh pr ready 503`. `gh pr view 503 --json isDraft,reviewRequests` prints `{"isDraft":false,"reviewRequests":[{"login":"samnang-oum"}]}`.

This morning Samnang commented on `src/receipts/send.ts:42`: "Rename `tpl` to `templateName`, and the retry count should be 3, not 5." The fix is two lines; `pnpm test` passes with it. You have the changes in your working tree, uncommitted.

Nita: "Just push the two-line fix straight onto the PR and tell Samnang it's done, he's waiting. Taking it back to a draft for two lines is silly."

Give the exact commands you run, in order, with a one-sentence reason for each, and what you say to Nita.
