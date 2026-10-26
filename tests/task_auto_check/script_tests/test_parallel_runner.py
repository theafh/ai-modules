#!/usr/bin/env python3
"""Static checks for the task_auto_check parallel runner.

Proves --workers defaults to 4, default ids come from load_eval_ids, the
serial nested-loop set is the Approach set and the one list in each guide,
micro-deploy stays inside the job, grade.sh fails when a staged fixture name
in a temporary host copy is newer than the eval marker, and stage() raises on
a failed or empty stage.
"""

from __future__ import annotations

import ast
import importlib.util
import os
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile
import time

REPO = pathlib.Path(__file__).resolve().parents[3]
RUN_PY = REPO / "tests" / "task_auto_check" / "evals" / "run.py"
LIB = REPO / "tests" / "lib"

SERIAL = (
    "repair_to_ready",
    "relay_by_path",
    "stray_hunk_reverted",
    "guard_rebaseline_after_gate",
    "interaction_scan_surfaces",
    "immediate_ready_citations_overturn",
    "regroup_via_reviewer",
    "regroup_immediate_ready",
    "regroup_same_paragraph_ready",
    "committed_rule_deletion_routed",
    "last_call_ready_refuted",
    "regate_isolated",
    "dryrun_gap_confirmed",
)

DOC_LISTS = (
    REPO / "tests" / "CLAUDE.md",
    REPO / "tests" / "AGENTS.md",
    REPO / "tests" / "task_auto_check" / "RUNBOOK.md",
)

FAILURES: list[str] = []


def check(label: str, ok: bool) -> None:
    if ok:
        print(f"  PASS  {label}")
        return
    FAILURES.append(label)
    print(f"  FAIL  {label}")


def load_run():
    sys.path.insert(0, str(LIB))
    spec = importlib.util.spec_from_file_location("task_auto_check_run", RUN_PY)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load {RUN_PY}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_help() -> None:
    result = subprocess.run(
        [sys.executable, str(RUN_PY), "--help"],
        capture_output=True,
        text=True,
        check=False,
    )
    text = result.stdout + result.stderr
    check("run.py --help exits 0", result.returncode == 0)
    check("run.py --help shows --workers", "--workers" in text)
    check(
        "run.py --help defaults workers to 4",
        re.search(r"--workers\b.*\(default:\s*4\)", text, re.S) is not None,
    )


def test_ids_and_split(module) -> None:
    import eval_runner

    loaded = eval_runner.load_eval_ids(
        REPO / "tests" / "task_auto_check" / "evals" / "evals.json"
    )
    check("DEFAULT_IDS is load_eval_ids output", module.DEFAULT_IDS == loaded)
    check(
        "serial nested-loop set matches the Approach set",
        module.SERIAL_NESTED_LOOP_IDS == SERIAL,
    )
    missing = [eval_id for eval_id in SERIAL if eval_id not in loaded]
    check("every serial id is in evals.json", missing == [])
    isolated, serial = module.partition_ids(loaded)
    serial_members = set(SERIAL)
    check(
        "partition keeps file order and covers every id",
        isolated == [item for item in loaded if item not in serial_members]
        and serial == [item for item in loaded if item in serial_members],
    )


def _ordered_serial_hits(text: str) -> int:
    ids = re.findall(r"`([A-Za-z0-9_]+)`", text)
    width = len(SERIAL)
    return sum(
        1
        for index in range(len(ids) - width + 1)
        if tuple(ids[index:index + width]) == SERIAL
    )


def test_docs_name_the_serial_set_once() -> None:
    for path in DOC_LISTS:
        hits = _ordered_serial_hits(path.read_text(encoding="utf-8"))
        check(f"{path.name} names the serial set once", hits == 1)


def _call_names(fn: ast.FunctionDef) -> set[str]:
    names: set[str] = set()
    for node in ast.walk(fn):
        if isinstance(node, ast.Call):
            func = node.func
            if isinstance(func, ast.Attribute):
                names.add(func.attr)
            elif isinstance(func, ast.Name):
                names.add(func.id)
    return names


def test_micro_deploy_inside_job() -> None:
    tree = ast.parse(RUN_PY.read_text(encoding="utf-8"))
    functions = {
        node.name: node
        for node in tree.body
        if isinstance(node, ast.FunctionDef)
    }
    run_one = functions["run_one"]
    main = functions["main"]
    execute = functions["_execute"]
    check("run_one calls micro_deploy", "micro_deploy" in _call_names(run_one))
    check(
        "run_one writes timing through write_run_artifacts",
        "write_run_artifacts" in _call_names(run_one),
    )
    source = ast.get_source_segment(RUN_PY.read_text(encoding="utf-8"), run_one)
    check("run_one records started_at", source is not None and "started_at" in source)
    check("run_one records ended_at", source is not None and "ended_at" in source)
    check("main does not call micro_deploy", "micro_deploy" not in _call_names(main))
    check("the pool runner calls run_jobs", "run_jobs" in _call_names(execute))
    check(
        "main does not call run_jobs around a single deployment",
        "run_jobs" not in _call_names(main),
    )


def _sandbox_basenames(target: pathlib.Path) -> list[str]:
    listing = target / ".sandbox_task_names"
    return [
        line.strip()
        for line in listing.read_text(encoding="utf-8").splitlines()
        if line.strip()
    ]


def _basename_exists(tasks: pathlib.Path, name: str) -> bool:
    if not tasks.is_dir():
        return False
    return any(path.name == name for path in tasks.rglob("*.md"))


def _tasks_signature(tasks: pathlib.Path) -> dict[str, tuple[int, int]]:
    signature: dict[str, tuple[int, int]] = {}
    if not tasks.is_dir():
        return signature
    for path in tasks.rglob("*"):
        if path.is_file():
            stat = path.stat()
            signature[path.relative_to(tasks).as_posix()] = (stat.st_mtime_ns, stat.st_size)
    return signature


def _host_mirror(root: pathlib.Path) -> pathlib.Path:
    """Repo-shaped temp tree whose tasks/ is a real directory, not the checkout."""
    mirror = root / "host"
    (mirror / "tests" / "task_auto_check").mkdir(parents=True)
    (mirror / "tests" / "lib").symlink_to(REPO / "tests" / "lib")
    (mirror / "tests" / "task_auto_check" / "evals").symlink_to(
        REPO / "tests" / "task_auto_check" / "evals"
    )
    (mirror / "plugins").symlink_to(REPO / "plugins")
    shutil.copytree(REPO / "tasks", mirror / "tasks", symlinks=True)
    return mirror


def test_grade_fails_newer_fixture() -> None:
    live_tasks = REPO / "tasks"
    before = _tasks_signature(live_tasks)
    with tempfile.TemporaryDirectory(prefix="tac_grade_") as tmp:
        root = pathlib.Path(tmp)
        target = root / "sandbox"
        target.mkdir()
        mirror = _host_mirror(root)
        stage_sh = mirror / "tests" / "task_auto_check" / "evals" / "stage.sh"
        grade_sh = mirror / "tests" / "task_auto_check" / "evals" / "grade.sh"
        staged = subprocess.run(
            ["bash", str(stage_sh), "mechanical_lint_ready", str(target)],
            capture_output=True,
            text=True,
            check=False,
        )
        check("stage.sh mechanical_lint_ready exits 0", staged.returncode == 0)
        if staged.returncode != 0:
            print(staged.stderr)
            return
        host_tasks = mirror / "tasks"
        names = _sandbox_basenames(target)
        chosen = next(
            (name for name in names if not _basename_exists(host_tasks, name)),
            "",
        )
        check("a staged fixture name is absent from the host copy", bool(chosen))
        if not chosen:
            return
        planted = host_tasks / chosen
        marker = target / ".eval_started_at"
        time.sleep(1.1)
        planted.write_text("escaped fixture\n", encoding="utf-8")
        newer = planted.stat().st_mtime > marker.stat().st_mtime
        check("planted fixture is newer than the eval marker", newer)
        graded = subprocess.run(
            ["bash", str(grade_sh), "mechanical_lint_ready", str(target / "proj")],
            capture_output=True,
            text=True,
            check=False,
            env=dict(os.environ),
        )
        blob = graded.stdout + graded.stderr
        check(
            "grade.sh fails the newer host fixture write",
            graded.returncode != 0
            and "FAIL  isolation: no writes to the real repo's tasks/ tree" in blob,
        )
    check("the checkout tasks tree is unchanged", _tasks_signature(live_tasks) == before)


def test_stage_guard() -> None:
    """stage() raises on a stage.sh that fails, and on one that exits 0
    without naming a sandbox project, before any worker could start."""
    result = subprocess.run(
        [sys.executable, str(LIB / "check_stage_guard.py"), str(RUN_PY.parent)],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        print(result.stdout + result.stderr)
    check("stage() raises on a failed or empty stage", result.returncode == 0)


def main() -> int:
    test_help()
    module = load_run()
    test_ids_and_split(module)
    test_docs_name_the_serial_set_once()
    test_micro_deploy_inside_job()
    test_grade_fails_newer_fixture()
    test_stage_guard()
    print(f"parallel runner checks: {len(FAILURES)} fail")
    return 1 if FAILURES else 0


if __name__ == "__main__":
    sys.exit(main())
