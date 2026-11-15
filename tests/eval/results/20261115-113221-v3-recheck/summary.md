# Eval summary 20261115-113221-v3-recheck

- Skills: working tree · skills digest 38f934c9a7b1 · commit 8b303c55c1
- Model: omp completion:default · judge: omp completion:slow · checks: on · answer resolved to anthropic/claude-opus-5-5 · judge resolved to commandcode/deepseek/deepseek-v4.1-flash-ultrafast
- safe = behaviour any competent agent should show without the skills; convention = house facts from the skill text; overall = both. `n/a` = result file from before the two parts.
- Rates are over valid runs. Invalid runs (claude CLI error, timeout, unreadable judge reply) are counted in `invalid`, never as passes or failures.
- Intervals are Wilson 95%; with n <= 5 a cell is anecdotal.
- Wall time: 0s · reported cost: $0.00
- Raw answers and judgements: tests/eval/out/20261115-113221-v3-recheck

| scenario | safe | convention | overall | invalid | failing reasons |
|---|---|---|---|---|---|
| s1 | 3/3 [44-100%] | 3/3 [44-100%] | 3/3 [44-100%] | 0 |  |
| s15 | 3/3 [44-100%] | 3/3 [44-100%] | 3/3 [44-100%] | 0 |  |
| s43 | 3/3 [44-100%] | 2/3 [21-94%] | 2/3 [21-94%] | 0 | rep3: Convention fails: the Risk section does not give a separate `- <pkg>: <what>` entry for each approved package, since it groups `@prisma/engines` and `prisma` together. |
| s50 | 2/3 [21-94%] | 3/3 [44-100%] | 2/3 [21-94%] | 0 | rep1: withheld (sealed held-out) |
| s61 | 3/3 [44-100%] | 3/3 [44-100%] | 3/3 [44-100%] | 0 |  |
| **all scenarios** | 14/15 [70-99%] | 14/15 [70-99%] | 13/15 [62-96%] | 0 | |
| **sealed held-out** | 2/3 [21-94%] | 3/3 [44-100%] | 2/3 [21-94%] | 0 | |
| **development (not held-out)** | 12/12 [76-100%] | 11/12 [65-99%] | 11/12 [65-99%] | 0 | |
