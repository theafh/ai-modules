---
description: Parallelize isolated task_auto_check evals at default 4 workers through the shared helper, and keep the Approach serial nested-loop set sequential in the same run.
scope: tests/task_auto_check/evals
created: 2026-10-04T22:11:10
updated: 2026-10-13T18:22:31
status: ready
reported-by: Andreas Hoffmann
---

# Parallelize isolated task_auto_check evals and keep the Approach serial nested-loop set sequential

## Goal

`python3 tests/task_auto_check/evals/run.py` runs every isolated eval
concurrently at default 4 workers, then runs the Approach serial nested-loop set
one at a time in the same invocation. Host `tasks/` fail-safes stay per-eval.
Cursor is the measurement vendor. The user-visible outcome: every isolated eval (every eval outside the Approach
serial nested-loop set) overlaps, while that serial nested-loop set still does not
contend with itself for the model.

## Context

`tests/task_auto_check/RUNBOOK.md` requires its repair-class six to run
sequentially, and `tests/CLAUDE.md` states the deep-repair-loop sequential
rule without naming the timeout-table six, because two nested loops in parallel
both miss even a 2305s timeout. Approach extends that documented serial set by
adding the timeout-table full-repair peers to the serial nested-loop set it
names. `DEFAULT_IDS` is already derived from `evals.json` via `_all_eval_ids()`. Each pass already micro-deploys the
skill, its sibling skills, and the `auto_*_task` agents through
`tests/lib/micro_deploy.py`. `WORKSPACE` is already
`tests/task_auto_check/workspace`. Timing-band measurement already closed on the archived [timeout-crash task](archive/tests_eval-runner-timeout-crash.md), which owns re-measuring that band.

This task consumes [the shared Pattern A eval runner](archive/tests_shared-pattern-a-eval-runner.md).
Cheap-first fixture probes in the RUNBOOK stay as operator guidance.

## Approach

Rewrite `evals/run.py` onto the shared helper. Derive the default id set from
`evals.json`. Split the run set by one serial nested-loop set — the RUNBOOK repair-class six (`repair_to_ready`, `relay_by_path`, `stray_hunk_reverted`, `guard_rebaseline_after_gate`, `interaction_scan_surfaces`, `immediate_ready_citations_overturn`) plus the timeout-table full-repair peers (`regroup_via_reviewer`, `regroup_immediate_ready`, `regroup_same_paragraph_ready`, `committed_rule_deletion_routed`, `last_call_ready_refuted`, `regate_isolated`): isolated evals go through the pool at default 4; that serial set runs with effective workers 1 after that pool, never overlapping another serial-set job. Keep each pass's micro-deployment
inside its job. When each job calls `write_run_artifacts` (or equivalent), keep in that job's workspace `timing.json` under `tests/task_auto_check/workspace/run-*/` every field the current writer already records there—including `skill_name`, `artefacts_read_from_micro_deployment`, `checkout_unread`, and `duration_s`—and add wall-clock bounds `started_at` and `ended_at` (Unix epoch seconds, or an equivalent pair of comparable timestamps) as extras (or an equivalent write). Keep the fixture-scoped host `tasks/` fail-safe
(`host_fixture_writes_clean` in `tests/lib/host_tasks_guard.sh`).

Rewrite the RUNBOOK sequential rule that begins `**Run repair-class evals sequentially, never concurrently.**` (and keep "Launch one `run.py` invocation at a time" in the same rewrite) in place so it names that Approach serial nested-loop set only, and states that the rest of the suite uses the default 4 workers.
`--workers 1` still serializes everything. Rewrite the Parallel workers intro
sentences and the parallel-workers conversion lists in `tests/CLAUDE.md` and
`tests/AGENTS.md` in place: intros that today name only the `task_auto_check`
repair-class nested loops name the Approach serial nested-loop set instead;
drop `task_auto_check` from the Pattern A runners that stay sequential until
sibling conversion lands, and name the serial nested-loop set Approach names
as that sequential exception.

**Out of scope:** Re-measuring the repair-class timing band, which
the timeout-crash task owns. Adding evals.
Live-testing unshipped editorial plugin harnesses.

## Acceptance

- `run.py --help` shows `--workers` defaulting to 4.
- `grade.sh` still fails an eval when a host `tasks/` fixture name that eval's
  sandbox staged is newer than that eval's marker (`host_fixture_writes_clean`
  in `tests/lib/host_tasks_guard.sh`).
- Each eval job in `run.py` still runs its micro-deployment inside that job,
  not once around the worker pool.
- Each eval job's workspace `timing.json` under
  `tests/task_auto_check/workspace/run-*/` still carries every field the
  current writer already records there—including `skill_name`,
  `artefacts_read_from_micro_deployment`, `checkout_unread`, and
  `duration_s`—and also carries `started_at` and `ended_at`.
- A `--force` (or otherwise uncached) `--workers 1` run of at least two isolated evals writes pairwise non-overlapping workspace `timing.json` windows via `started_at`/`ended_at` under `tests/task_auto_check/workspace/run-*/`; the recorded measurement evidence under `tests/task_auto_check/results/` shows those windows.
- Default ids remain every id in `evals.json`, supplied through the shared helper's
  `load_eval_ids` (or equivalent) after the runner lands on that helper.
- A default-vendor run (no `--vendor`) prints a graded summary covering every id.
  A `--force` (or otherwise uncached) measurement of that run shows isolated
  evals overlapping in workspace `timing.json` via `started_at`/`ended_at`; the
  serial nested-loop evals Approach names have pairwise non-overlapping windows
  there; the recorded measurement evidence under
  `tests/task_auto_check/results/` shows those windows.
- In that same default-vendor measurement's workspace `timing.json` records,
  every serial nested-loop eval Approach names has `started_at` at or
  after every isolated eval's `ended_at` (the isolated pool finishes before any
  serial nested-loop window begins); the recorded measurement evidence under
  `tests/task_auto_check/results/` shows that order.
- `RUNBOOK.md` no longer forbids concurrency for the whole suite; it forbids
  overlapping the serial nested-loop set Approach names only, states that the
  rest of the suite uses the default 4 workers, and keeps "Launch one
  `run.py` invocation at a time" in that rewritten sequential rule.
- `tests/CLAUDE.md` and `tests/AGENTS.md` Parallel workers intros name the
  Approach serial nested-loop set rather than only the `task_auto_check`
  repair-class nested loops; both no longer list `task_auto_check` among
  Pattern A runners that stay sequential until conversion; both still name
  the serial nested-loop set Approach names as a sequential exception.
