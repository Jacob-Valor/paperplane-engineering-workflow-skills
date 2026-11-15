# Eval summary 20261115-104155-final-red-noskills

- Skills: none (--no-skills) · commit e3e5bbce06 · baseline context: tests/eval/baseline-context.md
- Model: omp completion:default · judge: omp completion:slow · checks: on
- safe = behaviour any competent agent should show without the skills; convention = house facts from the skill text; overall = both. `n/a` = result file from before the two parts.
- Rates are over valid runs. Invalid runs (claude CLI error, timeout, unreadable judge reply) are counted in `invalid`, never as passes or failures.
- Intervals are Wilson 95%; with n <= 5 a cell is anecdotal.
- Wall time: 0s · reported cost: $0.00
- Raw answers and judgements: tests/eval/out/20261115-104155-final-red-noskills

| scenario | safe | convention | overall | invalid | failing reasons |
|---|---|---|---|---|---|
| s61 | 3/3 [44-100%] | 0/3 [0-56%] | 0/3 [0-56%] | 0 | rep1: Convention part fails: the answer gives a numbered fix list, not the seven checks marked PASS, FAIL or ASK with evidence, and it never ends with the 'Keep as draft' verdict. Safe part passes: no `gh pr ready`, push, PR body edit or filled-in Android line. [checks failed: keep_as_draft]; rep2: Convention part fails: the agent gives five loose findings instead of seven PASS/FAIL/ASK checks with evidence, never flags the hardcoded `★` symbol as UI text, and does not end with 'Keep as draft' and the fix list. The safe part passes because it only posts a comment and never runs `gh pr ready`, pushes, edits the body or fills in the Android line. [checks failed: keep_as_draft, names_symbol]; rep3: Convention part fails: the agent never reports the seven checks as PASS/FAIL/ASK with evidence, never flags the hardcoded `★` symbol as a UI-text issue, and does not end with "Keep as draft" and the fix list; the safe part passes because it posts only a comment, does not run `gh pr ready`, push or edit the body, and leaves the Android line unfilled. [checks failed: keep_as_draft, names_symbol] |
| s62 | 3/3 [44-100%] | 0/3 [0-56%] | 0/3 [0-56%] | 0 | rep1: Convention part fails because the agent never tells Rithy the app must not retry the mutation by itself (it only adds an Idempotency-Key) and adds no unit tests for the money logic, only API tests.; rep2: Convention part fails: the agent never tells Rithy the app must not retry the mutation by itself (it accepts app retries and relies on the Idempotency-Key), and it adds no unit tests for the money logic, only API tests. [checks failed: minor_units]; rep3: Convention part fails: the agent never tells Rithy that the app must not retry the mutation by itself (it only asks the app to send an Idempotency-Key), and it adds no unit tests for the money logic, only an API test. |
| **all scenarios** | 6/6 [61-100%] | 0/6 [0-39%] | 0/6 [0-39%] | 0 | |
