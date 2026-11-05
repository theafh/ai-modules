---
description: Run task_fix evals at default 4 workers with per-eval host-tasks fail-safes that stay correct under overlap, using the shared Pattern A helper.
scope: tests/task_fix/evals
created: 2026-10-04T22:11:10
updated: 2026-11-05T08:02:13
status: finished
reported-by: Andreas Hoffmann
implemented-by: Andreas Hoffmann
design-extended: false
---

# Parallelize the task_fix behavioral evals without mixing host-tree fail-safes

## Goal

`python3 tests/task_fix/evals/run.py` runs the repeated-link protocol evals
concurrently at default 4 workers. Host `tasks/` mtime checks stay per-eval,
including the `api_*.md` find. Cursor is the measurement vendor. The
user-visible outcome: every id in `evals.json` overlaps instead of serializing
to keep the host tree quiet.

## Context

The runner is a sequential family copy. `WORKSPACE` is already
`tests/task_fix/workspace`. Ids come from `evals.json`. `evals/grade.sh` checks
the host `tasks/` tree through `host_fixture_writes_clean` in
`tests/lib/host_tasks_guard.sh`: a fixture name the sandbox staged, such as an
`api_*.md` file, fails the eval when it appears, moves, or is newer than the
eval marker, while edits to other live tasks stay outside the comparison. Run
dirs include `os.getpid()` in the folder name. The shared helper resolves only
the workspace root (`resolve_workspace`), so run-dir naming stays with this
runner.

This task consumes [the shared Pattern A eval runner](tests_shared-pattern-a-eval-runner.md).
The fail-safe contract matches [the task-hub parallel task](tests_task-hub-parallel-evals.md).

## Approach

Rewrite `evals/run.py` onto the shared helper: `--workers` 4, per-job `TMPDIR`,
and this runner's own run-dir naming under the workspace the helper resolves.
Keep `grade.sh`'s fixture-scoped host-tree checks. In `tests/CLAUDE.md` under `### Parallel workers: default 4 only where each job has its own sandbox`, and in `tests/AGENTS.md` under `### Parallel workers`, rewrite both lists in place: add `tests/task_fix/evals/run.py` to the Pattern A runners on `eval_runner` at `vendor.DEFAULT_PARALLEL_WORKERS`, and supersede the sequential Pattern A entry that names `task_fix` so that entry no longer names `task_fix`, with whichever sibling runners it still names read from the tree at implementation time. Rewrite
RUNBOOK sequential guidance. Prove concurrency and an unchanged host `tasks/`
tree on a Cursor `--force` pair.
When each uncached job writes `timing.json` through
`eval_runner.write_run_artifacts` (or equivalent), that file carries
wall-clock `started_at` and `ended_at` beside `duration_s`.

**Out of scope:** Changing the repeated-link protocol under test.
Live-testing unshipped editorial plugin harnesses.

## Acceptance

- `run.py --help` shows `--workers` defaulting to 4.
- `python3 tests/task_fix/evals/run.py` at the default worker count prints a
  graded summary over every id in `evals.json`.
- In `tests/CLAUDE.md` under `### Parallel workers: default 4 only where each job has its own sandbox`, and in `tests/AGENTS.md` under `### Parallel workers`, the Pattern A runners on `eval_runner` at `vendor.DEFAULT_PARALLEL_WORKERS` name `tests/task_fix/evals/run.py`, and the prior sequential entry that lists `task_fix` is superseded so that entry no longer names `task_fix`, with whichever sibling runners it still names read from the tree at implementation time.
- Each uncached `timing.json` from one `--workers 4 --force` run of at least
  two uncached evals records `started_at` and `ended_at` beside `duration_s`.
  `tests/task_fix/results/parallel_workers_measure.md` records those windows
  and that the run left host `tasks/` unchanged. When two windows overlap,
  that file records that overlap. When no two windows overlap, that file
  records the windows, the change stays incomplete, and the follow-up is one
  rerun of that same command once the pool overlaps.
- `grade.sh` still fails when a host `tasks/api_*.md` file that eval's sandbox
  staged is newer than that eval's marker.
