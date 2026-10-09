# Paper Plane engineering workflow skills

Agent skills that encode the [Paper Plane engineering guide](https://github.com/paperplanehq/paperplane-engineering)
for every repository in the `paperplanehq` GitHub org. They follow the
[Agent Skills specification](https://agentskills.io/specification) and install with the
[`skills` CLI](https://github.com/vercel-labs/skills) into Claude Code, Codex, Cursor, Pi and other agents.

The skills hold agents to the same rules as people: work on a branch, open a PR into `develop`,
use pnpm only, keep secrets out of git, and leave merging, releasing and deploying to humans.

## Skills

| Skill | Use it when |
|---|---|
| [`paperplane-shipping-changes`](skills/paperplane-shipping-changes/SKILL.md) | Any code, config or dependency change: branch, commit, `pnpm add`, push, PR into `develop` |
| [`paperplane-reviewing-prs`](skills/paperplane-reviewing-prs/SKILL.md) | Reviewing a teammate's PR. Produces a findings report; a human approves and merges |
| [`paperplane-secret-incidents`](skills/paperplane-secret-incidents/SKILL.md) | gitleaks fails, a credential was committed or pasted, someone asks for `.env` values |
| [`paperplane-releasing`](skills/paperplane-releasing/SKILL.md) | Release PRs `develop → uat → main`, `prod-YYYY.MM.DD` tags, rollback, hotfixes, `app-vX.Y.Z` store tags |
| [`paperplane-repo-setup`](skills/paperplane-repo-setup/SKILL.md) | Onboarding a repo: standard CI, PR template, `AGENTS.md`, pnpm migration, branches |

Agents load a skill automatically when the request matches its description. You can also ask for
one by name: "use paperplane-shipping-changes".

## Which skills for your role

The guide has three human roles and no rules by job title. Full-stack, backend, frontend, mobile,
senior, tech lead: all are **developers**. Any developer can be a **reviewer**, as long as they
didn't write the PR and didn't prompt the agent that wrote it. The **CTO** (Pay) owns releases.

● every week · ◐ when it comes up · — not needed

| Guide role | shipping-changes | reviewing-prs | secret-incidents | releasing | repo-setup |
|---|---|---|---|---|---|
| Developer | ● | — | ◐ | ◐ | ◐ |
| Reviewer | — | ● | ◐ | — | — |
| CTO | — | ◐ | ● | ● | ● |

- **Developer:** every change is a branch and a PR into `develop` (guide §2–5). Use
  `paperplane-releasing` only for a hotfix, which you do "with the CTO" (§2). Use
  `paperplane-repo-setup` to write the file PRs for a repo (`chore/pnpm`, `chore/engineering-standard`).
  Mobile changes (TripBuddy, Sanaam, Studio apps) are verified on iOS **and** Android before the PR
  opens (§4); that is the only rule that depends on what you work on.
- **Reviewer:** checks the description matches the diff, CI is green, no secrets or `.env`, no
  `package-lock.json`/`yarn.lock`/`bun.lock`, tests for new logic, mobile verified on both platforms
  (§4). Then approves and squash-merges. A secret in the diff hands off to `paperplane-secret-incidents`.
- **CTO:** merges `develop → uat → main` with merge commits, tags `prod-YYYY.MM.DD`, deploys (§8).
  Gets told at once about leaked secrets, which must be rotated (§6). Applies repo settings that
  repo-setup writes out.

## What agents will and won't do

Agents follow the same rules as developers (§7), with less authority:

| Agents do | A person does instead |
|---|---|
| Work on a feature branch; commit as `type(scope): summary`; stage files by name | — |
| Show the person running them the full diff and wait for a go-ahead | That person reviews every line before the PR opens |
| Push their branch and open a PR into `develop` marked `AI-assisted: yes` | A reviewer approves and merges |
| Prepare release PRs, compute the `prod-*` tag, write out the commands | The CTO merges to `uat`/`main`, tags and deploys |
| Draft the CTO notification for a leaked secret, without the value | The CTO rotates it and approves any gitleaks allowlist entry |
| Prepare a history rewrite locally | A person force-pushes |

Nobody, person or agent, pushes directly to `develop`, `uat` or `main`, runs `npm install`, `yarn` or
`bun install`, commits a second lockfile, or commits or pastes a secret (§2, §5, §6). A rule that
doesn't fit your case: ask the CTO before working around it. Asking the agent isn't enough, even
when the CTO is the one asking.

## Install

The skills are installed from the private repo `paperplanehq/paperplane-engineering` once they are
merged into its `develop` branch. Installing uses your existing git or `gh` login.

```bash
# all skills, globally, for every agent on this machine
pnpm dlx skills add paperplanehq/paperplane-engineering -g --skill '*'

# update later
pnpm dlx skills update -g

# list what's available without installing
pnpm dlx skills add paperplanehq/paperplane-engineering --list
```

From a local checkout of this folder:

```bash
pnpm dlx skills add . -g --skill '*'
```

## Changing a skill

Skills are tested like code: write a pressure scenario, watch an agent without the skill fail it,
change the skill, and confirm agents with the skill pass it.

1. Write a scenario that tempts the violation with 3 or more pressures (deadline, someone senior
   asking, admin access, "I take responsibility"). Ask for exact commands and messages.
2. Run it on fresh agents, at least 3 with the skill and 2 without. If agents without the skill
   already behave correctly, there is nothing to fix.
3. Edit the `SKILL.md`. Put the excuses agents gave, word for word, in its **Rationalizations** table.
4. Re-run until every run with the skill passes.
5. Validate and open a PR into `develop` (see `paperplane-shipping-changes`):

```bash
uvx --from "git+https://github.com/agentskills/agentskills#subdirectory=skills-ref" \
  skills-ref validate skills/<skill-name>
pnpm dlx skills add . --list    # every skill still discovered
```

Rules for `SKILL.md`:

- `name` is lowercase with hyphens and matches the folder name.
- `description` starts with "Use when…" and lists triggers only, not the workflow. Agents that read
  a workflow summary in the description follow it and skip the body.
- Keep the body under 500 lines. Quote the guide; don't invent policy. If the guide changes,
  update the skill in the same PR or the next one.
