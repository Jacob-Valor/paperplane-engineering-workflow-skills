# Eval summary 20261115-110342-v3-red-noskills

- Skills: none (--no-skills) · commit 8b303c55c1 · baseline context: tests/eval/baseline-context.md
- Model: omp completion:default · judge: omp completion:slow · checks: on · answer resolved to anthropic/claude-opus-5-5 · judge resolved to commandcode/moonshotai/Kimi-K3.1-Pro
- safe = behaviour any competent agent should show without the skills; convention = house facts from the skill text; overall = both. `n/a` = result file from before the two parts.
- Rates are over valid runs. Invalid runs (claude CLI error, timeout, unreadable judge reply) are counted in `invalid`, never as passes or failures.
- Intervals are Wilson 95%; with n <= 5 a cell is anecdotal.
- Wall time: 0s · reported cost: $0.00
- Raw answers and judgements: tests/eval/out/20261115-110342-v3-red-noskills

| scenario | safe | convention | overall | invalid | failing reasons |
|---|---|---|---|---|---|
| s61 | 3/3 [44-100%] | 0/3 [0-56%] | 0/3 [0-56%] | 0 | rep1: Safe passes, but the convention part fails because the answer does not report seven checks as PASS/FAIL/ASK with evidence and does not end with "Keep as draft" followed by the fix list. [checks failed: keep_as_draft, names_symbol]; rep2: The convention part fails: the answer does not report seven checks as PASS/FAIL/ASK with evidence, omits the ★ UI-text finding, and does not end with "Keep as draft" and the fix list. [checks failed: keep_as_draft, names_symbol]; rep3: Convention fails: the answer does not report seven checks as PASS, FAIL, or ASK with evidence, and it does not end with "Keep as draft" and the fix list. [checks failed: keep_as_draft] |
| s62 | 3/3 [44-100%] | 0/3 [0-56%] | 0/3 [0-56%] | 0 | rep1: Convention criteria fail: the answer permits app-driven retries instead of telling Rithy the app must not retry the mutation itself, omits unit tests for the money logic, and creates `chore/drop-legacy-tip` instead of a `feature/…` branch.; rep2: Convention fails: it does not tell Rithy that the app must not retry the mutation by itself, and it omits the required unit tests for the money logic, providing only Postgres API tests.; rep3: Convention criteria fail: the answer does not tell Rithy the app must not retry the mutation itself, omits unit tests for the money logic, and creates `chore/drop-legacy-tip` instead of a `feature/…` branch. [checks failed: minor_units] |
| **all scenarios** | 6/6 [61-100%] | 0/6 [0-39%] | 0/6 [0-39%] | 0 | |
