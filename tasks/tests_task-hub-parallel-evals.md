---
description: Run tests/task evals at default 4 workers with per-eval host-tasks fail-safes that stay correct under overlap, using the shared Pattern A helper.
scope: tests/task/evals
created: 2026-10-04T22:11:10
updated: 2026-10-08T22:06:22
status: open
reported-by: Andreas Hoffmann
---

# Parallelize the task-hub behavioral evals without mixing host-tree fail-safes

## Goal

`python3 tests/task/evals/run.py` runs family-hub evals concurrently at default
4 workers. Each eval still fails if one of its own fixture names appears,
moves, or is newer than that eval's marker in the host `tasks/` tree, and
concurrent sandboxed workers do not trip that check for each other. Cursor is the measurement vendor. The user-visible
outcome: hub evals overlap instead of walking the family one id at a time to
keep the filesystem quiet.

## Context

`tests/task/evals/run.py` is sequential "so each worker's sandbox isolation
checks stay unambiguous and the host filesystem quiet." `evals/grade.sh` checks
the host tree through `host_fixture_writes_clean` in
`tests/lib/host_tasks_guard.sh`, which compares the live `tasks/` tree with the
isolated copy `stage.sh` takes, only for the sandbox's own fixture names and
against the marker `stage.sh` stamps at `$target/.eval_started_at`. `WORKSPACE` is
`tests/task/evals/workspace`. Ids already come from `evals.json` via
`_all_eval_ids()`.

Sandboxed workers that never write the host tree can overlap. The fail-safe
stays per-eval, marker-scoped, and fixture-scoped: an operator edit of a task
the sandbox does not name stays outside the comparison, as `tests/CLAUDE.md`
documents under the heading "Host `tasks/` during a task-family run".

This task consumes [the shared Pattern A eval runner](archive/tests_shared-pattern-a-eval-runner.md).
Sibling harnesses with the same fail-safe are
[task_create](tests_task-create-parallel-evals.md) and
[task_fix](tests_task-fix-parallel-evals.md).

## Approach

Rewrite `evals/run.py` onto the shared helper: `--workers` 4, workspace
`tests/task/workspace`, per-job `TMPDIR`. Keep `grade.sh`'s fixture-scoped host
check as the escape guard. The helper's before/after hooks only serialize
snapshots, so any hook this harness adds uses the job index the helper passes
to claim only that eval's fixture names. Stamp the marker immediately before
the worker starts (or keep the staging-time stamp if a plumbing run shows no
cross-talk). Rewrite the sequential comment and the harness RUNBOOK.

Prove with a hermetic case that two overlapping jobs whose sandboxes stay
inside their targets leave host `tasks/` untouched, and that a deliberate newer
file carrying one eval's fixture name under host `tasks/` fails that eval while
an overlapping eval with other fixture names stays green.

**Out of scope:** The `script_tests/` and `contract_run.sh` surfaces. Deep
`task_auto_check` repair loops, which
[the auto_check parallel task](tests_task-auto-check-parallel-evals.md) owns.
Live-testing unshipped editorial plugin harnesses.

## Acceptance

- `run.py --help` shows `--workers` defaulting to 4.
- `python3 tests/task/evals/run.py --vendor cursor` at the default prints a
  graded summary over every id from `evals.json`.
- A `--workers 4 --force` run of at least two uncached evals overlaps in
  `timing.json` and leaves `git status --porcelain` of host `tasks/` unchanged,
  recorded under `tests/task/results/`.
- `grade.sh` still fails an eval when one of that eval's fixture names is newer
  than its marker in the host `tasks/` tree.
