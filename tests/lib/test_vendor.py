#!/usr/bin/env python3
"""Unit tests for vendor.py — no network, no live worker calls.

Run:

    python3 tests/lib/test_vendor.py
"""

from __future__ import annotations

import argparse
import contextlib
import io
import json
import os
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
    check("claude worker model default", claude.worker_model == "opus")
    check("claude worker effort default", claude.worker_effort == "high")
    check("claude judge model default", claude.judge_model == "opus")
    check("claude judge effort default", claude.judge_effort == "xhigh")
    check("claude label", claude.label == "claude -p")

    cursor = vendor.config("cursor")
    check("cursor bin default", cursor.bin == "agent")
    check("cursor worker model default", cursor.worker_model == "auto")
    check("cursor judge model default", cursor.judge_model == "auto")
    check("cursor has no worker effort", cursor.worker_effort == "")
    check("cursor has no judge effort", cursor.judge_effort == "")
    check("cursor label", cursor.label == "agent -p")
    check("default parallel workers", vendor.DEFAULT_PARALLEL_WORKERS == 4)

    parser = argparse.ArgumentParser(add_help=False)
    vendor.add_vendor_arguments(parser, with_judge=True)
    resolved = vendor.resolve(parser.parse_args([]), with_judge=True)
    check("resolve default vendor", resolved.vendor == "cursor")
    check("resolve default worker model", resolved.worker_model == "auto")
    check("resolve default judge model", resolved.judge_model == "auto")
    check("resolve default worker effort is empty", resolved.worker_effort == "")
    check("resolve default judge effort is empty", resolved.judge_effort == "")
    check("resolve default worker bin", resolved.bin == "agent")
    claude_args = parser.parse_args(["--vendor", "claude"])
    resolved_claude = vendor.resolve(claude_args, with_judge=True)
    check("resolve explicit claude vendor", resolved_claude.vendor == "claude")
    check("resolve claude worker model", resolved_claude.worker_model == "opus")
    check("resolve claude worker effort", resolved_claude.worker_effort == "high")
    check("resolve claude judge model", resolved_claude.judge_model == "opus")
    check("resolve claude judge effort", resolved_claude.judge_effort == "xhigh")
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

    # --- sessions -----------------------------------------------------------
    claude_first = vendor.build_print_cmd(
        vendor="claude",
        bin="claude",
        model="sonnet",
        prompt="hello",
        output_format="stream-json",
        session_id="sess-1",
    )
    check(
        "claude first turn carries --session-id",
        "--session-id" in claude_first
        and claude_first[claude_first.index("--session-id") + 1] == "sess-1"
        and "--resume" not in claude_first,
    )
    claude_resumed = vendor.build_print_cmd(
        vendor="claude",
        bin="claude",
        model="sonnet",
        prompt="hello",
        output_format="stream-json",
        resume="sess-1",
    )
    check(
        "claude resumed turn carries --resume with the same id",
        "--resume" in claude_resumed
        and claude_resumed[claude_resumed.index("--resume") + 1] == "sess-1"
        and "--session-id" not in claude_resumed,
    )
    cursor_first = vendor.build_print_cmd(
        vendor="cursor",
        bin="agent",
        model="auto",
        prompt="hello",
        output_format="stream-json",
    )
    check(
        "cursor first turn carries no session flag",
        "--session-id" not in cursor_first and "--resume" not in cursor_first,
    )
    cursor_resumed = vendor.build_print_cmd(
        vendor="cursor",
        bin="agent",
        model="auto",
        prompt="hello",
        output_format="stream-json",
        resume="cursor-sess",
    )
    check(
        "cursor resumed turn carries --resume with the stream id",
        "--resume" in cursor_resumed
        and cursor_resumed[cursor_resumed.index("--resume") + 1] == "cursor-sess"
        and "--session-id" not in cursor_resumed,
    )
    claude_stream = vendor.build_print_cmd(
        vendor="claude",
        bin="claude",
        model="",
        prompt="hello",
        output_format="stream-json",
    )
    check(
        "claude unchanged command when no session is passed",
        claude_stream
        == [
            "claude", "-p", "--permission-mode", "bypassPermissions",
            "--output-format", "stream-json", "--verbose", "hello",
        ],
    )
    cursor_stream = vendor.build_print_cmd(
        vendor="cursor",
        bin="agent",
        model="auto",
        prompt="hello",
        output_format="stream-json",
    )
    check(
        "cursor unchanged command when no session is passed",
        cursor_stream
        == [
            "agent", "-p", "--force", "--sandbox", "disabled",
            "--model", "auto", "--output-format", "stream-json", "hello",
        ],
    )

    # --- stream-mode worker command ----------------------------------------
    claude_stream_cmd = vendor.build_stream_cmd(
        vendor="claude", bin="claude", model="", query="hello",
    )
    check(
        "claude stream argv without model",
        claude_stream_cmd
        == [
            "claude", "-p", "hello", "--output-format", "stream-json",
            "--verbose", "--include-partial-messages",
        ],
    )
    claude_stream_cmd = vendor.build_stream_cmd(
        vendor="claude", bin="claude", model="sonnet", query="hello",
    )
    check(
        "claude stream argv with model",
        claude_stream_cmd
        == [
            "claude", "-p", "hello", "--output-format", "stream-json",
            "--verbose", "--include-partial-messages", "--model", "sonnet",
        ],
    )
    cursor_stream_cmd = vendor.build_stream_cmd(
        vendor="cursor", bin="agent", model="", query="hello",
        workspace="/tmp/w",
    )
    check(
        "cursor stream argv without model",
        cursor_stream_cmd
        == [
            "agent", "-p", "--output-format", "stream-json", "--trust",
            "--workspace", "/tmp/w", "hello",
        ],
    )
    cursor_stream_cmd = vendor.build_stream_cmd(
        vendor="cursor", bin="agent", model="auto", query="hello",
        workspace="/tmp/w",
    )
    check(
        "cursor stream argv with model",
        cursor_stream_cmd
        == [
            "agent", "-p", "--output-format", "stream-json", "--trust",
            "--workspace", "/tmp/w", "--model", "auto", "hello",
        ],
    )
    # --- effort -------------------------------------------------------------
    effort_parser = argparse.ArgumentParser(add_help=False)
    vendor.add_vendor_arguments(effort_parser, with_judge=True)
    no_judge_parser = argparse.ArgumentParser(add_help=False)
    vendor.add_vendor_arguments(no_judge_parser)
    no_judge = vendor.resolve(no_judge_parser.parse_args(["--vendor", "claude"]))
    check("resolve without a judge leaves the judge effort unset",
          no_judge.judge_effort is None and no_judge.worker_effort == "high")
    claude_default = vendor.resolve(
        effort_parser.parse_args(["--vendor", "claude"]), with_judge=True
    )
    claude_print = vendor.build_print_cmd(
        vendor="claude", bin="claude", model=claude_default.worker_model,
        effort=claude_default.worker_effort, prompt="hello",
        output_format="stream-json",
    )
    check(
        "claude print command carries --model opus then --effort high",
        claude_print[claude_print.index("--model"):claude_print.index("--model") + 4]
        == ["--model", "opus", "--effort", "high"],
    )
    claude_stream = vendor.build_stream_cmd(
        vendor="claude", bin="claude", model=claude_default.worker_model,
        effort=claude_default.worker_effort, query="hello",
    )
    check(
        "claude stream command carries --model opus then --effort high",
        claude_stream[-4:] == ["--model", "opus", "--effort", "high"],
    )
    judge_cmd = vendor.build_print_cmd(
        vendor="claude", bin="claude", model=claude_default.judge_model,
        effort=claude_default.judge_effort, prompt="hello",
    )
    check(
        "claude judge command carries --model opus and --effort xhigh",
        judge_cmd[judge_cmd.index("--model") + 1] == "opus"
        and judge_cmd[judge_cmd.index("--effort") + 1] == "xhigh",
    )
    overridden = vendor.resolve(
        effort_parser.parse_args(
            ["--vendor", "claude", "--effort", "medium", "--judge-effort", "low"]
        ),
        with_judge=True,
    )
    check("--effort overrides the claude worker effort",
          overridden.worker_effort == "medium")
    check("--judge-effort overrides the claude judge effort",
          overridden.judge_effort == "low")
    dropped = vendor.resolve(
        effort_parser.parse_args(
            ["--vendor", "claude", "--effort", "", "--judge-effort", ""]
        ),
        with_judge=True,
    )
    check("--effort '' resolves to the empty effort", dropped.worker_effort == "")
    check("--judge-effort '' resolves to the empty effort",
          dropped.judge_effort == "")
    dropped_print = vendor.build_print_cmd(
        vendor="claude", bin="claude", model=dropped.worker_model,
        effort=dropped.worker_effort, prompt="hello",
    )
    dropped_stream = vendor.build_stream_cmd(
        vendor="claude", bin="claude", model=dropped.worker_model,
        effort=dropped.worker_effort, query="hello",
    )
    check("--effort '' drops the flag from the claude print command",
          "--effort" not in dropped_print and "opus" in dropped_print)
    check("--effort '' drops the flag from the claude stream command",
          "--effort" not in dropped_stream and "opus" in dropped_stream)
    check("a print command built without effort carries no --effort",
          "--effort" not in vendor.build_print_cmd(
              vendor="claude", bin="claude", model="opus", prompt="hello"))
    cursor_default = vendor.resolve(
        effort_parser.parse_args(["--vendor", "cursor"]), with_judge=True
    )
    cursor_print = vendor.build_print_cmd(
        vendor="cursor", bin="agent", model=cursor_default.worker_model,
        effort=cursor_default.worker_effort, prompt="hello",
    )
    cursor_stream = vendor.build_stream_cmd(
        vendor="cursor", bin="agent", model=cursor_default.worker_model,
        effort=cursor_default.worker_effort, query="hello", workspace="/tmp/w",
    )
    check("a cursor print command carries no --effort", "--effort" not in cursor_print)
    check("a cursor stream command carries no --effort",
          "--effort" not in cursor_stream)
    check_exit(
        "an explicit --effort on cursor stops naming Claude",
        lambda: vendor.resolve(
            effort_parser.parse_args(["--vendor", "cursor", "--effort", "high"]),
            with_judge=True,
        ),
        "only Claude has an effort control",
    )
    check_exit(
        "an explicit --judge-effort on cursor stops naming Claude",
        lambda: vendor.resolve(
            effort_parser.parse_args(["--vendor", "cursor", "--judge-effort", "max"]),
            with_judge=True,
        ),
        "only Claude has an effort control",
    )
    for label, argv in (
        ("an unlisted --effort level stops the parser with exit status 2",
         ["--vendor", "claude", "--effort", "hgih"]),
        ("an unlisted --judge-effort level stops the parser with exit status 2",
         ["--vendor", "claude", "--judge-effort", "XHIGH"]),
    ):
        try:
            with contextlib.redirect_stderr(io.StringIO()):
                effort_parser.parse_args(argv)
        except SystemExit as err:
            check(label, err.code == 2)
        else:
            check(label, False)
    cursor_empty = vendor.resolve(
        effort_parser.parse_args(["--vendor", "cursor", "--effort", ""]),
        with_judge=True,
    )
    check("--effort '' on cursor resolves without an error",
          cursor_empty.worker_effort == "")
    try:
        vendor.build_print_cmd(
            vendor="cursor", bin="agent", model="auto", effort="high",
            prompt="hello",
        )
        refused = False
    except ValueError as err:
        refused = "only Claude" in str(err)
    check("the cursor builder refuses a non-empty effort", refused)
    # A host CLAUDE_CODE_EFFORT_LEVEL would override --effort in the worker,
    # so the Claude worker env drops it. The token is preset so the env
    # builder skips its keychain lookup.
    saved_env = {
        key: os.environ.get(key)
        for key in ("CLAUDE_CODE_EFFORT_LEVEL", "CLAUDE_CODE_OAUTH_TOKEN")
    }
    try:
        os.environ["CLAUDE_CODE_EFFORT_LEVEL"] = "low"
        os.environ["CLAUDE_CODE_OAUTH_TOKEN"] = "test-token"
        check("the claude worker env drops a host CLAUDE_CODE_EFFORT_LEVEL",
              "CLAUDE_CODE_EFFORT_LEVEL" not in vendor.worker_env("claude"))
    finally:
        for key, value in saved_env.items():
            if value is None:
                os.environ.pop(key, None)
            else:
                os.environ[key] = value

    for name, argv in (
        ("claude", vendor.build_stream_cmd(
            vendor="claude", bin="claude", model="sonnet", query="hello")),
        ("cursor", vendor.build_stream_cmd(
            vendor="cursor", bin="agent", model="auto", query="hello",
            workspace="/tmp/w")),
    ):
        check(
            f"{name} stream argv keeps the default permission mode",
            not any(
                flag in argv
                for flag in ("--permission-mode", "--force", "--yolo")
            ),
        )

    # --- user-level skill roots --------------------------------------------
    old_home = os.environ.get("HOME")
    try:
        with tempfile.TemporaryDirectory() as home:
            os.environ["HOME"] = home
            claude_roots = vendor.skill_roots("claude")
            check(
                "claude skill roots are the native root alone",
                claude_roots == [pathlib.Path(home) / ".claude" / "skills"],
            )
            cursor_roots = vendor.skill_roots("cursor")
            check(
                "cursor skill roots put the native root first",
                cursor_roots[0] == pathlib.Path(home) / ".cursor" / "skills",
            )
            check(
                "cursor skill roots carry the compatibility roots",
                cursor_roots[1:]
                == [
                    pathlib.Path(home) / root / "skills"
                    for root in (".agents", ".claude", ".codex", ".grok")
                ],
            )
    finally:
        if old_home is None:
            os.environ.pop("HOME", None)
        else:
            os.environ["HOME"] = old_home

    # --- withholding --------------------------------------------------------
    for tool_class, names in (
        ("shell", ["Bash"]),
        ("write", ["Edit", "Write", "NotebookEdit"]),
    ):
        plan = vendor.withheld_tool_plan("claude", [tool_class])
        check(
            f"claude withholds {tool_class} by flag",
            list(plan.extra_args) == ["--disallowedTools", *names]
            and plan.withheld_by == {tool_class: "cli-flag"}
            and plan.declared == ()
            and plan.deny_entries == (),
        )
    for tool_class, entry in (("shell", "Shell(*)"), ("write", "Write(**)")):
        plan = vendor.withheld_tool_plan("cursor", [tool_class])
        check(
            f"cursor withholds {tool_class} by config",
            plan.extra_args == ()
            and plan.deny_entries == (entry,)
            and plan.withheld_by == {tool_class: "cli-config"}
            and plan.declared == (),
        )
    for vendor_name in ("claude", "cursor"):
        plan = vendor.withheld_tool_plan(vendor_name, ["spawn"])
        check(
            f"{vendor_name} declares spawn absent",
            plan.extra_args == ()
            and plan.deny_entries == ()
            and plan.declared == ("spawn",)
            and plan.withheld_by == {"spawn": "declared-absence"},
        )
    try:
        vendor.withheld_tool_plan("claude", ["Task"])
        rejected = False
    except ValueError as err:
        rejected = "unknown withheld tool class" in str(err)
    check("a value outside the class set is rejected", rejected)
    with tempfile.TemporaryDirectory() as td:
        workdir = pathlib.Path(td)
        written = vendor.write_cursor_deny_entries(workdir, ["Shell(*)", "Write(**)"])
        data = json.loads(written.read_text())
        check(
            "cursor deny entries land in the project config",
            written == workdir / ".cursor" / "cli.json"
            and data == {
                "permissions": {"allow": [], "deny": ["Shell(*)", "Write(**)"]}
            },
        )
        vendor.write_cursor_deny_entries(workdir, ["Shell(*)"])
        check(
            "cursor deny entries merge without duplicates",
            json.loads(written.read_text())["permissions"]["deny"]
            == ["Shell(*)", "Write(**)"],
        )
    check(
        "tool classes map from both vendor names",
        vendor.classify_tool("claude", "Bash") == "shell"
        and vendor.classify_tool("claude", "Task") == "spawn"
        and vendor.classify_tool("claude", "Edit") == "write"
        and vendor.classify_tool("cursor", "shellToolCall") == "shell"
        and vendor.classify_tool("cursor", "taskToolCall") == "spawn"
        and vendor.classify_tool("cursor", "editToolCall") == "write"
        and vendor.classify_tool("cursor", "readToolCall") == "other",
    )

    # Test Integrity: superseded behaviour. The **Vendor parity** decision
    # recorded in tasks/archive/tests_trigger-evals-cursor-vendor.md removed the
    # Cursor refusal this check used to pin, so it now proves the opposite:
    # Cursor reaches trigger_evals.
    vendor.require_vendor_allowed("cursor", "trigger_evals")
    check("cursor reaches trigger_evals", True)
    vendor.require_vendor_allowed("claude", "trigger_evals")
    check("claude reaches trigger_evals", True)
    check_exit(
        "cursor still blocks deployment_styles",
        lambda: vendor.require_vendor_allowed("cursor", "deployment_styles"),
        "does not support `--vendor cursor`",
    )
    check_exit(
        "cursor blocks natural_language",
        lambda: vendor.require_vendor_allowed("cursor", "natural_language"),
        "does not support `--vendor cursor`",
    )
    check("an ordinary harness defaults to cursor", vendor.default_vendor("task") == "cursor")
    check("no harness id defaults to cursor", vendor.default_vendor() == "cursor")
    natural_language = argparse.ArgumentParser(add_help=False)
    vendor.add_vendor_arguments(natural_language, harness_id="natural_language")
    check(
        "natural_language defaults to claude without --vendor",
        natural_language.parse_args([]).vendor == "claude",
    )
    check(
        "natural_language still parses an explicit cursor for the gate to reject",
        natural_language.parse_args(["--vendor", "cursor"]).vendor == "cursor",
    )
    # Test Integrity: superseded behaviour. The same **Vendor parity** decision
    # moved trigger_evals off the Claude-only default, so the trigger parser
    # now defaults to cursor without --vendor.
    trigger_parser = argparse.ArgumentParser(add_help=False)
    vendor.add_vendor_arguments(trigger_parser, harness_id="trigger_evals")
    check(
        "trigger_evals defaults to cursor without --vendor",
        trigger_parser.parse_args([]).vendor == "cursor",
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

        prefixed = root / "agents" / "auto_prefixed.md"
        prefixed.write_text(
            "---\n"
            "name: auto_prefixed\n"
            "description: base\n"
            "CLAUDE_model: sonnet\n"
            "CURSOR_model: auto\n"
            "CODEX_model: gpt\n"
            "CODEX_tools:\n"
            "  - Read\n"
            "  - Grep\n"
            "---\n"
            "body line\n"
        )
        expected = {
            "claude": (
                "---\nname: auto_prefixed\ndescription: base\n"
                "model: sonnet\n---\nbody line\n"
            ),
            "cursor": (
                "---\nname: auto_prefixed\ndescription: base\n"
                "model: auto\n---\nbody line\n"
            ),
        }
        for vendor_name in ("claude", "cursor"):
            direct = vendor.stage_agents(
                root / f"direct-{vendor_name}", vendor_name, [prefixed]
            )
            check(
                f"{vendor_name} stage_agents renders the worker's own key",
                len(direct) == 1
                and direct[0].read_text() == expected[vendor_name],
            )
            check(
                f"{vendor_name} stage_agents drops a prefixed multi-line block",
                len(direct) == 1
                and "CODEX_tools" not in direct[0].read_text()
                and "- Read" not in direct[0].read_text()
                and "- Grep" not in direct[0].read_text(),
            )
            via_skill = vendor.stage_skill_tree(
                root / f"tree-{vendor_name}", skill, vendor_name,
                agent_files=[prefixed],
            )
            staged_agent = (
                root / f"tree-{vendor_name}" / f".{vendor_name}" / "agents"
                / "auto_prefixed.md"
            )
            check(
                f"{vendor_name} stage_skill_tree renders the worker's own key",
                via_skill.is_file()
                and staged_agent.read_text() == expected[vendor_name],
            )

    print(f"\n{PASS} passed, {FAIL} failed")
    return 1 if FAIL else 0


if __name__ == "__main__":
    sys.exit(main())
