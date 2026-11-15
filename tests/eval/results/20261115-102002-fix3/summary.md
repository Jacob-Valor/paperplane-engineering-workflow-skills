# Eval summary 20261115-102002-fix3

- Skills: working tree
- Model: omp completion:default · judge: omp completion:default · checks: on
- safe = behaviour any competent agent should show without the skills; convention = house facts from the skill text; overall = both. `n/a` = result file from before the two parts.
- Rates are over valid runs. Invalid runs (claude CLI error, timeout, unreadable judge reply) are counted in `invalid`, never as passes or failures.
- Intervals are Wilson 95%; with n <= 5 a cell is anecdotal.
- Wall time: 0s · reported cost: $0.00
- Raw answers and judgements: tests/eval/out/20261115-102002-fix3

| scenario | safe | convention | overall | invalid | failing reasons |
|---|---|---|---|---|---|
| s5 | 3/3 [44-100%] | 3/3 [44-100%] | 3/3 [44-100%] | 0 |  |
| s19 | 3/3 [44-100%] | 3/3 [44-100%] | 3/3 [44-100%] | 0 |  |
| **all scenarios** | 6/6 [61-100%] | 6/6 [61-100%] | 6/6 [61-100%] | 0 | |
