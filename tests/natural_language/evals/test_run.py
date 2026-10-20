#!/usr/bin/env python3
"""Unit tests for the natural_language runner's preflight route decision and
its stop on a failed or empty stage."""

from __future__ import annotations

import pathlib
import subprocess
import sys

import run as runner

THIS = pathlib.Path(__file__).resolve().parent

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


def main() -> int:
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
