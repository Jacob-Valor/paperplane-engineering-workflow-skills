"""Run the scenario eval through an omp eval kernel's `completion()` instead of the `claude` CLI.

Use it when `claude -p` is not available (no login, no ANTHROPIC_API_KEY). It reuses run.py's prompts, judge
prompt, checks and summary, and writes the same directory layout, so `run.py --summarize DIR --save-results`
reads its output. Every judge.json and run.json records the model each call resolved to, from the handle's
`attempts`, not only the alias.

Only runs inside an omp Python eval kernel, which provides `completion`:

    import sys; sys.path.insert(0, "tests/eval")
    import omp_bridge
    out = omp_bridge.run(completion, ["s59", "s60"], reps=3, judge="slow")              # working tree
    out = omp_bridge.run(completion, ["s59"], reps=3, skill_ref="main", label="red")     # before
    omp_bridge.summarize(out)                                                            # also --save-results

Answer calls all start at once; each judge call starts when its answer arrives, and results are awaited in order:
`completion()` must be called from the kernel's main thread, so run.py's thread pool is not used. A call that fails
is `invalid`, as in run.py; `fill_invalid` re-runs those in place, refusing when the skill text changed since the run
started. `regrade` grades a finished run's answers again, every one, into a new directory (criteria or checks changed).
"""

import datetime
import json
import shutil
import hashlib
import time
from pathlib import Path

import checks
import run as R


def _file_digest(rel):
    """First 12 hex digits of a file's sha256: which criteria or checks a run was graded with."""
    return hashlib.sha256((R.REPO / rel).read_bytes()).hexdigest()[:12]


def _grading_digests():
    return {"criteria_digest": _file_digest("tests/README.md"), "checks_digest": _file_digest("tests/eval/checks.py")}


def _model(handle):
    attempts = getattr(handle, "attempts", None) or []
    return next((a.get("model") for a in reversed(attempts) if a.get("outcome") == "succeeded"), None)


def _judge(completion, scenario, criteria, answer, judge):
    jh = completion(R.judge_prompt(scenario, criteria, answer), system=R.JUDGE_SYSTEM_PROMPT, model=judge)
    raw = jh.wait()
    verdict = R.apply_checks(R.parse_judgement(raw), checks.run_checks(scenario["id"], answer))
    return verdict, raw, _model(jh)


def _write(stem, scenario, rep, t0, verdict, raw, answer_model, judge_model):
    verdict.update({"scenario": scenario["id"], "rep": rep, "judge_raw": raw, "seconds": round(time.time() - t0, 1),
                    "cost_usd": 0, "answer_model_id": answer_model, "judge_model_id": judge_model})
    Path(f"{stem}.judge.json").write_text(json.dumps(verdict, indent=2))


def run(completion, ids, reps=3, skill_ref=None, no_skills=False, baseline_context=None, label="",
        model="default", judge="slow", trigger=False):
    src = R.SkillSource(skill_ref)
    avail, crit = R.load_scenarios(), R.load_pass_criteria()
    bctx = R.read_baseline_context(baseline_context)
    stamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S") + (f"-{label}" if label else "")
    out = R.REPO / "tests" / "eval" / "out" / stamp
    out.mkdir(parents=True)
    meta = {"argv": ["tests/eval/omp_bridge.py"], "skill_ref": skill_ref, "no_skills": no_skills,
            "model": f"omp completion:{model}", "judge_model": f"omp completion:{judge}", "checks": True,
            "baseline_context": baseline_context, "fail_under": 1.0, "scenarios": ids, "reps": reps,
            "trigger": trigger, "skills_digest": None if no_skills else src.digest(),
            "commit": R.git("rev-parse", skill_ref or "HEAD").strip(),
            "tree_dirty": skill_ref is None and bool(R.git("status", "--porcelain", "--", "skills").strip()),
            **_grading_digests()}
    jobs = []
    for sid in ids:
        s = avail[sid]
        prompt = R.scenario_prompt(src, s, with_skills=not no_skills, baseline_context=bctx)
        for rep in range(1, reps + 1):
            jobs.append((s, rep, prompt, time.time(), completion(prompt, system=R.SYSTEM_PROMPT, model=model)))
    trig = [completion(R.trigger_prompt(src), system=R.SYSTEM_PROMPT, model=model) for _ in range(reps)] if trigger else []
    resolved = set()
    for s, rep, prompt, t0, h in jobs:
        base = out / s["id"]
        base.mkdir(exist_ok=True)
        stem = base / f"rep{rep}"
        Path(f"{stem}.prompt.md").write_text(prompt)
        try:
            answer = h.wait()
            Path(f"{stem}.answer.md").write_text(answer)
            verdict, raw, jm = _judge(completion, s, crit[s["id"]], answer, judge)
            _write(stem, s, rep, t0, verdict, raw, _model(h), jm)
            resolved.update({("answer", _model(h)), ("judge", jm)})
        except Exception as err:  # a failed call says nothing about the skill: invalid, as in run.py
            _write(stem, s, rep, t0, {"pass": False, "invalid": True, "reason": str(err)}, "", None, None)
    if trigger:
        expected = R.load_trigger_expected()
        (out / "trigger").mkdir()
        for i, h in enumerate(trig, 1):
            try:
                answer = h.wait()
                graded, invalid = R.grade_trigger(expected, R.parse_trigger_answer(answer)), False
            except Exception as err:
                answer, invalid = "", True
                graded = {n: (False, str(err)) for n in expected}
            Path(out / f"trigger/rep{i}.answer.md").write_text(answer)
            Path(out / f"trigger/rep{i}.result.json").write_text(json.dumps(
                {"rep": i, "seconds": 0, "cost_usd": 0, "invalid": invalid, "answer_model_id": _model(h),
                 "requests": {str(n): {"expected": expected[n], "pass": ok, "reason": why}
                              for n, (ok, why) in graded.items()}}, indent=2))
            resolved.add(("answer", _model(h)))
    meta["resolved_models"] = {k: sorted(m for kk, m in resolved if kk == k and m) for k in ("answer", "judge")}
    (out / "run.json").write_text(json.dumps(meta, indent=2))
    return out


def fill_invalid(completion, out, model="default", judge="slow", rounds=3):
    """Re-run the invalid runs of a working-tree run in place; refuse if the skill text changed since."""
    meta = json.loads((Path(out) / "run.json").read_text())
    src = R.SkillSource(meta.get("skill_ref"))
    if not meta.get("no_skills") and src.digest() != meta.get("skills_digest"):
        raise RuntimeError("skill text changed since this run started; start a new run instead")
    avail, crit = R.load_scenarios(), R.load_pass_criteria()
    bctx = R.read_baseline_context(meta.get("baseline_context"))
    for _ in range(rounds):
        todo = [jf for jf in sorted(Path(out).glob("s*/rep*.judge.json")) if json.loads(jf.read_text()).get("invalid")]
        if not todo:
            break
        started = []
        for jf in todo:
            v = json.loads(jf.read_text())
            s = avail[v["scenario"]]
            prompt = R.scenario_prompt(src, s, with_skills=not meta.get("no_skills"), baseline_context=bctx)
            started.append((jf, s, v["rep"], time.time(), completion(prompt, system=R.SYSTEM_PROMPT, model=model)))
        for jf, s, rep, t0, h in started:
            stem = str(jf)[: -len(".judge.json")]
            try:
                answer = h.wait()
                Path(f"{stem}.answer.md").write_text(answer)
                verdict, raw, jm = _judge(completion, s, crit[s["id"]], answer, judge)
                _write(stem, s, rep, t0, verdict, raw, _model(h), jm)
            except Exception as err:
                _write(stem, s, rep, t0, {"pass": False, "invalid": True, "reason": str(err)}, "", None, None)
    _refresh_models(out)
    return [str(jf.relative_to(out)) for jf in Path(out).glob("s*/rep*.judge.json")
            if json.loads(jf.read_text()).get("invalid")]


def _refresh_models(out):
    """Rebuild run.json's resolved_models from the judge files, after runs were added or re-graded."""
    meta_path = Path(out) / "run.json"
    meta = json.loads(meta_path.read_text())
    found = {"answer": set(), "judge": set()}
    for jf in Path(out).glob("s*/rep*.judge.json"):
        v = json.loads(jf.read_text())
        found["answer"].add(v.get("answer_model_id"))
        found["judge"].add(v.get("judge_model_id"))
    for tf in Path(out).glob("trigger/rep*.result.json"):
        found["answer"].add(json.loads(tf.read_text()).get("answer_model_id"))
    meta["resolved_models"] = {k: sorted(m for m in v if m) for k, v in found.items()}
    meta_path.write_text(json.dumps(meta, indent=2))


def regrade(completion, src, label="regraded", judge="slow"):
    """Grade every answer of a finished run again with the current criteria and checks, into <src>-<label>.
    The answers are not re-generated; the source directory is left as it was."""
    src = Path(src)
    dest = src.parent / f"{src.name}-{label}"
    shutil.copytree(src, dest)
    meta = json.loads((dest / "run.json").read_text())
    meta.update({"regraded_from": src.name, "argv": ["tests/eval/omp_bridge.py regrade"],
                 "judge_model": f"omp completion:{judge}", **_grading_digests()})
    (dest / "run.json").write_text(json.dumps(meta, indent=2))
    avail, crit = R.load_scenarios(), R.load_pass_criteria()
    pending = []
    for jf in sorted(dest.glob("s*/rep*.judge.json")):
        v = json.loads(jf.read_text())
        answer_path = Path(str(jf)[: -len(".judge.json")] + ".answer.md")
        if v.get("invalid") or not answer_path.is_file():
            continue
        s, answer = avail[v["scenario"]], answer_path.read_text()
        pending.append((jf, v, s, answer, completion(R.judge_prompt(s, crit[s["id"]], answer),
                                                     system=R.JUDGE_SYSTEM_PROMPT, model=judge)))
    for jf, v, s, answer, h in pending:
        try:
            raw = h.wait()
            verdict = R.apply_checks(R.parse_judgement(raw), checks.run_checks(s["id"], answer))
        except Exception as err:
            raw, verdict = "", {"pass": False, "invalid": True, "reason": str(err)}
        verdict.update({k: v.get(k) for k in ("scenario", "rep", "seconds", "cost_usd", "answer_model_id")})
        verdict.update({"judge_raw": raw, "judge_model_id": _model(h)})
        jf.write_text(json.dumps(verdict, indent=2))
    _refresh_models(dest)
    return dest


def summarize(out, save=True):
    """Print the summary; with save, also write tests/eval/results/<stamp>/ as `run.py --summarize --save-results`."""
    return R.summarize_dir(str(out), 1.0, save=save)
