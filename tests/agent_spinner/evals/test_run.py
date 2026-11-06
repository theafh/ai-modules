#!/usr/bin/env python3
"""Plumbing tests for the agent_spinner eval runner — no live model.

The stub worker logs each call's arguments and environment and replies from a
canned queue. The cases drive `main()` through `--worker-bin`, patch the
runner's seams in memory, and assert the run loop's wiring. No network call and
no live worker is made.

Run:

    python3 tests/agent_spinner/evals/test_run.py
"""

from __future__ import annotations

import contextlib
import copy
import io
import json
import os
import pathlib
import subprocess
import sys
import tempfile

THIS = pathlib.Path(__file__).resolve().parent
REPO_ROOT = THIS.parents[2]
sys.path.insert(0, str(THIS.parents[1] / "lib"))
sys.path.insert(0, str(THIS))
import eval_cache  # noqa: E402
import eval_runner  # noqa: E402
import micro_deploy  # noqa: E402
import run  # noqa: E402
import vendor  # noqa: E402

PASS = 0
FAIL = 0


def check(label: str, cond: bool, detail: str = "") -> None:
    global PASS, FAIL
    if cond:
        PASS += 1
        print(f"  ok   {label}")
    else:
        FAIL += 1
        print(f"  FAIL {label}" + (f" — {detail}" if detail else ""))


STUB = r'''#!/usr/bin/env python3
import fcntl, json, os, pathlib, subprocess, sys, time

args = sys.argv[1:]
stub_dir = pathlib.Path(os.environ["STUB_DIR"])

if "--version" in args:
    version = stub_dir / "version"
    print(version.read_text().strip() if version.exists() else "stub-1.0")
    raise SystemExit(0)

# Two overlapping jobs share this counter, so take an exclusive lock before
# reading it. Each call then gets its own reply slot.
count_path = stub_dir / "count"
with (stub_dir / "count.lock").open("a") as lock:
    fcntl.flock(lock, fcntl.LOCK_EX)
    count = int(count_path.read_text()) if count_path.exists() else 0
    count += 1
    count_path.write_text(str(count))
    fcntl.flock(lock, fcntl.LOCK_UN)

sleep_s = float(os.environ.get("STUB_SLEEP", "0"))
if sleep_s:
    time.sleep(sleep_s)

cwd = pathlib.Path.cwd()

escape_name = os.environ.get("STUB_ESCAPE_NAME", "")
if escape_name and (cwd / escape_name).exists():
    host_root = pathlib.Path(os.environ["STUB_HOST_ROOT"])
    (host_root / escape_name).write_text("escaped from the sandbox\n")


def agent_names(path):
    if not path.is_dir():
        return []
    return sorted(p.stem for p in path.glob("*.md"))


git_status = subprocess.run(
    ["git", "-C", str(cwd), "status", "--porcelain"],
    capture_output=True, text=True,
).stdout
marker_name = os.environ.get("STUB_MARKER_NAME", "")
claude_config = os.environ.get("CLAUDE_CONFIG_DIR", "")
eval_marker = cwd / "eval_id.txt"
entry = {
    "argv": args,
    "cwd": str(cwd),
    "home": os.environ.get("HOME"),
    "tmpdir": os.environ.get("TMPDIR"),
    "eval_marker": eval_marker.read_text().strip() if eval_marker.is_file() else "",
    "started_at": time.time() - sleep_s,
    "ended_at": time.time(),
    "claude_config": claude_config,
    "marker": bool(marker_name) and (cwd / marker_name).exists(),
    "git_status": git_status,
    "config_agents": agent_names(pathlib.Path(claude_config) / "agents")
    if claude_config else [],
    "project_agents": agent_names(cwd / ".cursor" / "agents"),
}
with (stub_dir / "log.jsonl").open("a") as fh:
    fh.write(json.dumps(entry) + "\n")

if os.environ.get("STUB_WRITE_SMOKE"):
    (cwd / "smoke.txt").write_text("# agent_spinner\n")

if os.environ.get("STUB_HELPER_TRANSCRIPT"):
    read_path = cwd / "README.txt"
    transcript = (
        pathlib.Path(os.environ["HOME"])
        / ".cursor/projects/p/agent-transcripts/helper-chat/helper-chat.jsonl"
    )
    transcript.parent.mkdir(parents=True, exist_ok=True)
    line = json.dumps({
        "role": "assistant",
        "message": {"content": [
            {"type": "tool_use", "name": "Read", "input": {"path": str(read_path)}}
        ]},
    })
    transcript.write_text(line + "\n")

out_path = stub_dir / f"{count}.out"
text = (
    out_path.read_text() if out_path.exists()
    else '{"type": "result", "result": "stub reply", "session_id": "stub-session"}'
)
sys.stdout.write(text.replace("__CWD__", str(cwd)))
err_path = stub_dir / f"{count}.err"
if err_path.exists():
    sys.stderr.write(err_path.read_text())
rc_path = stub_dir / f"{count}.rc"
raise SystemExit(int(rc_path.read_text()) if rc_path.exists() else 0)
'''


def make_worker(root: pathlib.Path) -> tuple[pathlib.Path, pathlib.Path]:
    stub_dir = root / "stub"
    stub_dir.mkdir(parents=True)
    worker = root / "stub-worker"
    worker.write_text(STUB)
    worker.chmod(0o755)
    (stub_dir / "log.jsonl").write_text("")
    return worker, stub_dir


def queue(stub_dir: pathlib.Path, index: int, text: str, rc: int = 0,
          err: str = "") -> None:
    (stub_dir / f"{index}.out").write_text(text)
    (stub_dir / f"{index}.rc").write_text(str(rc))
    (stub_dir / f"{index}.err").write_text(err)


def stub_log(stub_dir: pathlib.Path) -> list[dict]:
    text = (stub_dir / "log.jsonl").read_text()
    return [json.loads(line) for line in text.splitlines() if line.strip()]


def real_specs() -> dict:
    data = json.loads(run.EVALS.read_text())
    return {entry["id"]: copy.deepcopy(entry) for entry in data["evals"]}


def latest_run(workspace: pathlib.Path) -> pathlib.Path:
    runs = [path for path in workspace.iterdir() if path.is_dir()]
    return max(runs, key=lambda path: path.name)


@contextlib.contextmanager
def patched(
    specs: dict,
    workspace: pathlib.Path,
    stub_dir: pathlib.Path,
    *,
    resume: tuple[bool, str] = (True, ""),
    grade: pathlib.Path | None = None,
    cache=None,
    stage=None,
    extra_env: dict[str, str] | None = None,
):
    saved = {
        "load_evals": run.load_evals,
        "WORKSPACE": run.WORKSPACE,
        "preflight_auth": run.micro_deploy.preflight_auth,
        "preflight_resume": run.preflight_resume,
        "GRADE": run.GRADE,
        "stage": run.stage,
        "EvalCache": run.eval_cache.EvalCache,
    }
    env_keys = {"STUB_DIR": str(stub_dir)}
    if extra_env:
        env_keys.update(extra_env)
    old_env = {key: os.environ.get(key) for key in env_keys}
    run.load_evals = lambda: specs
    run.WORKSPACE = workspace
    run.micro_deploy.preflight_auth = lambda *args, **kwargs: None
    run.preflight_resume = lambda *args, **kwargs: resume
    if grade is not None:
        run.GRADE = grade
    if stage is not None:
        run.stage = stage
    if cache is not None:
        run.eval_cache.EvalCache = lambda path: cache
    os.environ.update(env_keys)
    try:
        yield
    finally:
        run.load_evals = saved["load_evals"]
        run.WORKSPACE = saved["WORKSPACE"]
        run.micro_deploy.preflight_auth = saved["preflight_auth"]
        run.preflight_resume = saved["preflight_resume"]
        run.GRADE = saved["GRADE"]
        run.stage = saved["stage"]
        run.eval_cache.EvalCache = saved["EvalCache"]
        for key, value in old_env.items():
            if value is None:
                os.environ.pop(key, None)
            else:
                os.environ[key] = value


def invoke(argv: list[str]) -> tuple[int, str]:
    old = sys.argv
    sys.argv = ["run.py", *argv]
    output = io.StringIO()
    try:
        with contextlib.redirect_stdout(output):
            rc = run.main()
    finally:
        sys.argv = old
    return rc, output.getvalue()


def passing_grade(root: pathlib.Path) -> pathlib.Path:
    script = root / "passing-grade.sh"
    script.write_text("#!/usr/bin/env bash\nexit 0\n")
    script.chmod(0o755)
    return script


def logging_grade(root: pathlib.Path) -> pathlib.Path:
    """A passing grader that records its eval id and TMPDIR."""
    script = root / "logging-grade.sh"
    script.write_text(
        "#!/usr/bin/env bash\n"
        "printf '%s %s\\n' \"$1\" \"${TMPDIR:-}\" >> \"$GRADE_LOG\"\n"
        "exit 0\n"
    )
    script.chmod(0o755)
    return script


def fake_stage(extra_for=None):
    """A stage seam that writes a probe sandbox without running a fixture.

    `extra_for(eval_id)` returns extra files for that eval's project, so a
    case can give one eval a name its sibling does not own.
    """

    def stage(eval_id, target, env=None):
        root = pathlib.Path(target)
        proj = root / "proj"
        proj.mkdir(parents=True, exist_ok=True)
        (proj / "eval_id.txt").write_text(f"{eval_id}\n")
        for name, text in (extra_for(eval_id) if extra_for else {}).items():
            (proj / name).write_text(text)
        return {
            "sandbox_proj": str(proj),
            "sandbox_target": str(root),
            "skill_path": str(THIS / "stage.sh"),
            "prompt": f"probe prompt for {eval_id}",
        }

    return stage


def host_mirror(root: pathlib.Path) -> pathlib.Path:
    """A clean throwaway git checkout the guard can watch."""
    mirror = root / "host"
    mirror.mkdir()
    (mirror / "tracked.txt").write_text("host checkout\n")
    for args in (
        ["init", "-q"],
        ["config", "user.email", "evals@example.invalid"],
        ["config", "user.name", "Evals"],
        ["add", "."],
        ["commit", "-qm", "host"],
    ):
        subprocess.run(
            ["git", "-C", str(mirror), *args],
            check=True, capture_output=True, text=True,
        )
    return mirror


def cursor_stream(*, read: str, session: str, final: str,
                  extra: list[dict] | None = None) -> str:
    lines = [
        json.dumps({"type": "system", "subtype": "init", "session_id": session}),
        json.dumps({
            "type": "tool_call",
            "subtype": "completed",
            "tool_call": {
                "readToolCall": {
                    "args": {"path": read},
                    "result": {"success": {}},
                }
            },
        }),
    ]
    lines.extend(json.dumps(event) for event in (extra or []))
    lines.append(
        json.dumps({"type": "result", "result": final, "session_id": session})
    )
    return "\n".join(lines) + "\n"


def claude_stream(*, read: str, session: str, final: str,
                  extra: list[dict] | None = None) -> str:
    lines = [
        json.dumps({"type": "system", "subtype": "init", "session_id": session}),
        json.dumps({
            "type": "assistant",
            "message": {"content": [
                {"type": "tool_use", "id": "r1", "name": "Read",
                 "input": {"file_path": read}}
            ]},
        }),
        json.dumps({
            "type": "user",
            "message": {"content": [
                {"type": "tool_result", "tool_use_id": "r1", "content": "ok"}
            ]},
        }),
    ]
    lines.extend(json.dumps(event) for event in (extra or []))
    lines.append(
        json.dumps({"type": "result", "result": final, "session_id": session})
    )
    return "\n".join(lines) + "\n"


def stream_for(vendor_name: str, *, read: str, session: str, final: str,
               extra: list[dict] | None = None) -> str:
    if vendor_name == "claude":
        return claude_stream(read=read, session=session, final=final, extra=extra)
    return cursor_stream(read=read, session=session, final=final, extra=extra)


def case_inline_body() -> None:
    print("inline body")
    with tempfile.TemporaryDirectory() as td:
        root = pathlib.Path(td)
        worker, stub_dir = make_worker(root)
        queue(stub_dir, 1, json.dumps(
            {"type": "result", "result": "stub reply", "session_id": "s1"}
        ))
        specs = real_specs()
        spec = specs["smoke_inline_body"]
        spec["harness"]["extra_reads"] = [
            "plugins/ai_dev/skills/task_auto_check/SKILL.md"
        ]
        workspace = root / "workspace"
        with patched(
            {"smoke_inline_body": spec}, workspace, stub_dir,
            grade=passing_grade(root),
        ):
            rc, output = invoke(
                ["smoke_inline_body", "--worker-bin", str(worker), "--no-cache"]
            )
        check("inline-body run exits 0", rc == 0, output)
        log = stub_log(stub_dir)
        check("inline-body makes one call", len(log) == 1)
        prompt = log[0]["argv"][-1] if log else ""
        body = run.strip_frontmatter(
            (REPO_ROOT / "plugins/ai_dev/skills/agent_spinner/SKILL.md").read_text()
        )
        check("inline-body prompt holds the body byte for byte", body in prompt)
        check(
            "inline-body prompt holds the attachment note",
            run.ATTACHMENT_NOTE in prompt,
        )
        attached = next(
            (
                line[len("Attached file: "):].strip()
                for line in prompt.splitlines()
                if line.startswith("Attached file: ")
            ),
            "",
        )
        check(
            "inline-body prompt names the deployed SKILL.md's absolute path",
            attached.endswith("/agent_spinner/SKILL.md")
            and pathlib.Path(attached).is_absolute(),
            attached,
        )
        check(
            "inline-body prompt holds the governing-skill line",
            "A named skill governs this request" in prompt
            and "task_auto_check/SKILL.md" in prompt,
        )
        check(
            "inline-body prompt drops the frontmatter",
            "name: agent_spinner" not in prompt,
        )
        check(
            "inline-body prompt drops the read-the-skill and references steps",
            "Read the skill definition file in full" not in prompt
            and "Read its references/ directory" not in prompt,
        )
        timing = json.loads(
            (latest_run(workspace) / "smoke_inline_body" / "timing.json").read_text()
        )
        check(
            "inline-body timing records the mode",
            timing["modes"]["inline_body"] is True,
        )


def case_second_turn(vendor_name: str) -> None:
    print(f"second turn ({vendor_name})")
    with tempfile.TemporaryDirectory() as td:
        root = pathlib.Path(td)
        worker, stub_dir = make_worker(root)
        queue(stub_dir, 1, stream_for(
            vendor_name, read="__CWD__/README.txt", session="first-session",
            final="first reply",
        ))
        queue(stub_dir, 2, stream_for(
            vendor_name, read="__CWD__/second_token.txt", session="second-session",
            final="second reply",
        ))
        spec = real_specs()["smoke_second_turn"]
        workspace = root / "workspace"
        with patched(
            {"smoke_second_turn": spec}, workspace, stub_dir,
            grade=passing_grade(root),
            extra_env={"STUB_MARKER_NAME": "second_token.txt"},
        ):
            rc, output = invoke([
                "smoke_second_turn", "--vendor", vendor_name,
                "--worker-bin", str(worker), "--no-cache",
            ])
        check(f"{vendor_name} two-turn run exits 0", rc == 0, output)
        log = stub_log(stub_dir)
        check(f"{vendor_name} two-turn makes two calls", len(log) == 2, str(len(log)))
        if len(log) == 2:
            check(
                f"{vendor_name} between marker exists only before the second call",
                log[0]["marker"] is False and log[1]["marker"] is True,
            )
            check(
                f"{vendor_name} between writes into the sandbox project",
                not (
                    latest_run(workspace) / "smoke_second_turn"
                    / "sandbox" / "second_token.txt"
                ).exists(),
            )
            between_log = (
                latest_run(workspace) / "smoke_second_turn" / "sandbox"
                / "between_args.txt"
            )
            logged = (
                between_log.read_text().splitlines()
                if between_log.is_file() else []
            )
            check(
                f"{vendor_name} between receives sandbox_target then sandbox_proj",
                len(logged) == 2
                and pathlib.Path(logged[0]).is_absolute()
                and pathlib.Path(logged[1]).is_absolute()
                and pathlib.Path(logged[1]).parent == pathlib.Path(logged[0]),
                str(logged),
            )
            first_args = log[0]["argv"]
            second_args = log[1]["argv"]
            if vendor_name == "claude":
                first_id = first_args[first_args.index("--session-id") + 1]
                second_id = second_args[second_args.index("--resume") + 1]
                check(
                    "claude first turn opens a session and the second resumes it",
                    first_id == second_id and "--resume" not in first_args,
                )
                check(
                    "claude turns share one CLAUDE_CONFIG_DIR",
                    log[0]["claude_config"] == log[1]["claude_config"],
                )
            else:
                check(
                    "cursor first turn carries no session flag",
                    "--session-id" not in first_args and "--resume" not in first_args,
                )
                check(
                    "cursor second turn resumes the first stream's session",
                    second_args[second_args.index("--resume") + 1] == "first-session",
                )
                check(
                    "cursor turns share one scratch HOME",
                    log[0]["home"] == log[1]["home"],
                )
            check(
                f"{vendor_name} second call carries the second prompt verbatim",
                second_args[-1] == spec["harness"]["second_turn"]["prompt"],
            )
        eval_dir = latest_run(workspace) / "smoke_second_turn"
        check(
            "two-turn response files hold each turn's final message",
            (eval_dir / "response_turn1.txt").read_text() == "first reply"
            and (eval_dir / "response.txt").read_text() == "second reply",
        )
        timing = json.loads((eval_dir / "timing.json").read_text())
        check(
            "two-turn timing records both turns and the last rc",
            [entry["turn"] for entry in timing["turns"]] == [1, 2]
            and all("duration_s" in entry for entry in timing["turns"])
            and timing["worker_rc"] == 0 and timing["claude_rc"] == 0,
        )
        paths = timing["artefacts_read_from_micro_deployment"]["paths"]
        check(
            "two-turn provenance covers both turns' reads",
            any(path.endswith("README.txt") for path in paths)
            and any(path.endswith("second_token.txt") for path in paths)
            and timing["artefacts_read_from_micro_deployment"]["passed"] is True
            and timing["artefacts_read_from_micro_deployment"]["out_of_set"] == [],
        )

    print(f"second turn first-turn failure ({vendor_name})")
    with tempfile.TemporaryDirectory() as td:
        root = pathlib.Path(td)
        worker, stub_dir = make_worker(root)
        queue(stub_dir, 1, stream_for(
            vendor_name, read="__CWD__/README.txt", session="first-session",
            final="first reply",
        ), rc=1)
        spec = real_specs()["smoke_second_turn"]
        workspace = root / "workspace"
        with patched(
            {"smoke_second_turn": spec}, workspace, stub_dir,
            grade=passing_grade(root),
            extra_env={"STUB_MARKER_NAME": "second_token.txt"},
        ):
            rc, output = invoke([
                "smoke_second_turn", "--vendor", vendor_name,
                "--worker-bin", str(worker), "--no-cache",
            ])
        log = stub_log(stub_dir)
        check(
            f"{vendor_name} a failed first turn sends no second",
            rc != 0 and len(log) == 1,
            output,
        )


def case_failed_preflight() -> None:
    print("failed resume pre-flight")
    with tempfile.TemporaryDirectory() as td:
        root = pathlib.Path(td)
        worker, stub_dir = make_worker(root)
        queue(stub_dir, 1, json.dumps(
            {"type": "result", "result": "stub reply", "session_id": "s1"}
        ))
        specs = real_specs()
        workspace = root / "workspace"
        with patched(
            {
                "smoke_second_turn": specs["smoke_second_turn"],
                "smoke_inline_body": specs["smoke_inline_body"],
            },
            workspace, stub_dir,
            resume=(False, "stub pre-flight failure"),
            grade=passing_grade(root),
        ):
            rc, output = invoke([
                "smoke_second_turn", "smoke_inline_body",
                "--worker-bin", str(worker), "--no-cache",
            ])
        check("a failed pre-flight fails the run", rc != 0)
        check(
            "the failed two-turn eval names the pre-flight and the vendor",
            "resume pre-flight failed for cursor" in output,
        )
        check(
            "the one-turn eval in the same run still runs",
            len(stub_log(stub_dir)) == 1 and "smoke_inline_body] PASS" in output,
        )
        stderr = (
            latest_run(workspace) / "smoke_second_turn" / "stderr.txt"
        ).read_text()
        check(
            "the failed two-turn eval records the pre-flight message",
            "stub pre-flight failure" in stderr,
        )


def case_staged_agents(vendor_name: str) -> None:
    print(f"staged agents ({vendor_name})")
    with tempfile.TemporaryDirectory() as td:
        root = pathlib.Path(td)
        worker, stub_dir = make_worker(root)
        queue(stub_dir, 1, json.dumps(
            {"type": "result", "result": "stub reply", "session_id": "s1"}
        ))
        specs = real_specs()
        spec = specs["smoke_staged_agent"]
        spec["harness"]["agents"].append(
            "plugins/knowledge_management/agents/auto_shaper_wiki.md"
        )
        workspace = root / "workspace"
        deploy_calls: list[list[str]] = []
        real_deploy = run.micro_deploy._run_deploy

        def recording_deploy(*, args, home, log_path):
            deploy_calls.append(list(args))
            return real_deploy(args=args, home=home, log_path=log_path)

        run.micro_deploy._run_deploy = recording_deploy
        try:
            with patched(
                {"smoke_staged_agent": spec}, workspace, stub_dir,
                grade=passing_grade(root),
            ):
                rc, output = invoke([
                    "smoke_staged_agent", "--vendor", vendor_name,
                    "--worker-bin", str(worker), "--no-cache",
                ])
        finally:
            run.micro_deploy._run_deploy = real_deploy
        check(f"{vendor_name} staged-agent run exits 0", rc == 0, output)
        eval_dir = latest_run(workspace) / "smoke_staged_agent"
        sandbox = eval_dir / "sandbox"
        proj = sandbox / "proj"
        if vendor_name == "claude":
            staged_agent = proj / ".claude" / "agents" / "smoke_replier.md"
        else:
            staged_agent = proj / ".cursor" / "agents" / "smoke_replier.md"
        check(
            f"{vendor_name} fixture agent lands in the project agent directory",
            staged_agent.is_file(),
        )
        log = stub_log(stub_dir)
        if vendor_name == "claude":
            check(
                "claude plugin role lands in the scratch configuration directory",
                bool(log) and "auto_shaper_wiki" in log[0]["config_agents"],
            )
        else:
            check(
                "cursor plugin role lands in the project agent directory",
                bool(log) and "auto_shaper_wiki" in log[0]["project_agents"],
            )
        check(
            f"{vendor_name} plugin role joins the deploy --only list",
            any("auto_shaper_wiki" in ",".join(call) for call in deploy_calls),
        )
        inventory = (sandbox / ".tree_sha256").read_text()
        check(
            f"{vendor_name} .tree_sha256 lists the fixture agent",
            "./" + staged_agent.relative_to(proj).as_posix() in inventory,
        )
        if vendor_name == "cursor":
            check(
                "cursor .tree_sha256 lists the plugin role",
                "./.cursor/agents/auto_shaper_wiki.md" in inventory,
            )
        check(
            f"{vendor_name} sandbox starts with a clean git status",
            bool(log) and log[0]["git_status"] == "",
            log[0]["git_status"] if log else "no log",
        )
        before = subprocess.run(
            ["bash", str(run.GRADE), "probe_definitions_no_spawn", str(proj)],
            capture_output=True, text=True,
        )
        check(
            f"{vendor_name} tree_unchanged passes before an edit",
            "PASS  sandbox tree byte-identical" in before.stdout,
        )
        staged_agent.write_text(staged_agent.read_text() + "\nedited\n")
        after = subprocess.run(
            ["bash", str(run.GRADE), "probe_definitions_no_spawn", str(proj)],
            capture_output=True, text=True,
        )
        check(
            f"{vendor_name} tree_unchanged fails once a staged file is edited",
            "FAIL  sandbox tree byte-identical" in after.stdout,
        )
        timing = json.loads((eval_dir / "timing.json").read_text())
        check(
            f"{vendor_name} timing names both staged agents",
            timing["staged_agents"] == ["smoke_replier", "auto_shaper_wiki"],
        )
        roots = [path.resolve() for path in run.source_roots_for(spec["harness"])]
        check(
            f"{vendor_name} source_roots_for covers the fixture agent directory",
            (THIS / "fixtures/smoke_staged_agent/agents").resolve() in roots,
        )
        check(
            f"{vendor_name} source_roots_for covers the plugin role",
            (
                REPO_ROOT
                / "plugins/knowledge_management/agents/auto_shaper_wiki.md"
            ).resolve() in roots,
        )


def case_withheld(vendor_name: str) -> None:
    print(f"withheld tools ({vendor_name})")
    with tempfile.TemporaryDirectory() as td:
        root = pathlib.Path(td)
        worker, stub_dir = make_worker(root)
        for index in (1, 2):
            queue(stub_dir, index, json.dumps(
                {"type": "result", "result": "stub reply", "session_id": "s1"}
            ))
        specs = real_specs()
        workspace = root / "workspace"
        with patched(
            {
                "smoke_withheld_shell": specs["smoke_withheld_shell"],
                "smoke_withheld_write": specs["smoke_withheld_write"],
            },
            workspace, stub_dir,
            grade=passing_grade(root),
        ):
            rc, output = invoke([
                "smoke_withheld_shell", "smoke_withheld_write",
                "--vendor", vendor_name,
                "--worker-bin", str(worker), "--no-cache",
                # This case reads the stub log by position, so serialize the
                # two ids to keep each tool class on its own record.
                "--workers", "1",
            ])
        check(f"{vendor_name} withheld run exits 0", rc == 0, output)
        log = stub_log(stub_dir)
        check(f"{vendor_name} withheld run makes two calls", len(log) == 2)
        for index, tool_class, names, mechanism, deny in (
            (0, "shell", ["Bash"], "cli-flag", "Shell(*)"),
            (1, "write", ["Edit", "Write", "NotebookEdit"], "cli-flag", "Write(**)"),
        ):
            if vendor_name == "claude":
                argv = log[index]["argv"] if index < len(log) else []
                flag_at = argv.index("--disallowedTools") if "--disallowedTools" in argv else -1
                check(
                    f"claude {tool_class} arrives as --disallowedTools with the table's names",
                    flag_at >= 0
                    and all(name in argv for name in names),
                )
                check(
                    f"claude {tool_class} prompt sits before the flag",
                    flag_at > 1 and argv[1] != "--permission-mode",
                )
                check(
                    f"claude {tool_class} prompt carries no declared-absence note",
                    run.DECLARED_ABSENCE_NOTE not in argv[1],
                )
            else:
                cli = (
                    latest_run(workspace) / "smoke_withheld_shell"
                    if tool_class == "shell"
                    else latest_run(workspace) / "smoke_withheld_write"
                ) / "sandbox" / "proj" / ".cursor" / "cli.json"
                check(
                    f"cursor {tool_class} deny entry lands in the project config",
                    cli.is_file() and deny in cli.read_text(),
                )
                check(
                    f"cursor {tool_class} call keeps --force and --sandbox disabled",
                    "--force" in log[index]["argv"]
                    and "--sandbox" in log[index]["argv"]
                    and log[index]["argv"][log[index]["argv"].index("--sandbox") + 1]
                    == "disabled",
                )
                check(
                    f"cursor {tool_class} sandbox starts with a clean git status",
                    index < len(log) and log[index]["git_status"] == "",
                    log[index]["git_status"] if index < len(log) else "no log",
                )
                check(
                    f"cursor {tool_class} prompt carries no declared-absence note",
                    run.DECLARED_ABSENCE_NOTE not in log[index]["argv"][-1],
                )
        for eval_id, tool_class, mechanism in (
            ("smoke_withheld_shell", "shell",
             "cli-flag" if vendor_name == "claude" else "cli-config"),
            ("smoke_withheld_write", "write",
             "cli-flag" if vendor_name == "claude" else "cli-config"),
        ):
            eval_dir = latest_run(workspace) / eval_id
            timing = json.loads((eval_dir / "timing.json").read_text())
            check(
                f"{vendor_name} {tool_class} timing records {mechanism}",
                timing["withheld_by"].get(tool_class) == mechanism,
            )
            check(
                f"{vendor_name} status lines name {tool_class}:{mechanism}",
                f"{tool_class}:{mechanism}" in output,
            )
            if vendor_name == "cursor":
                inventory = (eval_dir / "sandbox" / ".tree_sha256").read_text()
                check(
                    f"cursor {tool_class} inventory lists the deny file",
                    "./.cursor/cli.json" in inventory,
                )


def case_withheld_second_turn(vendor_name: str) -> None:
    print(f"withheld tools across two turns ({vendor_name})")
    with tempfile.TemporaryDirectory() as td:
        root = pathlib.Path(td)
        worker, stub_dir = make_worker(root)
        queue(stub_dir, 1, stream_for(
            vendor_name, read="__CWD__/README.txt", session="first-session",
            final="first reply",
        ))
        queue(stub_dir, 2, stream_for(
            vendor_name, read="__CWD__/second_token.txt", session="second-session",
            final="second reply",
        ))
        spec = real_specs()["smoke_second_turn"]
        spec["harness"]["disallowed_tools"] = ["shell", "write"]
        workspace = root / "workspace"
        with patched(
            {"smoke_second_turn": spec}, workspace, stub_dir,
            grade=passing_grade(root),
            extra_env={"STUB_MARKER_NAME": "second_token.txt"},
        ):
            rc, output = invoke([
                "smoke_second_turn", "--vendor", vendor_name,
                "--worker-bin", str(worker), "--no-cache",
            ])
        check(f"{vendor_name} two-turn withheld run exits 0", rc == 0, output)
        log = stub_log(stub_dir)
        check(
            f"{vendor_name} two-turn withheld run makes two calls",
            len(log) == 2,
            str(len(log)),
        )
        names = ["Bash", "Edit", "Write", "NotebookEdit"]
        for index in range(min(2, len(log))):
            argv = log[index]["argv"]
            if vendor_name == "claude":
                flag_at = (
                    argv.index("--disallowedTools")
                    if "--disallowedTools" in argv else -1
                )
                check(
                    f"claude turn {index + 1} withholds shell and write by flag",
                    flag_at >= 0 and all(name in argv for name in names),
                )
                check(
                    f"claude turn {index + 1} places the prompt before the flag",
                    flag_at > 1 and argv[1] != "--permission-mode",
                )
            else:
                cli = (
                    latest_run(workspace) / "smoke_second_turn" / "sandbox"
                    / "proj" / ".cursor" / "cli.json"
                )
                check(
                    f"cursor turn {index + 1} runs under the deny config",
                    cli.is_file()
                    and "Shell(*)" in cli.read_text()
                    and "Write(**)" in cli.read_text(),
                )
                check(
                    f"cursor turn {index + 1} keeps --force and --sandbox disabled",
                    "--force" in argv
                    and "--sandbox" in argv
                    and argv[argv.index("--sandbox") + 1] == "disabled",
                )


def case_spawn_declared(vendor_name: str) -> None:
    print(f"declared spawn absence ({vendor_name})")
    with tempfile.TemporaryDirectory() as td:
        root = pathlib.Path(td)
        worker, stub_dir = make_worker(root)
        queue(stub_dir, 1, json.dumps(
            {"type": "result", "result": "stub reply", "session_id": "s1"}
        ))
        spec = real_specs()["probe_definitions_no_spawn"]
        workspace = root / "workspace"
        with patched(
            {"probe_definitions_no_spawn": spec}, workspace, stub_dir,
            grade=passing_grade(root),
        ):
            rc, output = invoke([
                "probe_definitions_no_spawn", "--vendor", vendor_name,
                "--worker-bin", str(worker), "--no-cache",
            ])
        check(f"{vendor_name} declared-spawn run exits 0", rc == 0, output)
        log = stub_log(stub_dir)
        prompt = log[0]["argv"][-1] if log else ""
        check(
            f"{vendor_name} prompt carries the declared-absence note",
            run.DECLARED_ABSENCE_NOTE in prompt,
        )
        if vendor_name == "claude":
            check(
                "claude spawn carries no --disallowedTools",
                "--disallowedTools" not in log[0]["argv"],
            )
        else:
            cli = (
                latest_run(workspace) / "probe_definitions_no_spawn"
                / "sandbox" / "proj" / ".cursor" / "cli.json"
            )
            check(
                "cursor spawn carries no deny entry",
                not cli.exists(),
            )
        timing = json.loads(
            (latest_run(workspace) / "probe_definitions_no_spawn" / "timing.json")
            .read_text()
        )
        check(
            f"{vendor_name} timing records declared-absence",
            timing["withheld_by"] == {"spawn": "declared-absence"},
        )
        check(
            f"{vendor_name} verdict line names the declaration and no vendor command",
            any(
                "probe_definitions_no_spawn] PASS" in line
                and "spawn:declared-absence" in line
                and run.ABSENCE_SUFFIX in line
                and "claude -p" not in line
                and "agent -p" not in line
                for line in output.splitlines()
            ),
            output,
        )
        check(
            f"{vendor_name} run summary lists the declared-absence eval",
            "Declared-absence evals" in output
            and "probe_definitions_no_spawn" in output.split("Declared-absence evals")[-1],
        )
        return output.splitlines()


def case_cache_key() -> None:
    print("cache key")
    shell_before = vendor.withheld_tool_plan("claude", ["shell"])
    none_before = vendor.withheld_tool_plan("claude", [])
    shell_key_before = eval_cache.content_key(
        source_roots=[], harness_dir=run.THIS, model="auto",
        eval_id="smoke_shell",
        prompt=run.cache_prompt_value("prompt", shell_before, "v1", "smoke_shell"),
    )
    none_key_before = eval_cache.content_key(
        source_roots=[], harness_dir=run.THIS, model="auto",
        eval_id="no_withhold",
        prompt=run.cache_prompt_value("prompt", none_before, "v1", "no_withhold"),
    )
    original = vendor.WITHHELD_TOOL_CLASSES["shell"]["claude"]
    vendor.WITHHELD_TOOL_CLASSES["shell"]["claude"] = ("Bash", "Shell")
    try:
        shell_after = vendor.withheld_tool_plan("claude", ["shell"])
        none_after = vendor.withheld_tool_plan("claude", [])
        shell_key_after = eval_cache.content_key(
            source_roots=[], harness_dir=run.THIS, model="auto",
            eval_id="smoke_shell",
            prompt=run.cache_prompt_value("prompt", shell_after, "v1", "smoke_shell"),
        )
        none_key_after = eval_cache.content_key(
            source_roots=[], harness_dir=run.THIS, model="auto",
            eval_id="no_withhold",
            prompt=run.cache_prompt_value("prompt", none_after, "v1", "no_withhold"),
        )
    finally:
        vendor.WITHHELD_TOOL_CLASSES["shell"]["claude"] = original
    check(
        "patching the withholding table moves a withholding eval's key",
        shell_key_before != shell_key_after,
    )
    check(
        "patching the withholding table leaves a no-withhold eval's key unchanged",
        none_key_before == none_key_after,
    )
    check(
        "a smoke eval's key moves with the worker version",
        run.cache_prompt_value("p", none_before, "v1", "smoke_x")
        != run.cache_prompt_value("p", none_before, "v2", "smoke_x"),
    )
    check(
        "an ordinary eval's key ignores the worker version",
        run.cache_prompt_value("p", none_before, "v1", "ordinary")
        == run.cache_prompt_value("p", none_before, "v2", "ordinary"),
    )


class FakeCache:
    def __init__(self, entry: dict):
        self.entry = entry
        self.lookups: list[tuple[str, str]] = []

    def lookup(self, eval_id: str, key: str):
        self.lookups.append((eval_id, key))
        return self.entry

    def record(self, *args, **kwargs) -> None:
        return None


def case_cache_hit() -> None:
    print("cache hit")
    with tempfile.TemporaryDirectory() as td:
        root = pathlib.Path(td)
        worker, stub_dir = make_worker(root)
        spec = real_specs()["probe_definitions_no_spawn"]
        workspace = root / "workspace"
        cache = FakeCache({
            "passed": True,
            "graded_at": "2026-01-01T00:00:00",
            "model": "auto",
            "duration_s": 1.0,
            "response_excerpt": "cached reply",
            "grading_output": "cached grade",
        })
        with patched(
            {"probe_definitions_no_spawn": spec}, workspace, stub_dir,
            grade=passing_grade(root), cache=cache,
        ):
            rc, output = invoke([
                "probe_definitions_no_spawn",
                "--worker-bin", str(worker),
            ])
        check("a cache hit exits 0", rc == 0, output)
        check("a cache hit makes no worker call", stub_log(stub_dir) == [])
        check(
            "the CACHED line names the class and the declaration",
            "CACHED PASS" in output
            and "spawn:declared-absence" in output
            and run.ABSENCE_SUFFIX in output,
        )
        check(
            "a cached declared-absence eval appears in the run summary",
            "Declared-absence evals" in output
            and "probe_definitions_no_spawn" in output.split("Declared-absence evals")[-1],
        )
        timing = json.loads(
            (latest_run(workspace) / "probe_definitions_no_spawn" / "timing.json")
            .read_text()
        )
        check(
            "a replayed timing.json records withheld_by",
            timing["withheld_by"] == {"spawn": "declared-absence"},
        )


def case_tool_record(vendor_name: str) -> None:
    print(f"tool record ({vendor_name})")
    with tempfile.TemporaryDirectory() as td:
        root = pathlib.Path(td)
        worker, stub_dir = make_worker(root)
        if vendor_name == "claude":
            stream = "\n".join([
                json.dumps({"type": "system", "subtype": "init", "session_id": "s1",
                            "tools": ["Read", "Task"]}),
                json.dumps({
                    "type": "assistant",
                    "message": {"content": [
                        {"type": "tool_use", "id": "t1", "name": "Task",
                         "input": {"subagent_type": "smoke_replier",
                                   "prompt": "Say your line"}}
                    ]},
                }),
                json.dumps({
                    "type": "user",
                    "message": {"content": [
                        {"type": "tool_result", "tool_use_id": "t1",
                         "content": "SMOKE_STAGED_TOKEN"}
                    ]},
                }),
                json.dumps({"type": "result", "result": "staged reply",
                            "session_id": "s1"}),
            ]) + "\n"
        else:
            stream = "\n".join([
                json.dumps({"type": "system", "subtype": "init", "session_id": "s1"}),
                json.dumps({
                    "type": "tool_call", "subtype": "completed",
                    "tool_call": {"taskToolCall": {
                        "args": {"subagentType": "smoke_replier",
                                 "prompt": "Say your line"},
                        "result": {"success": {"agentId": "helper"}},
                    }},
                }),
                json.dumps({"type": "result", "result": "staged reply",
                            "session_id": "s1"}),
            ]) + "\n"
        queue(stub_dir, 1, stream)
        spec = real_specs()["smoke_staged_agent"]
        workspace = root / "workspace"
        with patched(
            {"smoke_staged_agent": spec}, workspace, stub_dir,
            grade=passing_grade(root),
        ):
            rc, output = invoke([
                "smoke_staged_agent", "--vendor", vendor_name,
                "--worker-bin", str(worker), "--no-cache",
            ])
        check(f"{vendor_name} tool-record run exits 0", rc == 0, output)
        log = stub_log(stub_dir)
        check(
            f"{vendor_name} tool-record call requests stream-json",
            bool(log) and "--output-format" in log[0]["argv"]
            and log[0]["argv"][log[0]["argv"].index("--output-format") + 1]
            == "stream-json",
        )
        eval_dir = latest_run(workspace) / "smoke_staged_agent"
        records = [
            json.loads(line)
            for line in (eval_dir / "tool_calls.jsonl").read_text().splitlines()
            if line.strip()
        ]
        spawns = [
            record for record in records
            if record["type"] == "tool_call" and record["class"] == "spawn"
        ]
        check(
            f"{vendor_name} tool record holds one spawn tagged by turn",
            len(spawns) == 1
            and spawns[0]["turn"] == 1
            and spawns[0]["helper"] == "smoke_replier"
            and spawns[0]["failed"] is False,
        )
        offered = [record for record in records if record["type"] == "offered_tools"]
        check(
            f"{vendor_name} offered classes follow the vendor's stream",
            (len(offered) == 1 and "spawn" in offered[0]["classes"])
            if vendor_name == "claude" else offered == [],
        )
        check(
            f"{vendor_name} response.txt holds the stream's final message",
            (eval_dir / "response.txt").read_text() == "staged reply",
        )


def case_tool_record_stream_only() -> None:
    print("tool record keeps stream calls only")
    with tempfile.TemporaryDirectory() as td:
        root = pathlib.Path(td)
        worker, stub_dir = make_worker(root)
        stream = "\n".join([
            json.dumps({"type": "system", "subtype": "init", "session_id": "s1"}),
            json.dumps({
                "type": "tool_call", "subtype": "completed",
                "tool_call": {"taskToolCall": {
                    "args": {"subagentType": "smoke_replier", "prompt": "x"},
                    "result": {"success": {"agentId": "helper"}},
                }},
            }),
            json.dumps({"type": "result", "result": "staged reply",
                        "session_id": "s1"}),
        ]) + "\n"
        queue(stub_dir, 1, stream)
        spec = real_specs()["smoke_staged_agent"]
        workspace = root / "workspace"
        with patched(
            {"smoke_staged_agent": spec}, workspace, stub_dir,
            grade=passing_grade(root),
            extra_env={"STUB_HELPER_TRANSCRIPT": "1"},
        ):
            rc, output = invoke([
                "smoke_staged_agent", "--worker-bin", str(worker), "--no-cache",
            ])
        check("stream-only tool record run exits 0", rc == 0, output)
        eval_dir = latest_run(workspace) / "smoke_staged_agent"
        records = [
            json.loads(line)
            for line in (eval_dir / "tool_calls.jsonl").read_text().splitlines()
            if line.strip()
        ]
        calls = [record for record in records if record["type"] == "tool_call"]
        check(
            "tool_calls.jsonl holds only the stream's spawn call",
            len(calls) == 1 and calls[0]["class"] == "spawn",
        )
        timing = json.loads((eval_dir / "timing.json").read_text())
        paths = timing["artefacts_read_from_micro_deployment"]["paths"]
        check(
            "the helper transcript's call still reaches the read checks",
            any(path.endswith("README.txt") for path in paths),
            str(paths),
        )


def case_grade_cases() -> None:
    print("grade.sh smoke cases")
    with tempfile.TemporaryDirectory() as td:
        root = pathlib.Path(td)
        response_dir = root / "run"
        response_dir.mkdir()
        response = response_dir / "response.txt"
        response.write_text("reply\n")

        target = root / "staged"
        subprocess.run(
            ["bash", str(THIS / "fixtures/smoke_staged_agent/setup.sh"), str(target)],
            check=True, capture_output=True, text=True,
        )
        proj = target / "proj"
        (proj / "smoke.txt").write_text("SMOKE_STAGED_TOKEN\n")
        missing = subprocess.run(
            ["bash", str(run.GRADE), "smoke_staged_agent", str(proj), str(response)],
            capture_output=True, text=True,
        )
        check(
            "smoke_staged_agent fails when no spawn call names the agent",
            missing.returncode != 0
            and "FAIL  tool record holds a spawn call" in missing.stdout,
        )
        (response_dir / "tool_calls.jsonl").write_text(json.dumps({
            "turn": 1, "type": "tool_call", "class": "spawn",
            "name": "Task", "helper": "smoke_replier",
            "input": {"subagent_type": "smoke_replier"},
            "result": "SMOKE_STAGED_TOKEN", "failed": False,
        }) + "\n")
        present = subprocess.run(
            ["bash", str(run.GRADE), "smoke_staged_agent", str(proj), str(response)],
            capture_output=True, text=True,
        )
        check("smoke_staged_agent passes with the spawn call", present.returncode == 0)

        for eval_id, tool_class, marker in (
            ("smoke_withheld_shell", "shell", "smoke_shell_marker.txt"),
            ("smoke_withheld_write", "write", "smoke_write_marker.txt"),
        ):
            case_target = root / eval_id
            subprocess.run(
                ["bash", str(THIS / f"fixtures/{eval_id}/setup.sh"), str(case_target)],
                check=True, capture_output=True, text=True,
            )
            case_proj = case_target / "proj"
            case_run = root / f"{eval_id}-run"
            case_run.mkdir()
            case_response = case_run / "response.txt"
            case_response.write_text("reply\n")
            (case_run / "tool_calls.jsonl").write_text(json.dumps({
                "turn": 1, "type": "offered_tools",
                "classes": ["other", tool_class],
            }) + "\n")
            unverified = subprocess.run(
                ["bash", str(run.GRADE), eval_id, str(case_proj), str(case_response)],
                capture_output=True, text=True,
            )
            check(
                f"{eval_id} fails when the class stays offered with no attempt",
                unverified.returncode != 0
                and "FAIL  " + tool_class + " class withheld or every attempt failed"
                in unverified.stdout,
            )
            (case_run / "tool_calls.jsonl").write_text(json.dumps({
                "turn": 1, "type": "tool_call", "class": tool_class,
                "name": tool_class + "ToolCall", "input": {},
                "result": "permissionDenied", "failed": True,
            }) + "\n")
            failed_attempt = subprocess.run(
                ["bash", str(run.GRADE), eval_id, str(case_proj), str(case_response)],
                capture_output=True, text=True,
            )
            check(
                f"{eval_id} passes when every attempt through the class failed",
                failed_attempt.returncode == 0,
            )
            check(
                f"{eval_id} marker stays absent",
                not (case_proj / marker).exists(),
            )


def case_same_verdict() -> None:
    print("same verdict on both vendors")
    verdicts = {}
    for vendor_name in ("claude", "cursor"):
        with tempfile.TemporaryDirectory() as td:
            root = pathlib.Path(td)
            worker, stub_dir = make_worker(root)
            queue(stub_dir, 1, json.dumps(
                {"type": "result", "result": "stub reply", "session_id": "s1"}
            ))
            spec = real_specs()["smoke_inline_body"]
            workspace = root / "workspace"
            with patched(
                {"smoke_inline_body": spec}, workspace, stub_dir,
                extra_env={"STUB_WRITE_SMOKE": "1"},
            ):
                rc, output = invoke([
                    "smoke_inline_body", "--vendor", vendor_name,
                    "--worker-bin", str(worker), "--no-cache",
                ])
            verdicts[vendor_name] = rc
            check(
                f"{vendor_name} stub run grades the same verdict",
                rc == 0 and "smoke_inline_body] PASS" in output,
                output,
            )
    check(
        "one stub reply grades to the same verdict under both vendors",
        verdicts == {"claude": 0, "cursor": 0},
    )


def case_invalid_class() -> None:
    print("invalid withheld class")
    with tempfile.TemporaryDirectory() as td:
        root = pathlib.Path(td)
        worker, stub_dir = make_worker(root)
        specs = real_specs()
        spec = specs["diagnostic_inline"]
        spec["harness"]["disallowed_tools"] = ["Task"]
        workspace = root / "workspace"
        with patched({"diagnostic_inline": spec}, workspace, stub_dir):
            rc, output = invoke([
                "diagnostic_inline", "--worker-bin", str(worker), "--no-cache",
            ])
        check("an unknown withheld class stops the run", rc == 2)
        check(
            "the error names the eval and the class",
            "diagnostic_inline" in output and "unknown withheld tool class" in output,
        )
        check("the run stops before any worker call", stub_log(stub_dir) == [])
        check("the run stops before staging", not workspace.exists())


def case_no_mode() -> None:
    print("no mode key")
    with tempfile.TemporaryDirectory() as td:
        root = pathlib.Path(td)
        worker, stub_dir = make_worker(root)
        queue(stub_dir, 1, json.dumps(
            {"type": "result", "result": "stub reply", "session_id": "s1"}
        ))
        spec = real_specs()["diagnostic_inline"]
        workspace = root / "workspace"
        with patched(
            {"diagnostic_inline": spec}, workspace, stub_dir,
            grade=passing_grade(root),
        ):
            rc, output = invoke([
                "diagnostic_inline", "--worker-bin", str(worker), "--no-cache",
            ])
        check("a no-mode eval exits 0", rc == 0, output)
        log = stub_log(stub_dir)
        check("a no-mode eval makes one call", len(log) == 1)
        prompt = log[0]["argv"][-1] if log else ""
        check(
            "a no-mode eval keeps today's worker prompt",
            prompt.startswith("You are running an automated skill regression eval.")
            and "1. Read the skill definition file in full:" in prompt
            and "2. Read its references/ directory" in prompt
            and run.ATTACHMENT_NOTE not in prompt,
        )
        check(
            "a no-mode eval passes no withheld flag",
            "--disallowedTools" not in log[0]["argv"],
        )
        timing = json.loads(
            (latest_run(workspace) / "diagnostic_inline" / "timing.json").read_text()
        )
        check(
            "a no-mode eval records no mode and no withholding",
            timing["modes"] == {
                "inline_body": False, "second_turn": False,
                "tool_record": False, "agents": [],
            }
            and timing["withheld_by"] == {},
        )


def case_eval_vendor_export() -> None:
    print("EVAL_VENDOR export")
    for vendor_name in ("claude", "cursor"):
        with tempfile.TemporaryDirectory() as td:
            root = pathlib.Path(td)
            worker, stub_dir = make_worker(root)
            queue(stub_dir, 1, json.dumps(
                {"type": "result", "result": "stub reply", "session_id": "s1"}
            ))
            grade_log = root / "grade.log"
            grade = root / "grade-env.sh"
            grade.write_text(
                "#!/usr/bin/env bash\n"
                "printf '%s\\n' \"${EVAL_VENDOR:-}\" >> \"$GRADE_LOG\"\n"
                "exit 0\n"
            )
            grade.chmod(0o755)
            spec = real_specs()["smoke_inline_body"]
            workspace = root / "workspace"
            with patched(
                {"smoke_inline_body": spec}, workspace, stub_dir,
                grade=grade, extra_env={"GRADE_LOG": str(grade_log)},
            ):
                rc, output = invoke([
                    "smoke_inline_body", "--vendor", vendor_name,
                    "--worker-bin", str(worker), "--no-cache",
                ])
            check(
                f"run_one exports EVAL_VENDOR={vendor_name} to grade.sh",
                rc == 0 and grade_log.read_text().strip() == vendor_name,
                output,
            )


def case_default_ids() -> None:
    print("default run set and worker count")
    with tempfile.TemporaryDirectory() as td:
        root = pathlib.Path(td)
        worker, stub_dir = make_worker(root)
        workspace = root / "workspace"
        captured: dict = {}

        def fake_execute(specs, ids, **kwargs):
            captured["ids"] = list(ids)
            captured["workers"] = kwargs.get("workers")
            return [(eval_id, True, False) for eval_id in ids]

        saved_execute = run._execute
        run._execute = fake_execute
        try:
            with patched(real_specs(), workspace, stub_dir):
                rc, output = invoke(["--worker-bin", str(worker), "--no-cache"])
        finally:
            run._execute = saved_execute
        expected = eval_runner.load_eval_ids(run.EVALS)
        check(
            "a bare run takes every id in evals.json, in file order",
            captured.get("ids") == expected,
            str(captured.get("ids")),
        )
        check(
            "a bare run uses the default 4 workers",
            captured.get("workers") == vendor.DEFAULT_PARALLEL_WORKERS,
            str(captured.get("workers")),
        )
        check(
            "a bare run prints a graded summary over every id",
            f"graded: {len(expected)}/{len(expected)} evals passed" in output
            and all(f"  {eval_id}: PASS" in output for eval_id in expected),
            output,
        )
        summary = json.loads((latest_run(workspace) / "summary.json").read_text())
        check(
            "a bare run writes summary.json for every id",
            summary["total"] == len(expected)
            and set(summary["results"]) == set(expected),
        )


def case_parallel_tmpdir() -> None:
    print("per-job TMPDIR across two overlapping jobs")
    ids = ("phase_plan_announcement", "diagnostic_inline")
    with tempfile.TemporaryDirectory() as td:
        root = pathlib.Path(td)
        worker, stub_dir = make_worker(root)
        for index in (1, 2):
            queue(stub_dir, index, json.dumps(
                {"type": "result", "result": "stub reply", "session_id": "s1"}
            ))
        grade_log = root / "grade.log"
        specs = {eval_id: real_specs()[eval_id] for eval_id in ids}
        workspace = root / "workspace"
        with patched(
            specs, workspace, stub_dir,
            grade=logging_grade(root),
            stage=fake_stage(),
            extra_env={"GRADE_LOG": str(grade_log), "STUB_SLEEP": "1"},
        ):
            rc, output = invoke([
                *ids, "--worker-bin", str(worker), "--no-cache",
                "--workers", "2",
            ])
        check("the two-job parallel run exits 0", rc == 0, output)
        log = stub_log(stub_dir)
        check(
            "the parallel run makes two worker calls",
            len(log) == 2,
            str(len(log)),
        )
        windows = sorted(
            (entry["started_at"], entry["ended_at"]) for entry in log
        )
        check(
            "the two worker windows overlap",
            len(windows) == 2 and windows[0][1] > windows[1][0],
            str(windows),
        )
        worker_tmp = {entry["eval_marker"]: entry["tmpdir"] for entry in log}
        grade_tmp = {}
        for line in grade_log.read_text().splitlines():
            eval_id, _, tmpdir = line.partition(" ")
            grade_tmp[eval_id] = tmpdir
        check(
            "each job carries its own eval marker",
            set(worker_tmp) == set(ids),
            str(worker_tmp),
        )
        check(
            "the two jobs get distinct worker TMPDIRs",
            len(set(worker_tmp.values())) == 2,
            str(worker_tmp),
        )
        check(
            "each job's grade env carries the same TMPDIR as its worker env",
            worker_tmp == grade_tmp,
            f"{worker_tmp} != {grade_tmp}",
        )


def case_escape_guard() -> None:
    print("owned-name host escape guard")
    ids = ("phase_plan_announcement", "diagnostic_inline")
    canary = "escape_canary.txt"
    with tempfile.TemporaryDirectory() as td:
        root = pathlib.Path(td)
        worker, stub_dir = make_worker(root)
        for index in (1, 2):
            queue(stub_dir, index, json.dumps(
                {"type": "result", "result": "stub reply", "session_id": "s1"}
            ))
        mirror = host_mirror(root)
        specs = {eval_id: real_specs()[eval_id] for eval_id in ids}
        workspace = root / "workspace"
        saved_repo = run.REPO_ROOT
        run.REPO_ROOT = mirror
        try:
            with patched(
                specs, workspace, stub_dir,
                grade=passing_grade(root),
                stage=fake_stage(
                    lambda eval_id: {canary: "own name\n"}
                    if eval_id == ids[0] else {}
                ),
                extra_env={
                    "STUB_ESCAPE_NAME": canary,
                    "STUB_HOST_ROOT": str(mirror),
                    "STUB_SLEEP": "1",
                },
            ):
                rc, output = invoke([
                    *ids, "--worker-bin", str(worker), "--no-cache",
                    "--workers", "2",
                ])
        finally:
            run.REPO_ROOT = saved_repo
        log = stub_log(stub_dir)
        windows = sorted(
            (entry["started_at"], entry["ended_at"]) for entry in log
        )
        check(
            "the escaping run made two overlapping worker calls",
            len(windows) == 2 and windows[0][1] > windows[1][0],
            str(windows),
        )
        check("the host mirror gained the canary", (mirror / canary).is_file())
        check("an escaped eval fails the run", rc == 1, output)
        check(
            "only the eval whose sandbox owns the canary fails",
            f"[{ids[0]}] FAIL" in output
            and f"[{ids[1]}] PASS" in output
            and f"[{ids[1]}] FAIL" not in output,
            output,
        )
        check(
            "the escape message names the owned path and the sandbox escape",
            canary in output and "sandbox escape" in output,
            output,
        )
        summary = json.loads(
            (latest_run(workspace) / "summary.json").read_text()
        )
        check(
            "summary.json records only the escaping eval as failed",
            summary["results"][ids[0]]["passed"] is False
            and summary["results"][ids[1]]["passed"] is True,
            json.dumps(summary["results"]),
        )


def main() -> int:
    print("test_run")
    case_inline_body()
    for vendor_name in ("claude", "cursor"):
        case_second_turn(vendor_name)
    case_failed_preflight()
    for vendor_name in ("claude", "cursor"):
        case_staged_agents(vendor_name)
    for vendor_name in ("claude", "cursor"):
        case_withheld(vendor_name)
    for vendor_name in ("claude", "cursor"):
        case_withheld_second_turn(vendor_name)
    lines = case_spawn_declared("claude")
    other_lines = case_spawn_declared("cursor")
    claude_verdict = next(
        (line for line in lines if "probe_definitions_no_spawn] PASS" in line), ""
    )
    cursor_verdict = next(
        (line for line in other_lines if "probe_definitions_no_spawn] PASS" in line), ""
    )
    check(
        "the declared-absence verdict line reads the same on both vendors",
        bool(claude_verdict) and claude_verdict == cursor_verdict,
    )
    case_cache_key()
    case_cache_hit()
    for vendor_name in ("claude", "cursor"):
        case_tool_record(vendor_name)
    case_tool_record_stream_only()
    case_grade_cases()
    case_same_verdict()
    case_invalid_class()
    case_no_mode()
    case_eval_vendor_export()
    case_default_ids()
    case_parallel_tmpdir()
    case_escape_guard()
    print(f"\n{PASS} passed, {FAIL} failed")
    return 0 if FAIL == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
