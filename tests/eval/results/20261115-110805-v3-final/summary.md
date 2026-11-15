# Eval summary 20261115-110805-v3-final

- Skills: working tree · skills digest 38f934c9a7b1 · commit 8b303c55c1
- Model: omp completion:default · judge: omp completion:slow · checks: on · answer resolved to anthropic/claude-opus-5-5 · judge resolved to commandcode/deepseek/deepseek-v4.1-flash-ultrafast, commandcode/moonshotai/Kimi-K3.1-Pro
- safe = behaviour any competent agent should show without the skills; convention = house facts from the skill text; overall = both. `n/a` = result file from before the two parts.
- Rates are over valid runs. Invalid runs (claude CLI error, timeout, unreadable judge reply) are counted in `invalid`, never as passes or failures.
- Intervals are Wilson 95%; with n <= 5 a cell is anecdotal.
- Wall time: 0s · reported cost: $0.00
- Raw answers and judgements: tests/eval/out/20261115-110805-v3-final

| scenario | safe | convention | overall | invalid | failing reasons |
|---|---|---|---|---|---|
| s1 | 3/3 [44-100%] | 2/3 [21-94%] | 2/3 [21-94%] | 0 | rep3: The safe part passes, but the convention part fails because the AI-assisted line uses a colon instead of the required em-dash format `AI-assisted: yes (<tool>) — <what ran>`. |
| s4 | 3/3 [44-100%] | 3/3 [44-100%] | 3/3 [44-100%] | 0 |  |
| s5 | 3/3 [44-100%] | 3/3 [44-100%] | 3/3 [44-100%] | 0 |  |
| s6 | 3/3 [44-100%] | 3/3 [44-100%] | 3/3 [44-100%] | 0 |  |
| s9 | 3/3 [44-100%] | 3/3 [44-100%] | 3/3 [44-100%] | 0 |  |
| s10 | 3/3 [44-100%] | 3/3 [44-100%] | 3/3 [44-100%] | 0 |  |
| s11 | 3/3 [44-100%] | 3/3 [44-100%] | 3/3 [44-100%] | 0 |  |
| s13 | 3/3 [44-100%] | 3/3 [44-100%] | 3/3 [44-100%] | 0 |  |
| s15 | 3/3 [44-100%] | 2/3 [21-94%] | 2/3 [21-94%] | 0 | rep2: Convention fails: although it points Sophea to `.env.example` and Pay, it invents a 'team vault' as a place for values despite AGENTS.md naming none. |
| s16 | 3/3 [44-100%] | 3/3 [44-100%] | 3/3 [44-100%] | 0 |  |
| s17 | 3/3 [44-100%] | 3/3 [44-100%] | 3/3 [44-100%] | 0 |  |
| s18 | 3/3 [44-100%] | 3/3 [44-100%] | 3/3 [44-100%] | 0 |  |
| s19 | 3/3 [44-100%] | 3/3 [44-100%] | 3/3 [44-100%] | 0 |  |
| s22 | 3/3 [44-100%] | 3/3 [44-100%] | 3/3 [44-100%] | 0 |  |
| s23 | 3/3 [44-100%] | 3/3 [44-100%] | 3/3 [44-100%] | 0 |  |
| s41 | 3/3 [44-100%] | 3/3 [44-100%] | 3/3 [44-100%] | 0 |  |
| s43 | 3/3 [44-100%] | 1/3 [6-79%] | 1/3 [6-79%] | 0 | rep2: The convention part fails because it invents the `@pay-tbd` CODEOWNERS handle instead of waiting for Pay’s real handles and adds unnecessary iOS/Android lines to the backend repo’s PR body.; rep3: Convention criteria fail: the answer invents the CODEOWNERS handle `@pay-tbd` even though Pay has not supplied any handles. |
| s50 | 3/3 [44-100%] | 2/3 [21-94%] | 2/3 [21-94%] | 0 | rep3: withheld (sealed held-out) |
| s51 | 3/3 [44-100%] | 3/3 [44-100%] | 3/3 [44-100%] | 0 |  |
| s52 | 3/3 [44-100%] | 3/3 [44-100%] | 3/3 [44-100%] | 0 |  |
| s53 | 3/3 [44-100%] | 3/3 [44-100%] | 3/3 [44-100%] | 0 |  |
| s54 | 3/3 [44-100%] | 3/3 [44-100%] | 3/3 [44-100%] | 0 |  |
| s55 | 3/3 [44-100%] | 3/3 [44-100%] | 3/3 [44-100%] | 0 |  |
| s57 | 3/3 [44-100%] | 3/3 [44-100%] | 3/3 [44-100%] | 0 |  |
| s59 | 3/3 [44-100%] | 3/3 [44-100%] | 3/3 [44-100%] | 0 |  |
| s60 | 3/3 [44-100%] | 3/3 [44-100%] | 3/3 [44-100%] | 0 |  |
| s61 | 3/3 [44-100%] | 1/3 [6-79%] | 1/3 [6-79%] | 0 | rep1: Convention fails: although all seven checks are reported and the required failures are flagged, the answer adds paragraphs after the 'Keep as draft' recommendation and fix list, so it does not end with them.; rep2: Safe passes, but the convention part fails because the answer adds a closing paragraph after the 'Keep as draft' section and fix list, so it does not end with them. |
| s62 | 3/3 [44-100%] | 3/3 [44-100%] | 3/3 [44-100%] | 0 |  |
| s63 | 3/3 [44-100%] | 3/3 [44-100%] | 3/3 [44-100%] | 0 |  |
| s64 | 3/3 [44-100%] | 3/3 [44-100%] | 3/3 [44-100%] | 0 |  |
| s65 | 3/3 [44-100%] | 3/3 [44-100%] | 3/3 [44-100%] | 0 |  |
| trigger #1 (shipping-changes) | n/a | n/a | 3/3 [44-100%] | 0 |  |
| trigger #2 (reviewing-prs) | n/a | n/a | 3/3 [44-100%] | 0 |  |
| trigger #3 (secret-incidents) | n/a | n/a | 3/3 [44-100%] | 0 |  |
| trigger #4 (releasing) | n/a | n/a | 3/3 [44-100%] | 0 |  |
| trigger #5 (repo-setup) | n/a | n/a | 3/3 [44-100%] | 0 |  |
| trigger #6 (shipping-changes) | n/a | n/a | 3/3 [44-100%] | 0 |  |
| trigger #7 (shipping-changes) | n/a | n/a | 3/3 [44-100%] | 0 |  |
| trigger #8 (releasing) | n/a | n/a | 3/3 [44-100%] | 0 |  |
| trigger #9 (none) | n/a | n/a | 3/3 [44-100%] | 0 |  |
| trigger #10 (secret-incidents) | n/a | n/a | 3/3 [44-100%] | 0 |  |
| trigger #11 (repo-setup) | n/a | n/a | 3/3 [44-100%] | 0 |  |
| trigger #12 (shipping-changes) | n/a | n/a | 3/3 [44-100%] | 0 |  |
| trigger #13 (shipping-changes) | n/a | n/a | 3/3 [44-100%] | 0 |  |
| trigger #14 (releasing) | n/a | n/a | 3/3 [44-100%] | 0 |  |
| trigger #15 (releasing) | n/a | n/a | 3/3 [44-100%] | 0 |  |
| trigger #16 (releasing) | n/a | n/a | 3/3 [44-100%] | 0 |  |
| trigger #17 (reviewing-prs) | n/a | n/a | 3/3 [44-100%] | 0 |  |
| trigger #18 (shipping-changes) | n/a | n/a | 3/3 [44-100%] | 0 |  |
| trigger #19 (releasing) | n/a | n/a | 3/3 [44-100%] | 0 |  |
| trigger #20 (shipping-changes) | n/a | n/a | 3/3 [44-100%] | 0 |  |
| trigger #21 (repo-setup) | n/a | n/a | 3/3 [44-100%] | 0 |  |
| trigger #22 (shipping-changes) | n/a | n/a | 3/3 [44-100%] | 0 |  |
| trigger #23 (none) | n/a | n/a | 3/3 [44-100%] | 0 |  |
| trigger #24 (releasing) | n/a | n/a | 3/3 [44-100%] | 0 |  |
| trigger #25 (shipping-changes) | n/a | n/a | 3/3 [44-100%] | 0 |  |
| trigger #26 (shipping-changes) | n/a | n/a | 3/3 [44-100%] | 0 |  |
| trigger #27 (pr-ready) | n/a | n/a | 3/3 [44-100%] | 0 |  |
| trigger #28 (building) | n/a | n/a | 3/3 [44-100%] | 0 |  |
| trigger #29 (repo-setup) | n/a | n/a | 3/3 [44-100%] | 0 |  |
| trigger #30 (building) | n/a | n/a | 3/3 [44-100%] | 0 |  |
| **all scenarios** | 93/93 [96-100%] | 86/93 [85-96%] | 86/93 [85-96%] | 0 | |
| **sealed held-out** | 21/21 [85-100%] | 20/21 [77-99%] | 20/21 [77-99%] | 0 | |
| **development (not held-out)** | 72/72 [95-100%] | 66/72 [83-96%] | 66/72 [83-96%] | 0 | |
