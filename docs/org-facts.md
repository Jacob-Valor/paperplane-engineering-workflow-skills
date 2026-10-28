# Org facts

The one place that lists what is specific to Paper Plane. When you fork these skills for another
org, edit the values below, then change the strings the grep command in the README lists. Nothing
reads this file at run time; it is a checklist for the fork.

| Fact | Paper Plane value | Where it appears |
|---|---|---|
| GitHub org slug | `paperplanehq` | skill `compatibility`/`author` fields, `repo-setup`, `audit.sh`, hook comments, README |
| Guide repo (source of truth, templates) | `paperplanehq/paperplane-engineering` | `shipping-changes`, `repo-setup`, README |
| CTO role | The CTO is named in the repo's `AGENTS.md` "## AI agents" section (at Paper Plane: Pay). Each skill defines this once and says "the CTO" after that | every skill; the name `Pay` appears only in that one sentence |
| Branches | `develop` (work), `uat` (staging), `main` (production) | all skills, hooks, `audit.sh` |
| Org rulesets (team convention, not in the guide; see [open questions](open-questions-for-cto.md)) | `protect-develop-uat-main`, `release-tags-owner-only` | `releasing`, `repo-setup` |
| Required CI check | `standard / checks`, from `standard-checks.yml@develop` | `reviewing-prs`, `repo-setup`, `audit.sh` |
| Release cadence and tags | `develop` to `uat` to `main`; `prod-YYYY.MM.DD` tags; `app-vX.Y.Z` store tags | `releasing`, `next-tag.sh` |
| Where the guide lives | `paperplanehq/paperplane-engineering` README, read after the repo's `AGENTS.md` | `shipping-changes` |
| Guide version | `2026-10-15` (`metadata.guide-version`) | every `SKILL.md`, `tests/drift/` |
| App repos (need iOS and Android checks) | TripBuddy, Sanaam, Studio | `shipping-changes` |

Rules that are not org facts (agents never merge or force-push, drafts only, pnpm only) are kept
identical across skills by `tests/scripts/test-skills-lint.sh`.
