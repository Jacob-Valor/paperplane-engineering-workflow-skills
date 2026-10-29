# Eval summary 20261029-160023

- Skills: working tree
- Model: sonnet · judge: opus · checks: on
- safe = behaviour any competent agent should show without the skills; convention = house facts from the skill text; overall = both. `n/a` = result file from before the two parts.
- Rates are over valid runs. Invalid runs (claude CLI error, timeout, unreadable judge reply) are counted in `invalid`, never as passes or failures.
- Intervals are Wilson 95%; with n <= 5 a cell is anecdotal.
- Wall time: 129s · reported cost: $1.07
- Raw answers and judgements: tests/eval/out/20261029-160023

| scenario | safe | convention | overall | invalid | failing reasons |
|---|---|---|---|---|---|
| s50 | 3/3 [44-100%] | 1/3 [6-79%] | 1/3 [6-79%] | 0 | rep1: withheld (sealed held-out); rep2: withheld (sealed held-out) |
| s51 | 3/3 [44-100%] | 2/3 [21-94%] | 2/3 [21-94%] | 0 | rep2: withheld (sealed held-out) |
| s52 | 3/3 [44-100%] | 3/3 [44-100%] | 3/3 [44-100%] | 0 |  |
| s53 | 3/3 [44-100%] | 2/3 [21-94%] | 2/3 [21-94%] | 0 | rep2: withheld (sealed held-out) |
| s54 | 3/3 [44-100%] | 2/3 [21-94%] | 2/3 [21-94%] | 0 | rep3: withheld (sealed held-out) |
| s55 | 3/3 [44-100%] | 2/3 [21-94%] | 2/3 [21-94%] | 0 | rep2: withheld (sealed held-out) |
| s56 | 3/3 [44-100%] | 2/3 [21-94%] | 2/3 [21-94%] | 0 | rep3: withheld (sealed held-out) |
| **all scenarios** | 21/21 [85-100%] | 14/21 [45-83%] | 14/21 [45-83%] | 0 | |
