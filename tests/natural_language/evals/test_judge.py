#!/usr/bin/env python3
"""Unit tests for the natural_language judge command.

The judge command must carry the vendor-resolved judge model and effort: on
Claude that is `opus` at `xhigh`, `--judge-effort` overrides the level, and
`--judge-effort ''` omits the flag. The harness is Claude-only, so every
case resolves `--vendor claude`. `subprocess.run` is stubbed inside
`judge.py`, so no judge starts and no model is called.

Run:

    python3 tests/natural_language/evals/test_judge.py
"""

from __future__ import annotations

import argparse
import json
import pathlib
import subprocess
import sys

THIS = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(THIS))

import judge as judge_mod  # noqa: E402  (sibling module; adds tests/lib)
import vendor  # noqa: E402  (shared vendor helper in tests/lib)

EVAL_ID = "connected_rewrite"

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
    vendor.add_vendor_arguments(
        parser, with_judge=True, harness_id="natural_language"
    )
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


def main() -> int:
    print("test_judge (natural_language)")

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

    print(f"\n{PASS} passed, {FAIL} failed")
    return 1 if FAIL else 0


if __name__ == "__main__":
    sys.exit(main())
