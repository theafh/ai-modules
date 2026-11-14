#!/usr/bin/env python3
"""Unit tests for the settings block in language_humanizer's run records and
for the re-grade's refusal to compare across judge settings.

Every external step is stubbed: the stage, the micro-deployment, the worker,
the grader subprocess, and the judge. No worker starts and no model is called.

Run:

    python3 tests/language_humanizer/evals/test_run.py
"""

from __future__ import annotations

import argparse
import contextlib
import io
import json
import pathlib
import shutil
import subprocess
import sys
import tempfile
import types

THIS = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(THIS))

import regrade  # noqa: E402  (sibling module; imports run and judge)
import run as run_mod  # noqa: E402

judge_mod = regrade.judge_mod
vendor = run_mod.vendor

SCENARIO = "fidelity_padded"
SETTINGS_KEYS = ("vendor", "worker_model", "worker_effort", "judge_model", "judge_effort")
CLAUDE_DEFAULTS = {
    "vendor": "claude",
    "worker_model": "opus",
    "worker_effort": "high",
    "judge_model": "opus",
    "judge_effort": "xhigh",
}
GRADE_REPLY = {
    "passed": True,
    "mechanical": {"words_kept": {"passed": True}},
    "integrity": {},
    "delivered_words": 10,
    "fixture_words": 12,
}

PASS = 0
FAIL = 0


def check(label: str, condition: bool, detail: object = "") -> None:
    global PASS, FAIL
    if condition:
        PASS += 1
        print(f"  ok   {label}")
    else:
        FAIL += 1
        print(f"  FAIL {label}" + (f": {detail}" if detail else ""))


def pick(record: dict, keys=SETTINGS_KEYS) -> dict:
    return {key: record.get(key, "<absent>") for key in keys}


def resolve(argv: list[str]) -> "vendor.Resolved":
    parser = argparse.ArgumentParser(add_help=False)
    vendor.add_vendor_arguments(parser, with_judge=True)
    return vendor.resolve(parser.parse_args(argv), with_judge=True)


@contextlib.contextmanager
def stubbed_externals(judged: list):
    """Stub the grader subprocess and the judge for the duration of a case."""

    real_subprocess_run = subprocess.run

    def fake_subprocess_run(cmd, *args, **kwargs):
        if len(cmd) > 1 and str(cmd[1]) == str(run_mod.GRADE):
            return subprocess.CompletedProcess(
                cmd, 0, stdout=json.dumps(GRADE_REPLY), stderr="")
        return real_subprocess_run(cmd, *args, **kwargs)

    def fake_judge(*args, effort="", **_kwargs):
        judged.append({"judge_vendor": args[4], "judge_model": args[6],
                       "judge_effort": effort})
        return {"no_invented_content": {"passed": True, "why": "stub"}}

    real_judge = judge_mod.judge
    subprocess.run = fake_subprocess_run
    judge_mod.judge = fake_judge
    try:
        yield
    finally:
        subprocess.run = real_subprocess_run
        judge_mod.judge = real_judge


def stubbed_pass(resolved, skip_judge: bool) -> tuple[dict, list]:
    """Run run_isolated_pass with every external step stubbed.

    Returns the verdict.json the pass wrote and the judge calls it made.
    """

    tmp = pathlib.Path(tempfile.mkdtemp(prefix="lh_test_run_"))
    root = tmp / "root"
    pass_dir = tmp / "pass-1"
    root.mkdir()
    pass_dir.mkdir()
    skill = tmp / "SKILL.md"
    skill.write_text("---\nname: language_humanizer\n---\n")
    judged: list = []

    def fake_stage(_scenario, target):
        proj = pathlib.Path(target) / "proj"
        proj.mkdir(parents=True, exist_ok=True)
        (proj / "draft.md").write_text("A draft.\n")
        (proj / "delivered.md").write_text("A delivered draft.\n")
        (pathlib.Path(target) / ".fixture_pristine").write_text("A draft.\n")
        return {"sandbox_proj": str(proj), "source_file": str(proj / "draft.md"),
                "skill_name": "language_humanizer", "skill_path": str(skill),
                "prompt": "Humanize draft.md."}

    @contextlib.contextmanager
    def fake_micro_deploy(*_args, **_kwargs):
        yield types.SimpleNamespace(path_map={"language_humanizer": skill})

    def fake_run_worker(**_kwargs):
        return types.SimpleNamespace(returncode=0, stdout="Delivered.\n", stderr="")

    def fake_provenance(_worker):
        return {"passed": True}, {"passed": True}

    deploy = run_mod.micro_deploy
    saved = (run_mod.stage, deploy.micro_deploy, deploy.run_worker,
             deploy.provenance_records)
    run_mod.stage = fake_stage
    deploy.micro_deploy = fake_micro_deploy
    deploy.run_worker = fake_run_worker
    deploy.provenance_records = fake_provenance
    try:
        with stubbed_externals(judged):
            args = argparse.Namespace(skip_judge=skip_judge, timeout=5,
                                      judge_timeout=5)
            run_mod.run_isolated_pass(SCENARIO, 1, pass_dir, root, args, resolved)
        verdict = json.loads((pass_dir / "verdict.json").read_text())
    finally:
        (run_mod.stage, deploy.micro_deploy, deploy.run_worker,
         deploy.provenance_records) = saved
        shutil.rmtree(tmp, ignore_errors=True)
    return verdict, judged


def regrade_run(original: dict | None, argv: list[str]) -> dict:
    """Re-grade a one-pass captured run whose summary.json holds `original`.

    `original=None` leaves summary.json out. Returns the exit code, the
    re-grade records, the stderr text, and the judge calls made.
    """

    tmp = pathlib.Path(tempfile.mkdtemp(prefix="lh_test_regrade_"))
    run_dir = tmp / "run-20261114-000000"
    pass_dir = run_dir / SCENARIO / "pass-1"
    proj = pass_dir / "sandbox" / "proj"
    proj.mkdir(parents=True)
    (proj / "draft.md").write_text("A draft.\n")
    (proj / "delivered.md").write_text("A delivered draft.\n")
    (pass_dir / "sandbox" / ".fixture_pristine").write_text("A draft.\n")
    (pass_dir / "response.txt").write_text("Delivered.\n")
    (pass_dir / "verdict.json").write_text(json.dumps(
        {"scenario": SCENARIO, "pass": 1, "passed": True, "worker_completed": True}))
    if original is not None:
        (run_dir / "summary.json").write_text(json.dumps(original))
    results = tmp / "results"
    judged: list = []
    real_results, real_argv = run_mod.RESULTS, sys.argv
    run_mod.RESULTS = results
    sys.argv = ["regrade.py", str(run_dir), "--workers", "1", *argv]
    err = io.StringIO()
    try:
        with stubbed_externals(judged), contextlib.redirect_stderr(err), \
                contextlib.redirect_stdout(io.StringIO()):
            rc = regrade.main()
        outcome = {
            "rc": rc,
            "summary": json.loads((run_dir / "summary.regrade.json").read_text()),
            "report": (run_dir / "summary.regrade.md").read_text(),
            "verdict": json.loads((pass_dir / "verdict.regrade.json").read_text()),
            "results": json.loads((results / f"{run_dir.name}-regrade.json").read_text()),
            "stderr": err.getvalue(),
            "judged": judged,
        }
    finally:
        run_mod.RESULTS, sys.argv = real_results, real_argv
        shutil.rmtree(tmp, ignore_errors=True)
    return outcome


def check_run_records() -> None:
    resolved = resolve(["--vendor", "claude"])
    settings = run_mod.run_settings(resolved, skip_judge=False)
    check("run_settings names opus at high and the judge opus at xhigh",
          pick(settings) == CLAUDE_DEFAULTS, settings)
    skipped = run_mod.run_settings(resolved, skip_judge=True)
    check("run_settings records null judge fields under --skip-judge",
          skipped["judge_model"] is None and skipped["judge_effort"] is None)
    cursor = run_mod.run_settings(resolve(["--vendor", "cursor"]), skip_judge=False)
    check("run_settings records Cursor's auto with empty efforts",
          pick(cursor) == {"vendor": "cursor", "worker_model": "auto",
                           "worker_effort": "", "judge_model": "auto",
                           "judge_effort": ""}, cursor)

    summary = run_mod.summarize({SCENARIO: []}, 5, settings)
    check("summarize carries the settings block into summary.json",
          pick(summary) == CLAUDE_DEFAULTS, summary)
    check("render names the worker and judge settings in the report",
          "Settings: vendor claude; worker model opus; worker effort high; "
          "judge opus at effort xhigh" in run_mod.render(summary))

    verdict, judged = stubbed_pass(resolved, skip_judge=False)
    check("run_isolated_pass writes the settings block into verdict.json",
          pick(verdict) == CLAUDE_DEFAULTS, verdict)
    check("the recorded judge settings are the ones the judge ran with",
          judged == [{"judge_vendor": "claude", "judge_model": "opus",
                      "judge_effort": "xhigh"}], judged)
    verdict, judged = stubbed_pass(resolved, skip_judge=True)
    check("verdict.json records null judge fields when no judge ran",
          verdict.get("judge_model") is None and verdict.get("judge_effort") is None
          and not judged, verdict)


def check_regrade() -> None:
    claude_run = {**CLAUDE_DEFAULTS, "denominator": 1, "scenarios": {}}
    regrade_keys = ("vendor", "worker_model", "worker_effort", "judge_vendor",
                    "judge_model", "judge_effort")
    same_judge = {**CLAUDE_DEFAULTS, "judge_vendor": "claude"}

    out = regrade_run(claude_run, ["--vendor", "claude"])
    check("a re-grade on the original judge keeps original_rates",
          out["summary"].get("original_rates") == {SCENARIO: "1/1"}
          and "original_mismatch" not in out["summary"], out["summary"])
    check("a re-grade on the original judge exits by the bar", out["rc"] == 0, out)
    check("summary.regrade.json carries the worker and judge settings",
          pick(out["summary"], regrade_keys) == same_judge, out["summary"])
    check("verdict.regrade.json carries the worker and judge settings",
          pick(out["verdict"], regrade_keys) == same_judge, out["verdict"])
    check("the results copy carries the worker and judge settings",
          pick(out["results"], regrade_keys) == same_judge, out["results"])
    check("the re-grade report keeps the as-run section",
          "## As-run rates before the instrument fix" in out["report"])

    out = regrade_run(claude_run, ["--vendor", "claude", "--judge-effort", "medium"])
    mismatch = out["summary"].get("original_mismatch", "")
    check("another judge effort leaves original_rates out",
          "original_rates" not in out["summary"], out["summary"])
    check("another judge effort records a mismatch naming both efforts",
          "judge_effort 'xhigh'" in mismatch and "judge_effort 'medium'" in mismatch,
          mismatch)
    check("another judge effort exits 1 and warns", out["rc"] == 1
          and "WARNING: original judge mismatch" in out["stderr"], out["stderr"])
    check("another judge effort still writes the re-grade settings",
          out["verdict"].get("judge_effort") == "medium"
          and out["results"].get("judge_effort") == "medium")
    check("the refused report drops the as-run section",
          "## As-run comparison refused" in out["report"]
          and "As-run rates before the instrument fix" not in out["report"])

    out = regrade_run(claude_run, ["--vendor", "claude", "--judge-model", "sonnet"])
    mismatch = out["summary"].get("original_mismatch", "")
    check("another judge model is refused and names both models",
          out["rc"] == 1 and "original_rates" not in out["summary"]
          and "judge_model 'opus'" in mismatch and "judge_model 'sonnet'" in mismatch,
          mismatch)

    cursor_run = {"vendor": "cursor", "worker_model": "auto", "worker_effort": "",
                  "judge_model": "auto", "denominator": 1, "scenarios": {}}
    out = regrade_run(cursor_run, ["--vendor", "claude", "--judge-model", "auto",
                                   "--judge-effort", ""])
    mismatch = out["summary"].get("original_mismatch", "")
    check("another judge vendor is refused and names both vendors",
          out["rc"] == 1 and "judge vendor 'cursor'" in mismatch
          and "judge vendor 'claude'" in mismatch, mismatch)
    out = regrade_run(cursor_run, ["--vendor", "cursor"])
    check("a Cursor run without a judge effort compares against a Cursor re-grade",
          out["rc"] == 0 and out["summary"].get("original_rates") == {SCENARIO: "1/1"},
          out["summary"])

    unrecorded = {"denominator": 1, "scenarios": {}}
    out = regrade_run(unrecorded, ["--vendor", "claude"])
    mismatch = out["summary"].get("original_mismatch", "")
    check("an original without judge fields refuses a re-judged comparison",
          out["rc"] == 1 and "original_rates" not in out["summary"]
          and "judge_model 'unknown'" in mismatch, mismatch)
    out = regrade_run(None, ["--vendor", "claude"])
    check("a run without summary.json refuses a re-judged comparison",
          out["rc"] == 1 and "judge_model 'unknown'"
          in out["summary"].get("original_mismatch", ""), out["summary"])
    out = regrade_run(unrecorded, ["--vendor", "claude", "--skip-judge"])
    check("a --skip-judge re-grade of that original keeps original_rates",
          out["rc"] == 0 and out["summary"].get("original_rates") == {SCENARIO: "1/1"}
          and not out["judged"], out["summary"])
    check("a --skip-judge re-grade carries the unrecorded judge forward as null",
          out["verdict"].get("judge_model") is None
          and out["verdict"].get("judge_vendor") is None, out["verdict"])
    out = regrade_run(claude_run, ["--vendor", "cursor", "--skip-judge"])
    check("a --skip-judge re-grade records the original judge, not --vendor",
          pick(out["summary"], regrade_keys) == same_judge and out["rc"] == 0,
          out["summary"])


def main() -> int:
    print("test_run (language_humanizer)")
    check_run_records()
    check_regrade()
    print(f"\n{PASS} passed, {FAIL} failed")
    return 1 if FAIL else 0


if __name__ == "__main__":
    sys.exit(main())
