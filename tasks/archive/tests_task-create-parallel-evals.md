---
description: Run task_create evals at default 4 workers with per-eval host-tasks fail-safes that stay correct under overlap, using the shared Pattern A helper.
scope: tests/task_create/evals
created: 2026-10-04T20:11:10Z
updated: 2026-11-04T11:59:12Z
status: finished
reported-by: Andreas Hoffmann
implemented-by: Andreas Hoffmann
design-extended: false
---

# Parallelize the task_create behavioral evals without mixing host-tree fail-safes

## Goal

`python3 tests/task_create/evals/run.py` runs the create-path evals concurrently
at default 4 workers. Host `tasks/` mtime checks stay per-eval. Cursor is the
measurement vendor. The user-visible outcome: every create-path eval this runner owns
(every id in `evals.json`, re-found at implementation time) overlaps
instead of running one after another to keep the host tree quiet.

## Context

The runner is a sequential copy of the family Pattern A loop. `evals/grade.sh`
checks the host `tasks/` tree through `host_fixture_writes_clean` in
`tests/lib/host_tasks_guard.sh`: a fixture name the sandbox staged fails the
eval when it appears, moves, or is newer than `$target/.eval_started_at`, while
edits to other live tasks stay outside the comparison. `WORKSPACE` is
`tests/task_create/evals/workspace`. Ids already come from `evals.json`.

This task consumes [the shared Pattern A eval runner](tests_shared-pattern-a-eval-runner.md).
The fail-safe contract matches [the task-hub parallel task](tests_task-hub-parallel-evals.md).

## Approach

Rewrite `evals/run.py` onto the shared helper: `--workers` 4, per-job
`TMPDIR`, and replace `WORKSPACE = THIS / "workspace"` with
`eval_runner.resolve_workspace` so the sole run root is
`tests/task_create/workspace`. When each uncached job writes `timing.json` (via
`eval_runner.write_run_artifacts` or equivalent), that file keeps every field
the current writer already records there—including `skill_name`,
`artefacts_read_from_micro_deployment`, `checkout_unread`, and `duration_s`—and
adds wall-clock `started_at` and `ended_at` beside `duration_s`. Keep
`grade.sh` marker checks. In `tests/task_create/RUNBOOK.md` under `## Reading a
failure`, rewrite the sentence that begins `Each run writes
`evals/workspace/run-<ts>/<id>/`:` in place so it names
`tests/task_create/workspace/run-<ts>/<id>/` as the only run path. Rewrite
RUNBOOK / evals README sequential guidance. In `tests/CLAUDE.md` under `###
Parallel workers: default 4 only where each job has its own sandbox`, and in
`tests/AGENTS.md` under `### Parallel workers`, rewrite both sections in place:
drop `task_create` from the Pattern A runners that stay sequential, leaving the
other listed exceptions in place, with whichever sibling runners that entry
still names read from the tree at implementation time, and add
`tests/task_create/evals/run.py` among the Pattern A runners on `eval_runner`
at `vendor.DEFAULT_PARALLEL_WORKERS`. Measure with one `--workers 4 --force`
run of at least two uncached evals on the default vendor (no `--vendor`), and
record its overlap evidence and host-tree outcome in
`tests/task_create/results/parallel_workers_measure.md`, the measurement
record the Acceptance items below read. Prove that run leaves host `tasks/`
unchanged, and that a planted newer host file carrying one eval's fixture name
still fails that eval.

**Out of scope:** `tests/task/script_tests/`, which already covers the bundled
scripts this skill drives. Live-testing unshipped editorial plugin harnesses.

## Acceptance

- `run.py --help` shows `--workers` defaulting to 4.
- In `tests/CLAUDE.md` under `### Parallel workers: default 4 only where each
  job has its own sandbox`, and in `tests/AGENTS.md` under `### Parallel
  workers`, the Pattern A runners on `eval_runner` at
  `vendor.DEFAULT_PARALLEL_WORKERS` name `tests/task_create/evals/run.py`, and
  the prior sequential entry that lists `task_create` is superseded so that
  entry no longer names `task_create`, with whichever sibling runners it still
  names read from the tree at implementation time.
- `python3 tests/task_create/evals/run.py` at the default worker count prints
  a graded summary over every id in `evals.json`.
- A graded run from `python3 tests/task_create/evals/run.py` writes its
  `run-<ts>` directory under the run root named in `## Approach`,
  `tests/task_create/workspace`, and `evals/run.py` obtains that path
  through `eval_runner.resolve_workspace` as the sole run root in place
  of `WORKSPACE = THIS / "workspace"`.
- In `tests/task_create/RUNBOOK.md`, the sentence that begins ``Each run writes `evals/workspace/run-<ts>/<id>/`:`` is superseded so it names `tests/task_create/workspace/run-<ts>/<id>/` as the only `run.py` run-root layout, with the prior root `tests/task_create/evals/workspace` superseded, so one canonical statement remains.
- Each uncached job's `timing.json` from a `--workers 4 --force` run of at
  least two uncached evals on the default vendor (no `--vendor`) keeps every
  field the current writer already records there—including `skill_name`,
  `artefacts_read_from_micro_deployment`, `checkout_unread`, and
  `duration_s`—and carries `started_at` and `ended_at` beside `duration_s`;
  those windows overlap; that run leaves `git status --porcelain` of host
  `tasks/` unchanged; the
  `tests/task_create/results/parallel_workers_measure.md` record shows that
  overlap and host-tree outcome; when the windows do not overlap or host
  `tasks/` changed, that record states the miss and parallelization is not
  shipped.
- `grade.sh` still fails when a host `tasks/` file carrying one of that eval's
  fixture names is newer than its marker.
- A `--workers 4 --force` run of at least two uncached evals shows distinct per-job `TMPDIR` values, or `evals/run.py` invokes `eval_runner.run_jobs` (which always installs them).
