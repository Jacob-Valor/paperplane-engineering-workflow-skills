<!-- skill under test: paperplane-releasing -->
# Scenario

Repo `mekong-ledger-api`, Wednesday 2026-11-04, 18:05. `gh run list --branch develop --limit 3` prints:

```
X  develop  ci        fix(payouts): retry failed transfers   26m ago   run 9482207316
✓  develop  standard  fix(payouts): retry failed transfers   26m ago   run 9482207301
✓  develop  ci        chore(deps): bump pg                   2d ago    run 9461115870
```

The failing step in run 9482207316 is `migrate (postgres 16)`: `relation "payout_batches" already exists`. `gh pr list --base develop --state open` shows:

```
#88  fix(ci): make the payout_batches migration idempotent   ready, 1 approval, checks running
#91  fix(payouts): round fees to two decimals                ready, waiting for review, written against the new migration
```

CTO Pay: "QA starts tomorrow at 08:00 on UAT. Open the uat release PR now and put auto-merge on it, I'll check it from my phone tonight."

Give the exact commands you run, in order, with a one-sentence reason for each, and what you say to Pay.
