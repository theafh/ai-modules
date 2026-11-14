#!/usr/bin/env python3
"""Unit tests for the language_humanizer judge command.

The judge command must carry the vendor-resolved judge model and effort: on
Claude that is `opus` at `xhigh`, `--judge-effort` overrides the level, and
`--judge-effort ''` omits the flag. The standalone `judge.main()` resolves
those judge settings from its own flags too, and it refuses the worker flags
`--model` and `--effort` with exit status 2 before any judge call, as
`regrade.main()` does before it reads a run directory.
`subprocess.run` is stubbed inside `judge.py`, so no judge starts and no
model is called.

Run:

    python3 tests/language_humanizer/evals/test_judge.py
"""

from __future__ import annotations

import argparse
import contextlib
import io
import json
import os
import pathlib
import subprocess
import sys

THIS = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(THIS))

import judge as judge_mod  # noqa: E402  (sibling module; adds tests/lib)
import regrade as regrade_mod  # noqa: E402  (sibling module; starts no worker on import)
import vendor  # noqa: E402  (shared vendor helper in tests/lib)

EVAL_ID = "fidelity_padded"

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


def flag_value(cmd: list[str], flag: str) -> str | None:
    """Return the value after `flag` in `cmd`, or None when it is absent."""

    if flag not in cmd:
        return None
    index = cmd.index(flag)
    return cmd[index + 1] if index + 1 < len(cmd) else None


def judge_command(argv: list[str]) -> tuple[list[str], dict]:
    """Resolve `argv` the way the runner does and return the judge command.

    The stub answers the judge call with a passing verdict for every rubric
    line, and answers any other call (the keychain lookup inside
    `vendor.worker_env`) with nothing, so only the judge command is recorded.
    """

    parser = argparse.ArgumentParser(add_help=False)
    vendor.add_vendor_arguments(parser, with_judge=True)
    resolved = vendor.resolve(parser.parse_args(argv), with_judge=True)
    seen: dict[str, list[str]] = {}
    reply = json.dumps(
        {key: {"passed": True, "why": "stub"} for key in judge_mod.RUBRICS[EVAL_ID]}
    )

    def fake_run(cmd, **_kwargs):
        if cmd and cmd[0] == resolved.bin:
            seen["cmd"] = list(cmd)
            return subprocess.CompletedProcess(cmd, 0, stdout=reply, stderr="")
        return subprocess.CompletedProcess(cmd, 1, stdout="", stderr="")

    real_run = judge_mod.subprocess.run
    judge_mod.subprocess.run = fake_run
    try:
        verdicts = judge_mod.judge(
            EVAL_ID, "fixture", "delivered", "response",
            resolved.vendor, resolved.bin, resolved.judge_model or "", 5,
            effort=resolved.judge_effort or "",
        )
    finally:
        judge_mod.subprocess.run = real_run
    return seen.get("cmd", []), verdicts


def main_command(argv: list[str]) -> tuple[list[str], int | str | None]:
    """Run the standalone `judge.main()` on `argv` and return its judge command.

    `main()` resolves the vendor flags itself, so this covers the entry point
    an operator runs rather than a judge call the test assembles. The three
    input files are `os.devnull`, the stub records the call whose binary is
    Claude's and answers it with a passing verdict for every rubric line, and
    the verdicts `main()` prints are discarded. When `main()` stops through
    `SystemExit`, as its parser does on a refused flag, this returns the exit
    status in place of its return value, together with any command recorded
    before the stop, and discards the parser's message too.
    """

    seen: dict[str, list[str]] = {}
    reply = json.dumps(
        {key: {"passed": True, "why": "stub"} for key in judge_mod.RUBRICS[EVAL_ID]}
    )
    claude_bin = vendor.config("claude").bin

    def fake_run(cmd, **_kwargs):
        if cmd and cmd[0] == claude_bin:
            seen["cmd"] = list(cmd)
            return subprocess.CompletedProcess(cmd, 0, stdout=reply, stderr="")
        return subprocess.CompletedProcess(cmd, 1, stdout="", stderr="")

    real_run, real_argv = judge_mod.subprocess.run, sys.argv
    judge_mod.subprocess.run = fake_run
    sys.argv = ["judge.py", EVAL_ID, os.devnull, os.devnull, os.devnull, *argv]
    sink = io.StringIO()
    try:
        with contextlib.redirect_stdout(sink), contextlib.redirect_stderr(sink):
            rc = judge_mod.main()
    except SystemExit as err:
        rc = err.code
    finally:
        judge_mod.subprocess.run = real_run
        sys.argv = real_argv
    return seen.get("cmd", []), rc


def regrade_exit(argv: list[str]) -> int | str | None:
    """Run `regrade.main()` on a missing run directory and return its exit.

    The parser refuses a worker flag with exit status 2 before the run
    directory is read. An accepted flag set reaches the run-directory check,
    which stops with its "not a run directory" message instead, so that
    message shows the refusal did not fire. The parser's output is discarded.
    """

    real_argv = sys.argv
    sys.argv = ["regrade.py", os.path.join(os.devnull, "no-run"), *argv]
    sink = io.StringIO()
    try:
        with contextlib.redirect_stdout(sink), contextlib.redirect_stderr(sink):
            return regrade_mod.main()
    except SystemExit as err:
        return err.code
    finally:
        sys.argv = real_argv


def main() -> int:
    print("test_judge (language_humanizer)")

    cmd, verdicts = judge_command(["--vendor", "claude"])
    check("the stubbed Claude judge call is recorded", bool(cmd), cmd)
    check("the stubbed judge reply grades every rubric line",
          all(item["passed"] for item in verdicts.values()), verdicts)
    check("the Claude judge command carries --model opus",
          flag_value(cmd, "--model") == "opus", cmd)
    check("the Claude judge command carries --effort xhigh",
          flag_value(cmd, "--effort") == "xhigh", cmd)

    cmd, _ = judge_command(["--vendor", "claude", "--judge-effort", "medium"])
    check("--judge-effort medium reaches the judge command",
          flag_value(cmd, "--effort") == "medium", cmd)
    check("--judge-effort leaves the judge model at opus",
          flag_value(cmd, "--model") == "opus", cmd)

    cmd, _ = judge_command(["--vendor", "claude", "--judge-effort", ""])
    check("--judge-effort '' leaves no --effort in the judge command",
          bool(cmd) and "--effort" not in cmd, cmd)

    cmd, _ = judge_command(["--vendor", "cursor"])
    check("the Cursor judge command carries --model auto",
          flag_value(cmd, "--model") == "auto", cmd)
    check("the Cursor judge command carries no --effort",
          bool(cmd) and "--effort" not in cmd, cmd)

    cmd, rc = main_command(["--vendor", "claude"])
    check("judge.main() on --vendor claude runs the stubbed judge call",
          bool(cmd) and rc == 0, cmd)
    check("judge.main() on --vendor claude carries --model opus",
          flag_value(cmd, "--model") == "opus", cmd)
    check("judge.main() on --vendor claude carries --effort xhigh",
          flag_value(cmd, "--effort") == "xhigh", cmd)

    cmd, _ = main_command(["--vendor", "claude", "--judge-model", "sonnet"])
    check("judge.main() on --judge-model sonnet carries --model sonnet",
          flag_value(cmd, "--model") == "sonnet", cmd)

    cmd, rc = main_command(["--vendor", "claude", "--model", "sonnet"])
    check("judge.main() on --model sonnet exits 2 before any judge call",
          rc == 2 and not cmd, (rc, cmd))

    cmd, rc = main_command(["--vendor", "claude", "--effort", "low"])
    check("judge.main() on --effort low exits 2 before any judge call",
          rc == 2 and not cmd, (rc, cmd))

    rc = regrade_exit(["--vendor", "claude", "--model", "sonnet"])
    check("regrade.main() on --model sonnet exits 2", rc == 2, rc)
    rc = regrade_exit(["--vendor", "claude", "--effort", "low"])
    check("regrade.main() on --effort low exits 2", rc == 2, rc)
    rc = regrade_exit(["--vendor", "claude", "--judge-model", "sonnet",
                       "--judge-effort", "low"])
    check("regrade.main() takes --judge-model and --judge-effort",
          isinstance(rc, str) and "not a run directory" in rc, rc)

    print(f"\n{PASS} passed, {FAIL} failed")
    return 1 if FAIL else 0


if __name__ == "__main__":
    sys.exit(main())
