#!/usr/bin/env python3
"""Human spot-check of the eval judge. Python 3 standard library only.

  python3 tests/eval/label.py sample --n 40 --seed 1   # read answers blind, type p / f / s / q
  python3 tests/eval/label.py report                   # human labels vs the judge: agreement, kappa, precision, recall
  python3 tests/eval/label.py --self-test              # offline, fake data

`sample` picks a stratified random sample (round-robin over scenarios, so each scenario gets about
the same number of answers) from tests/eval/labels/answers/*.md, skips answers you already labeled,
and shows each one WITHOUT any verdict, next to the scenario text and its pass criteria. Your keys:
p = pass, f = fail, s = skip (not recorded), q = quit. Each p/f appends one line to
tests/eval/labels/human.jsonl:

  {"run": "tests/eval/labels/answers/s1-opus-skills-1.md", "scenario": "s1",
   "human_pass": true, "labeler": "<git user.name or $USER>", "ts": "2026-10-27T10:15:00+00:00"}

The newest line per run wins, so you can change your mind by labeling a run again with `--relabel RUN`.
`report` joins human.jsonl with the judge verdict (`judge_pass`) in labels.jsonl by `run`, and prints
overall agreement with a Wilson 95% interval, Cohen's kappa, and per scenario the judge's precision
(of the answers the judge passed, the share you passed) and recall (of the answers you passed, the
share the judge passed), each with a Wilson interval, then lists every disagreement.
"""

import argparse
import datetime
import json
import math
import os
import random
import re
import subprocess
import sys
import tempfile
from collections import defaultdict
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]


class Paths:
    def __init__(self, root=REPO):
        self.root = Path(root)
        self.tests = self.root / "tests"
        self.answers = self.tests / "eval" / "labels" / "answers"
        self.labels = self.tests / "eval" / "labels" / "labels.jsonl"
        self.human = self.tests / "eval" / "labels" / "human.jsonl"
        self.scenarios = self.tests / "scenarios"
        self.readme = self.tests / "README.md"


def wilson(passed, total, z=1.96):
    if total == 0:
        return (0.0, 1.0)
    p = passed / total
    d = 1 + z * z / total
    centre = (p + z * z / (2 * total)) / d
    half = z * math.sqrt(p * (1 - p) / total + z * z / (4 * total * total)) / d
    return (max(0.0, centre - half), min(1.0, centre + half))


def fmt(passed, total):
    if total == 0:
        return "n/a"
    lo, hi = wilson(passed, total)
    return f"{passed}/{total} = {100 * passed / total:.0f}% [{100 * lo:.0f}-{100 * hi:.0f}%]"


def kappa(pairs):
    """Cohen's kappa for [(human, judge)] booleans; None when undefined."""
    n = len(pairs)
    if n == 0:
        return None
    po = sum(h == j for h, j in pairs) / n
    ph = sum(h for h, _ in pairs) / n
    pj = sum(j for _, j in pairs) / n
    pe = ph * pj + (1 - ph) * (1 - pj)
    if pe == 1:
        return 1.0 if po == 1 else None
    return (po - pe) / (1 - pe)


def read_jsonl(path):
    if not path.exists():
        return []
    return [json.loads(x) for x in path.read_text().splitlines() if x.strip()]


def scenario_of(path):
    m = re.match(r"^(s\d+)-", Path(path).name)
    return m.group(1) if m else None


def criteria_for(paths, sid):
    num = sid[1:]
    for line in paths.readme.read_text().splitlines():
        m = re.match(rf"^\|\s*S{num}\b[^|]*\|[^|]*\|\s*(.*?)\s*\|\s*$", line)
        if m:
            # Two-part rows: show Safe and Convention on their own lines. Label overall pass = both parts pass.
            return re.sub(r"\s*\*\*Convention:\*\*", "\n**Convention:**", m.group(1))
    return "(no pass criteria row found in tests/README.md)"


def scenario_text(paths, sid):
    for f in sorted(paths.scenarios.glob(f"{sid}-*.md")):
        return f.read_text()
    return "(scenario file not found)"


def latest_human(paths):
    out = {}
    for row in read_jsonl(paths.human):
        out[row["run"]] = row
    return out


def rel(paths, f):
    try:
        return str(f.relative_to(paths.root))
    except ValueError:
        return str(f)


def pick_sample(paths, n, seed, include_labeled=False):
    """Stratified: shuffle each scenario's answers, then take round-robin across scenarios."""
    done = set() if include_labeled else set(latest_human(paths))
    by_sc = defaultdict(list)
    for f in sorted(paths.answers.glob("*.md")):
        sid = scenario_of(f)
        if sid and rel(paths, f) not in done:
            by_sc[sid].append(f)
    rng = random.Random(seed)
    for files in by_sc.values():
        rng.shuffle(files)
    order = sorted(by_sc, key=lambda s: int(s[1:]))
    rng.shuffle(order)
    picked = []
    while len(picked) < n and any(by_sc.values()):
        for sid in order:
            if by_sc[sid] and len(picked) < n:
                picked.append(by_sc[sid].pop())
    rng.shuffle(picked)
    return picked


def labeler():
    try:
        name = subprocess.run(["git", "config", "user.name"], capture_output=True, text=True, timeout=5).stdout.strip()
    except (OSError, subprocess.SubprocessError):
        name = ""
    return name or os.environ.get("USER", "unknown")


def show(paths, f, i, total):
    sid = scenario_of(f)
    bar = "=" * 78
    print(f"\n{bar}\nAnswer {i}/{total}  ({sid})  -- the judge's verdict is hidden\n{bar}")
    print("SCENARIO\n" + scenario_text(paths, sid).strip())
    print("\nPASS CRITERIA\n" + criteria_for(paths, sid))
    print("\nANSWER\n" + f.read_text().strip() + "\n")


def cmd_sample(paths, n, seed, relabel=None, input_fn=input, out=print):
    files = [paths.root / relabel] if relabel else pick_sample(paths, n, seed)
    if not files:
        out("Nothing left to label.")
        return 0
    who, done, skipped = labeler(), 0, 0
    paths.human.parent.mkdir(parents=True, exist_ok=True)
    for i, f in enumerate(files, 1):
        show(paths, f, i, len(files))
        while True:
            try:
                key = input_fn("pass / fail / skip / quit [p/f/s/q]: ").strip().lower()
            except EOFError:
                key = "q"
            if key in ("p", "f", "s", "q"):
                break
        if key == "q":
            break
        if key == "s":
            skipped += 1
            continue
        row = {"run": rel(paths, f), "scenario": scenario_of(f), "human_pass": key == "p",
               "labeler": who, "ts": datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds")}
        with paths.human.open("a") as fh:
            fh.write(json.dumps(row) + "\n")
        done += 1
    out(f"\nlabeled {done}, skipped {skipped}. Run: python3 tests/eval/label.py report")
    return 0


def compute(paths):
    """Return (rows, skipped): rows are dicts with run, scenario, human, judge, label."""
    human = latest_human(paths)
    judge = {r["run"]: r for r in read_jsonl(paths.labels)}
    rows, missing = [], []
    for run, h in human.items():
        j = judge.get(run)
        if j is None or "judge_pass" not in j:
            missing.append(run)
            continue
        rows.append({"run": run, "scenario": h.get("scenario") or scenario_of(run), "human": bool(h["human_pass"]),
                     "judge": bool(j["judge_pass"]), "label": j.get("label_pass"), "reason": j.get("reason", "")})
    return rows, missing


def prf(rows):
    tp = sum(r["human"] and r["judge"] for r in rows)
    fp = sum(not r["human"] and r["judge"] for r in rows)
    fn = sum(r["human"] and not r["judge"] for r in rows)
    return tp, fp, fn


def cmd_report(paths, out=print):
    rows, missing = compute(paths)
    if not rows:
        out("No human labels joined with a judge verdict yet. Run: python3 tests/eval/label.py sample --n 40")
        return 0
    agree = sum(r["human"] == r["judge"] for r in rows)
    k = kappa([(r["human"], r["judge"]) for r in rows])
    out(f"human labels with a judge verdict: {len(rows)}" + (f" ({len(missing)} without one, ignored)" if missing else ""))
    out(f"agreement human vs judge: {fmt(agree, len(rows))}")
    out("Cohen's kappa: " + ("n/a (one class only)" if k is None else f"{k:.2f}"))
    with_label = [r for r in rows if isinstance(r["label"], bool)]
    if with_label:
        out(f"agreement human vs earlier agent label: {fmt(sum(r['human'] == r['label'] for r in with_label), len(with_label))}")
    tp, fp, fn = prf(rows)
    out(f"judge precision (judge pass -> human pass): {fmt(tp, tp + fp)}")
    out(f"judge recall (human pass -> judge pass): {fmt(tp, tp + fn)}")
    out("\nper scenario (n, agreement, judge precision, judge recall; intervals are Wilson 95%, n is small):")
    by_sc = defaultdict(list)
    for r in rows:
        by_sc[r["scenario"]].append(r)
    for sid in sorted(by_sc, key=lambda s: int(s[1:]) if s[1:].isdigit() else 0):
        rs = by_sc[sid]
        tp, fp, fn = prf(rs)
        out(f"  {sid:<4} n={len(rs):<3} agree {fmt(sum(r['human'] == r['judge'] for r in rs), len(rs)):<24} "
            f"precision {fmt(tp, tp + fp):<24} recall {fmt(tp, tp + fn)}")
    bad = [r for r in rows if r["human"] != r["judge"]]
    out(f"\ndisagreements ({len(bad)}):")
    for r in bad:
        out(f"  {r['run']}: human {'pass' if r['human'] else 'fail'}, judge {'pass' if r['judge'] else 'fail'}"
            + (f"\n      judge reason: {r['reason']}" if r["reason"] else ""))
    return 0


def self_test():
    failures = []

    def expect(cond, what):
        print(("ok   " if cond else "FAIL ") + what)
        if not cond:
            failures.append(what)

    expect(abs(kappa([(True, True), (False, False)]) - 1.0) < 1e-9, "kappa 1 for perfect agreement")
    expect(abs(kappa([(True, False), (False, True)]) + 1.0) < 1e-9, "kappa -1 for perfect disagreement")
    expect(kappa([(True, True), (True, True)]) == 1.0, "kappa defined when both always pass and agree")
    k = kappa([(True, True)] * 40 + [(False, False)] * 40 + [(True, False)] * 10 + [(False, True)] * 10)
    expect(abs(k - 0.6) < 1e-9, "kappa 0.6 on a known table")
    lo, hi = wilson(8, 10)
    expect(0.49 < lo < 0.50 and 0.93 < hi < 0.95, "Wilson 8/10 is about 49-94%")
    expect(wilson(0, 0) == (0.0, 1.0), "Wilson with n=0")

    with tempfile.TemporaryDirectory() as td:
        paths = Paths(td)
        paths.answers.mkdir(parents=True)
        paths.scenarios.mkdir(parents=True)
        paths.readme.write_text("| S1 first | shipping | does the thing |\n| S2 second | releasing | does the other |\n"
                                "| S3 third | reviewing-prs | third criteria |\n")
        for sid in ("s1", "s2", "s3"):
            (paths.scenarios / f"{sid}-x.md").write_text(f"<!-- skill under test: x -->\n# Scenario {sid}\n")
        judge_rows = []
        for sid in ("s1", "s2", "s3"):
            for n in range(1, 7):
                run = f"tests/eval/labels/answers/{sid}-m-skills-{n}.md"
                (paths.root / run).write_text(f"answer text {sid} {n}")
                judge_rows.append({"run": run, "scenario": sid, "judge_pass": n % 2 == 0, "label_pass": n % 2 == 0,
                                   "reason": "fake"})
        paths.labels.write_text("\n".join(json.dumps(r) for r in judge_rows) + "\n")

        s1 = pick_sample(paths, 9, seed=1)
        expect(len(s1) == 9 and len(set(s1)) == 9, "sample returns n distinct answers")
        expect({scenario_of(f) for f in s1} == {"s1", "s2", "s3"} and
               all(sum(scenario_of(f) == s for f in s1) == 3 for s in ("s1", "s2", "s3")), "sample is stratified by scenario")
        expect(pick_sample(paths, 9, seed=1) == s1, "same seed, same sample")
        expect(pick_sample(paths, 9, seed=2) != s1, "different seed, different sample")

        lines, seen = [], []
        shown = []

        def fake_input(prompt):
            return keys.pop(0)

        # Drive 6 answers: p, f, s, p, f, q. The judge verdict must never be printed.
        keys = ["x", "p", "f", "s", "p", "f", "q"]
        import io
        import contextlib
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            cmd_sample(paths, 9, 1, input_fn=fake_input, out=lines.append)
        shown = buf.getvalue()
        expect("answer text" in shown and "does the" in shown and "Scenario s" in shown, "sample shows the answer, scenario and criteria")
        expect("judge_pass" not in shown and "fake" not in shown, "sample hides the judge verdict")
        human = read_jsonl(paths.human)
        expect(len(human) == 4 and [h["human_pass"] for h in human] == [True, False, True, False],
               "p/f append, s is not recorded, q stops")
        expect(all(h["run"] in {r["run"] for r in judge_rows} for h in human), "human.jsonl rows point at saved answers")

        again = pick_sample(paths, 20, seed=1)
        expect(len(again) == 14 and not {rel(paths, Path(paths.root / h["run"])) for h in human} & {rel(paths, f) for f in again},
               "answers already labeled are not offered again")

        # Report on a controlled file: 10 labels, 8 agree, 1 FP, 1 FN
        paths.human.write_text("")
        fake = []
        for i, r in enumerate(judge_rows[:10]):
            h = r["judge_pass"]
            if i == 0:
                h = not h
            if i == 1:
                h = not h
            fake.append({"run": r["run"], "scenario": r["scenario"], "human_pass": h})
        paths.human.write_text("\n".join(json.dumps(x) for x in fake) + "\n")
        out = []
        cmd_report(paths, out=out.append)
        text = "\n".join(out)
        expect("human labels with a judge verdict: 10" in text, "report counts joined labels")
        expect("agreement human vs judge: 8/10 = 80% [49-94%]" in text, "report prints agreement with a Wilson interval")
        expect("Cohen's kappa:" in text and "per scenario" in text, "report prints kappa and per-scenario rows")
        expect("disagreements (2):" in text, "report lists the 2 disagreements")
        expect("judge precision" in text and "judge recall" in text, "report prints precision and recall")
        out2 = []
        paths.human.write_text("")
        cmd_report(paths, out=out2.append)
        expect("No human labels" in out2[0], "report with no labels says what to do")

    if failures:
        print(f"\n{len(failures)} self-test check(s) failed")
        return 1
    print("\nself-test passed")
    return 0


def main(argv):
    ap = argparse.ArgumentParser(description="Human spot-check of the eval judge.")
    ap.add_argument("--self-test", action="store_true", help="offline test with fake data")
    sub = ap.add_subparsers(dest="cmd")
    sp = sub.add_parser("sample", help="label answers blind")
    sp.add_argument("--n", type=int, default=40)
    sp.add_argument("--seed", type=int, default=1)
    sp.add_argument("--relabel", metavar="RUN", help="show one saved answer again, e.g. tests/eval/labels/answers/s1-opus-skills-1.md")
    sub.add_parser("report", help="compare human labels with the judge")
    args = ap.parse_args(argv)
    if args.self_test:
        return self_test()
    paths = Paths()
    if args.cmd == "sample":
        return cmd_sample(paths, args.n, args.seed, args.relabel)
    if args.cmd == "report":
        return cmd_report(paths)
    ap.print_usage(sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
