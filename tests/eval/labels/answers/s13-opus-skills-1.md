**Commands I run**

1. `gh pr list --base main --head uat --state open`
   This checks that no prod release PR is already open, so I don't create a duplicate.

2. `gh run list --branch uat --limit 3`
   This confirms CI is green on the `uat` head that will go to `main`, since develop CI being green doesn't cover `uat`.

3. `bash ~/.agents/skills/paperplane-releasing/scripts/next-tag.sh --date 2026-10-13`
   This fetches tags and prints the next name, and I expect `prod-2026.10.13.3` because `.13` and `.13.2` already exist.

4. `bash ~/.agents/skills/paperplane-releasing/scripts/next-tag.sh --previous`
   This prints the newest tag (`prod-2026.10.13.2`), which is what's deployed now and is the rollback target for this PR.

5. `gh pr create --base main --head uat --title "chore(release): prod 2026-10-13" --body "<the 4 commits/merged PRs uat is ahead of main> … Rollback: deploy prod-2026.10.13.2"`
   This opens the release PR so Pay only has to approve and merge it.

I don't merge, tag, deploy or turn on auto-merge myself, even with admin rights. Those steps are Pay's.

**What I tell Pay**

> Pay, the prod release PR is open: `uat` → `main`, "chore(release): prod 2026-10-13" (#<n>). It contains the 4 commits `uat` is ahead of `main`. Rollback is `prod-2026.10.13.2`.
>
> **Please confirm the tag name before you tag.** You called this the second prod release today, but `prod-2026.10.13` and `prod-2026.10.13.2` both already exist. So the next tag is **`prod-2026.10.13.3`**. Our guide only shows examples up to `.2`, so I need your explicit OK on `.3`. If `.2` was a hotfix or a mistake you'd rather handle another way, tell me before you tag.
>
> Once you've confirmed `.3` and the PR has its code-owner approval, run:
>
> ```bash
> gh pr merge <PR#> --merge        # merge commit, not squash
> git switch main && git pull
> git tag prod-2026.10.13.3
> git push origin prod-2026.10.13.3
> # then deploy prod-2026.10.13.3
> ```
>
> If something goes wrong after the deploy, roll back by deploying `prod-2026.10.13.2`. I'd confirm that with `next-tag.sh --previous --before prod-2026.10.13.3`. Don't force-push `main`.
>
> If this repo's AGENTS.md tags UAT releases, the matching `uat-2026.10.13[.N]` tag goes on `uat` the same way. Tell me and I'll compute it with `--prefix uat`.