---
description: Run skill_doctor evals at default 4 workers through the shared helper, keep evals.json-derived ids, and prove isolation with a Cursor default run.
scope: tests
created: 2026-10-04T22:11:10
updated: 2026-11-06T22:40:12
status: finished
reported-by: Andreas Hoffmann
implemented-by: Andreas Hoffmann
design-extended: false
---

# Parallelize the skill_doctor behavioral evals at default four workers

## Goal

`python3 tests/skill_doctor/evals/run.py` runs doctor evals concurrently at
default 4 workers. Cursor is the measurement vendor. The user-visible outcome:
the staged fixtures overlap instead of remaining serial pending an isolation
sweep.

## Context

Operator docs list `skill_doctor` with `guardrail_audit` as serial until proven.
Ids already come from `evals.json` via `all_eval_ids()` after a frozen list
silently skipped new evals. `WORKSPACE` is already `tests/skill_doctor/workspace`.
`stage.sh` does not stamp `.eval_started_at` the way sibling harnesses do;
checksum manifests still prove the check-only contract. The runner already
writes `summary.json`.

This task consumes [the shared Pattern A eval runner](tests_shared-pattern-a-eval-runner.md).

## Approach

Rewrite `evals/run.py` onto the shared helper: `--workers` 4, per-job `TMPDIR`,
evals.json-derived ids, and this runner's own `summary.json`, since the helper
prints its graded summary to stdout and writes no summary file. Preserve the
shipped vendor-resolved micro-deployment, verdict cache, `worker_isolation`
sandbox roots, and read-provenance gate. Replace the serial dict comprehension
with `eval_runner.run_jobs` / `add_workers_argument` and an `on_error` callback,
and write each uncached `timing.json` through `eval_runner.write_run_artifacts`
with `started_at` and `ended_at` passed as extra timing fields beside
`duration_s`. Thread the job environment `run_jobs` hands each job into every
subprocess that job starts: `stage()` passes it as `env=` to `stage.sh`; the
micro-deployment env takes the job's `TMPDIR`/`TEMP`/`TMP` before
`micro_deploy.run_worker`, the way `tests/git_commit/evals/run.py` does; and the
`grade.sh` call passes it as `env=`. Each job's fresh temp directory is then the
one its stage, worker, and grader all use. Keep the checksum manifest `stage.sh` writes to
`$target/.eval_checksums` as each eval's escape check and keep the micro-deploy
read-integrity gate: the manifest covers only that eval's own sandbox, so
overlapping evals need no staging marker or hook to keep their verdicts apart.
Document the default 4-worker pool and `--workers` in README/RUNBOOK.

In `tests/AGENTS.md` under `### Parallel workers`, and in `tests/CLAUDE.md`
under `### Parallel workers: default 4 only where each job has its own
sandbox`, add `tests/skill_doctor/evals/run.py` to the Pattern A runners on
`eval_runner` at `vendor.DEFAULT_PARALLEL_WORKERS` sentence and supersede the
remaining `skill_doctor` sequential bullet, leaving the `agent_spinner` bullet
in place. Land this task after `tasks/archive/tests_guardrail-audit-parallel-evals.md`,
which rewrites that sentence and bullet in both files, so these edits apply on
that task's shipped text.

**Out of scope:** Changing `resolve_scope.py` / `discovery_safety.py` script
tests. Live-testing unshipped editorial plugin harnesses.

## Acceptance

- `run.py --help` shows `--workers` defaulting to 4.
- `python3 tests/skill_doctor/evals/run.py` at the default worker count
  prints a graded summary over every id in `evals.json`.
- A `--workers 4 --force` run of at least two uncached evals records
  `started_at` and `ended_at` for each eval in
  `tests/skill_doctor/workspace/run-<ts>/<id>/timing.json`, and
  `tests/skill_doctor/results/parallel-workers-windows.md` records those
  windows. When two windows overlap, that file records the overlap. When no two
  windows overlap, that file records the windows, the change stays incomplete,
  and the follow-up is one rerun of that same command once the pool overlaps.
- Default ids remain derived from `evals.json`, not a frozen list.
- In `tests/AGENTS.md` under `### Parallel workers`, and in `tests/CLAUDE.md`
  under `### Parallel workers: default 4 only where each job has its own
  sandbox`, the Pattern A runners on `eval_runner` at
  `vendor.DEFAULT_PARALLEL_WORKERS` sentence names
  `tests/skill_doctor/evals/run.py`, and neither file carries a sequential-list
  entry for `skill_doctor`.
