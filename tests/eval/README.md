# Eval runner

`run.py` runs the agent scenarios in `../scenarios/` and the triggering test with the `claude` CLI, so you do not have to start each subagent by hand. Python 3 standard library only.

```bash
python3 tests/eval/run.py --scenarios s12 --reps 1                 # skills from the working tree
python3 tests/eval/run.py --scenarios all --skill-ref main --reps 2  # baseline: skills from main
python3 tests/eval/run.py --trigger --reps 1                       # triggering test only
python3 tests/eval/run.py --scenarios all --no-skills --reps 3      # baseline: no skills at all
python3 tests/eval/run.py --scenarios s1,s9 --dry-run              # print the prompts, call nothing
```

| Option | Default | Meaning |
|---|---|---|
| `--scenarios` | `all` (none with `--trigger`) | Comma-separated ids (`s1,s9`) or `all` |
| `--reps` | `3` | Runs per scenario, and per triggering test |
| `--skill-ref` | working tree | Read `skills/` from this git ref (tag, branch, commit) |
| `--no-skills` | off | Leave the skills out: shows what each skill adds. Not with `--skill-ref` or `--trigger` |
| `--model` | claude default | Model for the answers (and the grading, unless `--judge-model`) |
| `--judge-model` | `--model` | Model for the grading. Keep it fixed when you compare answer models |
| `--jobs` | `4` | Runs at the same time |
| `--out` | `tests/eval/out` | Results go to `<out>/<timestamp>/` |
| `--trigger` | off | Also run `triggering.md` |
| `--dry-run` | off | Print the prompts and pass criteria; call nothing |

Each run is two `claude -p` calls with no tools, no saved session and `--safe-mode` (no CLAUDE.md, installed skills or hooks):

1. **Answer.** The prompt is the role-play instructions, the skill under test (named on the scenario's first line) with its scripts' names and header comments, `00-environment.md` and the scenario. Shipping scenarios also get `paperplane-secret-incidents`.
2. **Grade.** A second call gets the scenario's row from the pass-criteria table in `../README.md` and the answer, and returns `{"pass": ..., "reason": ...}`.

The triggering test gives the `name: description` pairs and `triggering.md`, then checks each line against the expected table in `../README.md`: an extra skill passes, a missing or wrong one fails.

Output: `<timestamp>/<scenario>/repN.{prompt,answer,judge}.*`, `trigger/repN.*` and `summary.md` (`scenario | passed/total | failing reasons`, also printed). Each `repN.judge.json` also records the answer's `input_tokens`, `output_tokens` and `answer_seconds`.

## Benchmark

Agents run these skills on whatever model the developer picked, so check a skill change on a small, a medium and a large model, against the no-skills baseline, with one fixed grader:

```bash
for m in haiku sonnet opus; do
  python3 tests/eval/run.py --scenarios all --reps 5 --model $m --judge-model opus --out /tmp/bench/skills-$m
  python3 tests/eval/run.py --scenarios all --reps 3 --model $m --judge-model opus --no-skills --out /tmp/bench/base-$m
  python3 tests/eval/run.py --trigger --reps 5 --model $m --out /tmp/bench/trig-$m
done
```

A scenario that passes without skills on every model doesn't test the skill. A scenario that fails on several models points to unclear wording, not to a weak model.

Exit codes: 0 every run passed · 1 at least one run failed · 2 usage error.

The grader is a model too. Read the answers of every failing run, and a sample of passing ones, before you change a skill or record results in `../RESULTS.md`.
