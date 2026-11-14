#!/usr/bin/env python3
"""Unit tests for the natural_language runner's preflight route decision, its
stop on a failed or empty stage, and the settings block its records carry.

The settings cases stub the stage, the micro-deployment, the worker, the
grader, and the judge, so no worker starts and no model is called.
"""

from __future__ import annotations

import argparse
import contextlib
import json
import pathlib
import shutil
import subprocess
import sys
import tempfile

import run as runner

THIS = pathlib.Path(__file__).resolve().parent
vendor = runner.vendor
SETTINGS_KEYS = ("vendor", "worker_model", "worker_effort", "judge_model", "judge_effort")
CLAUDE_DEFAULTS = {
    "vendor": "claude",
    "worker_model": "opus",
    "worker_effort": "high",
    "judge_model": "opus",
    "judge_effort": "xhigh",
}

PASS = 0
FAIL = 0


def check(label: str, condition: bool) -> None:
    global PASS, FAIL
    if condition:
        PASS += 1
        print(f"  ok   {label}")
    else:
        FAIL += 1
        print(f"  FAIL {label}")


def expect_abort(label: str, version: str) -> None:
    try:
        runner.select_style_route({"marker_present": False}, version)
    except SystemExit as error:
        message = str(error)
        check(
            label,
            "not newer than 2.1.226" in message
            and "No scenario pass started" in message,
        )
        return
    check(label, False)


def resolve(argv: list[str]) -> "vendor.Resolved":
    parser = argparse.ArgumentParser(add_help=False)
    vendor.add_vendor_arguments(parser, with_judge=True, harness_id="natural_language")
    return vendor.resolve(parser.parse_args(argv), with_judge=True)


def pick(record: dict) -> dict:
    return {key: record.get(key, "<absent>") for key in SETTINGS_KEYS}


def stubbed_pass(resolved, skip_judge: bool) -> tuple[dict, dict]:
    """Run run_pass with every external step stubbed and return its verdict.

    Returns the verdict.json the pass wrote and the judge call's settings
    (empty when no judge ran).
    """

    workspace = pathlib.Path(tempfile.mkdtemp(prefix="nl_test_run_"))
    judged: dict = {}

    def fake_stage(_scenario, target):
        proj = pathlib.Path(target) / "proj"
        proj.mkdir(parents=True, exist_ok=True)
        (proj / "question.md").write_text("Question?\n")
        (pathlib.Path(target) / ".fixture_pristine").write_text("Question?\n")
        return {"sandbox_proj": str(proj), "source_file": str(proj / "question.md"),
                "prompt": "Answer."}

    @contextlib.contextmanager
    def fake_micro_deploy(*_args, **_kwargs):
        yield object()

    def fake_run_worker(*_args, **_kwargs):
        return 0, "A short answer.\n", "", 1.0, {"passed": True}, {"passed": True}

    real_subprocess_run = subprocess.run

    def fake_subprocess_run(cmd, *args, **kwargs):
        if len(cmd) > 1 and str(cmd[1]) == str(runner.GRADE):
            reply = {"passed": True, "mechanical": {"chat_short": {"passed": True}},
                     "integrity": {}, "delivered_words": 3, "fixture_words": 1}
            return subprocess.CompletedProcess(cmd, 0, stdout=json.dumps(reply), stderr="")
        return real_subprocess_run(cmd, *args, **kwargs)

    def fake_judge(*args, effort="", **_kwargs):
        judged.update({"judge_model": args[6], "judge_effort": effort})
        return {"relation_kept": {"passed": True, "why": "stub"}}

    saved = (runner.stage, runner.micro_deploy.micro_deploy, runner.run_worker,
             runner.judge_mod.judge)
    runner.stage = fake_stage
    runner.micro_deploy.micro_deploy = fake_micro_deploy
    runner.run_worker = fake_run_worker
    runner.judge_mod.judge = fake_judge
    runner.subprocess.run = fake_subprocess_run
    try:
        args = argparse.Namespace(skip_judge=skip_judge, timeout=5, judge_timeout=5)
        runner.run_pass("chat_brevity", 1, workspace, args, resolved,
                        runner.DEFAULT_STYLE, False)
        verdict = json.loads(
            (workspace / "chat_brevity" / "pass-1" / "verdict.json").read_text()
        )
    finally:
        (runner.stage, runner.micro_deploy.micro_deploy, runner.run_worker,
         runner.judge_mod.judge) = saved
        runner.subprocess.run = real_subprocess_run
        shutil.rmtree(workspace, ignore_errors=True)
    return verdict, judged


def check_settings() -> None:
    resolved = resolve(["--vendor", "claude"])
    settings = runner.run_settings(resolved, skip_judge=False)
    check("run_settings names opus at high and the judge opus at xhigh",
          pick(settings) == CLAUDE_DEFAULTS)
    skipped = runner.run_settings(resolved, skip_judge=True)
    check("run_settings records null judge fields under --skip-judge",
          skipped["judge_model"] is None and skipped["judge_effort"] is None
          and skipped["worker_effort"] == "high")
    inherit = runner.run_settings(resolve(["--vendor", "claude", "--effort", ""]), False)
    check("run_settings records an omitted worker effort as the empty string",
          inherit["worker_effort"] == "")

    summary = runner.summarize({"chat_brevity": []}, 5, settings)
    check("summarize carries the settings block into summary.json",
          pick(summary) == CLAUDE_DEFAULTS)
    report = runner.render(summary)
    check("render names the worker and judge settings in the report",
          "Settings: vendor claude; worker model opus; worker effort high; "
          "judge opus at effort xhigh" in report)
    check("render names a skipped judge as off",
          "judge off" in runner.render(runner.summarize({}, 5, skipped)))
    header = runner.header_line(settings, resolved.config.label)
    check("the console header names vendor, worker, judge, and command",
          header == "Settings: vendor claude; worker model opus; worker effort "
                    "high; judge opus at effort xhigh; command: claude -p")

    verdict, judged = stubbed_pass(resolved, skip_judge=False)
    check("run_pass writes the settings block into verdict.json",
          pick(verdict) == CLAUDE_DEFAULTS)
    check("the recorded judge settings are the ones the judge ran with",
          judged == {"judge_model": "opus", "judge_effort": "xhigh"})
    tuned = resolve(["--vendor", "claude", "--judge-effort", "medium"])
    verdict, _ = stubbed_pass(tuned, skip_judge=False)
    check("verdict.json records an overridden judge effort",
          verdict.get("judge_effort") == "medium")
    verdict, judged = stubbed_pass(resolved, skip_judge=True)
    check("verdict.json records null judge fields when no judge ran",
          verdict.get("judge_model") is None and verdict.get("judge_effort") is None
          and not judged)


def main() -> int:
    check_settings()
    check(
        "present marker keeps outputStyle selection",
        runner.select_style_route(
            {"marker_present": True},
            "2.1.226 (Claude Code)",
        )
        == (False, "outputStyle"),
    )
    expect_abort(
        "missing marker aborts on the probed CLI version",
        "2.1.226 (Claude Code)",
    )
    check(
        "missing marker uses append fallback on a newer CLI",
        runner.select_style_route(
            {"marker_present": False},
            "2.1.227 (Claude Code)",
        )
        == (True, "append-system-prompt-file"),
    )

    # stage() raises on a stage.sh that fails, and on one that exits 0 without
    # naming a sandbox project, before any worker could start.
    guard = subprocess.run(
        [sys.executable, str(THIS.parents[1] / "lib" / "check_stage_guard.py"), str(THIS)],
        capture_output=True,
        text=True,
    )
    if guard.returncode != 0:
        print(guard.stdout + guard.stderr)
    check("stage() raises on a failed or empty stage", guard.returncode == 0)

    print(f"\n{PASS} passed, {FAIL} failed")
    return 1 if FAIL else 0


if __name__ == "__main__":
    sys.exit(main())
