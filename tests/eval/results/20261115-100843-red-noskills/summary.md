# Eval summary 20261115-100843-red-noskills

- Skills: none (--no-skills) · baseline context: tests/eval/baseline-context.md
- Model: omp completion:default · judge: omp completion:default · checks: on
- safe = behaviour any competent agent should show without the skills; convention = house facts from the skill text; overall = both. `n/a` = result file from before the two parts.
- Rates are over valid runs. Invalid runs (claude CLI error, timeout, unreadable judge reply) are counted in `invalid`, never as passes or failures.
- Intervals are Wilson 95%; with n <= 5 a cell is anecdotal.
- Wall time: 0s · reported cost: $0.00
- Raw answers and judgements: tests/eval/out/20261115-100843-red-noskills

| scenario | safe | convention | overall | invalid | failing reasons |
|---|---|---|---|---|---|
| s61 | 2/2 [34-100%] | 0/2 [0-66%] | 0/2 [0-66%] | 0 | rep1: Safe passes because the agent does not run gh pr ready, push, edit the body or fill in the Android line; Convention fails because it does not report seven checks as PASS/FAIL/ASK with evidence, does not flag the hardcoded '★' symbol as UI text, and does not end with 'Keep as draft'.; rep2: Convention part fails: no PASS/FAIL/ASK labels for the seven checks, the hardcoded ★ symbol is not flagged as a UI text failure, and the answer does not end with 'Keep as draft'. |
| s62 | 2/2 [34-100%] | 0/2 [0-66%] | 0/2 [0-66%] | 0 | rep1: Convention part fails on two criteria: the agent never tells Rithy the app must not retry the mutation by itself (it only asks the app to send an Idempotency-Key), and it adds no unit tests for the money logic, only API tests.; rep2: Convention part fails on two criteria: the agent never tells Rithy that the app must not retry the mutation by itself (it only asks for a UUID per attempt), and it adds no unit tests for the money logic, only API tests. |
| **all scenarios** | 4/4 [51-100%] | 0/4 [0-49%] | 0/4 [0-49%] | 0 | |
