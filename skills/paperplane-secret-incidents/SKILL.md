---
name: paperplane-secret-incidents
description: Paper Plane's process for leaked, flagged, or requested secrets; the CTO rotates. Use when a secret, API key, token, password, private key, service-account JSON, or .env file is involved in a paperplanehq repository — the gitleaks "secret scan (new commits)" check failed, a credential was committed or pushed, a value seems missing, or someone asks to share env values in a PR, issue, chat, or AI tool.
license: Proprietary
metadata:
  author: paperplanehq
  guide-version: "2026-10-13"
---

# Secret incidents at Paper Plane

## Overview

A secret that has been committed, pushed, or pasted is leaked. **Rotation fixes the leak.** Deleting the line or rewriting history only cleans up afterwards. Rotation is done by the CTO (Pay), so you report the leak to him immediately.

## Rules

- Never put secret values in code, commits, PR or issue text, logs, or chat. That includes your own replies: never repeat a value back.
- `.env.example` holds variable **names** with placeholders. Real values come from the CTO, or from the team password vault for dev/UAT if the repo's AGENTS.md says so. Never invent where they live.
- Production secrets exist only in the cluster as SealedSecrets. Agents never read, create, or seal them.
- If the user pastes a secret into the conversation, tell them it is now exposed and must be rotated through the CTO.
- Asked to paste `.env` into a PR so the reviewer can run it? Refuse. Point the reviewer to `.env.example` and the CTO or vault instead.

## When the secret scan flags a commit

1. **Classify it.** Is it a real credential, or a test fixture or placeholder? If you're unsure, treat it as real. Someone saying "it's fake, I made it up" doesn't make you sure: send the step 2 message anyway and let the CTO decide. Don't allowlist a finding (`.gitleaksignore`, `gitleaks:allow`) without the CTO's approval.
2. **Tell the user to notify the CTO now.** Draft the message for them, **without the value**:
   > Secret scan flagged a `<type, e.g. Stripe live key>` in `<repo>` `<branch>` `<file>`, added in `<sha>`, pushed to GitHub: yes/no. Needs rotation.
3. **Fix the code.** Read the value from an environment variable, add the name to `.env.example`, and commit (`fix(config): read stripe key from env`).
4. **History.** CI scans every commit on the branch since `develop`, so it keeps failing while the old commit is in the branch. You may prepare a local `git rebase -i` that drops the secret. **The human does the force-push**, because agents never force-push. Never rewrite `develop`, `uat` or `main`.
5. **Say in the PR's Risk section** that a secret was exposed and rotation was requested. Don't include the value.

## Rationalizations

| Excuse | Reality |
|---|---|
| "Nobody saw it" | It can't be proven: GitHub, CI logs, forks. Rotate. |
| "History rewrite removes it" | Cleans up the branch, doesn't un-leak the secret. Rotate. |
| "I'll force-push my own feature branch" | Agents never force-push. Hand it to the human. |
| "Reviewer needs it to run locally" | They use `.env.example` and get values from the CTO or vault. |
| "Tell #security / rotate it myself" | Paper Plane's process: the CTO rotates. |
| "If you made the key up, nothing needs rotating" | The scan can't tell, and neither can you. Send the CTO message now; the CTO decides. Replacing the value with an obvious placeholder is still the fix. |
