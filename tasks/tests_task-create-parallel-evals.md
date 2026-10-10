---
description: Run task_create evals at default 4 workers with per-eval host-tasks fail-safes that stay correct under overlap, using the shared Pattern A helper.
scope: tests/task_create/evals
created: 2026-10-04T22:11:10
updated: 2026-10-09T18:10:40
status: open
reported-by: Andreas Hoffmann
---

# Parallelize the task_create behavioral evals without mixing host-tree fail-safes

## Goal

`python3 tests/task_create/evals/run.py` runs the create-path evals concurrently
at default 4 workers. Host `tasks/` mtime checks stay per-eval. Cursor is the
measurement vendor. The user-visible outcome: the three Decide-or-label evals
overlap instead of running one after another to keep the host tree quiet.

## Context

The runner is a sequential copy of the family Pattern A loop. `evals/grade.sh`
checks the host `tasks/` tree through `host_fixture_writes_clean` in
`tests/lib/host_tasks_guard.sh`: a fixture name the sandbox staged fails the
eval when it appears, moves, or is newer than `$target/.eval_started_at`, while
edits to other live tasks stay outside the comparison. `WORKSPACE` is
`tests/task_create/evals/workspace`. Ids already come from `evals.json`.

This task consumes [the shared Pattern A eval runner](archive/tests_shared-pattern-a-eval-runner.md).
The fail-safe contract matches [the task-hub parallel task](tests_task-hub-parallel-evals.md).

## Approach

Rewrite `evals/run.py` onto the shared helper: `--workers` 4, workspace
`tests/task_create/workspace`, per-job `TMPDIR`. Keep `grade.sh` marker checks.
Rewrite RUNBOOK / evals README sequential guidance. Prove host `tasks/` stays
unchanged across a concurrent `--force` pair, and that a planted newer host
file carrying one eval's fixture name still fails that eval.

**Out of scope:** `tests/task/script_tests/`, which already covers the bundled
scripts this skill drives. Live-testing unshipped editorial plugin harnesses.

## Acceptance

- `run.py --help` shows `--workers` defaulting to 4.
- `python3 tests/task_create/evals/run.py` at the default worker count prints
  a graded summary over every id in `evals.json`.
- A `--workers 4 --force` run of at least two uncached evals overlaps in
  `timing.json` and leaves host `tasks/` unchanged, recorded under
  `tests/task_create/results/`.
- `grade.sh` still fails when a host `tasks/` file carrying one of that eval's
  fixture names is newer than its marker.
