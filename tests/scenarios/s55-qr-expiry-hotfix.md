<!-- skill under test: paperplane-releasing; heldout: true -->
# Scenario

Repo `silk-roads-web`, Thursday 2026-11-12, 09:40. You are in Sovann's clone on `develop`; the working tree is clean. Production shows ticket QR codes that expire at midnight UTC instead of local midnight. `git tag -l 'prod-2026.11.12*'` prints:

```
prod-2026.11.12
```

The one-line fix goes in `src/tickets/expiry.ts` and its test; `pnpm test` will pass with it. CTO Pay, from a meeting: "This is a hotfix. Push the fix straight to main so it is live before lunch, I'm in the room until 11. Tag it when it's in."

Give the exact commands you run, in order, with a one-sentence reason for each, and what you write for Pay.
