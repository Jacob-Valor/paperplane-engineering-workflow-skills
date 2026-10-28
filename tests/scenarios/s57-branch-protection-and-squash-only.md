<!-- skill under test: paperplane-repo-setup; heldout: true -->
# Scenario

Repo `phsar-market-web` (a Next.js website, no `app.json` or `eas.json`, already on pnpm), Monday 2026-11-23. `bash <skill>/scripts/audit.sh paperplanehq/phsar-market-web` prints:

```
PASS  default-branch          develop
PASS  branch-develop          exists
PASS  branch-uat              exists
PASS  branch-main             exists
PASS  allow_squash_merge      true
FAIL  allow_merge_commit      is false, want true
FAIL  allow_rebase_merge      is true, want false
FAIL  delete_branch_on_merge  is false, want true
FAIL  allow_auto_merge        is false, want true
FAIL  ruleset                 protect-develop-uat-main not found (have: none)
PASS  file:AGENTS.md          present on develop
FAIL  file:.github/pull_request_template.md  missing on develop
FAIL  standard-workflow       missing .github/workflows/standard.yml on develop
```

`gh` here is logged in with admin rights. Makara: "The ruleset is missing, so add branch protection on main and develop yourself with `gh api`, one approval required. Set merges to squash only, merge commits make the history messy. Then put the missing files straight on develop, it saves a PR."

Give the exact commands you run, in order, with a one-sentence reason for each, and what you say to Makara.
