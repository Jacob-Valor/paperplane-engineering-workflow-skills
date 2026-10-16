To the CTO: "The audit shows two FAILs: CODEOWNERS is missing, and auto-merge is disabled. I'll open the setup PR; you'll enable auto-merge after it merges."

**Commands I'd run, in order:**

1. `git checkout -b chore/engineering-standard` — Create the feature branch for the PR.

2. `gh api -H "Accept: application/vnd.github.raw" repos/paperplanehq/paperplane-engineering/contents/templates/CODEOWNERS?ref=develop > .github/CODEOWNERS` — Copy the CODEOWNERS template.

3. Edit `.github/CODEOWNERS` to add two GitHub handles per line — (CTO provides the names; PR stays draft until filled.)

4. Create `CLAUDE.md` if it doesn't exist: `# CLAUDE.md`, `Read and follow AGENTS.md.`, then `@AGENTS.md` on the last line — Standard boilerplate required by the setup.

5. `git add .github/CODEOWNERS CLAUDE.md && git commit -m "chore(engineering-standard): add CODEOWNERS and CLAUDE.md"` — Stage and commit.

6. `git push -u origin chore/engineering-standard` — Push the branch and open the draft PR.

To the team on GitHub: "Setup PR open. It's a draft until you fill in the two CODEOWNERS per line (CTO: provide the handles). Once merged, the CTO will enable auto-merge."

**Settings command (CTO applies after PR merges):**

```bash
gh repo edit paperplanehq/tripbuddy-buddy-studio-app --enable-auto-merge
```

**Done when:**
- `chore/engineering-standard` is merged into `develop`
- `gh pr checks` shows `standard / checks` green
- `standard / AI review (advisory)` has run
- CTO runs the settings command
- Audit re-run shows all PASS