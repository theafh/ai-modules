---
description: Run task_fix evals at default 4 workers with per-eval host-tasks fail-safes that stay correct under overlap, using the shared Pattern A helper.
scope: tests/task_fix/evals
created: 2026-10-04T22:11:10
updated: 2026-10-09T18:10:40
status: open
reported-by: Andreas Hoffmann
---

# Parallelize the task_fix behavioral evals without mixing host-tree fail-safes

## Goal

`python3 tests/task_fix/evals/run.py` runs the repeated-link protocol evals
concurrently at default 4 workers. Host `tasks/` mtime checks stay per-eval,
including the `api_*.md` find. Cursor is the measurement vendor. The
user-visible outcome: the three protocol evals overlap instead of serializing
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

This task consumes [the shared Pattern A eval runner](archive/tests_shared-pattern-a-eval-runner.md).
The fail-safe contract matches [the task-hub parallel task](tests_task-hub-parallel-evals.md).

## Approach

Rewrite `evals/run.py` onto the shared helper: `--workers` 4, per-job `TMPDIR`,
and this runner's own run-dir naming under the workspace the helper resolves.
Keep `grade.sh`'s fixture-scoped host-tree checks. Rewrite
RUNBOOK sequential guidance. Prove concurrency and an unchanged host `tasks/`
tree on a Cursor `--force` pair.

**Out of scope:** Changing the repeated-link protocol under test.
Live-testing unshipped editorial plugin harnesses.

## Acceptance

- `run.py --help` shows `--workers` defaulting to 4.
- `python3 tests/task_fix/evals/run.py` at the default worker count prints a
  graded summary over every id in `evals.json`.
- A `--workers 4 --force` run of at least two uncached evals overlaps in
  `timing.json` and leaves host `tasks/` unchanged, recorded under
  `tests/task_fix/results/`.
- `grade.sh` still fails when a host `tasks/api_*.md` file that eval's sandbox
  staged is newer than that eval's marker.
