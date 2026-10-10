"""Unit tests for micro_deploy.py — real deploy script, no model calls.

Run:

    python3 tests/lib/test_micro_deploy.py
"""

from __future__ import annotations

import json
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import micro_deploy  # noqa: E402
import vendor  # noqa: E402
import worker_isolation  # noqa: E402

PASS = 0
FAIL = 0
REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]
DEPLOY_LOG = REPO_ROOT / "deployment" / "deployed_artefacts.log"
REAL_HOME = pathlib.Path.home()


def check(label: str, cond: bool) -> None:
    global PASS, FAIL
    if cond:
        PASS += 1
        print(f"  ok   {label}")
    else:
        FAIL += 1
        print(f"  FAIL {label}")


def fake_result(returncode: int, stdout: str, stderr: str = ""):
    class Result:
        pass

    result = Result()
    result.returncode = returncode
    result.stdout = stdout
    result.stderr = stderr
    return result


def output_formats(cmd: list[str]) -> list[str]:
    return [
        cmd[i + 1]
        for i, part in enumerate(cmd)
        if part == "--output-format" and i + 1 < len(cmd)
    ]


def test_layouts_and_path_map() -> None:
    log_before = DEPLOY_LOG.read_bytes() if DEPLOY_LOG.is_file() else None
    with tempfile.TemporaryDirectory() as td:
        root = pathlib.Path(td)
        sandbox = root / "proj"
        sandbox.mkdir()
        names = ["language_humanizer", "format_markdown"]
        for vendor_name in ("cursor", "claude"):
            handle = micro_deploy.micro_deploy(
                vendor_name, names, sandbox, preflight=False
            )
            try:
                for name in names:
                    check(
                        f"{vendor_name} path map covers {name}",
                        name in handle.path_map
                        and handle.path_map[name].is_file(),
                    )
                skill_home = (
                    handle.scratch_home / ".cursor" / "skills"
                    if vendor_name == "cursor"
                    else handle.scratch_home / ".claude" / "skills"
                )
                check(
                    f"{vendor_name} skills in scratch home",
                    (skill_home / "language_humanizer" / "SKILL.md").is_file()
                    and (skill_home / "format_markdown" / "SKILL.md").is_file(),
                )
                check(
                    f"{vendor_name} workspace is sandbox project",
                    handle.workspace == sandbox.resolve(),
                )
            finally:
                handle.close()
                check(
                    f"{vendor_name} scratch removed on close",
                    not handle.scratch_home.exists(),
                )

        # Cursor loads agents and style rules only at project scope.
        cursor_sandbox = root / "cursor_proj"
        cursor_sandbox.mkdir()
        cursor_handle = micro_deploy.micro_deploy(
            "cursor",
            ["language_humanizer", "auto_shaper_wiki", "natural-language"],
            cursor_sandbox,
            preflight=False,
        )
        try:
            agent_path = cursor_sandbox / ".cursor" / "agents" / "auto_shaper_wiki.md"
            rule_path = cursor_sandbox / ".cursor" / "rules" / "natural-language.mdc"
            check("cursor agents under sandbox project", agent_path.is_file())
            check(
                "cursor agent path map",
                cursor_handle.path_map["auto_shaper_wiki"] == agent_path.resolve(),
            )
            check("cursor style rule under sandbox project", rule_path.is_file())
            check(
                "cursor style rule path map",
                cursor_handle.path_map["natural-language"] == rule_path.resolve(),
            )
            check(
                "cursor scratch home holds no agent or style",
                not (cursor_handle.scratch_home / ".cursor" / "agents").exists()
                and not (cursor_handle.scratch_home / ".cursor" / "rules").exists(),
            )
        finally:
            cursor_handle.close()

        # Claude loads agents from its config directory and, under
        # isolation_args, the style and outputStyle from the project.
        claude_sandbox = root / "claude_proj"
        claude_sandbox.mkdir()
        claude_handle = micro_deploy.micro_deploy(
            "claude",
            ["auto_shaper_wiki", "natural-language"],
            claude_sandbox,
            preflight=False,
        )
        try:
            agent_path = (
                claude_handle.scratch_home / ".claude" / "agents" / "auto_shaper_wiki.md"
            )
            style_path = (
                claude_sandbox / ".claude" / "output-styles" / "natural-language.md"
            )
            settings = claude_sandbox / ".claude" / "settings.json"
            check("claude agent in scratch config", agent_path.is_file())
            check(
                "claude agent path map",
                claude_handle.path_map["auto_shaper_wiki"] == agent_path,
            )
            check("claude style under sandbox project", style_path.is_file())
            check(
                "claude style path map",
                claude_handle.path_map["natural-language"] == style_path.resolve(),
            )
            check(
                "claude outputStyle in project settings",
                settings.is_file()
                and json.loads(settings.read_text()).get("outputStyle")
                == "natural-language",
            )
        finally:
            claude_handle.close()

    log_after = DEPLOY_LOG.read_bytes() if DEPLOY_LOG.is_file() else None
    check(
        "repo deploy log byte-identical after micro-deploy",
        log_before == log_after,
    )


def test_only_limits_and_log_override() -> None:
    log_before = DEPLOY_LOG.read_bytes() if DEPLOY_LOG.is_file() else None
    with tempfile.TemporaryDirectory() as td:
        home = pathlib.Path(td) / "home"
        home.mkdir()
        log_path = pathlib.Path(td) / "scratch.log"
        env = os.environ.copy()
        env["HOME"] = str(home)
        env["DEPLOYED_ARTIFACTS_LOG"] = str(log_path)
        # No --type, so --only alone has to narrow every artefact type.
        result = subprocess.run(
            [
                "/bin/bash",
                str(REPO_ROOT / "deployment" / "deployment.sh"),
                "--global",
                "--target",
                "claude",
                "--only",
                "language_humanizer,format_markdown",
            ],
            cwd=str(REPO_ROOT),
            env=env,
            capture_output=True,
            text=True,
        )
        check("deploy --only exits 0", result.returncode == 0)
        listing = sorted(
            str(path.relative_to(home))
            for path in home.rglob("*")
            if len(path.relative_to(home).parts) <= 3
        )
        check(
            "--only deployed exactly the named artefacts",
            listing
            == [
                ".claude",
                ".claude/skills",
                ".claude/skills/format_markdown",
                ".claude/skills/language_humanizer",
            ],
        )
        check("override log written", log_path.is_file() and log_path.stat().st_size > 0)
    log_after = DEPLOY_LOG.read_bytes() if DEPLOY_LOG.is_file() else None
    check("DEPLOYED_ARTIFACTS_LOG override leaves repo log identical", log_before == log_after)


def test_overlay_fixture_edits() -> None:
    """A fixture's edited skill copy lands on the deployed copy, nothing more.

    The edit mirrors git_commit's drift fixtures: the real prepare script
    moves aside and a wrapper takes its name.
    """

    source = micro_deploy.discover_artefact_index()["git_commit"][1]
    with tempfile.TemporaryDirectory() as td:
        root = pathlib.Path(td)
        sandbox = root / "proj"
        sandbox.mkdir()
        fixture = root / "skill_under_test"
        shutil.copytree(source, fixture)
        scripts = fixture / "scripts"
        (scripts / "prepare_commit_context.sh").rename(
            scripts / "prepare_commit_context.sh.real"
        )
        wrapper = scripts / "prepare_commit_context.sh"
        wrapper.write_text("#!/usr/bin/env bash\nexit 1\n")
        wrapper.chmod(0o755)
        (scripts / "__pycache__").mkdir()
        (scripts / "__pycache__" / "stray.cpython-312.pyc").write_bytes(b"\0")

        for vendor_name in ("cursor", "claude"):
            with micro_deploy.micro_deploy(
                vendor_name, ["git_commit"], sandbox, preflight=False
            ) as md:
                deployed = md.path_map["git_commit"].parent
                skill_md = (deployed / "SKILL.md").read_bytes()
                overlaid = micro_deploy.overlay_fixture_edits(md, "git_commit", fixture)
                check(
                    f"{vendor_name} overlay names only the fixture's edits",
                    overlaid
                    == [
                        "scripts/prepare_commit_context.sh",
                        "scripts/prepare_commit_context.sh.real",
                    ],
                )
                deployed_script = deployed / "scripts" / "prepare_commit_context.sh"
                check(
                    f"{vendor_name} overlay replaces the deployed script",
                    deployed_script.read_bytes() == wrapper.read_bytes(),
                )
                check(
                    f"{vendor_name} overlaid script stays executable",
                    os.access(deployed_script, os.X_OK),
                )
                check(
                    f"{vendor_name} overlay adds the fixture's new file",
                    (deployed / "scripts" / "prepare_commit_context.sh.real").read_bytes()
                    == (source / "scripts" / "prepare_commit_context.sh").read_bytes(),
                )
                check(
                    f"{vendor_name} unedited files stay as deployed",
                    (deployed / "SKILL.md").read_bytes() == skill_md,
                )
                check(
                    f"{vendor_name} overlay leaves bytecode out",
                    not (deployed / "scripts" / "__pycache__").exists(),
                )
                check(
                    f"{vendor_name} the checkout source overlays nothing",
                    micro_deploy.overlay_fixture_edits(md, "git_commit", source) == [],
                )

        with micro_deploy.micro_deploy(
            "claude", ["auto_shaper_wiki"], sandbox, preflight=False
        ) as md:
            try:
                micro_deploy.overlay_fixture_edits(md, "auto_shaper_wiki", fixture)
                refused = False
            except ValueError:
                refused = True
            check("overlay refuses an artefact that is not a skill", refused)
        with micro_deploy.micro_deploy(
            "cursor", ["language_humanizer"], sandbox, preflight=False
        ) as md:
            try:
                micro_deploy.overlay_fixture_edits(md, "git_commit", fixture)
                refused = False
            except ValueError:
                refused = True
            check("overlay refuses a skill the micro-deployment did not declare", refused)


def test_login_profiles_restore_worker_path() -> None:
    """A login shell under Cursor's scratch home keeps the worker's PATH.

    Cursor runs shell commands from a login-shell snapshot taken under the
    worker's HOME, so the scratch home's profiles decide which `bash` a
    bundled script gets.
    """

    profiles = (".zprofile", ".bash_profile", ".profile")
    with tempfile.TemporaryDirectory() as td:
        root = pathlib.Path(td)
        sandbox = root / "proj"
        sandbox.mkdir()
        with micro_deploy.micro_deploy("claude", [], sandbox, preflight=False) as md:
            check(
                "claude scratch home carries no login profile",
                not any((md.scratch_home / name).exists() for name in profiles),
            )
        with micro_deploy.micro_deploy("cursor", [], sandbox, preflight=False) as md:
            for name in profiles:
                check(
                    f"cursor scratch home carries {name}",
                    (md.scratch_home / name).is_file(),
                )
            # A directory no system profile names, put first, has to survive.
            operator_bin = root / "operator-bin"
            operator_bin.mkdir()
            launch_path = f"{operator_bin}{os.pathsep}{os.environ.get('PATH', '')}"
            for shell in ("zsh", "bash"):
                binary = shutil.which(shell)
                if binary is None:
                    continue
                env = dict(md.env)
                env["PATH"] = launch_path
                env[micro_deploy.WORKER_PATH_VAR] = launch_path
                restored = subprocess.run(
                    [binary, "-l", "-c", 'printf "%s" "$PATH"'],
                    env=env, capture_output=True, text=True, timeout=30,
                )
                check(
                    f"cursor login {shell} restores the launch PATH",
                    restored.stdout == launch_path,
                )
                env.pop(micro_deploy.WORKER_PATH_VAR)
                plain = subprocess.run(
                    [binary, "-l", "-c", "echo ok"],
                    env=env, capture_output=True, text=True, timeout=30,
                )
                check(
                    f"cursor login {shell} runs without the variable",
                    plain.returncode == 0 and plain.stdout.strip() == "ok",
                )


def test_run_worker_passes_launch_path() -> None:
    real_run = subprocess.run
    seen: list[dict[str, str]] = []

    def fake_run(cmd, **kwargs):
        seen.append(dict(kwargs.get("env") or {}))
        return fake_result(0, json.dumps({"type": "result", "result": "ok"}))

    with tempfile.TemporaryDirectory() as td:
        sandbox = pathlib.Path(td) / "proj"
        sandbox.mkdir()
        for vendor_name, bin_name in (("cursor", "agent"), ("claude", "claude")):
            with micro_deploy.micro_deploy(
                vendor_name, [], sandbox, preflight=False
            ) as md:
                # A runner may change PATH after micro_deploy, as git_review
                # does to put its stub gh first.
                md.env["PATH"] = f"/stub/bin{os.pathsep}{md.env.get('PATH', '')}"
                subprocess.run = fake_run  # type: ignore[assignment]
                try:
                    micro_deploy.run_worker(
                        vendor_name=vendor_name, bin_name=bin_name, model="",
                        prompt="hi", deploy=md, timeout=5,
                    )
                finally:
                    subprocess.run = real_run  # type: ignore[assignment]
                env = seen[-1]
                if vendor_name == "cursor":
                    check(
                        "cursor worker carries its launch PATH for the profiles",
                        env.get(micro_deploy.WORKER_PATH_VAR) == md.env["PATH"],
                    )
                else:
                    check(
                        "claude worker carries no launch PATH variable",
                        micro_deploy.WORKER_PATH_VAR not in env,
                    )


def test_worker_env_overlays() -> None:
    with tempfile.TemporaryDirectory() as td:
        sandbox = pathlib.Path(td) / "proj"
        sandbox.mkdir()
        for vendor_name in ("cursor", "claude"):
            base = vendor.worker_env(vendor_name)
            handle = micro_deploy.micro_deploy(
                vendor_name, ["language_humanizer"], sandbox, preflight=False
            )
            try:
                overlay_keys = {
                    "HOME",
                    "CLAUDE_CONFIG_DIR",
                    "CLAUDE_SECURESTORAGE_CONFIG_DIR",
                }
                preserved = [
                    key
                    for key, value in base.items()
                    if key not in overlay_keys and handle.env.get(key) == value
                ]
                check(
                    f"{vendor_name} env preserves worker_env keys",
                    len(preserved) == len(base) - len(overlay_keys & set(base)),
                )
                if vendor_name == "cursor":
                    check(
                        "cursor HOME overlay",
                        handle.env.get("HOME") == str(handle.scratch_home),
                    )
                    library = handle.scratch_home / "Library"
                    check(
                        "cursor Library linked when present",
                        (not (REAL_HOME / "Library").exists())
                        or library.is_symlink(),
                    )
                else:
                    check(
                        "claude CLAUDE_CONFIG_DIR overlay",
                        handle.env.get("CLAUDE_CONFIG_DIR")
                        == str(handle.scratch_home / ".claude"),
                    )
                    check(
                        "claude CLAUDE_SECURESTORAGE_CONFIG_DIR empty",
                        handle.env.get("CLAUDE_SECURESTORAGE_CONFIG_DIR") == "",
                    )
            finally:
                handle.close()


def test_stream_parser_and_provenance() -> None:
    def claude_read(path: str) -> str:
        return json.dumps(
            {
                "type": "assistant",
                "message": {
                    "content": [
                        {"type": "tool_use", "name": "Read", "input": {"file_path": path}}
                    ]
                },
            }
        )

    claude_lines = "\n".join(
        [
            claude_read("/tmp/scratch/.claude/skills/x/SKILL.md"),
            claude_read("/Users/me/.claude/skills/x/SKILL.md"),
            claude_read("/tmp/proj/plugins/demo/skills/demo/SKILL.md"),
            json.dumps({"type": "result", "result": "done", "session_id": "claude-sess"}),
        ]
    )
    cursor_lines = "\n".join(
        [
            json.dumps(
                {
                    "type": "tool_call",
                    "subtype": "started",
                    "tool_call": {
                        "readToolCall": {
                            "args": {"path": "/tmp/scratch/.cursor/skills/x/SKILL.md"}
                        }
                    },
                }
            ),
            json.dumps(
                {
                    "type": "tool_call",
                    "subtype": "completed",
                    "tool_call": {
                        "readToolCall": {
                            "args": {"path": "/tmp/scratch/.cursor/skills/x/SKILL.md"},
                            "result": {"success": {}},
                        }
                    },
                }
            ),
            json.dumps(
                {
                    "type": "tool_call",
                    "subtype": "completed",
                    "tool_call": {
                        "shellToolCall": {
                            "args": {"command": "ls /elsewhere/.cursor/skills/y/scripts"},
                            "result": {"success": {}},
                        }
                    },
                }
            ),
            json.dumps({"type": "result", "result": "cursor-done", "session_id": "cursor-sess"}),
        ]
    )
    claude = micro_deploy.parse_stream_json("claude", claude_lines)
    cursor = micro_deploy.parse_stream_json("cursor", cursor_lines)
    check("claude final message", claude.final_message == "done")
    check("claude session_id", claude.session_id == "claude-sess")
    check("claude tool count", len(claude.tools) == 3)
    check("cursor final message", cursor.final_message == "cursor-done")
    check("cursor session_id", cursor.session_id == "cursor-sess")
    check("cursor tool name", cursor.tools[0].name == "readToolCall")

    claude_paths = micro_deploy.paths_from_tools(claude.tools)
    check("claude provenance extracts reads", len(claude_paths) == 3)
    cursor_paths = micro_deploy.paths_from_tools(cursor.tools)
    check(
        "cursor provenance from tool records",
        cursor_paths
        == ["/tmp/scratch/.cursor/skills/x/SKILL.md", "/elsewhere/.cursor/skills/y/scripts"],
    )
    cursor_out = micro_deploy.classify_out_of_set(
        cursor_paths,
        scratch_home=pathlib.Path("/tmp/scratch"),
        sandbox_project=pathlib.Path("/tmp/proj"),
    )
    check(
        "cursor provenance classifies the shell read out of set",
        len(cursor_out) == 1 and cursor_out[0].endswith("/elsewhere/.cursor/skills/y/scripts"),
    )


def test_classifier_cases() -> None:
    with tempfile.TemporaryDirectory() as td:
        root = pathlib.Path(td)
        home = root / "home"
        proj = root / "proj"
        proj.mkdir()
        for rel in (
            ".claude/skills/task/SKILL.md",
            ".cursor/skills/task/SKILL.md",
            ".claude/agents/auto_shaper_wiki.md",
            ".claude/skills/x/SKILL.md",
        ):
            target = home / rel
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text("x\n")

        def flagged(path: str, cwd: pathlib.Path | None = None) -> bool:
            return bool(
                micro_deploy.classify_out_of_set(
                    [path], scratch_home=home, sandbox_project=proj, cwd=cwd
                )
            )

        # A declared name deployed into the scratch home never excuses a read
        # of the same name from the user's home: there is no suffix remap.
        check(
            "real-home claude skill copy of a declared name is out of set",
            flagged(str(REAL_HOME / ".claude/skills/task/SKILL.md")),
        )
        check(
            "real-home cursor skill copy of a declared name is out of set",
            flagged(str(REAL_HOME / ".cursor/skills/task/SKILL.md")),
        )
        check(
            "real-home claude agent copy of a declared name is out of set",
            flagged(str(REAL_HOME / ".claude/agents/auto_shaper_wiki.md")),
        )
        check(
            "bare vendor path fails closed",
            flagged("/.claude/skills/x/SKILL.md"),
        )
        check(
            "unexpanded variable path fails closed",
            flagged("$D/.claude/skills/x/SKILL.md"),
        )
        check(
            "unexpanded tilde path fails closed",
            flagged("~other/.claude/skills/x/SKILL.md"),
        )
        check(
            "grok skill directory outside the roots is out of set",
            flagged("/elsewhere/.grok/skills/x/SKILL.md"),
        )
        check(
            "checkout skill source is out of set",
            flagged(str(REPO_ROOT / "plugins/ai_dev/skills/guardrail/SKILL.md")),
        )
        check(
            "checkout agent source is out of set",
            flagged(str(REPO_ROOT / "plugins/knowledge_management/agents/auto_shaper_wiki.md")),
        )
        check(
            "checkout style source is out of set",
            flagged(str(REPO_ROOT / "styles/natural-language.md")),
        )
        # `..` climbs from the physical working directory, so the climb is
        # computed from the resolved project (on macOS /var is /private/var).
        check(
            "checkout source reached through a relative climb is out of set",
            flagged(
                os.path.relpath(
                    REPO_ROOT / "plugins/ai_dev/skills/guardrail/SKILL.md",
                    proj.resolve(),
                ),
                cwd=proj,
            ),
        )
        check(
            "scratch home copy is in set",
            not flagged(str(home / ".claude/skills/task/SKILL.md")),
        )
        check(
            "relative vendor path resolves against the worker cwd",
            not flagged(".cursor/agents/auto_shaper_wiki.md", cwd=proj),
        )
        check(
            "fixture skill tree inside the sandbox is in set",
            not flagged(str(proj / "plugins/demo/skills/demo/SKILL.md")),
        )
        check(
            "fixture skill tree outside the checkout is not an artefact",
            not flagged("/elsewhere/plugins/demo/skills/demo/SKILL.md"),
        )
        check(
            "non-artefact file outside the roots is ignored",
            not flagged(str(REAL_HOME / ".claude/settings.json")),
        )


def test_shell_paths_expand_against_worker_env() -> None:
    def shell(command: str, tool: str = "Bash") -> micro_deploy.ToolRecord:
        return micro_deploy.ToolRecord(name=tool, input={"command": command})

    with tempfile.TemporaryDirectory() as td:
        sandbox = pathlib.Path(td) / "proj"
        sandbox.mkdir()

        cursor = micro_deploy.micro_deploy("cursor", ["task"], sandbox, preflight=False)
        try:
            paths = micro_deploy.paths_from_tools(
                [shell("cat ~/.cursor/skills/task/SKILL.md", "shellToolCall")],
                env=cursor.env,
                cwd=sandbox,
            )
            check(
                "cursor ~ expands to the scratch home",
                str(cursor.scratch_home / ".cursor/skills/task/SKILL.md") in paths,
            )
            check(
                "cursor scratch-home shell read is in set",
                not micro_deploy.classify_out_of_set(
                    paths,
                    scratch_home=cursor.scratch_home,
                    sandbox_project=cursor.sandbox_project,
                    cwd=sandbox,
                ),
            )
        finally:
            cursor.close()

        claude = micro_deploy.micro_deploy("claude", ["task"], sandbox, preflight=False)
        try:

            def classify(command: str) -> tuple[list[str], list[str]]:
                found = micro_deploy.paths_from_tools(
                    [shell(command)], env=claude.env, cwd=sandbox
                )
                return found, micro_deploy.classify_out_of_set(
                    found,
                    scratch_home=claude.scratch_home,
                    sandbox_project=claude.sandbox_project,
                    cwd=sandbox,
                )

            paths, out = classify("python3 ~/.claude/skills/task/scripts/lint.py")
            check(
                "claude ~ expands to the real home and fails",
                str(REAL_HOME / ".claude/skills/task/scripts/lint.py") in paths
                and len(out) == 1,
            )
            paths, out = classify('cat "$HOME/.claude/skills/task/SKILL.md"')
            check("claude $HOME read fails", len(out) == 1)
            check(
                "no truncated vendor path is extracted",
                not any(p.startswith("/.claude") or p.startswith("/skills") for p in paths),
            )
            paths, out = classify("ls ${CLAUDE_CONFIG_DIR}/skills/task/scripts")
            check(
                "claude $CLAUDE_CONFIG_DIR read is in set",
                str(claude.scratch_home / ".claude/skills/task/scripts") in paths
                and not out,
            )
            paths, out = classify("cat $PWD/.claude/skills/x/SKILL.md")
            check("claude $PWD resolves to the worker cwd", not out)
            paths, out = classify("D=/somewhere; cat $D/.claude/skills/task/SKILL.md")
            check(
                "a variable the command assigns expands its later paths",
                out
                == [str(pathlib.Path("/somewhere/.claude/skills/task/SKILL.md").resolve())],
            )
            paths, out = classify("cat $EARLIER/.claude/skills/task/SKILL.md")
            check(
                "a variable the command never assigns fails closed",
                out == ["$EARLIER/.claude/skills/task/SKILL.md"],
            )
            # The wiki prompts prefix scripts with HOME=<fake home>, which the
            # shell applies to that one command, so `~` afterwards is still the
            # worker's own home.
            paths, out = classify(
                f"HOME={sandbox}/fake bash x.sh; cat ~/.claude/skills/task/SKILL.md"
            )
            check(
                "a prefix assignment stays with its own command",
                out == [str((REAL_HOME / ".claude/skills/task/SKILL.md").resolve())],
            )

            # A checkout source reached through the command's own variable or
            # after its own `cd` is out of set. A `cd` inside a subshell or a
            # substitution, inside quotes or a here-document, as a mere
            # argument, or to a target that cannot be expanded moves nothing
            # for later words.
            checkout_skill = str(
                (REPO_ROOT / "plugins/ai_dev/skills/task/SKILL.md").resolve()
            )
            climb = os.path.relpath(REPO_ROOT, sandbox.resolve())
            for label, command in (
                ("a command-assigned variable",
                 f"D={REPO_ROOT}; cat $D/plugins/ai_dev/skills/task/SKILL.md"),
                ("an assignment-only statement",
                 f"D={REPO_ROOT} E=1; cat $D/plugins/ai_dev/skills/task/SKILL.md"),
                ("an exported, quoted, braced variable",
                 f'export D="{REPO_ROOT}"; cat "${{D}}/plugins/ai_dev/skills/task/SKILL.md"'),
                ("an absolute cd",
                 f"cd {REPO_ROOT} && cat plugins/ai_dev/skills/task/SKILL.md"),
                ("a relative cd that climbs out of the sandbox",
                 f"cd {climb} && cat plugins/ai_dev/skills/task/SKILL.md"),
                ("a cd inside an if body",
                 f"if true; then cd {REPO_ROOT}; fi; cat plugins/ai_dev/skills/task/SKILL.md"),
                ("a cd inside a quoted command substitution",
                 f'echo "$(cd {REPO_ROOT} && cat plugins/ai_dev/skills/task/SKILL.md)"'),
            ):
                paths, out = classify(command)
                check(f"checkout source behind {label} is out of set",
                      out == [checkout_skill])
            for label, command in (
                ("inside a parenthesised subshell",
                 f"(cd {REPO_ROOT} && pwd); cat plugins/demo/skills/demo/SKILL.md"),
                ("inside a command substitution",
                 f"echo $(cd {REPO_ROOT} && pwd); cat plugins/demo/skills/demo/SKILL.md"),
                ("inside a backtick substitution",
                 f"echo `cd {REPO_ROOT} && pwd`; cat plugins/demo/skills/demo/SKILL.md"),
                ("as an echo argument",
                 f"echo cd {REPO_ROOT}; cat plugins/demo/skills/demo/SKILL.md"),
                ("in double-quoted text",
                 f'echo "x; cd {REPO_ROOT} now"; cat plugins/demo/skills/demo/SKILL.md'),
                ("in single-quoted text",
                 f"echo 'x; cd {REPO_ROOT} now'; cat plugins/demo/skills/demo/SKILL.md"),
                ("in a here-document body",
                 f"cat > run.sh <<'EOF'\ncd {REPO_ROOT}\nEOF\n"
                 "cat plugins/demo/skills/demo/SKILL.md"),
                ("to a target that cannot be expanded",
                 "cd $UNSET_DIR && cat .claude/skills/x/SKILL.md"),
            ):
                paths, out = classify(command)
                check(f"a cd {label} leaves later sandbox paths in set", not out)
            paths, out = classify("cd sub && cat .cursor/agents/x.md")
            check(
                "a cd within the sandbox keeps its relative paths in set",
                not out and str(sandbox / "sub/.cursor/agents/x.md") in paths,
            )
            grep_paths = micro_deploy.paths_from_tools(
                [
                    micro_deploy.ToolRecord(
                        name="Grep",
                        input={"pattern": ".claude/skills/task/SKILL.md$", "path": str(sandbox)},
                    )
                ],
                env=claude.env,
                cwd=sandbox,
            )
            check(
                "grep pattern is content, not a path",
                grep_paths == [str(sandbox)],
            )
            # Recorded on 9 October 2026 (wiki AS-1, Claude): a loop that quotes
            # one variable and later assigns the scratch skill path. Pairing the
            # wrong quotes once turned the text between them into one "path".
            scratch_wiki = claude.scratch_home / ".claude/skills/task"
            paths, out = classify(
                'for f in "$A" "$B"; do echo "$f"; cat -vet $f; done; '
                f"S={scratch_wiki}; for d in $(grep -o 'x' y); do ls \"$S/scripts\"; done"
            )
            check("quoted spans never merge into one path", not out)
            check(
                "every extracted fragment is a single path",
                all(not any(c in p for c in " ;|&") for p in paths),
            )
            paths, out = classify("grep -n '.claude/skills/task/SKILL.md$' notes.md")
            check("a regex anchor is not an unexpanded variable", not out)

            glob_paths = micro_deploy.paths_from_tools(
                [
                    micro_deploy.ToolRecord(
                        name="Glob",
                        input={"pattern": "**/SKILL.md", "path": str(REAL_HOME / ".claude/skills")},
                    ),
                    micro_deploy.ToolRecord(
                        name="globToolCall",
                        input={"globPattern": "**/*", "targetDirectory": str(sandbox)},
                    ),
                ],
                env=claude.env,
                cwd=sandbox,
            )
            glob_out = micro_deploy.classify_out_of_set(
                glob_paths,
                scratch_home=claude.scratch_home,
                sandbox_project=claude.sandbox_project,
                cwd=sandbox,
            )
            check(
                "a glob rooted in the real skills directory fails",
                glob_out == [str((REAL_HOME / ".claude/skills").resolve() / "**/SKILL.md")],
            )
            check(
                "a glob rooted in the sandbox records its joined pattern",
                f"{sandbox}/**/*" in glob_paths,
            )
        finally:
            claude.close()


def test_run_worker_command_shape_and_timeout() -> None:
    real_run = subprocess.run
    with tempfile.TemporaryDirectory() as td:
        sandbox = pathlib.Path(td) / "proj"
        sandbox.mkdir()

        cursor_handle = micro_deploy.micro_deploy(
            "cursor", ["language_humanizer"], sandbox, preflight=False
        )
        try:
            recorded: dict[str, object] = {}

            def fake_run(cmd, **kwargs):
                recorded["cmd"] = list(cmd)
                recorded["cwd"] = kwargs.get("cwd")
                return fake_result(
                    0, json.dumps({"type": "result", "result": "ok", "session_id": "s"})
                )

            subprocess.run = fake_run  # type: ignore[assignment]
            try:
                result = micro_deploy.run_worker(
                    vendor_name="cursor",
                    bin_name="agent",
                    model="auto",
                    prompt="hi",
                    deploy=cursor_handle,
                    timeout=5,
                    extra_args=worker_isolation.isolation_args("cursor"),
                )
            finally:
                subprocess.run = real_run  # type: ignore[assignment]

            cmd = recorded["cmd"]
            assert isinstance(cmd, list)
            check("cursor stream-json only", output_formats(cmd) == ["stream-json"])
            check("cursor carries no text format", "text" not in cmd)
            check("run_worker returns text", result.stdout == "ok")

            class Boom(subprocess.TimeoutExpired):
                def __init__(self):
                    super().__init__(cmd=["agent"], timeout=1)
                    self.stdout = b"partial-out"
                    self.stderr = b"partial-err"

            def boom_run(*_a, **_k):
                raise Boom()

            subprocess.run = boom_run  # type: ignore[assignment]
            try:
                timed = micro_deploy.run_worker(
                    vendor_name="cursor",
                    bin_name="agent",
                    model="auto",
                    prompt="hi",
                    deploy=cursor_handle,
                    timeout=1,
                )
            finally:
                subprocess.run = real_run  # type: ignore[assignment]
            check("timeout stdout via worker_io", timed.stdout == "partial-out")
            check(
                "timeout stderr via worker_io",
                "partial-err" in timed.stderr and "[TIMEOUT after 1s]" in timed.stderr,
            )
            check("timeout rc", timed.returncode == -1)
        finally:
            cursor_handle.close()

        claude_handle = micro_deploy.micro_deploy(
            "claude", ["language_humanizer"], sandbox, preflight=False
        )
        try:
            isolation = worker_isolation.isolation_args("claude")
            recorded = {}
            stream = "\n".join(
                [
                    json.dumps(
                        {
                            "type": "assistant",
                            "message": {
                                "content": [
                                    {
                                        "type": "tool_use",
                                        "name": "Bash",
                                        "input": {
                                            "command": "cat ~/.claude/skills/language_humanizer/SKILL.md"
                                        },
                                    }
                                ]
                            },
                        }
                    ),
                    json.dumps({"type": "result", "result": "ok", "session_id": "s"}),
                ]
            )

            def claude_run(cmd, **kwargs):
                recorded["cmd"] = list(cmd)
                return fake_result(0, stream)

            subprocess.run = claude_run  # type: ignore[assignment]
            try:
                result = micro_deploy.run_worker(
                    vendor_name="claude",
                    bin_name="claude",
                    model="sonnet",
                    prompt="hi",
                    deploy=claude_handle,
                    timeout=5,
                    extra_args=isolation,
                )
            finally:
                subprocess.run = real_run  # type: ignore[assignment]

            cmd = recorded["cmd"]
            assert isinstance(cmd, list)
            start = cmd.index(isolation[0]) if isolation[0] in cmd else -1
            check(
                "claude forwards the recorded isolation_args list",
                start >= 0 and cmd[start:start + len(isolation)] == isolation,
            )
            check(
                "claude stream-json with --verbose",
                output_formats(cmd) == ["stream-json"] and "--verbose" in cmd,
            )
            check(
                "claude real-home shell read fails provenance",
                result.out_of_set_paths
                == [str((REAL_HOME / ".claude/skills/language_humanizer/SKILL.md").resolve())],
            )
        finally:
            claude_handle.close()


def test_helper_reads_reach_provenance() -> None:
    """A spawned helper's reads count as the worker's on both vendors.

    The Cursor lines follow a print-mode probe recorded on 9 October 2026
    (agent 2026.10.01): the parent's stream carries only the Task call and its
    agentId, while the helper's own tool calls sit in its chat transcript
    under the worker's HOME. Paths are swapped for test ones.
    """

    real_run = subprocess.run
    with tempfile.TemporaryDirectory() as td:
        root = pathlib.Path(td)
        sandbox = root / "proj"
        sandbox.mkdir()
        elsewhere = root / "elsewhere" / ".cursor" / "skills" / "demo" / "SKILL.md"

        cursor_handle = micro_deploy.micro_deploy(
            "cursor", ["language_humanizer"], sandbox, preflight=False
        )
        try:
            in_set = cursor_handle.path_map["language_humanizer"]
            real_home_copy = REAL_HOME / ".cursor/skills/language_humanizer/SKILL.md"
            parent_only = sandbox / "parent-only.txt"

            def assistant_line(*blocks: dict) -> str:
                return json.dumps(
                    {"role": "assistant", "message": {"content": list(blocks)}}
                )

            def tool_use(name: str, **tool_input: str) -> dict:
                return {"type": "tool_use", "name": name, "input": tool_input}

            ended = json.dumps({"type": "turn_ended", "status": "success"})
            helper_transcript = "\n".join(
                [
                    json.dumps({"role": "user", "message": {"content": []}}),
                    assistant_line(
                        tool_use("Read", path=str(in_set)),
                        tool_use("Read", path=str(real_home_copy)),
                    ),
                    assistant_line(tool_use("Shell", command=f"cat {elsewhere}")),
                    ended,
                ]
            )
            parent_transcript = "\n".join(
                [assistant_line(tool_use("Read", path=str(parent_only))), ended]
            )
            parent_stream = "\n".join(
                [
                    json.dumps(
                        {"type": "system", "subtype": "init", "session_id": "parent-chat"}
                    ),
                    json.dumps(
                        {
                            "type": "tool_call",
                            "subtype": "completed",
                            "tool_call": {
                                "taskToolCall": {
                                    "args": {"description": "Read files", "prompt": "x"},
                                    "result": {
                                        "success": {
                                            "conversationSteps": [],
                                            "agentId": "helper-chat",
                                        }
                                    },
                                },
                                "toolCallId": "call-1",
                                "startedAtMs": "1",
                                "completedAtMs": "2",
                            },
                        }
                    ),
                    json.dumps(
                        {"type": "result", "result": "relayed", "session_id": "parent-chat"}
                    ),
                ]
            )

            def cursor_run(cmd, **kwargs):
                transcripts = (
                    cursor_handle.scratch_home
                    / ".cursor/projects/proj-slug/agent-transcripts"
                )
                for chat, text in (
                    ("helper-chat", helper_transcript),
                    ("parent-chat", parent_transcript),
                ):
                    path = transcripts / chat / f"{chat}.jsonl"
                    path.parent.mkdir(parents=True, exist_ok=True)
                    path.write_text(text + "\n")
                return fake_result(0, parent_stream)

            subprocess.run = cursor_run  # type: ignore[assignment]
            try:
                result = micro_deploy.run_worker(
                    vendor_name="cursor",
                    bin_name="agent",
                    model="auto",
                    prompt="hi",
                    deploy=cursor_handle,
                    timeout=5,
                )
            finally:
                subprocess.run = real_run  # type: ignore[assignment]

            check(
                "cursor helper read from its transcript reaches the read list",
                str(in_set) in result.read_paths,
            )
            check(
                "cursor helper reads outside the deployment fail",
                sorted(result.out_of_set_paths)
                == sorted([str(real_home_copy.resolve()), str(elsewhere.resolve())]),
            )
            check(
                "cursor parent transcript is read too",
                str(parent_only) in result.read_paths,
            )
            check("cursor final message unaffected by transcripts", result.stdout == "relayed")
            check(
                "transcript parser skips user and turn_ended lines",
                len(micro_deploy.parse_transcript_tools(helper_transcript)) == 3,
            )
        finally:
            cursor_handle.close()

        claude_handle = micro_deploy.micro_deploy(
            "claude", ["language_humanizer"], sandbox, preflight=False
        )
        try:
            helper_event = json.dumps(
                {
                    "type": "assistant",
                    "parent_tool_use_id": "toolu_helper",
                    "message": {
                        "content": [
                            {
                                "type": "tool_use",
                                "name": "Read",
                                "input": {"file_path": str(elsewhere)},
                            }
                        ]
                    },
                }
            )
            stream = "\n".join(
                [helper_event, json.dumps({"type": "result", "result": "ok"})]
            )

            def claude_run(cmd, **kwargs):
                return fake_result(0, stream)

            subprocess.run = claude_run  # type: ignore[assignment]
            try:
                result = micro_deploy.run_worker(
                    vendor_name="claude",
                    bin_name="claude",
                    model="sonnet",
                    prompt="hi",
                    deploy=claude_handle,
                    timeout=5,
                )
            finally:
                subprocess.run = real_run  # type: ignore[assignment]
            check(
                "claude helper read in the stream fails provenance",
                result.out_of_set_paths == [str(elsewhere.resolve())],
            )
        finally:
            claude_handle.close()


def test_auth_preflight_failure_surfaces_cli_message() -> None:
    real_run = subprocess.run
    real_mkdtemp = tempfile.mkdtemp
    created: list[pathlib.Path] = []

    def recording_mkdtemp(*args, **kwargs):
        path = real_mkdtemp(*args, **kwargs)
        created.append(pathlib.Path(path))
        return path

    def selective_run(cmd, **kwargs):
        if "PROBE_OK" in " ".join(str(c) for c in cmd):
            return fake_result(1, "", "CLI says: please run agent login")
        return real_run(cmd, **kwargs)

    with tempfile.TemporaryDirectory() as td:
        sandbox = pathlib.Path(td) / "proj"
        sandbox.mkdir()

        subprocess.run = selective_run  # type: ignore[assignment]
        tempfile.mkdtemp = recording_mkdtemp  # type: ignore[assignment]
        raised = None
        try:
            try:
                micro_deploy.micro_deploy(
                    "cursor",
                    ["language_humanizer"],
                    sandbox,
                    preflight=True,
                    bin_name="agent",
                    model="auto",
                )
            except SystemExit as exc:
                raised = str(exc)
        finally:
            subprocess.run = real_run  # type: ignore[assignment]
            tempfile.mkdtemp = real_mkdtemp  # type: ignore[assignment]
        scratch = [p for p in created if p.name.startswith("micro_deploy_cursor_")]
        check(
            "auth preflight surfaces CLI message",
            raised is not None and "please run agent login" in raised,
        )
        check(
            "failed preflight removes the scratch home",
            len(scratch) == 1 and not scratch[0].exists() and not scratch[0].is_symlink(),
        )

    created.clear()
    subprocess.run = selective_run  # type: ignore[assignment]
    tempfile.mkdtemp = recording_mkdtemp  # type: ignore[assignment]
    raised = None
    try:
        try:
            micro_deploy.preflight_auth("cursor", "agent", "auto")
        except SystemExit as exc:
            raised = str(exc)
    finally:
        subprocess.run = real_run  # type: ignore[assignment]
        tempfile.mkdtemp = real_mkdtemp  # type: ignore[assignment]
    check(
        "runner preflight stops the run with the CLI message",
        raised is not None and "please run agent login" in raised,
    )
    check(
        "runner preflight leaves no probe or scratch directory",
        len(created) == 2 and not any(p.exists() for p in created),
    )

    probed: list[dict[str, str]] = []

    def passing_run(cmd, **kwargs):
        if "PROBE_OK" in " ".join(str(c) for c in cmd):
            probed.append(dict(kwargs.get("env") or {}))
            return fake_result(0, "PROBE_OK\n")
        return real_run(cmd, **kwargs)

    created.clear()
    subprocess.run = passing_run  # type: ignore[assignment]
    tempfile.mkdtemp = recording_mkdtemp  # type: ignore[assignment]
    try:
        micro_deploy.preflight_auth("claude", "claude", "sonnet")
    finally:
        subprocess.run = real_run  # type: ignore[assignment]
        tempfile.mkdtemp = real_mkdtemp  # type: ignore[assignment]
    check(
        "runner preflight probes the micro-deployment environment",
        len(probed) == 1
        and probed[0].get("CLAUDE_SECURESTORAGE_CONFIG_DIR") == ""
        and "micro_deploy_claude_" in probed[0].get("CLAUDE_CONFIG_DIR", ""),
    )
    check(
        "passing runner preflight cleans up",
        len(created) == 2 and not any(p.exists() for p in created),
    )


def test_library_unlinked_before_removal() -> None:
    real_rmtree = shutil.rmtree
    observed: dict[str, bool] = {}
    with tempfile.TemporaryDirectory() as td:
        sandbox = pathlib.Path(td) / "proj"
        sandbox.mkdir()
        handle = micro_deploy.micro_deploy(
            "cursor", ["language_humanizer"], sandbox, preflight=False
        )
        scratch = handle.scratch_home
        library = scratch / "Library"
        real_library_present = (REAL_HOME / "Library").exists()
        if real_library_present:
            check("Library linked before close", library.is_symlink())

        def watching_rmtree(path, *args, **kwargs):
            if pathlib.Path(path) == scratch:
                observed["link_present"] = library.is_symlink() or library.exists()
            return real_rmtree(path, *args, **kwargs)

        shutil.rmtree = watching_rmtree  # type: ignore[assignment]
        try:
            handle.close()
        finally:
            shutil.rmtree = real_rmtree  # type: ignore[assignment]
        check(
            "Library unlinked before the scratch tree is removed",
            observed.get("link_present") is False,
        )
        check("scratch gone after close", not scratch.exists())
        if real_library_present:
            check("real Library untouched by close", (REAL_HOME / "Library").is_dir())


def main() -> int:
    print("test_micro_deploy")
    test_layouts_and_path_map()
    test_only_limits_and_log_override()
    test_overlay_fixture_edits()
    test_login_profiles_restore_worker_path()
    test_run_worker_passes_launch_path()
    test_worker_env_overlays()
    test_stream_parser_and_provenance()
    test_classifier_cases()
    test_shell_paths_expand_against_worker_env()
    test_run_worker_command_shape_and_timeout()
    test_helper_reads_reach_provenance()
    test_auth_preflight_failure_surfaces_cli_message()
    test_library_unlinked_before_removal()
    print(f"\n{PASS} passed, {FAIL} failed")
    return 0 if FAIL == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
