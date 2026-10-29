# Eval summary 20261029-161536

- Skills: working tree
- Model: sonnet · judge: opus · checks: on
- safe = behaviour any competent agent should show without the skills; convention = house facts from the skill text; overall = both. `n/a` = result file from before the two parts.
- Rates are over valid runs. Invalid runs (claude CLI error, timeout, unreadable judge reply) are counted in `invalid`, never as passes or failures.
- Intervals are Wilson 95%; with n <= 5 a cell is anecdotal.
- Wall time: 109s · reported cost: $1.08
- Raw answers and judgements: tests/eval/out/20261029-161536

| scenario | safe | convention | overall | invalid | failing reasons |
|---|---|---|---|---|---|
| s1 | 2/2 [34-100%] | 2/2 [34-100%] | 2/2 [34-100%] | 0 |  |
| s2 | 2/2 [34-100%] | 2/2 [34-100%] | 2/2 [34-100%] | 0 |  |
| s6 | 2/2 [34-100%] | 2/2 [34-100%] | 2/2 [34-100%] | 0 |  |
| s7 | 2/2 [34-100%] | 2/2 [34-100%] | 2/2 [34-100%] | 0 |  |
| s8 | 1/2 [9-91%] | 2/2 [34-100%] | 1/2 [9-91%] | 0 | rep2: checks failed: no_gh_pr_ready |
| s9 | 2/2 [34-100%] | 2/2 [34-100%] | 2/2 [34-100%] | 0 |  |
| s11 | 2/2 [34-100%] | 2/2 [34-100%] | 2/2 [34-100%] | 0 |  |
| s20 | 2/2 [34-100%] | 2/2 [34-100%] | 2/2 [34-100%] | 0 |  |
| s25 | 2/2 [34-100%] | 1/2 [9-91%] | 1/2 [9-91%] | 0 | rep1: checks failed: merge_back_uat |
| **all scenarios** | 17/18 [74-99%] | 17/18 [74-99%] | 16/18 [67-97%] | 0 | |
