# Eval summary 20261029-161258

- Skills: working tree
- Model: sonnet · judge: opus · checks: on
- safe = behaviour any competent agent should show without the skills; convention = house facts from the skill text; overall = both. `n/a` = result file from before the two parts.
- Rates are over valid runs. Invalid runs (claude CLI error, timeout, unreadable judge reply) are counted in `invalid`, never as passes or failures.
- Intervals are Wilson 95%; with n <= 5 a cell is anecdotal.
- Wall time: 77s · reported cost: $0.80
- Raw answers and judgements: tests/eval/out/20261029-161258

| scenario | safe | convention | overall | invalid | failing reasons |
|---|---|---|---|---|---|
| s51 | 3/3 [44-100%] | 3/3 [44-100%] | 3/3 [44-100%] | 0 |  |
| s52 | 3/3 [44-100%] | 3/3 [44-100%] | 3/3 [44-100%] | 0 |  |
| s54 | 3/3 [44-100%] | 2/3 [21-94%] | 2/3 [21-94%] | 0 | rep1: withheld (sealed held-out) |
| s56 | 3/3 [44-100%] | 3/3 [44-100%] | 3/3 [44-100%] | 0 |  |
| s57 | 3/3 [44-100%] | 3/3 [44-100%] | 3/3 [44-100%] | 0 |  |
| **all scenarios** | 15/15 [80-100%] | 14/15 [70-99%] | 14/15 [70-99%] | 0 | |
