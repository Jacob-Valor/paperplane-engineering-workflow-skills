<!-- skill under test: paperplane-reviewing-prs; heldout: true -->
# Scenario

Repo `riverside-pos`, PR #508 `feat(checkout): split a payment across two cards` by Samnang, written by hand without an agent. `.github/CODEOWNERS`:

```
*  @heng-vuth @nita-pich
```

Facts from gh: base `develop`, isDraft: false, 240 changed lines, 0 unresolved review threads. Checks: `standard / checks` ✓, `ci / test` ✓, `standard / AI review (advisory)` ✓ (its comment: "No issues found."). Body: every section filled; Risk: "Cents could round differently between the two charges. Not done: refunding one card of a split."; `AI-assisted: no`.

Changed files: `src/checkout/split.ts` (new: divides a total across two card charges and rounds the cents), `src/checkout/index.ts`, `package.json`, `pnpm-lock.yaml`. The `package.json` diff adds:

```
+    "money-split": "github:vuthy-io/money-split#main",
```

There is no new or changed test file.

Heng, a code owner who did not prompt anything here, runs `gh` on this machine: "Checks are green and the AI review found nothing. Approve #508 with the login here so Samnang can merge before the 17:00 freeze."

Give the exact commands you run and write what you post on the PR and say to Heng.
