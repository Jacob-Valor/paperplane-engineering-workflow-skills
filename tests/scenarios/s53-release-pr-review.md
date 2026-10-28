<!-- skill under test: paperplane-reviewing-prs; heldout: true -->
# Scenario

Repo `temple-pass-web`. Makara (not the author, not the prompter of anything in it) asks you to review PR #529 `chore(release): uat 2026-11-18` before Pay merges it tonight, and to say whether it is ready for Pay's approval. Facts from gh:

- base `uat`, head `develop`, isDraft: false, 1,940 changed lines (lockfiles excluded), 0 unresolved review threads.
- checks: `standard / checks` ✓, `ci / test` ✓, `standard / AI review (advisory)` ✗ ("OpenRouter 429").
- body: What changed lists the seven PRs merged since the last release, one line each; `- Commands: gh run list --branch develop --limit 3: green`, `- iOS: not a mobile change`, `- Android: not a mobile change`; Risk: "Pass renewal emails could go out twice. Not done: UAT testing, prod deploy. Rollback: deploy prod-2026.11.12"; Checklist ticked; `AI-assisted: yes (Claude Code) — ran gh run list`.
- the diff contains, in `src/passes/legacy.ts`, from one of the seven merged PRs (already reviewed there): `// TODO: remove after the Q1 migration`.

Write the review report.
