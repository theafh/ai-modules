---
description: Run skill_doctor evals at default 4 workers through the shared helper, keep evals.json-derived ids, and prove isolation with a Cursor default run.
scope: tests/skill_doctor/evals
created: 2026-10-04T22:11:10
updated: 2026-10-08T22:06:22
status: open
reported-by: Andreas Hoffmann
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

This task consumes [the shared Pattern A eval runner](archive/tests_shared-pattern-a-eval-runner.md).

## Approach

Rewrite `evals/run.py` onto the shared helper: `--workers` 4, per-job `TMPDIR`,
evals.json-derived ids, and this runner's own `summary.json`, since the helper
prints its graded summary to stdout and writes no summary file. Keep the
checksum manifest `stage.sh` writes to `$target/.eval_checksums` as each eval's
escape check: it covers only that eval's own sandbox, so overlapping evals need
no staging marker or hook to keep their verdicts apart. Rewrite README / RUNBOOK
sequential language.

**Out of scope:** Changing `resolve_scope.py` / `discovery_safety.py` script
tests. Live-testing unshipped editorial plugin harnesses.

## Acceptance

- `run.py --help` shows `--workers` defaulting to 4.
- `python3 tests/skill_doctor/evals/run.py --vendor cursor` at the default
  prints a graded summary over every id in `evals.json`.
- A `--workers 4 --force` run of at least two uncached evals overlaps in
  `timing.json`, recorded under `tests/skill_doctor/results/`.
- Default ids remain derived from `evals.json`, not a frozen list.
