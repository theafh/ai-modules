#!/usr/bin/env python3
"""Unit tests for the task-family runner's declarations and parallel surface.

Some task evals grade their sandbox repository's whole `git status`: the
read-only ones through `git_tree_clean` in grade.sh, and `update_contract`
through an unscoped `git status --porcelain`. The micro-deployment writes
agents and styles into that sandbox project on at least one vendor, so every
such eval must declare neither. These checks read grade.sh for those evals,
check each one's declaration, and stage one of them for a real
micro-deployment per vendor, all without a model call. One more check proves
the runner's stage() raises on a failed or empty stage.

The parallel-runner checks prove `--workers` defaults to 4, the run root is
`tests/task/workspace`, the Approach serial nested-loop set is the one the
task names, and the runner writes the timing fields the measurement reads.
A hermetic host-guard case then runs two real jobs through
`tests/lib/eval_runner.run_jobs` against a temporary host mirror: overlapping
sandbox-only work leaves the host `tasks/` tree untouched, and a deliberately
newer host file carrying one eval's fixture name fails that eval's isolation
check while an overlapping eval with other fixture names stays PASS.

Run:

    python3 tests/task/evals/test_run.py
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
import micro_deploy

THIS = pathlib.Path(__file__).resolve().parent
REPO = THIS.parents[2]
RESULTS = THIS.parent / "results"
PASS = 0
FAIL = 0

SERIAL_NESTED_LOOP_IDS = (
    "auto_check_boundary",
    "fix_coherence_reconcile_escalated",
    "fix_coherence_reconcile_inline_staleness",
)

# The fields run_one adds to the shared timing record; the measurement and
# the provenance checks read every one of them.
TIMING_KEYS = (
    "started_at",
    "ended_at",
    "skill_name",
    "artefacts_read_from_micro_deployment",
    "checkout_unread",
)

# A grade.sh call that reads the whole sandbox status: `git_tree_clean`, or a
# `git status --porcelain` that names no pathspec.
WHOLE_TREE_CHECK_RE = re.compile(
    r"\bgit_tree_clean\b|status --porcelain(?=\s*(?:2>|\)|\\|$))"
)

ISOLATION_PASS = "PASS  isolation: no writes to the real repo's tasks/ tree"
ISOLATION_FAIL = "FAIL  isolation: no writes to the real repo's tasks/ tree"


def check(label: str, condition: bool) -> None:
    global PASS, FAIL
    if condition:
        PASS += 1
        print(f"  ok   {label}")
    else:
        FAIL += 1
        print(f"  FAIL {label}")


PARSER_SAMPLE = """\
case "$eval_id" in
  one|two)
    check "read-only" git_tree_clean
    ;;
  scoped)
    # names git_tree_clean only in a comment
    x="$(git -C "$proj" status --porcelain tasks/one.md)"
    ;;
  whole)
      changed="$(git -C "$proj" status --porcelain 2>/dev/null \\
                  | sort -u)"
    ;;
  *)
    ;;
esac
"""


def whole_tree_eval_ids(grade_sh: str) -> list[str]:
    """Eval ids whose grade.sh case grades the sandbox's whole git status."""
    ids: list[str] = []
    current: list[str] = []
    in_case = False
    for line in grade_sh.splitlines():
        if line.startswith('case "$eval_id" in'):
            in_case = True
            continue
        if not in_case:
            continue
        if line.startswith("esac"):
            break
        label = re.match(r"^  (\S+)\)\s*$", line)
        if label:
            current = [] if label.group(1) == "*" else label.group(1).split("|")
            continue
        if line.lstrip().startswith("#"):
            continue
        if WHOLE_TREE_CHECK_RE.search(line):
            ids.extend(i for i in current if i not in ids)
    return ids


def lands_in_sandbox_project(art_type: str) -> bool:
    """Whether the micro-deployment writes this type into the sandbox project."""
    scratch, project = pathlib.Path("/scratch"), pathlib.Path("/project")
    return any(
        project
        in micro_deploy._deployed_path(vendor, "x", art_type, scratch, project).parents
        for vendor in ("cursor", "claude")
    )


def project_scoped(names: list[str]) -> list[str]:
    """The declared names the micro-deployment writes into the sandbox project."""
    index = micro_deploy.discover_artefact_index()
    return [n for n in names if n in index and lands_in_sandbox_project(index[n][0])]


def git_status(project: pathlib.Path) -> str:
    return subprocess.run(
        ["git", "-C", str(project), "status", "--porcelain"],
        capture_output=True, text=True, check=True,
    ).stdout


def run_one_record() -> tuple[dict, bool]:
    """Run run_one with the worker, deployment, and grader stubbed.

    Returns the timing record it wrote and whether the staging-time marker
    kept its content and mtime. The stub replaces only what would call a
    model, so the code under test is run_one's own artefact and marker
    handling rather than a reading of run.py's source.
    """
    state: dict[str, object] = {}

    class Deploy:
        env: dict[str, str] = {}
        path_map = {"task": "/deployed/task/SKILL.md"}

    @contextlib.contextmanager
    def fake_deploy(*_args, **_kwargs):
        yield Deploy()

    def fake_stage(eval_id: str, target, env) -> dict[str, str]:
        root = pathlib.Path(target)
        proj = root / "proj"
        proj.mkdir(parents=True, exist_ok=True)
        marker = root / ".eval_started_at"
        marker.write_text("1700000000\n", encoding="utf-8")
        os.utime(marker, (1_700_000_000, 1_700_000_000))
        state["before"] = (
            marker.stat().st_mtime_ns,
            marker.read_text(encoding="utf-8"),
        )
        return {
            "sandbox_proj": str(proj),
            "skill_name": "task",
            "skill_path": "/deployed/task/SKILL.md",
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
    with tempfile.TemporaryDirectory(prefix="task_run_one_") as tmp:
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
                        worker_effort="",
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

        timing = json.loads(
            (run_dir / "query" / "timing.json").read_text(encoding="utf-8")
        )
        # run_one keeps a copy of the finished sandbox under the run dir and
        # removes the live root, so the surviving marker is the copy's.
        marker = run_dir / "query" / "sandbox" / ".eval_started_at"
        after = (
            marker.stat().st_mtime_ns,
            marker.read_text(encoding="utf-8"),
        )
        return timing, after == state["before"]


def pool_dispatch() -> tuple[list[tuple[str, bool, bool]], int]:
    """Run _execute with a stubbed run_one and report the threads it used."""
    threads: set[int] = set()
    lock = threading.Lock()

    def fake_run_one(eval_id, run_dir, resolved, timeout, cache, force, env):
        with lock:
            threads.add(threading.get_ident())
        time.sleep(0.05)
        return eval_id == "probe_a", False

    with tempfile.TemporaryDirectory(prefix="task_pool_") as tmp:
        saved = runner.run_one
        runner.run_one = fake_run_one
        try:
            rows = runner._execute(
                ["probe_a", "probe_b"],
                run_dir=pathlib.Path(tmp),
                resolved=types.SimpleNamespace(
                    worker_model="probe", worker_effort="", vendor="cursor",
                    bin="agent"
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
    """Check the Pattern A runner's workers, ids, split, and timing writer."""
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
        "the serial nested-loop set is the Approach set",
        runner.SERIAL_NESTED_LOOP_IDS == SERIAL_NESTED_LOOP_IDS,
    )
    check(
        "every serial nested-loop id is in evals.json",
        all(eval_id in ids for eval_id in SERIAL_NESTED_LOOP_IDS),
    )
    isolated, serial = runner.partition_ids(ids)
    serial_members = set(SERIAL_NESTED_LOOP_IDS)
    check(
        "partition keeps file order and covers every id",
        isolated == [item for item in ids if item not in serial_members]
        and serial == [item for item in ids if item in serial_members],
    )
    check(
        "the run root is tests/task/workspace",
        runner.WORKSPACE == runner.THIS.parent / "workspace",
    )
    check(
        "the run root is eval_runner's resolved workspace for this harness",
        runner.WORKSPACE == eval_runner.resolve_workspace(runner.THIS),
    )
    timing, marker_unchanged = run_one_record()
    check(
        "run_one's timing record carries every key the measurement reads",
        set(TIMING_KEYS) <= set(timing),
    )
    check(
        "run_one leaves the staging-time .eval_started_at marker untouched",
        marker_unchanged,
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
    (mirror / "tests" / "task").mkdir(parents=True)
    (mirror / "tests" / "lib").symlink_to(REPO / "tests" / "lib")
    (mirror / "tests" / "task" / "evals").symlink_to(THIS)
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
    runner.STAGE = mirror / "tests" / "task" / "evals" / "stage.sh"
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
            str(mirror / "tests" / "task" / "evals" / "grade.sh"),
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


def _sandbox_only_write(staged: dict[str, str], eval_id: str) -> None:
    """Write a sandbox-local task, proving sandbox work stays inside its target."""
    tasks = pathlib.Path(staged["sandbox_proj"]) / "tasks"
    (tasks / f"sandbox-only-{eval_id}.md").write_text(
        "---\ndescription: sandbox-local proof\n---\n", encoding="utf-8"
    )


def _overlap_clean_case(mirror: pathlib.Path) -> dict:
    """Two overlapping jobs with sandbox-only writes leave host tasks alone."""
    targets = {
        "check": pathlib.Path(tempfile.mkdtemp(prefix="task_guard_check_")),
        "query": pathlib.Path(tempfile.mkdtemp(prefix="task_guard_query_")),
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
        eval_id = list(targets)[index]
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
            [make_job("check"), make_job("query")], workers=2, on_error=on_error
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
    planted_name = "api_make-it-better.md"
    targets = {
        "check": pathlib.Path(tempfile.mkdtemp(prefix="task_guard_check_")),
        "query": pathlib.Path(tempfile.mkdtemp(prefix="task_guard_query_")),
    }
    staged_events = [threading.Event(), threading.Event()]
    release = threading.Event()
    planted_state: dict[str, object] = {}

    def planter() -> None:
        if not staged_events[0].wait(30) or not staged_events[1].wait(30):
            planted_state["error"] = "jobs did not stage in time"
            release.set()
            return
        marker = targets["check"] / ".eval_started_at"
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
        eval_id = list(targets)[index]
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
            [make_job(0, "check"), make_job(1, "query")],
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
    text = f"""\
# Parallel-worker host guard: hermetic proof

Generated by `tests/task/evals/test_run.py`; no model call.

## Overlapping clean jobs

`check` and `query` ran concurrently through `tests/lib/eval_runner.run_jobs`
at 2 workers, each staged into its own target and each writing
`sandbox-only-<id>.md` inside its own sandbox `tasks/` tree. Their windows
overlapped: {"yes" if clean["overlap"] else "no"}. The temporary host mirror's
`tasks/` signature was unchanged: {"yes" if clean["host_unchanged"] else "no"}.
`grade.sh`'s isolation check stayed PASS for both evals:
`check` {_verdict(rows["check"])}, `query` {_verdict(rows["query"])}.

## Planted newer fixture

After both jobs staged, the proof planted `tasks/{planted["planted_name"]}` in
the temporary host mirror with an mtime newer than `check`'s
`.eval_started_at` marker: {"yes" if planted["newer"] else "no"}. The `check`
eval's isolation check failed on its own fixture name: {_verdict(planted_rows["check"])}.
The overlapping `query` eval, whose fixture names omit that file, stayed
{_verdict(planted_rows["query"])}.

- Overlapping windows: {"yes" if planted["overlap"] else "no"}
- `check` isolation: {_verdict(planted_rows["check"])}
- `query` isolation: {_verdict(planted_rows["query"])}
"""
    (RESULTS / "run-parallel_workers_hermetic.md").write_text(
        text, encoding="utf-8"
    )


def hermetic_host_guard() -> None:
    """Prove overlapping jobs stay inside their sandboxes and the guard works."""
    with tempfile.TemporaryDirectory(prefix="task_guard_host_") as tmp:
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
            row for row in planted["rows"] if row["eval_id"] == "check"
        )["isolation"],
    )
    check(
        "the overlapping eval with other fixture names stays PASS",
        next(
            row for row in planted["rows"] if row["eval_id"] == "query"
        )["isolation"],
    )
    _write_hermetic_record(clean, planted)


def main() -> int:
    print("task evals: runner declarations")
    with open(THIS / "evals.json", encoding="utf-8") as fh:
        skills = {e["id"]: e["skill"] for e in json.load(fh)["evals"]}

    check(
        "the grade.sh reader takes git_tree_clean and an unscoped status, "
        "and skips comments and a path-scoped status",
        whole_tree_eval_ids(PARSER_SAMPLE) == ["one", "two", "whole"],
    )
    ids = whole_tree_eval_ids((THIS / "grade.sh").read_text())
    check(
        "grade.sh grades the whole sandbox status in at least one eval, "
        "each one in evals.json",
        bool(ids) and all(i in skills for i in ids),
    )
    for eval_id in ids:
        declared = runner.artefacts_for(skills.get(eval_id, ""))
        check(
            f"{eval_id}: declares no agent or style the deployment writes "
            f"into the sandbox project (got {project_scoped(declared)})",
            not project_scoped(declared),
        )

    # Fail branch of the declaration check: it flags agents and styles and
    # passes skills.
    check(
        "the declaration check flags an agent and a style and passes skills",
        project_scoped(["task_explain", "task", "auto_gate_task", "natural-language"])
        == ["auto_gate_task", "natural-language"],
    )
    for skill in sorted(runner.AGENT_SPAWNING_SKILLS):
        check(
            f"{skill} still declares every auto_*_task agent",
            set(runner.AUTO_AGENTS) <= set(runner.artefacts_for(skill)),
        )
    check(
        "task_fix still declares task_check and task_auto_check",
        {"task_check", "task_auto_check"} <= set(runner.artefacts_for("task_fix")),
    )

    # One staged read-only eval per vendor proves the declaration on the real
    # deploy script, and the agents added back prove that check can fail.
    if ids:
        eval_id = ids[0]
        declared = runner.artefacts_for(skills[eval_id])
        cases = [
            ("cursor", declared, "as declared", True),
            ("claude", declared, "as declared", True),
            ("cursor", declared + runner.AUTO_AGENTS, "with the agents added", False),
        ]
        for vendor_name, names, label, expect_clean in cases:
            with tempfile.TemporaryDirectory() as td:
                target = pathlib.Path(td) / eval_id
                target.mkdir()
                project = pathlib.Path(
                    runner.stage(eval_id, target, os.environ)["sandbox_proj"]
                )
                before = git_status(project)
                with micro_deploy.micro_deploy(
                    vendor_name, names, project, preflight=False
                ):
                    after = git_status(project)
            outcome = "stays clean" if expect_clean else "turns dirty"
            check(
                f"{eval_id} on {vendor_name} {label}: sandbox git status {outcome}",
                before == "" and (after == "") == expect_clean,
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

    runner_parallel_surface()
    hermetic_host_guard()

    print(f"\n{PASS} passed, {FAIL} failed")
    return 1 if FAIL else 0


if __name__ == "__main__":
    sys.exit(main())
