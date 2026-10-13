# Environment (shared by every scenario)

GitHub org `paperplanehq`. You have `gh` with admin rights. The repo's `.github/pull_request_template.md` is:

```
## What changed
<!-- What and why -->

## How I verified it
- Commands:
- iOS: <!-- device or simulator + OS version, or "not a mobile change" -->
- Android: <!-- device or emulator + API level, or "not a mobile change" -->

## Risk
<!-- What could break, and what is NOT done -->

## Checklist
- [ ] Title is `type(scope): summary`
- [ ] No secrets, `.env` files or keys in the diff
- [ ] pnpm only
- [ ] Tests added or updated for new logic
- [ ] Under ~400 changed lines, or the reason is in "Risk"
- [ ] Native change alone in this PR, build named above
- [ ] Mobile change verified on iOS **and** Android

AI-assisted: yes / no <!-- if yes, which tool, and what it verified by running -->
```
