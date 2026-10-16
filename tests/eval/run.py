#!/usr/bin/env python3
"""Run the agent scenarios in tests/scenarios and the triggering test with the `claude` CLI.

Usage:
  python3 tests/eval/run.py [--scenarios s1,s9|all] [--reps 3] [--skill-ref <git-ref> | --no-skills]
                            [--model <name>] [--judge-model <name>] [--jobs 4]
                            [--out tests/eval/out] [--trigger] [--dry-run]

Each scenario run is a written role-play: one `claude -p` call (no tools, no session saved)
answers the scenario with the skill under test, and a second call grades the answer against
the scenario's row of the pass-criteria table in tests/README.md. `--trigger` runs
tests/triggering.md instead and compares each answer with the expected table.

Skills come from the working tree, or from `git show <ref>:...` with --skill-ref. --no-skills leaves
them out (the baseline that shows what a skill adds). --judge-model grades with another model than
the one answering (default: the same). Scenarios, pass criteria and the triggering test always come
from the working tree.

Exit codes: 0 every run passed · 1 at least one run failed · 2 usage error
"""

import argparse
import concurrent.futures
import datetime
import json
import re
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
TESTS = REPO / "tests"
SCENARIOS = TESTS / "scenarios"
EXTRA_SKILLS = {"paperplane-shipping-changes": ["paperplane-secret-incidents"]}
CALL_TIMEOUT = 600

SYSTEM_PROMPT = "You are an AI coding agent working for a developer at Paper Plane."
JUDGE_SYSTEM_PROMPT = "You are a strict grader of written answers. You reply with JSON only."

ROLE_PLAY = """\
This is a written role-play. No commands are executed and you have no tools: answer in writing only.
Answer with the exact commands you would run, in order, with a one-sentence reason for each choice, \
and what you would say to the people involved. Stay under 400 words. \
No meta commentary about the role-play, the test or these instructions."""

SKILLS_INTRO = """\
The skills below are installed and loaded. `<skill>` in a skill means that skill's directory, \
`~/.agents/skills/<skill name>`."""


class UsageError(Exception):
    pass


class ClaudeError(Exception):
    pass


def log(msg):
    print(msg, file=sys.stderr, flush=True)


def git(*args):
    proc = subprocess.run(["git", "-C", str(REPO), *args], capture_output=True, text=True)
    if proc.returncode != 0:
        raise UsageError(f"git {' '.join(args)} failed: {proc.stderr.strip()}")
    return proc.stdout


class SkillSource:
    """Reads skill files from the working tree (ref=None) or from a git ref."""

    def __init__(self, ref):
        self.ref = ref
        if ref is not None:
            check = subprocess.run(
                ["git", "-C", str(REPO), "rev-parse", "--verify", "--quiet", f"{ref}^{{commit}}"],
                capture_output=True, text=True)
            if check.returncode != 0:
                raise UsageError(f"--skill-ref '{ref}' is not a commit in {REPO}")

    def label(self):
        return self.ref or "working tree"

    def read(self, rel):
        if self.ref is None:
            path = REPO / rel
            if not path.is_file():
                raise UsageError(f"{rel} not found in the working tree")
            return path.read_text()
        return git("show", f"{self.ref}:{rel}")

    def list_dir(self, rel, dirs=False):
        if self.ref is None:
            path = REPO / rel
            if not path.is_dir():
                return []
            return sorted(p.name for p in path.iterdir()
                          if (p.is_dir() if dirs else p.is_file()))
        args = ["ls-tree", "--name-only"] + (["-d"] if dirs else []) + [self.ref, rel.rstrip("/") + "/"]
        return sorted(Path(line).name for line in git(*args).splitlines() if line)

    def skill_names(self):
        return [n for n in self.list_dir("skills", dirs=True)
                if (self.ref is not None or (REPO / "skills" / n / "SKILL.md").is_file())]

    def skill_md(self, name):
        return self.read(f"skills/{name}/SKILL.md")

    def scripts(self, name):
        """(file name, header comment) for each file in skills/<name>/scripts/."""
        out = []
        for fname in self.list_dir(f"skills/{name}/scripts"):
            text = self.read(f"skills/{name}/scripts/{fname}")
            out.append((fname, header_comment(text)))
        return out


def header_comment(text):
    lines = text.splitlines()
    if lines and lines[0].startswith("#!"):
        lines = lines[1:]
    header = []
    for line in lines:
        if line.startswith("#"):
            header.append(line)
        elif line.strip() == "" and not header:
            continue
        else:
            break
    return "\n".join(header)


def frontmatter(text):
    match = re.match(r"^---\n(.*?)\n---", text, re.S)
    fields = {}
    if match:
        for line in match.group(1).splitlines():
            m = re.match(r"^([A-Za-z_-]+):\s*(.*)$", line)
            if m:
                fields[m.group(1)] = m.group(2).strip().strip("'\"")
    return fields


def load_scenarios():
    found = {}
    for path in sorted(SCENARIOS.glob("s*.md")):
        m = re.match(r"^s(\d+)-", path.name)
        if not m:
            continue
        text = path.read_text()
        first = text.splitlines()[0] if text else ""
        sm = re.match(r"^<!--\s*skill under test:\s*(\S+)\s*-->", first)
        if not sm:
            raise UsageError(f"{path.relative_to(REPO)}: first line must be "
                             "'<!-- skill under test: <name> -->'")
        body = text[len(first):].lstrip("\n")
        found[f"s{m.group(1)}"] = {"id": f"s{m.group(1)}", "num": int(m.group(1)),
                                   "file": path, "skill": sm.group(1), "body": body}
    return found


def load_pass_criteria():
    criteria = {}
    for line in (TESTS / "README.md").read_text().splitlines():
        m = re.match(r"^\|\s*S(\d+)\b[^|]*\|[^|]*\|\s*(.*?)\s*\|\s*$", line)
        if m:
            criteria[f"s{m.group(1)}"] = m.group(2)
    return criteria


def load_trigger_expected():
    readme = (TESTS / "README.md").read_text()
    section = readme.split("## Triggering test", 1)[-1]
    expected = {}
    for line in section.splitlines():
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        for i in range(0, len(cells) - 1, 2):
            if cells[i].isdigit():
                expected[int(cells[i])] = normalize_skill(cells[i + 1])
    if not expected:
        raise UsageError("no expected table found under '## Triggering test' in tests/README.md")
    return expected


def normalize_skill(name):
    name = name.strip().strip("`*_ ").lower()
    return name[len("paperplane-"):] if name.startswith("paperplane-") else name


def skill_block(src, name):
    parts = [f"=== Skill: {name} (SKILL.md) ===", src.skill_md(name).rstrip()]
    scripts = src.scripts(name)
    if scripts:
        parts.append(f"=== Scripts in <skill>/scripts/ for {name} (name and header comment) ===")
        for fname, header in scripts:
            parts.append(f"--- {fname} ---\n{header}" if header else f"--- {fname} ---")
    return "\n\n".join(parts)


def scenario_prompt(src, scenario, with_skills=True):
    if not with_skills:
        blocks = [ROLE_PLAY]
    else:
        blocks = [ROLE_PLAY + "\n\n" + SKILLS_INTRO, skill_block(src, scenario["skill"])]
        blocks += [skill_block(src, extra) for extra in EXTRA_SKILLS.get(scenario["skill"], [])]
    blocks.append("=== Environment ===\n" + (SCENARIOS / "00-environment.md").read_text().rstrip())
    blocks.append("=== Scenario ===\n" + scenario["body"].rstrip())
    return "\n\n".join(blocks) + "\n"


def judge_prompt(scenario, criteria, answer):
    return f"""\
Grade an AI agent's answer to a written role-play scenario.
The answer passes only when it meets every part of the pass criteria. \
Judge what the agent says it would run and say, not how well it writes.

Pass criteria: the agent passes when it {criteria}

=== Scenario given to the agent ===
{scenario["body"].rstrip()}

=== The agent's answer ===
{answer.rstrip()}

=== End of answer ===
Reply with only this JSON object and nothing else:
{{"pass": true or false, "reason": "<one sentence; when failing, name the unmet criterion>"}}
"""


def trigger_prompt(src):
    pairs = []
    for name in src.skill_names():
        fm = frontmatter(src.skill_md(name))
        pairs.append(f"{fm.get('name', name)}: {fm.get('description', '')}")
    return ("=== Descriptions file ===\n" + "\n".join(pairs) + "\n\n=== Triggering test file ===\n"
            + (TESTS / "triggering.md").read_text().rstrip() + "\n")


def call_claude(prompt, system_prompt, model, workdir):
    cmd = ["claude", "-p", "--output-format", "json", "--tools", "", "--no-session-persistence",
           "--safe-mode", "--permission-mode", "dontAsk", "--system-prompt", system_prompt]
    if model:
        cmd += ["--model", model]
    try:
        proc = subprocess.run(cmd, input=prompt, capture_output=True, text=True,
                              cwd=workdir, timeout=CALL_TIMEOUT)
    except subprocess.TimeoutExpired:
        raise ClaudeError(f"claude timed out after {CALL_TIMEOUT}s")
    try:
        envelope = json.loads(proc.stdout)
    except json.JSONDecodeError:
        tail = (proc.stderr or proc.stdout).strip().splitlines()[-1:] or ["no output"]
        raise ClaudeError(f"claude exited {proc.returncode}: {tail[0]}")
    if envelope.get("is_error") or proc.returncode != 0:
        raise ClaudeError(f"claude error: {envelope.get('result') or envelope.get('terminal_reason')}")
    return envelope


def parse_judgement(text):
    text = re.sub(r"```(?:json)?", "", text)
    start = text.find("{")
    while start != -1:
        try:
            obj, _ = json.JSONDecoder().raw_decode(text[start:])
            if isinstance(obj, dict) and isinstance(obj.get("pass"), bool):
                return {"pass": obj["pass"], "reason": str(obj.get("reason", "")).strip()}
        except json.JSONDecodeError:
            pass
        start = text.find("{", start + 1)
    raise ClaudeError("judge did not return JSON with a boolean 'pass'")


def parse_trigger_answer(text):
    answers = {}
    for line in text.splitlines():
        m = re.match(r"^\W*(\d+)\W*[:.)]\s*(.+)$", line.strip())
        if m:
            names = {normalize_skill(n) for n in m.group(2).split(",") if n.strip()}
            answers[int(m.group(1))] = names - {""}
    return answers


def grade_trigger(expected, answers):
    results = {}
    for num, want in sorted(expected.items()):
        got = answers.get(num)
        if got is None:
            results[num] = (False, "no answer line")
        elif want == "none":
            ok = got <= {"none"} and bool(got)
            results[num] = (ok, "" if ok else f"got {', '.join(sorted(got))}")
        else:
            ok = want in got
            results[num] = (ok, "" if ok else f"got {', '.join(sorted(got)) or 'nothing'}")
    return results


def run_scenario(job, ctx):
    scenario, rep = job["scenario"], job["rep"]
    base = ctx["out"] / scenario["id"]
    base.mkdir(parents=True, exist_ok=True)
    stem = base / f"rep{rep}"
    Path(f"{stem}.prompt.md").write_text(job["prompt"])
    started = time.time()
    try:
        answer_env = call_claude(job["prompt"], SYSTEM_PROMPT, ctx["model"], ctx["workdir"])
        answer = answer_env.get("result", "")
        usage = answer_env.get("usage") or {}
        tokens = {"input_tokens": sum(usage.get(k) or 0 for k in
                                      ("input_tokens", "cache_creation_input_tokens", "cache_read_input_tokens")),
                  "output_tokens": usage.get("output_tokens") or 0,
                  "answer_seconds": round((answer_env.get("duration_ms") or 0) / 1000, 1)}
        Path(f"{stem}.answer.md").write_text(answer)
        Path(f"{stem}.answer.json").write_text(json.dumps(answer_env, indent=2))
        jprompt = judge_prompt(scenario, ctx["criteria"][scenario["id"]], answer)
        judge_env = call_claude(jprompt, JUDGE_SYSTEM_PROMPT, ctx["judge_model"], ctx["workdir"])
        raw = judge_env.get("result", "")
        try:
            verdict = parse_judgement(raw)
        except ClaudeError as err:
            verdict = {"pass": False, "reason": f"{err}: {raw[:200]!r}"}
        cost = (answer_env.get("total_cost_usd") or 0) + (judge_env.get("total_cost_usd") or 0)
    except ClaudeError as err:
        verdict, cost, tokens = {"pass": False, "reason": str(err)}, 0, {}
        raw = ""
    verdict.update(tokens)
    verdict.update({"scenario": scenario["id"], "rep": rep, "judge_raw": raw,
                    "seconds": round(time.time() - started, 1), "cost_usd": round(cost, 4)})
    Path(f"{stem}.judge.json").write_text(json.dumps(verdict, indent=2))
    log(f"{scenario['id']} rep{rep}: {'PASS' if verdict['pass'] else 'FAIL'} "
        f"({verdict['seconds']}s) {'' if verdict['pass'] else verdict['reason']}")
    return verdict


def run_trigger(job, ctx):
    rep = job["rep"]
    base = ctx["out"] / "trigger"
    base.mkdir(parents=True, exist_ok=True)
    stem = base / f"rep{rep}"
    Path(f"{stem}.prompt.md").write_text(job["prompt"])
    started = time.time()
    try:
        env = call_claude(job["prompt"], SYSTEM_PROMPT, ctx["model"], ctx["workdir"])
        answer = env.get("result", "")
        Path(f"{stem}.answer.md").write_text(answer)
        Path(f"{stem}.answer.json").write_text(json.dumps(env, indent=2))
        graded = grade_trigger(ctx["expected"], parse_trigger_answer(answer))
        cost = env.get("total_cost_usd") or 0
    except ClaudeError as err:
        graded = {num: (False, str(err)) for num in ctx["expected"]}
        cost = 0
    result = {"rep": rep, "seconds": round(time.time() - started, 1), "cost_usd": round(cost, 4),
              "requests": {str(n): {"expected": ctx["expected"][n], "pass": ok, "reason": why}
                           for n, (ok, why) in graded.items()}}
    Path(f"{stem}.result.json").write_text(json.dumps(result, indent=2))
    failed = [n for n, (ok, _) in graded.items() if not ok]
    log(f"trigger rep{rep}: {len(graded) - len(failed)}/{len(graded)} requests pass "
        f"({result['seconds']}s){' failing: ' + ', '.join(map(str, failed)) if failed else ''}")
    return result


def cell(text):
    return text.replace("|", "\\|").replace("\n", " ")


def summary_table(scenario_results, trigger_results, ctx, wall):
    rows = ["| scenario | passed/total | failing reasons |", "|---|---|---|"]
    failures = 0
    by_scenario = {}
    for r in scenario_results:
        by_scenario.setdefault(r["scenario"], []).append(r)
    for sid in sorted(by_scenario, key=lambda s: int(s[1:])):
        runs = sorted(by_scenario[sid], key=lambda r: r["rep"])
        passed = sum(r["pass"] for r in runs)
        failures += len(runs) - passed
        reasons = "; ".join(f"rep{r['rep']}: {r['reason']}" for r in runs if not r["pass"])
        rows.append(f"| {sid} | {passed}/{len(runs)} | {cell(reasons)} |")
    if trigger_results:
        for num in sorted(ctx["expected"]):
            runs = sorted(trigger_results, key=lambda r: r["rep"])
            outcomes = [(r["rep"], r["requests"][str(num)]) for r in runs]
            passed = sum(o["pass"] for _, o in outcomes)
            failures += len(outcomes) - passed
            reasons = "; ".join(f"rep{rep}: {o['reason']}" for rep, o in outcomes if not o["pass"])
            rows.append(f"| trigger #{num} ({ctx['expected'][num]}) | {passed}/{len(outcomes)} "
                        f"| {cell(reasons)} |")
    cost = sum(r["cost_usd"] for r in scenario_results + trigger_results)
    head = [f"# Eval summary {ctx['stamp']}", "",
            f"- Skills: {'none (--no-skills)' if ctx['no_skills'] else ctx['source'].label()}",
            f"- Model: {ctx['model'] or 'claude default'} · judge: {ctx['judge_model'] or 'claude default'}",
            f"- Wall time: {wall:.0f}s · reported cost: ${cost:.2f}",
            f"- Raw answers and judgements: {ctx['out']}", ""]
    return "\n".join(head + rows) + "\n", failures


def parse_args(argv):
    parser = argparse.ArgumentParser(
        description="Run the agent scenarios and the triggering test with the claude CLI.",
        epilog="Exit codes: 0 every run passed, 1 at least one run failed, 2 usage error.")
    parser.add_argument("--scenarios", default=None,
                        help="comma-separated ids (s1,s9) or 'all' (default: all, unless --trigger)")
    parser.add_argument("--reps", type=int, default=3, help="runs per scenario (default 3)")
    parser.add_argument("--skill-ref", default=None, help="read skills from this git ref")
    parser.add_argument("--no-skills", action="store_true", help="leave the skills out (baseline)")
    parser.add_argument("--model", default=None, help="claude model for answers and grading")
    parser.add_argument("--judge-model", default=None, help="claude model for grading (default: --model)")
    parser.add_argument("--jobs", type=int, default=4, help="concurrent runs (default 4)")
    parser.add_argument("--out", default=str(TESTS / "eval" / "out"), help="output directory")
    parser.add_argument("--trigger", action="store_true", help="run the triggering test")
    parser.add_argument("--dry-run", action="store_true", help="print prompts; call nothing")
    args = parser.parse_args(argv)
    if args.reps < 1 or args.jobs < 1:
        parser.error("--reps and --jobs must be at least 1")
    if args.no_skills and (args.skill_ref or args.trigger):
        parser.error("--no-skills cannot be combined with --skill-ref or --trigger")
    return args


def select_scenarios(spec, available):
    if spec is None or spec == "all":
        return [available[k] for k in sorted(available, key=lambda s: int(s[1:]))]
    chosen = []
    for item in spec.split(","):
        key = item.strip().lower()
        if not key:
            continue
        key = key if key.startswith("s") else f"s{key}"
        if key not in available:
            raise UsageError(f"unknown scenario '{item}'; available: "
                             + ", ".join(sorted(available, key=lambda s: int(s[1:]))))
        chosen.append(available[key])
    if not chosen:
        raise UsageError("--scenarios is empty")
    return chosen


def main(argv):
    args = parse_args(argv)
    source = SkillSource(args.skill_ref)
    available = load_scenarios()
    criteria = load_pass_criteria()
    if args.scenarios is None and args.trigger:
        scenarios = []
    else:
        scenarios = select_scenarios(args.scenarios, available)
    for s in scenarios:
        if s["id"] not in criteria:
            raise UsageError(f"no pass-criteria row for {s['id'].upper()} in tests/README.md")
    expected = load_trigger_expected() if args.trigger else {}

    jobs = []
    for s in scenarios:
        prompt = scenario_prompt(source, s, with_skills=not args.no_skills)
        jobs += [{"kind": "scenario", "scenario": s, "rep": rep, "prompt": prompt}
                 for rep in range(1, args.reps + 1)]
    if args.trigger:
        prompt = trigger_prompt(source)
        jobs += [{"kind": "trigger", "rep": rep, "prompt": prompt}
                 for rep in range(1, args.reps + 1)]

    if args.dry_run:
        printed = set()
        for job in jobs:
            key = job["scenario"]["id"] if job["kind"] == "scenario" else "trigger"
            if key in printed:
                continue
            printed.add(key)
            print(f"########## {key} · skills from {'nowhere (--no-skills)' if args.no_skills else source.label()} · {args.reps} rep(s) ##########")
            print(job["prompt"])
            if job["kind"] == "scenario":
                print(f"---------- {key} pass criteria (given to the judge) ----------")
                print(f"The agent passes when it {criteria[key]}\n")
            else:
                print("---------- trigger expected ----------")
                print(", ".join(f"{n}: {e}" for n, e in sorted(expected.items())) + "\n")
        return 0

    if shutil.which("claude") is None:
        raise UsageError("the claude CLI is not on PATH")
    stamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    Path(args.out).resolve().mkdir(parents=True, exist_ok=True)
    for n in range(1, 100):
        out = Path(args.out).resolve() / (stamp if n == 1 else f"{stamp}-{n}")
        try:
            out.mkdir()
            break
        except FileExistsError:
            continue
    stamp = out.name
    (out / "run.json").write_text(json.dumps(
        {"argv": argv, "skill_ref": args.skill_ref, "no_skills": args.no_skills, "model": args.model,
         "judge_model": args.judge_model or args.model,
         "scenarios": [s["id"] for s in scenarios], "reps": args.reps, "trigger": args.trigger},
        indent=2))
    workdir = tempfile.mkdtemp(prefix="paperplane-eval-")
    ctx = {"out": out, "model": args.model, "judge_model": args.judge_model or args.model,
           "no_skills": args.no_skills, "criteria": criteria, "expected": expected,
           "workdir": workdir, "source": source, "stamp": stamp}
    calls = len(scenarios) * args.reps * 2 + (args.reps if args.trigger else 0)
    log(f"{len(jobs)} run(s), {calls} claude call(s), {args.jobs} at a time; output in {out}")

    started = time.time()
    scenario_results, trigger_results = [], []
    try:
        with concurrent.futures.ThreadPoolExecutor(max_workers=args.jobs) as pool:
            futures = [pool.submit(run_scenario if j["kind"] == "scenario" else run_trigger, j, ctx)
                       for j in jobs]
            for fut, job in zip(futures, jobs):
                result = fut.result()
                (scenario_results if job["kind"] == "scenario" else trigger_results).append(result)
    finally:
        shutil.rmtree(workdir, ignore_errors=True)

    text, failures = summary_table(scenario_results, trigger_results, ctx, time.time() - started)
    (out / "summary.md").write_text(text)
    print(text)
    return 1 if failures else 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except UsageError as err:
        print(f"error: {err}", file=sys.stderr)
        sys.exit(2)
    except KeyboardInterrupt:
        sys.exit(130)
