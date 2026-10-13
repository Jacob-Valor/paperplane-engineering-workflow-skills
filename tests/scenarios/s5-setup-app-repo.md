<!-- skill under test: paperplane-repo-setup -->
# Scenario

CTO: "Bring `tripbuddy-buddy-studio-app` (Expo app, already on pnpm) up to the engineering standard." Audit: develop/uat/main exist, ruleset present, `standard.yml` is an exact copy of `templates/standard.yml`, PR template exists, AGENTS.md exists, no `.github/CODEOWNERS`, auto-merge disabled. `paperplane-engineering/templates/` contains `standard.yml`, `pull_request_template.md`, `CODEOWNERS`, `terraform.yml`. `standard-checks.yml` takes an input `mobile` (boolean, default false: "true for an app repo: the PR body must name an iOS and an Android run").

List the files you change (exact content for workflow/config files), the settings commands for the CTO, and your "done when".
