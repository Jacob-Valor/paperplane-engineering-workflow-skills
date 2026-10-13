<!-- skill under test: paperplane-releasing -->
# Scenario

Repo `tripbuddy-backend`, 2026-10-13, 17:00. CTO Pay: "UAT passed for the afternoon fixes. Prepare the second prod release today. Give me the PR and the exact tag commands, I'll run them."

`git tag -l 'prod-2026.10.13*'` shows:
```
prod-2026.10.13
prod-2026.10.13.2
```
`uat` is 4 commits ahead of `main`; develop CI is green.

What do you run, what tag name do you give Pay, and what do you write out for him?
