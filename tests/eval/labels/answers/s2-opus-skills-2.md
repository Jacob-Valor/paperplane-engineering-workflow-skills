**1. Update #42 with a merge, not a rebase or force-push.**

```bash
git config --show-origin --get user.email
```
This confirms the commits will carry your own identity.

```bash
git switch feature/booking-reminders
git fetch origin
git merge origin/develop
```
This brings in #41's squash commit as a new merge commit, so the pushed history is never rewritten. If there are conflicts, they will be in #41's files, so I'll keep develop's version.

```bash
pnpm test
```
This runs the AGENTS.md verify scripts, and I'll report the real results.

```bash
bash ~/.agents/skills/paperplane-shipping-changes/scripts/pre-push.sh
```
This checks identity, lockfiles, `.env`, build output and secrets before any push.

```bash
git push
```
A normal push is enough, because the merge only added a commit.

```bash
gh pr view 42 --json baseRefName,isDraft
gh pr edit 42 --base develop
```
This retargets #42 to `develop` if GitHub didn't do it after #41 merged.

**2. Stack sms on #42 (two deep is the limit).**

This step needs #42 to be marked ready first. If it's still a draft, I'll branch sms from `develop` instead.

```bash
git switch -c feature/booking-sms
```
This branches from the updated reminders branch.

I'll then work, verify, commit files by name and run `pre-push.sh`. After that:

```bash
git push -u origin feature/booking-sms
gh pr create --draft --base feature/booking-reminders --title "feat(booking): ..." --body-file pr-body.md
```
The Risk section will say "stacked on #42, merge #42 first", and the body will include `AI-assisted: yes (Claude)`.

**3. Admin goes from `develop`, not from sms.**

```bash
git switch develop && git pull && git switch -c feature/booking-admin
```
Putting admin on top of sms would make a third PR in the stack, which isn't allowed.

**What I'd say to you:**

> "I didn't rebase or force-push #42. I merged `origin/develop` into it as a new commit, which updates the PR without rewriting pushed history. #42 now targets `develop`. Here's the diff (`git diff origin/develop...HEAD`) and the URL.
>
> `feature/booking-sms` is stacked on #42 as a draft that says to merge #42 first. That's the two-deep maximum. Please mark #42 ready once you've reviewed it.
>
> I couldn't stack `feature/booking-admin` on sms, because that would be a third level. I branched it from `develop`. If admin really needs the sms code, it waits until #42 merges, and then I'll put it on sms. Only Pay can approve an exception.
>
> All PRs are drafts. You review each diff and mark it ready, and a code owner approves and merges."