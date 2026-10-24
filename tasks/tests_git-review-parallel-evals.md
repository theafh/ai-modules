---
description: Run git_review evals at default 4 workers through the shared helper, isolate per-eval temp files, and treat model contention as a timeout-tuning problem rather than a serial requirement.
scope: tests/git_review/evals
created: 2026-10-04T22:11:10
updated: 2026-10-24T00:59:09
status: ready
reported-by: Andreas Hoffmann
---

# Parallelize the git_review behavioral evals at default four workers

## Goal

`python3 tests/git_review/evals/run.py` runs isolated review evals concurrently
with `--workers` defaulting to 4. Per-eval timeout stays the deadline that fails
one slow worker, not a reason to serialize the suite. Cursor is the measurement
vendor; Claude remains a compatibility vendor through the same helper. The
user-visible outcome: a large review sweep overlaps workers instead of running
one eval at a time because two jobs might contend for the model.

## Context

`tests/git_review/evals/run.py` is sequential on purpose: "two review workers on
one machine contend for the model and both slow past the per-eval timeout."
Default `--timeout` is 600s. `evals/grade.sh` already stages per-eval sandboxes
and writes a Python snippet under `${TMPDIR:-/tmp}/git_review_grade.XXXXXX.py`.
`tests/git_review/RUNBOOK.md` repeats the sequential instruction.

Contention can still lengthen a job. That is a timeout and `--workers` tuning
concern. Isolated sandboxes already exist, so correctness does not require a
single-file walk.

This task consumes [the shared Pattern A eval runner](archive/tests_shared-pattern-a-eval-runner.md).
[The timeout-crash task](archive/tests_eval-runner-timeout-crash.md) still owns the
`task_auto_check` timing band, not this harness.

## Approach

Rewrite `evals/run.py` onto the shared helper: `--workers` default 4, workspace at
`tests/git_review/workspace`. Keep vendor resolution on `tests/lib/vendor.py`.
Apply the helper's per-job `TMPDIR`/`TEMP`/`TMP` mapping as the environment of `stage` (so `stage` runs under that mapping, matching the env-passing pattern in `tests/git_commit/evals/run.py` and `tests/git_checkout/evals/run.py`—not those runners' `stage()` return shapes). Keep `stage()` returning `sandbox_repo`, `prompt`, `target`, and `gh_env` while adding the job `env` argument; then copy that same mapping onto the worker env before folding `gh_env`, so a fixture that sets `TMPDIR` in `gh_env` (as `push_approval` does for gradeable `report.md` mtime) still wins for the worker; pass that same job mapping—not the post-`gh_env` worker env—to the `grade.sh` subprocess so its `mktemp` stays isolated per job, and keep that subprocess's argv as the current three-argument form `grade.sh <id> <sandbox_repo> <response.txt>` (the worker's captured response path under the run tree), rewriting the existing call onto the helper rather than adopting the sibling Pattern A two-argument `grade.sh <id> <workdir>` shape. Each eval's
`timing.json` is written through the shared helper's `write_run_artifacts`
path with `started_at` and `ended_at` beside `duration_s`, matching
`tests/git_commit/evals/run.py`. Pass each job's helper `TMPDIR` into
`write_run_artifacts` as the extra timing field `tmpdir`. Rewrite the sequential comment and the
RUNBOOK sentence that forbids concurrent review workers. In `tests/AGENTS.md`
under `### Parallel workers`, and in `tests/CLAUDE.md` under `### Parallel
workers: default 4 only where each job has its own sandbox`, rewrite the
Pattern A `eval_runner` / `DEFAULT_PARALLEL_WORKERS` pool sentence in place
so `tests/git_review/evals/run.py` joins that set beside the existing runners,
and supersede the sequential-list entry that names `git_review` for timeout
contention.
Keep the two files' Parallel-workers sections in lockstep with each other.
Rewrite the `git_review/` inventory row in `tests/CLAUDE.md` and the
`**git_review/**` bullet in `tests/README.md` in place to the sibling
Pattern A form used by `git_commit` / `git_checkout`: name `evals/run.py`
in the shared `tests/lib/eval_runner` pool. Rewrite the driver intro plus
`## Running` passages in `tests/git_review/evals/README.md` in place to that
same sibling Pattern A form, naming the shared pool with `--workers`
defaulting to 4 (`vendor.DEFAULT_PARALLEL_WORKERS`) and `--workers 1` as the
serial opt-in, superseding each surface's current non-pool wording.
After `write_run_artifacts`, keep copying `gh_calls.log` and `script_calls.log`
from the staged target into the eval run directory when those files exist.

If a `--workers 4 --force` timeout-band sample of eval ids 18
(`deep_file_defect`), 41 (`push_approval`), and 2 (`clean_change`) shows
`duration_s` crowding the 600s default, raise this harness's `--timeout`
default to observed upper + 300 (the headroom formula in
`tests/task_auto_check/RUNBOOK.md` under Timing-band re-measurement) and
record that band in this harness's RUNBOOK. When the sample's ceilings stay
clear of 600s, leave `--timeout` at 600. `--workers 1` remains the latency
reading.

**Out of scope:** Adding review evals. Changing `collect_review_evidence.sh`.
Live-testing unshipped editorial plugin harnesses.

## Acceptance

- `run.py --help` shows `--workers` defaulting to 4 and still documents
  `--timeout`.
- `evals/run.py` sets the `--workers` default to `vendor.DEFAULT_PARALLEL_WORKERS`, through `eval_runner.add_workers_argument` or an equivalent `default=` naming that constant.
- `evals/run.py` imports `eval_runner`, dispatches jobs through
  `eval_runner.run_jobs`, and still calls `vendor.add_vendor_arguments` and
  `vendor.resolve`.
- `python3 tests/git_review/evals/run.py` at the default worker count prints a
  graded summary over every id in `evals.json` (or a named subset plus a
  second `--force` pair that proves overlap), with no TypeError on a timeout
  path.
- A `--workers 4 --force` run of at least two uncached evals writes each
  eval's `timing.json` solely through `eval_runner.write_run_artifacts` (or an
  equivalent call of that helper), and those files each carry `started_at` and
  `ended_at` beside `duration_s`; `tests/git_review/results/parallel-tmpdir-windows.md`
  records overlapping wall-clock windows
  from those fields; when the sample's windows do not overlap, that file states
  the incomplete outcome and names the follow-up `--force` rerun that will
  re-check overlap.
- A `--workers 4 --force` overlap sample recorded in `tests/git_review/results/parallel-tmpdir-windows.md`
  shows distinct per-job `TMPDIR` values read from each sampled eval's
  `timing.json` `tmpdir` field (each job's helper `TMPDIR`, persisted through
  `write_run_artifacts` extras); `evals/run.py` passes the helper job
  `TMPDIR`/`TEMP`/`TMP` mapping as the environment of `stage`, applies that same
  mapping onto the worker environment before folding `gh_env`, and passes that
  same job mapping as the environment of the `grade.sh` subprocess; `evals/run.py` still invokes `grade.sh` with three arguments—eval id, sandbox repo, and the worker's `response.txt` path—as the one canonical grade call (the prior three-argument form remains; a two-argument sibling-style call does not replace it).
- `evals/run.py`'s `stage()` accepts the job `env` argument and still returns the four keys `sandbox_repo`, `prompt`, `target`, and `gh_env` (not a sibling Pattern A two-key shape).
- A forge eval's run directory under the `run-<ts>` tree carries `gh_calls.log`
  and `script_calls.log` copied from the staged target after
  `write_run_artifacts` when those files exist on the target.
- `RUNBOOK.md` and `evals/run.py` no longer instruct sequential-only runs as
  the correctness rule; they name `--workers 1` as the serial opt-in.
- In `tests/AGENTS.md` under `### Parallel workers`, and in `tests/CLAUDE.md`
  under `### Parallel workers: default 4 only where each job has its own
  sandbox`, the Pattern A `eval_runner` / `DEFAULT_PARALLEL_WORKERS` pool
  sentence names `tests/git_review/evals/run.py` among the parallel runners,
  and the prior sequential-list entry that named `git_review` for timeout
  contention is superseded in both files. One canonical parallel-policy
  statement remains per file; the two files stay in lockstep.
- The `git_review/` inventory row in `tests/CLAUDE.md` names `evals/`
  behavioral evals through `evals/run.py` in the shared
  `tests/lib/eval_runner` pool (sibling Pattern A form); the prior non-pool
  wording that ended at bare `via evals/run.py` is superseded, and one
  canonical pool statement remains in that row.
- The `**git_review/**` bullet in `tests/README.md` names the shared
  `tests/lib/eval_runner` pool beside the default Cursor worker (as
  `git_commit/` / `git_checkout/` already do); the prior non-pool clause
  ("default Cursor worker with a deterministic `grade.sh`") is superseded,
  and one canonical pool statement remains in that bullet.
- In `tests/git_review/evals/README.md`, the driver intro and `## Running`
  name the shared `eval_runner` pool and `--workers` defaulting to 4, with
  `--workers 1` as the serial opt-in, matching the sibling Pattern A
  `evals/README.md` shape; any prior sequential-only run story on those
  passages is superseded, and one canonical pool/`--workers` statement
  remains per passage.
- A graded run from `python3 tests/git_review/evals/run.py` (default vendor)
  writes its `run-<ts>` directory under `tests/git_review/workspace`, and
  `evals/run.py` names that path as the sole run root in place of
  `WORKSPACE = THIS / "workspace"`.
- In `RUNBOOK.md`, the `grade.sh` example under `## Grade an already-run
  sandbox` and the run-tree under `## Reading a run` each name
  `tests/git_review/workspace` as the only `run.py` run root. The prior root
  `tests/git_review/evals/workspace` is superseded in both passages.
- A `--workers 4 --force` timeout-band sample of ids 18, 41, and 2 in
  `tests/git_review/results/timeout-band.md` states either the raise outcome or the
  leave-at-600 outcome. On raise, `run.py --help` (or the argparse
  `default=`) shows the raised upper+300 `--timeout` value, this harness's
  RUNBOOK records that band, and that file states both. On leave,
  that file states that observed ceilings stayed clear of 600s with
  `--timeout` left at 600.
