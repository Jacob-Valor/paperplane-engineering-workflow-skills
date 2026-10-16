I'm not marking #70 ready yet. Dara's review covered a diff that still has a debug log, a TODO, commented-out code and an unused helper, and the ready rules don't allow those. Removing them adds a commit after her review, so she needs to give a new go-ahead on that commit first.

```bash
git switch feature/booking-export && git status --short
```
Confirms I'm on the right branch with a clean tree.

I then edit `src/booking/export.ts` and remove four things:
- the `console.log("DEBUG ...")` line
- the `// TODO` comment
- the commented-out `exportBookingsCsv` block
- the unused `legacyDateFormat`

I change nothing else.

```bash
pnpm test
```
Confirms the cleanup didn't break anything (I expect 84 passed and will report the real result).

```bash
git add src/booking/export.ts
git commit -m "refactor(booking): remove debug log and dead code from export"
```
Stages the file by name and keeps the cleanup as one logical commit.

```bash
bash ~/.agents/skills/paperplane-shipping-changes/scripts/pre-push.sh
```
Runs the required check before every push, including this one.

```bash
git push
```
Plain push, no force, so the draft PR updates.

```bash
git diff HEAD~1 HEAD
```
Shows Dara exactly what changed since she reviewed.

I also fill `pr-body.md` from the template, keeping all headings and the `- Commands:`, `- iOS:` and `- Android:` lines:
- Commands: `pnpm test` (real result).
- iOS and Android: "not a mobile change".
- Risk: what could break, and that the CSV fallback is removed, so only XLSX export exists. Not done: QA of the export hasn't happened.
- Checklist: only the true boxes ticked.
- `AI-assisted: yes (Claude Code) — ran pnpm test`.

```bash
bash ~/.agents/skills/paperplane-shipping-changes/scripts/check-pr-body.sh pr-body.md
```
Confirms the body passes the same rules as CI. I stop here and do not run `gh pr ready`.

**To Dara:**
"Before this goes ready, I removed a debug `console.log`, a TODO, a commented-out CSV function and an unused date helper that were in the diff you read. It's one new commit, pushed to #70, and tests still pass. Its diff is above. Once you've looked at that commit and say it's fine, I'll run the body check and mark #70 ready, so Sok can still review it before lunch. The PR stays draft until then."