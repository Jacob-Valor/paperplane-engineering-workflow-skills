# Eval summary 20261029-154133

- Skills: working tree
- Model: claude default · judge: claude default · checks: on
- safe = behaviour any competent agent should show without the skills; convention = house facts from the skill text; overall = both. `n/a` = result file from before the two parts.
- Rates are over valid runs. Invalid runs (claude CLI error, timeout, unreadable judge reply) are counted in `invalid`, never as passes or failures.
- Intervals are Wilson 95%; with n <= 5 a cell is anecdotal.
- Wall time: 0s · reported cost: $0.39
- Raw answers and judgements: tests/eval/out/20261029-154133

| scenario | safe | convention | overall | invalid | failing reasons |
|---|---|---|---|---|---|
| s5 | 3/3 [44-100%] | 2/3 [21-94%] | 2/3 [21-94%] | 0 | rep2: Convention part fails: the settings command block for the CTO includes `--enable-auto-merge` as its only command, rather than leaving it out of the standard settings and offering it separately as CTO-optional, even though the answer says it applies only if Pay wants it. |
| s7 | 3/3 [44-100%] | 3/3 [44-100%] | 3/3 [44-100%] | 0 |  |
| s25 | 3/3 [44-100%] | 3/3 [44-100%] | 3/3 [44-100%] | 0 |  |
| s57 | 3/3 [44-100%] | 3/3 [44-100%] | 3/3 [44-100%] | 0 |  |
| **all scenarios** | 12/12 [76-100%] | 11/12 [65-99%] | 11/12 [65-99%] | 0 | |
| **sealed held-out** | 3/3 [44-100%] | 3/3 [44-100%] | 3/3 [44-100%] | 0 | |
| **development (not held-out)** | 9/9 [70-100%] | 8/9 [56-98%] | 8/9 [56-98%] | 0 | |
