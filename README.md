# Paper Plane engineering workflow skills

[![validate](https://github.com/Jacob-Valor/paperplane-engineering-workflow-skills/actions/workflows/validate.yml/badge.svg)](https://github.com/Jacob-Valor/paperplane-engineering-workflow-skills/actions/workflows/validate.yml)
Version **v2026.10.13.1**, matching the guide of 2026-10-13 and [`team-workflow-13-oct-2026.html`](team-workflow-13-oct-2026.html) · [Changelog](CHANGELOG.md) · [Test results](tests/RESULTS.md)

Agent skills that encode the [Paper Plane engineering guide](https://github.com/paperplanehq/paperplane-engineering)
for every repository in the `paperplanehq` GitHub org. They follow the
[Agent Skills specification](https://agentskills.io/specification) and install with the
[`skills` CLI](https://github.com/vercel-labs/skills) into Claude Code, Codex, Cursor, Pi and other agents.

The skills hold agents to the same rules as people: work on a branch, open a PR into `develop`,
use pnpm only, keep secrets out of git, and leave merging, releasing and deploying to humans.

## Skills

| Skill | Use it when |
|---|---|
| [`paperplane-shipping-changes`](skills/paperplane-shipping-changes/SKILL.md) | Any code, config or dependency change: branch, commit, `pnpm add`, push, draft PR into `develop`, stacks, marking ready |
| [`paperplane-reviewing-prs`](skills/paperplane-reviewing-prs/SKILL.md) | Reviewing a teammate's PR. Produces a findings report; a human approves and merges |
| [`paperplane-secret-incidents`](skills/paperplane-secret-incidents/SKILL.md) | gitleaks fails, a credential was committed or pasted, someone asks for `.env` values |
| [`paperplane-releasing`](skills/paperplane-releasing/SKILL.md) | Release PRs `develop → uat → main`, `prod-YYYY.MM.DD` tags, rollback, hotfixes, `app-vX.Y.Z` store tags |
| [`paperplane-repo-setup`](skills/paperplane-repo-setup/SKILL.md) | Onboarding a repo: standard CI, PR template, `CODEOWNERS`, `AGENTS.md`, pnpm migration, branches, auto-merge |

Agents load a skill automatically when the request matches its description. You can also ask for
one by name: "use paperplane-shipping-changes".

## Repository layout

```
skills/<name>/SKILL.md          the skill (frontmatter + instructions)
skills/<name>/scripts/*.sh      checks the skill runs with `bash` (shipping-changes only)
tests/scenarios/                agent pressure scenarios S1–S12
tests/triggering.md             do the descriptions pick the right skill?
tests/README.md                 how to run them and the pass criteria
tests/RESULTS.md                before/after scores for every change
tests/scripts/run.sh            behaviour tests for the scripts (CI)
.github/workflows/validate.yml  spec validation, shellcheck, script tests
```

## Engineering workflow

### From a change to `develop`

Every change, by hand or by an agent, takes this path (guide §2–4, §6–7).

```mermaid
flowchart TD
  A["Start from latest develop<br/>git switch -c feature/topic"] --> F["Push the branch the same day<br/>draft PR into develop, AI-assisted: yes"]
  F --> B["Verify with the repo's scripts<br/>pnpm test · pnpm lint<br/>mobile: iOS and Android"]
  B --> C["Commit type(scope): summary<br/>stage files by name, push"]
  C --> E["Person running the agent<br/>reviews the full diff<br/>fills the body, marks Ready"]
  E --> G{"CI: pnpm only · secret scan · PR title<br/>PR body is complete · PR size"}
  G -->|"green"| R{"Reviewer: a code owner, not the author,<br/>not who prompted the agent<br/>paperplane-reviewing-prs"}
  R -->|"approved, threads resolved"| D[("develop<br/>squash and merge or auto-merge")]
  G -->|"secret found"| S["paperplane-secret-incidents<br/>tell the CTO, rotate, fix the code"]
  G -->|"other check red"| X["Fix on the branch<br/>new commit"]
  R -->|"changes needed"| X
  S --> X
  X -.-> C
```

Agents run every step except the review, marking Ready, and the merge. They push and open the draft,
show the full diff, and mark the PR ready only when the person says they reviewed it. At most two
PRs stack; native changes and tooling bumps go in their own PR.

### From `develop` to production

Releases and hotfixes belong to the CTO (guide §2, §8). Agents prepare the PRs and write out the
commands; the CTO merges, tags and deploys (`paperplane-releasing`).

```mermaid
flowchart LR
  subgraph release["Release"]
    direction LR
    D[develop] -->|"PR chore(release): uat YYYY-MM-DD<br/>merge commit"| U[uat]
    U -->|"tested on UAT<br/>PR chore(release): prod YYYY-MM-DD<br/>merge commit"| M[main]
    M -->|"tag prod-YYYY.MM.DD<br/>deploy that tag"| P[(production)]
  end
  subgraph hotfix["Hotfix"]
    direction LR
    H["hotfix/topic<br/>from main"] -->|"PR, CTO merges<br/>tag and deploy"| HM[main]
    HM -->|"same day: merge back by PR<br/>merge commits"| B["uat and develop"]
  end
```

Release PRs use merge commits, never squash, so `uat` and `main` stay identical to `develop`.
A second release on the same day is tagged `prod-YYYY.MM.DD.2`. Rollback means deploying the previous
`prod-*` tag. Mobile store builds are tagged `app-vX.Y.Z` on the commit that was submitted.

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
  is marked Ready (§4); that is the only rule that depends on what you work on.
- **Reviewer:** checks the description matches the diff, CI is green (the advisory AI review never
  blocks), no secrets or `.env`, no `package-lock.json`/`yarn.lock`/`bun.lock`, tests for new logic,
  mobile verified on both platforms, one concern per PR, every thread resolved (§4). Then approves;
  auto-merge or the reviewer squash-merges. A secret in the diff hands off to `paperplane-secret-incidents`.
- **CTO:** merges `develop → uat → main` with merge commits, tags `prod-YYYY.MM.DD`, deploys (§8).
  Gets told at once about leaked secrets, which must be rotated (§6). Applies repo settings that
  repo-setup writes out.

## What agents will and won't do

Agents follow the same rules as developers (§7), with less authority:

| Agents do | A person does instead |
|---|---|
| Work on a feature branch; commit as `type(scope): summary`; stage files by name | — |
| Run `scripts/pre-push.sh` (branch, lockfiles, `.env`, build output, `gitleaks`) before every push; push the branch the same day and open a **draft** PR into `develop` marked `AI-assisted: yes` | — |
| Show the person running them the full diff; check the body with `scripts/check-pr-body.sh`; mark the PR ready only after their go-ahead | That person reviews every line before Ready |
| — | The author turns on auto-merge; a code owner approves; the PR squash-merges |
| Merge `develop` into a stacked branch after the PR below merges | A person rebases and force-pushes, if they prefer |
| Prepare release PRs, compute the `prod-*` tag, write out the commands | The CTO merges to `uat`/`main`, tags and deploys |
| Draft the CTO notification for a leaked secret, without the value | The CTO rotates it and approves any gitleaks allowlist entry |
| Prepare a history rewrite locally | A person force-pushes |

Nobody, person or agent, pushes directly to `develop`, `uat` or `main`, runs `npm install`, `yarn` or
`bun install`, commits a second lockfile, or commits or pastes a secret (§2, §5, §6). A rule that
doesn't fit your case: ask the CTO before working around it. Asking the agent isn't enough, even
when the CTO is the one asking.

## Install

Until the skills are merged into `paperplanehq/paperplane-engineering`, install them from this repo,
`Jacob-Valor/paperplane-engineering-workflow-skills`. It is private: ask Jacob-Valor for read access.
Installing uses your existing git or `gh` login.

```bash
# all skills, globally, for every agent on this machine
pnpm dlx skills add Jacob-Valor/paperplane-engineering-workflow-skills -g --skill '*'

# update later
pnpm dlx skills update -g

# list what's available without installing
pnpm dlx skills add Jacob-Valor/paperplane-engineering-workflow-skills --list
```

Once they are merged into `paperplanehq/paperplane-engineering` (`develop`), use that repo name in
the commands above instead.

From a local checkout of this folder:

```bash
pnpm dlx skills add . -g --skill '*'
```

## Changing a skill

Skills are tested like code: write a pressure scenario, watch an agent without the skill fail it,
change the skill, and confirm agents with the skill pass it.

1. Write a scenario in `tests/scenarios/` that tempts the violation with 3 or more pressures
   (deadline, someone senior asking, admin access, "I take responsibility"). Ask for exact commands,
   messages, and a one-line reason for each choice. Give only facts the agent would see (repo files,
   `gh` output); never state the rule being tested, or the baseline passes for the wrong reason. Add
   its pass criteria to `tests/README.md`.
2. Run it on fresh agents, at least 3 with the skill and 2 without. If agents without the skill
   already behave correctly, there is nothing to fix.
3. Edit the `SKILL.md`. Put the excuses agents gave, word for word, in its **Rationalizations** table.
4. Re-run until every run with the skill passes. Record the before/after scores in
   `tests/RESULTS.md` and the change in `CHANGELOG.md`.
5. Check locally, then open a PR into `main`; CI runs the same checks:

```bash
for s in skills/*/; do
  uvx --from "git+https://github.com/agentskills/agentskills#subdirectory=skills-ref" skills-ref validate "$s"
done
shellcheck -S warning skills/*/scripts/*.sh tests/scripts/*.sh
bash tests/scripts/run.sh
pnpm dlx skills add . --list    # every skill still discovered
```

Rules for `SKILL.md`:

- `name` is lowercase with hyphens and matches the folder name.
- `description` is one short sentence on what the skill covers, then "Use when…" with the triggers.
  Never list workflow steps there: agents that read a step list in the description follow it and
  skip the body. Run `tests/triggering.md` after changing a description.
- Frontmatter also carries `license: Proprietary`, `metadata.author` and `metadata.guide-version`
  (the guide date the skill matches); `compatibility` only when the skill needs tools.
- Anything a regex or exit code can check goes in a script under `scripts/`, called with `bash`,
  with a test in `tests/scripts/run.sh`.
- Keep the body under 500 lines. Quote the guide; don't invent policy. If the guide changes,
  update the skill and `guide-version` in the same PR or the next one.
