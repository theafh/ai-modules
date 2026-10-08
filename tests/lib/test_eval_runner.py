#!/usr/bin/env python3
"""Unit tests for eval_runner.py — no network, no live worker calls.

Run:

    python3 tests/lib/test_eval_runner.py
"""

from __future__ import annotations

import argparse
import json
import os
import pathlib
import signal
import subprocess
import sys
import tempfile
import threading
import time
from collections.abc import Mapping

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import eval_cache  # noqa: E402
import eval_runner  # noqa: E402
import vendor  # noqa: E402

PASS = 0
FAIL = 0

# Overlap timing: how long a job waits at a barrier or an event before the test
# counts the jobs as not overlapping, how long a hook holds the hook lock so
# unserialized hooks would overlap, and how long the interrupt check keeps its
# two running jobs busy after the Ctrl-C arrives.
BARRIER_TIMEOUT_S = 5
HOOK_PAUSE_S = 0.1
INTERRUPT_HOLD_S = 0.5


def check(label: str, cond: bool) -> None:
    global PASS, FAIL
    if cond:
        PASS += 1
        print(f"  ok   {label}")
    else:
        FAIL += 1
        print(f"  FAIL {label}")


def keep_exception(_index: int, exc: Exception) -> Exception:
    """``on_error`` for checks whose jobs are not meant to raise.

    It keeps the exception in its slot, so a check comparing results sees it.
    """

    return exc


def test_argparse_default_workers() -> None:
    parser = argparse.ArgumentParser(add_help=False)
    eval_runner.add_workers_argument(parser)
    args = parser.parse_args([])
    check(
        "argparse --workers defaults to DEFAULT_PARALLEL_WORKERS",
        args.workers == vendor.DEFAULT_PARALLEL_WORKERS == 4,
    )
    custom = argparse.ArgumentParser(add_help=False)
    eval_runner.add_workers_argument(custom, help_text="custom workers help")
    check(
        "add_workers_argument takes help_text",
        "custom workers help" in custom.format_help(),
    )


def test_load_eval_ids_file_order() -> None:
    with tempfile.TemporaryDirectory() as td:
        path = pathlib.Path(td) / "evals.json"
        path.write_text(
            json.dumps(
                {
                    "skill_name": "demo",
                    "evals": [
                        {"id": "zeta", "prompt": "z"},
                        {"id": "alpha", "prompt": "a"},
                        {"id": "mu", "prompt": "m"},
                    ],
                }
            )
        )
        check(
            "load_eval_ids keeps file order",
            eval_runner.load_eval_ids(path) == ["zeta", "alpha", "mu"],
        )
        numeric = pathlib.Path(td) / "numeric_evals.json"
        numeric.write_text(json.dumps({"evals": [{"id": 3}, {"id": 1}, {"id": 2}]}))
        check(
            "load_eval_ids returns numeric ids as strings in file order",
            eval_runner.load_eval_ids(numeric) == ["3", "1", "2"],
        )


def test_resolve_workspace() -> None:
    with tempfile.TemporaryDirectory() as td:
        skill = pathlib.Path(td) / "demo_skill"
        evals = skill / "evals"
        evals.mkdir(parents=True)
        from_skill = eval_runner.resolve_workspace(skill)
        from_evals = eval_runner.resolve_workspace(evals)
        expected = (skill / "workspace").resolve()
        check(
            "workspace resolves under tests/<skill>/workspace",
            from_skill == expected,
        )
        check(
            "workspace from evals/ matches skill/workspace",
            from_evals == expected,
        )


def test_concurrent_distinct_tmpdirs() -> None:
    barrier = threading.Barrier(2)
    seen: dict[str, dict[str, str]] = {}
    broken: list[str] = []
    lock = threading.Lock()

    def job(label: str):
        def run(env):
            try:
                barrier.wait(timeout=BARRIER_TIMEOUT_S)
            except threading.BrokenBarrierError:
                broken.append(label)
            marker = pathlib.Path(env["TMPDIR"]) / f"{label}.txt"
            marker.write_text(label)
            time.sleep(0.15)
            with lock:
                seen[label] = {
                    "tmpdir": env["TMPDIR"],
                    "TEMP": env["TEMP"],
                    "TMP": env["TMP"],
                    "self": marker.read_text(),
                    "other": [
                        p.name
                        for p in pathlib.Path(env["TMPDIR"]).iterdir()
                        if p.name != f"{label}.txt"
                    ],
                }
            return label

        return run

    results = eval_runner.run_jobs(
        [job("a"), job("b")],
        workers=vendor.DEFAULT_PARALLEL_WORKERS,
        on_error=keep_exception,
    )
    check("default workers runs both jobs", results == ["a", "b"])
    check("default-worker jobs overlapped", broken == [])
    check("job a TMPDIR == TEMP == TMP",
          seen["a"]["tmpdir"] == seen["a"]["TEMP"] == seen["a"]["TMP"])
    check("job b TMPDIR == TEMP == TMP",
          seen["b"]["tmpdir"] == seen["b"]["TEMP"] == seen["b"]["TMP"])
    check("concurrent jobs get distinct temp dirs",
          seen["a"]["tmpdir"] != seen["b"]["tmpdir"])
    check("job a cannot see job b files", seen["a"]["other"] == [])
    check("job b cannot see job a files", seen["b"]["other"] == [])
    check("job a temp dir removed after return",
          not pathlib.Path(seen["a"]["tmpdir"]).exists())
    check("job b temp dir removed after return",
          not pathlib.Path(seen["b"]["tmpdir"]).exists())


def test_workers_one_serial() -> None:
    order: list[str] = []
    lock = threading.Lock()
    active = {"n": 0, "max": 0}

    def job(label: str):
        def run(env):
            with lock:
                active["n"] += 1
                active["max"] = max(active["max"], active["n"])
            time.sleep(0.05)
            with lock:
                order.append(label)
                active["n"] -= 1
            return label

        return run

    results = eval_runner.run_jobs(
        [job("first"), job("second")], workers=1, on_error=keep_exception
    )
    check("workers 1 preserves submission order", results == ["first", "second"])
    check("workers 1 never overlaps jobs", active["max"] == 1)
    check("workers 1 runs in order", order == ["first", "second"])


def test_raising_job_keeps_other_results() -> None:
    """A raising job fills its own slot, and every other job keeps its result."""

    def boom(_env: Mapping[str, str]) -> str:
        raise TypeError("can't concat str to bytes")

    def ok(label: str) -> eval_runner.JobFn:
        def run(_env: Mapping[str, str]) -> str:
            time.sleep(0.02)
            return label

        return run

    def run_with_on_error(workers: int) -> tuple[list, list[tuple[int, str, bool]]]:
        faults: list[tuple[int, str, bool]] = []

        def on_error(index: int, exc: Exception) -> str:
            on_caller = threading.current_thread() is threading.main_thread()
            faults.append((index, str(exc), on_caller))
            return f"fault-{index}"

        jobs = [boom] + [ok(f"eval-{n}") for n in range(1, 6)]
        try:
            results = eval_runner.run_jobs(jobs, workers=workers, on_error=on_error)
        except Exception as exc:  # the escape these checks exist to catch
            results = [exc]
        return results, faults

    expected = ["fault-0", "eval-1", "eval-2", "eval-3", "eval-4", "eval-5"]
    for workers in (1, vendor.DEFAULT_PARALLEL_WORKERS):
        results, faults = run_with_on_error(workers)
        check(f"workers {workers}: other jobs keep their results", results == expected)
        check(
            f"workers {workers}: on_error gets the raising job's index and error",
            [(index, message) for index, message, _ in faults]
            == [(0, "can't concat str to bytes")],
        )
        check(
            f"workers {workers}: on_error runs on the calling thread",
            [on_caller for _, _, on_caller in faults] == [True],
        )

    ran: list[str] = []

    def tracked(_env: Mapping[str, str]) -> str:
        ran.append("job")
        return "job"

    try:
        eval_runner.run_jobs([tracked], workers=1)  # no on_error, on purpose
        refused = False
    except TypeError:
        refused = True
    check("run_jobs refuses a call without on_error", refused and ran == [])


def test_interrupt_cancels_queued_jobs() -> None:
    """A Ctrl-C keeps queued jobs from starting and lets running jobs finish."""

    started: list[int] = []
    lock = threading.Lock()
    both_running = threading.Event()

    def job(index: int) -> eval_runner.JobFn:
        def run(_env: Mapping[str, str]) -> int:
            with lock:
                started.append(index)
                if len(started) == 2:
                    both_running.set()
            time.sleep(INTERRUPT_HOLD_S)
            return index

        return run

    def interrupt() -> None:
        if both_running.wait(timeout=BARRIER_TIMEOUT_S):
            os.kill(os.getpid(), signal.SIGINT)

    # A shell that starts this script in the background ignores SIGINT, so
    # install the default handler for the length of the check.
    previous = signal.signal(signal.SIGINT, signal.default_int_handler)
    interrupted = False
    try:
        threading.Thread(target=interrupt, daemon=True).start()
        eval_runner.run_jobs(
            [job(n) for n in range(8)], workers=2, on_error=keep_exception
        )
    except KeyboardInterrupt:
        interrupted = True
    finally:
        signal.signal(signal.SIGINT, previous)
    check("Ctrl-C surfaces as KeyboardInterrupt", interrupted)
    check("Ctrl-C keeps queued jobs from starting", sorted(started) == [0, 1])


def test_hooks_serialized() -> None:
    """One lock runs every hook call alone while the job bodies overlap.

    Both jobs meet at a start barrier and a finish barrier, so their after
    hooks contend for the lock at the same moment. Each hook call holds for
    HOOK_PAUSE_S, so without the helper's lock two calls would overlap.
    """

    start = threading.Barrier(2)
    finish = threading.Barrier(2)
    guard = threading.Lock()
    in_hook = {"n": 0, "max": 0}
    broken: list[str] = []

    def hold_hook() -> None:
        with guard:
            in_hook["n"] += 1
            in_hook["max"] = max(in_hook["max"], in_hook["n"])
        time.sleep(HOOK_PAUSE_S)
        with guard:
            in_hook["n"] -= 1

    def before(_index: int) -> None:
        hold_hook()

    def after(_index: int, _before_state: None) -> None:
        hold_hook()

    def job(label: str) -> eval_runner.JobFn:
        def run(_env: Mapping[str, str]) -> str:
            try:
                start.wait(timeout=BARRIER_TIMEOUT_S)
                finish.wait(timeout=BARRIER_TIMEOUT_S)
            except threading.BrokenBarrierError:
                broken.append(label)
            return label

        return run

    results = eval_runner.run_jobs(
        [job("a"), job("b")],
        workers=2,
        on_error=keep_exception,
        before=before,
        after=after,
    )
    check("serialized-hook jobs both return", results == ["a", "b"])
    check("serialized-hook job bodies overlapped", broken == [])
    check("hook calls never overlap", in_hook["max"] == 1)


def test_hooks_receive_job_index() -> None:
    """Each hook gets its own job's index and runs on that job's thread.

    The serial run reuses one thread for all three jobs, and the middle job
    raises before doing anything, which is the case where a thread-local label
    still held the previous job's value. The pool run checks the same pairing
    while jobs overlap.
    """

    def run_indexed(workers: int) -> tuple[list[tuple[int, object]], bool]:
        pairs: list[tuple[int, object]] = []
        hook_threads: dict[tuple[str, int], int] = {}
        job_threads: dict[int, int] = {}

        def before(index: int) -> int:
            hook_threads[("before", index)] = threading.get_ident()
            return index

        def after(index: int, before_state: object) -> None:
            hook_threads[("after", index)] = threading.get_ident()
            pairs.append((index, before_state))

        def job(index: int, fails: bool) -> eval_runner.JobFn:
            def run(_env: Mapping[str, str]) -> int:
                job_threads[index] = threading.get_ident()
                if fails:
                    raise RuntimeError("staging failed before the job did anything")
                return index

            return run

        try:
            eval_runner.run_jobs(
                [job(0, False), job(1, True), job(2, False)],
                workers=workers,
                on_error=keep_exception,
                before=before,
                after=after,
            )
        except Exception:  # an escape the pairing check below reports
            pass
        same_thread = all(
            (kind, index) in hook_threads
            and index in job_threads
            and hook_threads[(kind, index)] == job_threads[index]
            for kind in ("before", "after")
            for index in range(3)
        )
        return sorted(pairs), same_thread

    for workers in (1, vendor.DEFAULT_PARALLEL_WORKERS):
        pairs, same_thread = run_indexed(workers)
        check(
            f"workers {workers}: each after hook gets its own job's index and state",
            pairs == [(0, 0), (1, 1), (2, 2)],
        )
        check(f"workers {workers}: hooks run on their own job's thread", same_thread)


def test_hook_attribution_by_owned_names() -> None:
    """A guard that claims only its own job's names blames the escaping job.

    Both before hooks snapshot a clean host tree. The escaping job writes a
    canary named after itself and keeps running until the clean job's after
    hook has run, so that hook sees the canary inside its own window. It claims
    nothing, because the canary carries the other job's name, and the escaping
    job's after hook claims the canary once that job finishes. A guard that
    claimed every new name would have blamed the clean job.
    """

    with tempfile.TemporaryDirectory() as td:
        host = pathlib.Path(td) / "host_tree"
        host.mkdir()
        labels = ["escape", "clean"]
        start = threading.Barrier(2)
        canary_written = threading.Event()
        clean_checked = threading.Event()
        broken: list[str] = []
        seen: dict[str, set[str]] = {}
        claims: list[tuple[str, str]] = []

        def before(_index: int) -> set[str]:
            return {p.name for p in host.iterdir()}

        def after(index: int, before_state: set[str]) -> None:
            # The index names the job this hook brackets, so the guard looks
            # up that job's names directly.
            label = labels[index]
            new = {p.name for p in host.iterdir()} - before_state
            seen[label] = new
            for name in sorted(new):
                if name.startswith(f"{label}-"):
                    claims.append((label, name))
                    (host / name).unlink(missing_ok=True)
            if label == "clean":
                clean_checked.set()

        def job(label: str, escapes: bool) -> eval_runner.JobFn:
            def run(_env: Mapping[str, str]) -> str:
                try:
                    start.wait(timeout=BARRIER_TIMEOUT_S)
                except threading.BrokenBarrierError:
                    broken.append(label)
                if escapes:
                    (host / f"{label}-canary.txt").write_text("escaped")
                    canary_written.set()
                    if not clean_checked.wait(timeout=BARRIER_TIMEOUT_S):
                        broken.append(label)
                elif not canary_written.wait(timeout=BARRIER_TIMEOUT_S):
                    broken.append(label)
                return label

            return run

        results = eval_runner.run_jobs(
            [job(labels[0], True), job(labels[1], False)],
            workers=2,
            on_error=keep_exception,
            before=before,
            after=after,
        )
        check("attribution jobs both return", results == ["escape", "clean"])
        check("escaping job ran past the clean job's after hook", broken == [])
        check(
            "clean job's after hook saw the canary inside its window",
            "escape-canary.txt" in seen.get("clean", set()),
        )
        check(
            "only the escaping job claims its canary",
            claims == [("escape", "escape-canary.txt")],
        )
        check("host tree restored after attribution", list(host.iterdir()) == [])


def test_before_failure_skips_after() -> None:
    """A before hook that raises skips the job and its after hook."""

    ran: list[str] = []
    after_calls: list[object] = []
    faults: list[Exception] = []

    def before(_index: int) -> set[str]:
        raise RuntimeError("git status failed")

    def after(_index: int, before_state: object) -> None:
        after_calls.append(before_state)

    def job(_env: Mapping[str, str]) -> str:
        ran.append("job")
        return "job"

    def on_error(_index: int, exc: Exception) -> str:
        faults.append(exc)
        return "fault"

    try:
        results = eval_runner.run_jobs(
            [job], workers=1, before=before, after=after, on_error=on_error
        )
    except Exception as exc:  # an escape the slot check below reports
        results = [exc]
    check("failed before hook fills the job's slot", results == ["fault"])
    check(
        "failed before hook surfaces as itself",
        len(faults) == 1 and isinstance(faults[0], RuntimeError),
    )
    check("failed before hook skips the job", ran == [])
    check("failed before hook skips the after hook", after_calls == [])


def test_callable_owns_sandbox_staging() -> None:
    """Callables stage their own sandboxes; the helper leaves TMPDIR empty."""

    with tempfile.TemporaryDirectory() as td:
        root = pathlib.Path(td)

        def job(
            env: Mapping[str, str],
        ) -> tuple[pathlib.Path, pathlib.Path, list[str] | None]:
            # Read the job's temp dir while the job runs: the helper deletes it
            # once the callable returns, so a look from outside finds nothing.
            job_tmp = pathlib.Path(env["TMPDIR"])
            helper_entries = None
            if job_tmp.is_dir():
                helper_entries = sorted(p.name for p in job_tmp.iterdir())
            workdir = root / "sandbox_proj"
            workdir.mkdir()
            agents = workdir / ".cursor" / "agents"
            agents.mkdir(parents=True)
            (agents / "auto_demo.md").write_text("# auto_demo\n")
            (workdir / "notes.md").write_text("staged by callable\n")
            return workdir, agents / "auto_demo.md", helper_entries

        workdir, agent, helper_entries = eval_runner.run_jobs(
            [job], workers=1, on_error=keep_exception
        )[0]
        check("callable created its own workdir", workdir.is_dir())
        check(
            "callable placed spawnable agent under workdir agents/",
            agent.is_file(),
        )
        check(
            "job TMPDIR held nothing from the helper when the callable started",
            helper_entries == [],
        )


def test_write_run_artifacts() -> None:
    with tempfile.TemporaryDirectory() as td:
        eval_dir = pathlib.Path(td) / "eval-1"
        eval_runner.write_run_artifacts(
            eval_dir,
            stdout="worker out\n",
            stderr="worker err\n",
            eval_id="eval-1",
            duration_s=1.25,
            worker_rc=0,
            model="auto",
        )
        check("writes response.txt",
              (eval_dir / "response.txt").read_text() == "worker out\n")
        check("writes stderr.txt",
              (eval_dir / "stderr.txt").read_text() == "worker err\n")
        timing = json.loads((eval_dir / "timing.json").read_text())
        check("timing.json has worker_rc", timing["worker_rc"] == 0)
        check("timing.json has claude_rc", timing["claude_rc"] == 0)
        check("timing.json keeps eval_id", timing["eval_id"] == "eval-1")


def test_cache_skip_and_record() -> None:
    with tempfile.TemporaryDirectory() as td:
        root = pathlib.Path(td)
        cache = eval_cache.EvalCache(root / ".eval_cache")
        skill = root / "skill"
        skill.mkdir()
        (skill / "SKILL.md").write_text("# demo\n")
        harness = root / "evals"
        harness.mkdir()
        (harness / "evals.json").write_text('{"evals":[{"id":"e1"}]}\n')
        key = eval_cache.content_key(
            source_roots=[skill],
            harness_dir=harness,
            model="auto",
            eval_id="e1",
            prompt="do it",
        )
        eval_dir = root / "run" / "e1"
        miss = eval_runner.cache_lookup(
            cache, "e1", key, eval_dir, force=False
        )
        check("cache miss returns None", miss is None)
        recorded = eval_runner.cache_record(
            cache,
            "e1",
            key,
            passed=True,
            model="auto",
            duration_s=2.0,
            worker_rc=0,
            grading_output="PASS\n",
            response_excerpt="hello",
        )
        check("cache record stores passed", recorded["passed"] is True)
        hit_dir = root / "run" / "e1-hit"
        hit = eval_runner.cache_lookup(
            cache, "e1", key, hit_dir, force=False
        )
        check("cache hit returns entry", hit is not None and hit["passed"] is True)
        check("cache hit writes replay artifacts",
              (hit_dir / "cached.json").is_file())
        forced = eval_runner.cache_lookup(
            cache, "e1", key, root / "run" / "e1-force", force=True
        )
        check("force skips cache hit", forced is None)


def test_timeout_bytes_path() -> None:
    exc = subprocess.TimeoutExpired(
        cmd=["claude", "-p"],
        timeout=30,
        output=b"partial out\n",
        stderr=b"partial err\n",
    )
    try:
        stdout, stderr = eval_runner.timeout_streams(exc, 30)
        raised = None
    except TypeError as err:
        stdout = stderr = ""
        raised = err
    check("timeout bytes path does not raise", raised is None)
    check("timeout stdout decodes", stdout == "partial out\n")
    check(
        "timeout stderr appends note",
        stderr == "partial err\n\n[TIMEOUT after 30s]",
    )


def test_submission_order_summary() -> None:
    barrier = threading.Barrier(2)
    finish_order: list[str] = []
    broken: list[str] = []
    lock = threading.Lock()

    def job(label: str, delay: float):
        def run(env):
            try:
                barrier.wait(timeout=BARRIER_TIMEOUT_S)
            except threading.BrokenBarrierError:
                broken.append(label)
            time.sleep(delay)
            with lock:
                finish_order.append(label)
            return (label, label == "keep", False)

        return run

    # Submit keep then drop; drop finishes first, but results stay submission order.
    results = eval_runner.run_jobs(
        [job("keep", 0.2), job("drop", 0.01)],
        workers=2,
        on_error=keep_exception,
    )
    check("submission-order jobs overlapped", broken == [])
    check("results reassembled in submission order",
          [row[0] for row in results] == ["keep", "drop"])
    check("completion order differed from submission",
          finish_order == ["drop", "keep"])

    import io
    from contextlib import redirect_stdout

    buf = io.StringIO()
    with redirect_stdout(buf):
        eval_runner.print_summary(results)
    text = buf.getvalue()
    keep_at = text.index("keep:")
    drop_at = text.index("drop:")
    check("summary prints in submission order", keep_at < drop_at)


def test_vendor_constant_unchanged() -> None:
    check("DEFAULT_PARALLEL_WORKERS remains 4", vendor.DEFAULT_PARALLEL_WORKERS == 4)


def main() -> int:
    test_argparse_default_workers()
    test_load_eval_ids_file_order()
    test_resolve_workspace()
    test_concurrent_distinct_tmpdirs()
    test_workers_one_serial()
    test_raising_job_keeps_other_results()
    test_interrupt_cancels_queued_jobs()
    test_hooks_serialized()
    test_hooks_receive_job_index()
    test_hook_attribution_by_owned_names()
    test_before_failure_skips_after()
    test_callable_owns_sandbox_staging()
    test_write_run_artifacts()
    test_cache_skip_and_record()
    test_timeout_bytes_path()
    test_submission_order_summary()
    test_vendor_constant_unchanged()

    print(f"\n{PASS} passed, {FAIL} failed")
    return 1 if FAIL else 0


if __name__ == "__main__":
    sys.exit(main())
