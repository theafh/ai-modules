#!/usr/bin/env python3
"""Unit tests for vendor.py — no network, no live worker calls.

Run:

    python3 tests/lib/test_vendor.py
"""

from __future__ import annotations

import argparse
import pathlib
import sys
import tempfile

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import vendor  # noqa: E402

PASS = 0
FAIL = 0


def check(label: str, cond: bool) -> None:
    global PASS, FAIL
    if cond:
        PASS += 1
        print(f"  ok   {label}")
    else:
        FAIL += 1
        print(f"  FAIL {label}")


def check_exit(label: str, fn, needle: str) -> None:
    try:
        fn()
    except SystemExit as err:
        check(label, needle in str(err))
        return
    check(label, False)


def make_skill(root: pathlib.Path) -> pathlib.Path:
    skill = root / "skills" / "demo_skill"
    (skill / "scripts").mkdir(parents=True)
    (skill / "SKILL.md").write_text("# demo\nbody\n")
    (skill / "scripts" / "helper.sh").write_text("echo hi\n")
    return skill


def make_agent(root: pathlib.Path) -> pathlib.Path:
    agent = root / "agents" / "auto_demo.md"
    agent.parent.mkdir(parents=True)
    agent.write_text("# auto_demo\n")
    return agent


def main() -> int:
    claude = vendor.config("claude")
    check("claude bin default", claude.bin == "claude")
    check("claude worker model default", claude.worker_model == "sonnet")
    check("claude judge model inherits", claude.judge_model == "")
    check("claude label", claude.label == "claude -p")

    cursor = vendor.config("cursor")
    check("cursor bin default", cursor.bin == "agent")
    check("cursor worker model default", cursor.worker_model == "auto")
    check("cursor judge model default", cursor.judge_model == "auto")
    check("cursor label", cursor.label == "agent -p")
    check("default parallel workers", vendor.DEFAULT_PARALLEL_WORKERS == 4)

    parser = argparse.ArgumentParser(add_help=False)
    vendor.add_vendor_arguments(parser, with_judge=True)
    resolved = vendor.resolve(parser.parse_args([]), with_judge=True)
    check("resolve default vendor", resolved.vendor == "cursor")
    check("resolve default worker model", resolved.worker_model == "auto")
    check("resolve default judge model", resolved.judge_model == "auto")
    check("resolve default worker bin", resolved.bin == "agent")
    claude_args = parser.parse_args(["--vendor", "claude"])
    resolved_claude = vendor.resolve(claude_args, with_judge=True)
    check("resolve explicit claude vendor", resolved_claude.vendor == "claude")
    check("resolve claude worker model", resolved_claude.worker_model == "sonnet")
    check("resolve claude judge model", resolved_claude.judge_model == "")
    check("resolve claude worker bin", resolved_claude.bin == "claude")

    cursor_args = parser.parse_args(
        ["--vendor", "cursor", "--claude-bin", "custom-agent", "--model", ""]
    )
    resolved_cursor = vendor.resolve(cursor_args, with_judge=True)
    check("resolve cursor vendor", resolved_cursor.vendor == "cursor")
    check("resolve deprecated bin alias", resolved_cursor.bin == "custom-agent")
    check("resolve empty worker model inherits", resolved_cursor.worker_model == "")
    check("resolve cursor default judge model", resolved_cursor.judge_model == "auto")

    cmd = vendor.build_print_cmd(
        vendor="claude",
        bin="claude",
        model="",
        prompt="hello",
    )
    check(
        "claude cmd without model",
        cmd == ["claude", "-p", "--permission-mode", "bypassPermissions", "hello"],
    )

    cmd = vendor.build_print_cmd(
        vendor="claude",
        bin="claude",
        model="sonnet",
        prompt="hello",
    )
    check(
        "claude cmd with model",
        cmd == [
            "claude",
            "-p",
            "--permission-mode",
            "bypassPermissions",
            "--model",
            "sonnet",
            "hello",
        ],
    )

    cmd = vendor.build_print_cmd(
        vendor="claude",
        bin="claude",
        model="sonnet",
        prompt="hello",
        extra_args=["--disallowedTools", "Edit"],
        prompt_before_flags=True,
    )
    check(
        "claude prompt-before-flags shape",
        cmd == [
            "claude",
            "-p",
            "hello",
            "--permission-mode",
            "bypassPermissions",
            "--model",
            "sonnet",
            "--disallowedTools",
            "Edit",
        ],
    )

    cmd = vendor.build_print_cmd(
        vendor="cursor",
        bin="agent",
        model="auto",
        workspace="/tmp/workspace",
        prompt="hello",
    )
    check(
        "cursor cmd with workspace",
        cmd == [
            "agent",
            "-p",
            "--force",
            "--sandbox",
            "disabled",
            "--workspace",
            "/tmp/workspace",
            "--model",
            "auto",
            "--output-format",
            "text",
            "hello",
        ],
    )

    check_exit(
        "cursor blocks trigger_evals",
        lambda: vendor.require_vendor_allowed("cursor", "trigger_evals"),
        "does not support `--vendor cursor`",
    )
    vendor.require_vendor_allowed("claude", "trigger_evals")
    check("claude allows trigger_evals", True)
    check_exit(
        "cursor blocks natural_language",
        lambda: vendor.require_vendor_allowed("cursor", "natural_language"),
        "does not support `--vendor cursor`",
    )
    check("an ordinary harness defaults to cursor", vendor.default_vendor("task") == "cursor")
    check("no harness id defaults to cursor", vendor.default_vendor() == "cursor")
    for harness in ("natural_language", "trigger_evals"):
        claude_only = argparse.ArgumentParser(add_help=False)
        vendor.add_vendor_arguments(claude_only, harness_id=harness)
        check(
            f"{harness} defaults to claude without --vendor",
            claude_only.parse_args([]).vendor == "claude",
        )
        check(
            f"{harness} still parses an explicit cursor for the gate to reject",
            claude_only.parse_args(["--vendor", "cursor"]).vendor == "cursor",
        )

    with tempfile.TemporaryDirectory() as td:
        root = pathlib.Path(td)
        skill = make_skill(root)
        agent = make_agent(root)

        staged_cursor = vendor.stage_skill_tree(
            root / "sandbox-cursor",
            skill,
            "cursor",
            agent_files=[agent],
        )
        check(
            "cursor stages skill path",
            staged_cursor == root / "sandbox-cursor" / ".cursor" / "skills"
            / "demo_skill" / "SKILL.md",
        )
        check("cursor staged skill exists", staged_cursor.is_file())
        check(
            "cursor staged script exists",
            (staged_cursor.parent / "scripts" / "helper.sh").is_file(),
        )
        check(
            "cursor staged agent exists",
            (root / "sandbox-cursor" / ".cursor" / "agents" / "auto_demo.md").is_file(),
        )

        staged_claude = vendor.stage_skill_tree(root / "sandbox-claude", skill, "claude")
        check(
            "claude stages skill path",
            staged_claude == root / "sandbox-claude" / ".claude" / "skills"
            / "demo_skill" / "SKILL.md",
        )
        check("claude staged skill exists", staged_claude.is_file())

    print(f"\n{PASS} passed, {FAIL} failed")
    return 1 if FAIL else 0


if __name__ == "__main__":
    sys.exit(main())
