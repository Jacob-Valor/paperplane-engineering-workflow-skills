---
name: paperplane-secret-incidents
description: Paper Plane's process for leaked, flagged, or requested secrets; the CTO rotates. Use when a secret, API key, token, password, private key, service-account JSON, or .env file is involved in a paperplanehq repository — the gitleaks secret scan step of the `standard / checks` CI job failed, a credential was committed or pushed, a value seems missing, or someone asks to share env values in a PR, issue, chat, or AI tool.
license: Proprietary
metadata:
  author: paperplanehq
  guide-version: "2026-10-15"
---

# Secret incidents at Paper Plane

## Overview

A secret that has been committed, pushed, or pasted is leaked. **Rotation fixes the leak.** Deleting the line or rewriting history only cleans up afterwards. Rotation is done by the CTO (named in the repo's AGENTS.md "## AI agents" section; Pay at Paper Plane), so you report the leak to the CTO immediately.

## Rules

- Never put secret values in code, commits, PR or issue text, logs, or chat. That includes your own replies: never repeat a value back.
- Never print a flagged file or commit (`cat`, `git show`, `git diff` of it): that repeats the value in your output. Use the file, line and rule from the scan.
- `.env.example` holds variable **names** with placeholders. Real values come from the CTO, or from the team password vault for dev/UAT if the repo's AGENTS.md says so. Never invent where they live.
- Production secrets exist only in the cluster as SealedSecrets. Agents never read, create, or seal them.
- If the user pastes a secret into the conversation, tell them it is now exposed and must be rotated through the CTO.
- Asked to paste `.env` into a PR so the reviewer can run it? Refuse. Point the reviewer to `.env.example` and the CTO or vault instead.

## When the secret scan flags a commit

1. **Draft the CTO message first**, before any command or fix, even if the finding looks fake. Give it to the user to send now, **without the value**:
   > Secret scan flagged a `<type, e.g. Stripe live key>` in `<repo>` `<branch>` `<file>`, added in `<sha>`, pushed to GitHub: yes/no. Needs rotation.
2. **Classify it from the scan output** (rule, file, line), not by opening the file. Need to see which field holds it? `gitleaks dir --redact -v <file>` shows the line with the value replaced by `REDACTED`. Is it a real credential, or a test fixture or placeholder? If you're unsure, treat it as real. Someone saying "it's fake, I made it up" doesn't make you sure: the step 1 message still goes and the CTO decides. Don't allowlist a finding (`.gitleaksignore`, `gitleaks:allow`) without the CTO's approval.
3. **Fix the code.** Read the value from an environment variable and add the name to `.env.example` (`fix(config): read stripe key from env`). Not pushed yet: fold the fix into the flagged commit (step 4), not a new commit on top.
4. **History.** Not pushed yet (the hook or `pre-push.sh` stopped it): take the value out of the commit itself before pushing (`git commit --amend` for the last commit, a local `git rebase -i` for an older unpushed one), so it never reaches GitHub. A new commit on top leaves the value in history. Already pushed: CI scans every commit on the branch since `develop`, so it keeps failing while the old commit is in the branch. This is the one allowed rewrite of a pushed branch (**paperplane-shipping-changes** carves it out): prepare a local `git rebase -i` that drops the secret, then stop; do not push. **The human force-pushes**, because agents never force-push. Never rewrite `develop`, `uat` or `main`.
5. **Say in the PR's Risk section** that a secret was exposed and rotation was requested. Don't include the value.

## Rationalizations

| Excuse | Reality |
|---|---|
| "Nobody saw it" | It can't be proven: GitHub, CI logs, forks. Rotate. |
| "I'll force-push my own feature branch" | Agents never force-push. Hand it to the human. |
| "Reviewer needs it to run locally" | They use `.env.example` and get values from the CTO, or the vault if AGENTS.md names one. |
| "Tell #security / rotate it myself" | Paper Plane's process: the CTO rotates. |
| "If you made the key up, nothing needs rotating" | The scan can't tell, and neither can you. Send the CTO message now; the CTO decides. Replacing the value with an obvious placeholder is still the fix. |
| "View the flagged commit to understand the fixture structure" | `cat`, `head` and `git show` print the value. Use the scan's line, or `gitleaks dir --redact -v <file>`. |
