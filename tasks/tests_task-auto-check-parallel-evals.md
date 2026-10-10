---
description: Parallelize isolated task_auto_check evals at default 4 workers through the shared helper, and keep the repair-class nested loops sequential in the same run.
scope: tests/task_auto_check/evals
created: 2026-10-04T22:11:10
updated: 2026-10-09T17:46:37
status: open
reported-by: Andreas Hoffmann
---

# Parallelize isolated task_auto_check evals and keep repair-class loops sequential

## Goal

`python3 tests/task_auto_check/evals/run.py` runs every isolated eval
concurrently at default 4 workers, then runs the repair-class nested-loop evals
one at a time in the same invocation. Host `tasks/` fail-safes stay per-eval.
Cursor is the measurement vendor. The user-visible outcome: mechanical and
gate-only evals overlap, while the long repair loops still do not contend with
each other for the model.

## Context

`tests/CLAUDE.md` and `tests/task_auto_check/RUNBOOK.md` require repair-class
evals (`repair_to_ready`, `guard_rebaseline_after_gate`,
`interaction_scan_surfaces`, `immediate_ready_citations_overturn`) to run
sequentially because two nested loops in parallel both miss even an 1800s
timeout. `DEFAULT_IDS` is a frozen list. Each pass already micro-deploys the
skill, its sibling skills, and the `auto_*_task` agents through
`tests/lib/micro_deploy.py`. `WORKSPACE` is already
`tests/task_auto_check/workspace`. Timing-band measurement is a
separate remaining thread on the timeout-crash task.

This task consumes [the shared Pattern A eval runner](archive/tests_shared-pattern-a-eval-runner.md).
Cheap-first fixture probes in the RUNBOOK stay as operator guidance.

## Approach

Rewrite `evals/run.py` onto the shared helper. Derive the default id set from
`evals.json`. Split the run set by a harness key or a named repair-class set
in `evals.json` / the RUNBOOK: isolated evals go through the pool at default 4;
repair-class evals run with effective workers 1 after (or before) that pool,
never overlapping another repair-class job. Keep each pass's micro-deployment
inside its job. Keep the fixture-scoped host `tasks/` fail-safe
(`host_fixture_writes_clean` in `tests/lib/host_tasks_guard.sh`).

Rewrite the RUNBOOK sequential rule in place so it names the repair-class
subset only, and states that the rest of the suite uses the default 4 workers.
`--workers 1` still serializes everything.

**Out of scope:** Re-measuring the repair-class timing band, which
[the timeout-crash task](tests_eval-runner-timeout-crash.md) owns. Adding evals.
Live-testing unshipped editorial plugin harnesses.

## Acceptance

- `run.py --help` shows `--workers` defaulting to 4.
- Default ids are every id in `evals.json`; the frozen `DEFAULT_IDS` list is
  gone.
- A default-vendor run (no `--vendor`) prints a graded summary covering every id.
  Isolated evals in that run overlap in `timing.json`; the repair-class evals
  the RUNBOOK names have pairwise non-overlapping windows, recorded under
  `tests/task_auto_check/results/`.
- `RUNBOOK.md` no longer forbids concurrency for the whole suite; it forbids
  overlapping repair-class nested loops only.
