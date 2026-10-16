**Commands, in order**

1. `git fetch origin --tags --prune` so I see the real remote state, not a stale local one.
2. `date +%F` because my clock shows 2026-10-16, not the 13th, and the tag date must match the actual release day.
3. `git show -s --format='%h %ci %s' prod-2026.10.13 prod-2026.10.13.2` to find what the two existing tags point at.
4. `git branch -r --contains prod-2026.10.13.2` to check whether `.2` is already on `main`, meaning the second release has already shipped.
5. `git log --oneline origin/main..origin/uat` to list exactly the 4 commits that would ship.
6. `gh pr list --repo paperplanehq/tripbuddy-backend --base main --head uat` so I don't open a duplicate PR.
7. `gh pr create --repo paperplanehq/tripbuddy-backend --base main --head uat --title "release(prod): afternoon fixes 2026-10-13" --body-file pr-body.md` to open the release PR, with the body following the template:
   - **What changed:** the 4 commits from step 5.
   - **How I verified it:** UAT passed per Pay, develop CI is green, and the commands above. iOS and Android: not a mobile change.
   - **Risk:** prod deploy of 4 commits. The tag is not created yet, and the PR is not merged.
   - **AI-assisted:** yes, Claude. It verified only git and gh state, not runtime behaviour.

I will not create or push any tag myself, because Pay asked to run those.

**Message to Pay**

> Release PR is open: <link>, `uat` into `main`, 4 commits listed in the body.
>
> Before you tag, two things need your call:
> 1. **The name.** `prod-2026.10.13` and `prod-2026.10.13.2` already exist, so today's "second" release is really the third. The next free name is **`prod-2026.10.13.3`**. If `.2` was a mistake and never deployed, tell me before you tag. Please don't reuse or move a pushed prod tag.
> 2. **The date.** My machine's clock reads 2026-10-16. If today really is the 16th, the tag should be `prod-2026.10.16`.
>
> After the PR is merged:
> ```
> git fetch origin
> git checkout main && git pull --ff-only
> git log -1 --oneline        # confirm this is the merge commit of the PR
> git tag -a prod-2026.10.13.3 -m "Prod release 3, 2026-10-13: afternoon fixes (PR #<n>)"
> git push origin prod-2026.10.13.3
> ```
> If the commit from `git log -1` isn't the PR's merge commit, stop and ping me.