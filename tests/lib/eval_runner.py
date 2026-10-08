"""Shared Pattern A eval-runner helper for isolated-sandbox behavioral harnesses.

Harnesses that give each job its own sandbox import this module instead of
copying a ThreadPoolExecutor loop. The helper:

- registers ``--workers`` defaulting to ``vendor.DEFAULT_PARALLEL_WORKERS`` (4),
- runs caller-supplied job callables in a pool (or serially at ``--workers 1``),
  turns a job that raises into the fault result the caller's required
  ``on_error`` builds, in that job's own slot, and keeps queued jobs from
  starting after a Ctrl-C,
- gives every job a fresh ``TMPDIR`` / ``TEMP`` / ``TMP`` and removes it after,
- optionally runs before/after hooks around each job, one call at a time and
  with the job's index, so escape-guard snapshots never interleave and a guard
  claims only the names its own job owns (see ``run_jobs``),
- writes ``response.txt`` / ``stderr.txt`` / ``timing.json`` (both ``worker_rc``
  and ``claude_rc``),
- decodes timeout streams through ``worker_io.as_text``,
- loads eval ids from ``evals.json`` in file order, as strings,
- resolves ``workspace/`` to ``tests/<skill>/workspace``,
- skips and records through ``eval_cache``.

Job callables own sandbox staging (workdir creation and workdir agent
placement under ``.{claude,cursor}/agents/``). Cursor/Claude differences stay
in ``vendor.py``; this module only consumes ``vendor.DEFAULT_PARALLEL_WORKERS``
and, when asked, ``vendor.worker_env``.
"""

from __future__ import annotations

import concurrent.futures
import json
import os
import pathlib
import shutil
import subprocess
import tempfile
import threading
from collections.abc import Callable, Mapping, Sequence
from typing import Any

import eval_cache
import vendor
from worker_io import as_text

JobFn = Callable[[Mapping[str, str]], Any]
BeforeHook = Callable[[int], Any]
AfterHook = Callable[[int, Any], Any]
ErrorFn = Callable[[int, Exception], Any]


def add_workers_argument(parser, *, help_text: str | None = None) -> None:
    """Register ``--workers`` defaulting to ``vendor.DEFAULT_PARALLEL_WORKERS``."""

    parser.add_argument(
        "--workers",
        type=int,
        default=vendor.DEFAULT_PARALLEL_WORKERS,
        help=help_text
        or (
            "Concurrent jobs, each with its own TMPDIR "
            f"(default: {vendor.DEFAULT_PARALLEL_WORKERS}). "
            "Pass 1 to serialize."
        ),
    )


def load_eval_ids(evals_json: pathlib.Path | str) -> list[str]:
    """Return every eval id from ``evals.json`` in file order, as strings.

    The git harnesses store numeric ids, and a run directory, a cache key, and
    a shell argument all need the string form.
    """

    data = json.loads(pathlib.Path(evals_json).read_text(encoding="utf-8"))
    entries = data if isinstance(data, list) else data["evals"]
    return [str(entry["id"]) for entry in entries]


def resolve_workspace(skill_or_evals_dir: pathlib.Path | str) -> pathlib.Path:
    """Resolve ``tests/<skill>/workspace`` from a skill or ``evals/`` directory."""

    path = pathlib.Path(skill_or_evals_dir).resolve()
    if path.name == "evals":
        path = path.parent
    return path / "workspace"


def timeout_streams(
    exc: subprocess.TimeoutExpired, timeout: int
) -> tuple[str, str]:
    """Decode ``TimeoutExpired`` stdout/stderr through ``worker_io.as_text``."""

    stdout = as_text(exc.stdout)
    stderr = as_text(exc.stderr) + f"\n[TIMEOUT after {timeout}s]"
    return stdout, stderr


def write_run_artifacts(
    eval_dir: pathlib.Path | str,
    *,
    stdout: str,
    stderr: str,
    eval_id: str,
    duration_s: float,
    worker_rc: int,
    model: str,
    **extra_timing: Any,
) -> None:
    """Write ``response.txt``, ``stderr.txt``, and ``timing.json``.

    ``timing.json`` always carries both ``worker_rc`` and ``claude_rc`` set to
    the same return code so older graders that read either key keep working.
    """

    dest = pathlib.Path(eval_dir)
    dest.mkdir(parents=True, exist_ok=True)
    (dest / "response.txt").write_text(stdout)
    (dest / "stderr.txt").write_text(stderr)
    timing = {
        "eval_id": eval_id,
        "duration_s": duration_s,
        "worker_rc": worker_rc,
        "claude_rc": worker_rc,
        "model": model,
        **extra_timing,
    }
    (dest / "timing.json").write_text(json.dumps(timing, indent=2))


def cache_lookup(
    cache: eval_cache.EvalCache | None,
    eval_id: str,
    key: str | None,
    eval_dir: pathlib.Path | str,
    *,
    force: bool,
) -> dict | None:
    """Return a cache hit entry after writing replay artifacts, else ``None``."""

    if cache is None or key is None or force:
        return None
    hit = cache.lookup(eval_id, key)
    if hit is None:
        return None
    eval_cache.write_replay_artifacts(eval_dir, hit)
    return hit


def cache_record(
    cache: eval_cache.EvalCache | None,
    eval_id: str,
    key: str | None,
    *,
    passed: bool,
    model: str,
    duration_s: float,
    worker_rc: int,
    grading_output: str,
    response_excerpt: str,
) -> dict | None:
    """Record a miss when a cache and key are present; otherwise return ``None``."""

    if cache is None or key is None:
        return None
    return cache.record(
        eval_id,
        key,
        passed=passed,
        model=model,
        duration_s=duration_s,
        worker_rc=worker_rc,
        grading_output=grading_output,
        response_excerpt=response_excerpt,
    )


def _job_env(tmpdir: pathlib.Path, vendor_name: str | None) -> dict[str, str]:
    if vendor_name is None:
        env = os.environ.copy()
    else:
        env = vendor.worker_env(vendor_name)
    path = str(tmpdir)
    env["TMPDIR"] = path
    env["TEMP"] = path
    env["TMP"] = path
    return env


def _run_one(
    index: int,
    job: JobFn,
    *,
    vendor_name: str | None,
    before: BeforeHook | None,
    after: AfterHook | None,
    hook_lock: threading.Lock,
) -> Any:
    tmpdir = pathlib.Path(tempfile.mkdtemp(prefix="eval_runner_"))
    try:
        before_state = None
        if before is not None:
            with hook_lock:
                before_state = before(index)
        # When before raises, control never reaches the job or the after hook,
        # so the snapshot error surfaces as itself rather than via a None state.
        try:
            return job(_job_env(tmpdir, vendor_name))
        finally:
            if after is not None:
                with hook_lock:
                    after(index, before_state)
    finally:
        shutil.rmtree(tmpdir, ignore_errors=True)


def run_jobs(
    jobs: Sequence[JobFn],
    *,
    workers: int,
    on_error: ErrorFn,
    vendor_name: str | None = None,
    before: BeforeHook | None = None,
    after: AfterHook | None = None,
) -> list[Any]:
    """Run job callables and return results in submission order.

    Each job receives an environment mapping whose ``TMPDIR``, ``TEMP``, and
    ``TMP`` all point at a fresh directory unique to that job. The directory is
    removed after the callable returns. When ``vendor_name`` is set, the env
    starts from ``vendor.worker_env``; otherwise it starts from ``os.environ``.

    Every caller passes ``on_error``, so each runner decides at the call site
    what a fault looks like. A job that raises an ``Exception``, from its
    callable or from one of its hooks, fills only its own slot, with the
    return value of ``on_error(index, exc)``, and every other job still runs
    and keeps its result. ``on_error`` runs on the calling thread, one call at
    a time, so it can print and build a harness-fault verdict without a lock.
    A ``KeyboardInterrupt``, or any other ``BaseException``, keeps queued jobs
    from starting, lets the running jobs finish, and then propagates.

    Optional hooks bracket each job on the job's own thread as
    ``before(index)`` and ``after(index, before_state)``. The index tells a
    guard which job it brackets, so the guard looks up what that job owns
    without thread-local state, which a reused pool thread carries over from
    its previous job. One lock serializes every hook call, so two snapshots
    never interleave. ``after`` runs only once ``before`` has returned, and its
    ``before_state`` is ``None`` when no ``before`` is given.

    The lock orders snapshots but cannot attribute a change. Job bodies still
    overlap when ``workers`` is greater than 1, so an after hook sees every
    change made since its own before snapshot, a sibling job's included. An
    escape guard therefore claims only the names its own job owns, the way
    ``tests/lib/host_tasks_guard.sh`` compares only the sandbox's fixture
    names. A guard that claims any change in a shared tree, such as an
    unscoped host-checkout ``git status``, needs ``workers=1``.
    """

    if not jobs:
        return []

    workers = max(1, int(workers))
    hook_lock = threading.Lock()

    def invoke(index: int, job: JobFn) -> Any:
        return _run_one(
            index,
            job,
            vendor_name=vendor_name,
            before=before,
            after=after,
            hook_lock=hook_lock,
        )

    results: list[Any] = [None] * len(jobs)
    if workers == 1 or len(jobs) == 1:
        for index, job in enumerate(jobs):
            try:
                results[index] = invoke(index, job)
            except Exception as exc:
                results[index] = on_error(index, exc)
        return results

    with concurrent.futures.ThreadPoolExecutor(
        max_workers=min(workers, len(jobs))
    ) as pool:
        try:
            futures = {
                pool.submit(invoke, index, job): index
                for index, job in enumerate(jobs)
            }
            for fut in concurrent.futures.as_completed(futures):
                index = futures[fut]
                try:
                    results[index] = fut.result()
                except Exception as exc:
                    results[index] = on_error(index, exc)
        except BaseException:
            # Leaving the with block waits for every queued job, so cancel the
            # queue first and let only the running jobs finish. Submission sits
            # inside this guard because a Ctrl-C can land while it runs.
            pool.shutdown(wait=False, cancel_futures=True)
            raise
    return results


def print_summary(
    rows: Sequence[tuple[str, bool, bool]],
    *,
    heading: str | None = None,
) -> None:
    """Print a graded summary in submission (eval-id / file) order.

    Each row is ``(eval_id, passed, was_cached)``.
    """

    if heading:
        print(heading)
    else:
        print("=" * 56)
    ok = sum(1 for _, passed, _ in rows if passed)
    cached_n = sum(1 for _, _, was_cached in rows if was_cached)
    print(f"graded: {ok}/{len(rows)} evals passed ({cached_n} from cache)")
    for eval_id, passed, was_cached in rows:
        label = "PASS" if passed else "FAIL"
        suffix = " (cached)" if was_cached else ""
        print(f"  {eval_id}: {label}{suffix}")
