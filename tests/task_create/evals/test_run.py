#!/usr/bin/env python3
"""Unit tests for the task_create runner's parallel surface and host guard.

The runner moved onto `tests/lib/eval_runner`, so these checks pin the
parallel contract: `--workers` defaults to 4, ids come from `evals.json` in
file order, the run root is `tests/task_create/workspace`, `timing.json`
carries the fields the measurement reads, and `_execute` dispatches jobs
concurrently through `eval_runner.run_jobs`. One check proves the runner's
`stage()` raises on a failed or empty stage.

A hermetic host-guard case then runs two real jobs through
`tests/lib/eval_runner.run_jobs` against a temporary repo-shaped host mirror:
overlapping sandbox-only work leaves the mirror's `tasks/` tree untouched, and
a deliberately newer host file carrying one eval's sandbox fixture name fails
that eval's isolation check while the overlapping eval with other fixture
names stays PASS. The real `tasks/` tree is never written.

Run:

    python3 tests/task_create/evals/test_run.py
"""

from __future__ import annotations

import contextlib
import io
import json
import os
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile
import threading
import time
import types

import run as runner  # puts tests/lib on sys.path for the imports below
import eval_runner

THIS = pathlib.Path(__file__).resolve().parent
REPO = THIS.parents[2]
RESULTS = THIS.parent / "results"
PASS = 0
FAIL = 0

# The fields run_one writes into the shared timing record; the measurement and
# the provenance checks read every one of them.
TIMING_KEYS = (
    "eval_id",
    "started_at",
    "ended_at",
    "skill_name",
    "artefacts_read_from_micro_deployment",
    "checkout_unread",
    "duration_s",
    "worker_rc",
    "claude_rc",
    "model",
)

ISOLATION_PASS = "PASS  isolation: no writes to the real repo's tasks/ tree"
ISOLATION_FAIL = "FAIL  isolation: no writes to the real repo's tasks/ tree"

# Two evals whose fixtures stage quickly and whose sandboxes hold no live task
# files, so the hermetic case supplies each sandbox's own fixture name.
GUARD_EVAL_IDS = ("reconcile-recorded", "related-precedent-novel")


def check(label: str, condition: bool) -> None:
    global PASS, FAIL
    if condition:
        PASS += 1
        print(f"  ok   {label}")
    else:
        FAIL += 1
        print(f"  FAIL {label}")


def run_one_record() -> dict:
    """Run run_one with the worker, deployment, and grader stubbed.

    The stub replaces only what would call a model, so the code under test is
    run_one's own artefact and timing handling rather than a reading of
    run.py's source.
    """

    class Deploy:
        env: dict[str, str] = {}
        path_map = {"task_create": "/deployed/task_create/SKILL.md"}

    @contextlib.contextmanager
    def fake_deploy(*_args, **_kwargs):
        yield Deploy()

    def fake_stage(eval_id: str, target, env) -> dict[str, str]:
        root = pathlib.Path(target)
        proj = root / "proj"
        proj.mkdir(parents=True, exist_ok=True)
        return {
            "sandbox_proj": str(proj),
            "skill_name": "task_create",
            "skill_path": "/deployed/task_create/SKILL.md",
            "prompt": "probe",
        }

    worker = types.SimpleNamespace(returncode=0, stdout="probe response\n", stderr="")
    grade = subprocess.CompletedProcess([], 0, "grade ok\n", "")
    replacements = (
        (runner, "stage", fake_stage),
        (runner, "subprocess", types.SimpleNamespace(run=lambda *_a, **_k: grade)),
        (runner.micro_deploy, "micro_deploy", fake_deploy),
        (runner.micro_deploy, "run_worker", lambda **_kwargs: worker),
        (
            runner.micro_deploy,
            "provenance_records",
            lambda _worker: ({"status": "PASS"}, {"status": "PASS"}),
        ),
        (runner.micro_deploy, "read_checks_passed", lambda _integrity, _unread: True),
    )
    saved = [
        (module, name, getattr(module, name))
        for module, name, _value in replacements
    ]
    with tempfile.TemporaryDirectory(prefix="task_create_run_one_") as tmp:
        run_dir = pathlib.Path(tmp)
        try:
            for module, name, value in replacements:
                setattr(module, name, value)
            with contextlib.redirect_stdout(io.StringIO()):
                runner.run_one(
                    "query",
                    run_dir,
                    types.SimpleNamespace(
                        worker_model="probe",
                        vendor="cursor",
                        bin="agent",
                        config=types.SimpleNamespace(label="probe"),
                    ),
                    1,
                    None,
                    False,
                    {},
                )
        finally:
            for module, name, value in saved:
                setattr(module, name, value)

        return json.loads(
            (run_dir / "query" / "timing.json").read_text(encoding="utf-8")
        )


def pool_dispatch() -> tuple[list[tuple[str, bool, bool]], int]:
    """Run _execute with a stubbed run_one and report the threads it used."""
    threads: set[int] = set()
    lock = threading.Lock()

    def fake_run_one(eval_id, run_dir, resolved, timeout, cache, force, env):
        with lock:
            threads.add(threading.get_ident())
        time.sleep(0.05)
        return eval_id == "probe_a", False

    with tempfile.TemporaryDirectory(prefix="task_create_pool_") as tmp:
        saved = runner.run_one
        runner.run_one = fake_run_one
        try:
            rows = runner._execute(
                ["probe_a", "probe_b"],
                run_dir=pathlib.Path(tmp),
                resolved=types.SimpleNamespace(
                    worker_model="probe", vendor="cursor", bin="agent"
                ),
                timeout=1,
                cache=None,
                force=False,
                workers=2,
            )
        finally:
            runner.run_one = saved
    return rows, len(threads)


def runner_parallel_surface() -> None:
    """Check the Pattern A runner's workers, ids, workspace, and timing writer."""
    with open(THIS / "evals.json", encoding="utf-8") as fh:
        ids = [e["id"] for e in json.load(fh)["evals"]]

    help_run = subprocess.run(
        [sys.executable, str(THIS / "run.py"), "--help"],
        capture_output=True,
        text=True,
        check=False,
    )
    help_text = help_run.stdout + help_run.stderr
    check("run.py --help exits 0", help_run.returncode == 0)
    check("run.py --help shows --workers", "--workers" in help_text)
    check(
        "run.py --help defaults workers to 4",
        re.search(r"--workers\b.*\(default:\s*4\)", help_text, re.S) is not None,
    )
    check("DEFAULT_IDS is evals.json file order", runner.DEFAULT_IDS == ids)
    check(
        "the run root is tests/task_create/workspace",
        runner.WORKSPACE == runner.THIS.parent / "workspace",
    )
    check(
        "the run root is eval_runner's resolved workspace for this harness",
        runner.WORKSPACE == eval_runner.resolve_workspace(runner.THIS),
    )
    timing = run_one_record()
    check(
        "run_one's timing record carries every key the measurement reads",
        set(TIMING_KEYS) <= set(timing),
    )
    check(
        "run_one's timing record keeps started_at before ended_at",
        timing["started_at"] <= timing["ended_at"],
    )
    rows, pool_threads = pool_dispatch()
    check(
        "the pool dispatch runs run.py's jobs concurrently through "
        "eval_runner.run_jobs",
        rows == [("probe_a", True, False), ("probe_b", False, False)]
        and pool_threads == 2,
    )


def _host_mirror(root: pathlib.Path) -> pathlib.Path:
    """Repo-shaped temp tree whose tasks/ is a real directory, not the checkout."""
    mirror = root / "host"
    (mirror / "tests" / "task_create").mkdir(parents=True)
    (mirror / "tests" / "lib").symlink_to(REPO / "tests" / "lib")
    (mirror / "tests" / "task_create" / "evals").symlink_to(THIS)
    (mirror / "plugins").symlink_to(REPO / "plugins")
    shutil.copytree(REPO / "tasks", mirror / "tasks", symlinks=True)
    return mirror


def _tasks_signature(tasks: pathlib.Path) -> dict[str, tuple[int, int]]:
    signature: dict[str, tuple[int, int]] = {}
    if not tasks.is_dir():
        return signature
    for path in tasks.rglob("*"):
        if path.is_file():
            stat = path.stat()
            signature[path.relative_to(tasks).as_posix()] = (
                stat.st_mtime_ns,
                stat.st_size,
            )
    return signature


@contextlib.contextmanager
def _mirror_stage(mirror: pathlib.Path):
    """Point the runner's stage() at the mirror's stage.sh for the block."""
    old = runner.STAGE
    runner.STAGE = mirror / "tests" / "task_create" / "evals" / "stage.sh"
    try:
        yield
    finally:
        runner.STAGE = old


def _grade_isolation(
    mirror: pathlib.Path, eval_id: str, target: pathlib.Path, env
) -> tuple[bool, int, str]:
    """Run the mirror's real grade.sh and read its isolation verdict."""
    grade_env = dict(env)
    grade_env.pop("RESPONSE_FILE", None)
    graded = subprocess.run(
        [
            "bash",
            str(mirror / "tests" / "task_create" / "evals" / "grade.sh"),
            eval_id,
            str(target / "proj"),
        ],
        capture_output=True,
        text=True,
        check=False,
        env=grade_env,
    )
    blob = graded.stdout + graded.stderr
    return ISOLATION_PASS in blob, graded.returncode, blob


def _sandbox_only_write(staged: dict[str, str], eval_id: str) -> str:
    """Write a sandbox-local task, proving sandbox work stays inside its target.

    The basename is the eval's own fixture name: the guard records the
    sandbox's task names at grade time, so this is the name a host escape
    would have to carry to fail that eval.
    """
    name = f"sandbox-only-{eval_id}.md"
    tasks = pathlib.Path(staged["sandbox_proj"]) / "tasks"
    (tasks / name).write_text(
        "---\n"
        'description: "Sandbox-local proof task."\n'
        'scope: "sandbox proof"\n'
        "created: 2026-01-01T00:00:00\n"
        "updated: 2026-01-01T00:00:00\n"
        "status: open\n"
        "reported-by: Evals\n"
        "---\n\n"
        "# Sandbox-local proof\n",
        encoding="utf-8",
    )
    return name


def _overlap_clean_case(mirror: pathlib.Path) -> dict:
    """Two overlapping jobs with sandbox-only writes leave host tasks alone."""
    targets = {
        eval_id: pathlib.Path(tempfile.mkdtemp(prefix="task_create_guard_"))
        for eval_id in GUARD_EVAL_IDS
    }
    barrier = threading.Barrier(2, timeout=30)
    before = _tasks_signature(mirror / "tasks")

    def make_job(eval_id: str):
        def job(env):
            started = time.time()
            staged = runner.stage(eval_id, targets[eval_id], env)
            _sandbox_only_write(staged, eval_id)
            barrier.wait()
            isolation, rc, _blob = _grade_isolation(
                mirror, eval_id, targets[eval_id], env
            )
            return {
                "eval_id": eval_id,
                "started": started,
                "ended": time.time(),
                "isolation": isolation,
                "rc": rc,
            }

        return job

    def on_error(index: int, exc: Exception) -> dict:
        eval_id = GUARD_EVAL_IDS[index]
        return {
            "eval_id": eval_id,
            "started": None,
            "ended": None,
            "isolation": False,
            "rc": None,
            "error": str(exc),
        }

    with _mirror_stage(mirror):
        rows = eval_runner.run_jobs(
            [make_job(eval_id) for eval_id in GUARD_EVAL_IDS],
            workers=2,
            on_error=on_error,
        )
    after = _tasks_signature(mirror / "tasks")
    first, second = rows
    overlap = (
        first["started"] is not None
        and second["started"] is not None
        and first["started"] < second["ended"]
        and second["started"] < first["ended"]
    )
    for target in targets.values():
        shutil.rmtree(target, ignore_errors=True)
    return {
        "rows": rows,
        "overlap": overlap,
        "host_unchanged": before == after,
    }


def _overlap_planted_case(mirror: pathlib.Path) -> dict:
    """A newer host fixture name fails its eval; the overlapping eval stays PASS."""
    planted_name = f"sandbox-only-{GUARD_EVAL_IDS[0]}.md"
    targets = {
        eval_id: pathlib.Path(tempfile.mkdtemp(prefix="task_create_guard_"))
        for eval_id in GUARD_EVAL_IDS
    }
    staged_events = [threading.Event(), threading.Event()]
    release = threading.Event()
    planted_state: dict[str, object] = {}

    def planter() -> None:
        if not staged_events[0].wait(30) or not staged_events[1].wait(30):
            planted_state["error"] = "jobs did not stage in time"
            release.set()
            return
        marker = targets[GUARD_EVAL_IDS[0]] / ".eval_started_at"
        planted = mirror / "tasks" / planted_name
        planted.write_text("escaped fixture\n", encoding="utf-8")
        newer = marker.stat().st_mtime + 5
        os.utime(planted, (newer, newer))
        planted_state["newer"] = planted.stat().st_mtime > marker.stat().st_mtime
        release.set()

    planter_thread = threading.Thread(target=planter, daemon=True)
    planter_thread.start()

    def make_job(index: int, eval_id: str):
        def job(env):
            started = time.time()
            staged = runner.stage(eval_id, targets[eval_id], env)
            _sandbox_only_write(staged, eval_id)
            staged_events[index].set()
            if not release.wait(30):
                raise RuntimeError("the planted-file step did not release the jobs")
            isolation, rc, _blob = _grade_isolation(
                mirror, eval_id, targets[eval_id], env
            )
            return {
                "eval_id": eval_id,
                "started": started,
                "ended": time.time(),
                "isolation": isolation,
                "rc": rc,
            }

        return job

    def on_error(index: int, exc: Exception) -> dict:
        eval_id = GUARD_EVAL_IDS[index]
        return {
            "eval_id": eval_id,
            "started": None,
            "ended": None,
            "isolation": False,
            "rc": None,
            "error": str(exc),
        }

    with _mirror_stage(mirror):
        rows = eval_runner.run_jobs(
            [make_job(index, eval_id) for index, eval_id in enumerate(GUARD_EVAL_IDS)],
            workers=2,
            on_error=on_error,
        )
    planter_thread.join(timeout=5)
    first, second = rows
    overlap = (
        first["started"] is not None
        and second["started"] is not None
        and first["started"] < second["ended"]
        and second["started"] < first["ended"]
    )
    for target in targets.values():
        shutil.rmtree(target, ignore_errors=True)
    return {
        "rows": rows,
        "overlap": overlap,
        "planted_name": planted_name,
        "newer": bool(planted_state.get("newer")),
        "planter_error": planted_state.get("error"),
    }


def _verdict(row: dict) -> str:
    return "PASS" if row["isolation"] else "FAIL"


def _write_hermetic_record(clean: dict, planted: dict) -> None:
    RESULTS.mkdir(parents=True, exist_ok=True)
    rows = {row["eval_id"]: row for row in clean["rows"]}
    planted_rows = {row["eval_id"]: row for row in planted["rows"]}
    first, second = GUARD_EVAL_IDS
    text = f"""\
# Parallel-worker host guard: hermetic proof

Generated by `tests/task_create/evals/test_run.py`; no model call.

## Overlapping clean jobs

`{first}` and `{second}` ran concurrently through
`tests/lib/eval_runner.run_jobs` at 2 workers, each staged into its own target
and each writing its own sandbox-only task file inside its sandbox `tasks/`
tree. Their windows overlapped: {"yes" if clean["overlap"] else "no"}. The
temporary host mirror's `tasks/` signature was unchanged:
{"yes" if clean["host_unchanged"] else "no"}. `grade.sh`'s isolation check
stayed PASS for both evals: `{first}` {_verdict(rows[first])},
`{second}` {_verdict(rows[second])}.

## Planted newer fixture

After both jobs staged, the proof planted `tasks/{planted["planted_name"]}` in
the temporary host mirror with an mtime newer than `{first}`'s
`.eval_started_at` marker: {"yes" if planted["newer"] else "no"}. The `{first}`
eval's isolation check failed on its own fixture name:
{_verdict(planted_rows[first])}. The overlapping `{second}` eval, whose fixture
name omits that file, stayed {_verdict(planted_rows[second])}.

- Overlapping windows: {"yes" if planted["overlap"] else "no"}
- `{first}` isolation: {_verdict(planted_rows[first])}
- `{second}` isolation: {_verdict(planted_rows[second])}
"""
    (RESULTS / "run-parallel_workers_hermetic.md").write_text(
        text, encoding="utf-8"
    )


def hermetic_host_guard() -> None:
    """Prove overlapping jobs stay inside their sandboxes and the guard works."""
    with tempfile.TemporaryDirectory(prefix="task_create_guard_host_") as tmp:
        mirror = _host_mirror(pathlib.Path(tmp))
        clean = _overlap_clean_case(mirror)
        planted = _overlap_planted_case(mirror)

    check("two overlapping jobs overlap in wall clock", clean["overlap"])
    check(
        "two overlapping sandbox-only jobs leave host tasks/ untouched",
        clean["host_unchanged"],
    )
    check(
        "the clean overlapping jobs pass the isolation check",
        all(row["isolation"] for row in clean["rows"]),
    )
    check(
        "the clean overlapping jobs ran without a harness fault",
        all("error" not in row for row in clean["rows"]),
    )
    check("the planted-file jobs overlap in wall clock", planted["overlap"])
    check(
        "the planted-file jobs ran without a harness fault",
        all("error" not in row for row in planted["rows"])
        and planted["planter_error"] is None,
    )
    check(
        "the planted file is newer than the eval marker",
        planted["newer"],
    )
    check(
        "the planted fixture name fails its own eval's isolation check",
        not next(
            row for row in planted["rows"] if row["eval_id"] == GUARD_EVAL_IDS[0]
        )["isolation"],
    )
    check(
        "the overlapping eval with other fixture names stays PASS",
        next(
            row for row in planted["rows"] if row["eval_id"] == GUARD_EVAL_IDS[1]
        )["isolation"],
    )
    _write_hermetic_record(clean, planted)


def main() -> int:
    print("task_create evals: runner parallel surface")

    guard = subprocess.run(
        [sys.executable, str(THIS.parents[1] / "lib" / "check_stage_guard.py"), str(THIS)],
        capture_output=True,
        text=True,
    )
    if guard.returncode != 0:
        print(guard.stdout + guard.stderr)
    check("stage() raises on a failed or empty stage", guard.returncode == 0)

    runner_parallel_surface()
    hermetic_host_guard()

    print(f"\n{PASS} passed, {FAIL} failed")
    return 1 if FAIL else 0


if __name__ == "__main__":
    sys.exit(main())
