---
description: Run guardrail_audit evals at default 4 workers through the shared helper, derive ids from evals.json, and prove isolation with a Cursor default run.
scope: tests/guardrail_audit/evals
created: 2026-10-04T20:11:10Z
updated: 2026-11-05T22:29:16Z
status: finished
reported-by: Andreas Hoffmann
implemented-by: Andreas Hoffmann
design-extended: false
---

# Parallelize the guardrail_audit behavioral evals at default four workers

## Goal

`python3 tests/guardrail_audit/evals/run.py` runs the audit evals concurrently
at default 4 workers. Ids come from `evals.json`. Cursor is the measurement
vendor. The user-visible outcome: the staged fixtures overlap instead of
waiting on an unproven isolation story.

## Context

Operator docs list `guardrail_audit` as serial because "no isolation sweep has
proven concurrent evals yet." Each eval already stages its own sandbox through
`stage.sh`. `DEFAULT_IDS` is frozen and can silently skip a newly added eval.
`WORKSPACE` is `tests/guardrail_audit/evals/workspace`. Graders are
byte-identity plus response markers, so they share no TMPDIR scan with
`git_commit`.

This task consumes [the shared Pattern A eval runner](tests_shared-pattern-a-eval-runner.md).

## Approach

Rewrite `evals/run.py` onto the shared helper: derive ids from `evals.json`,
`--workers` 4, workspace `tests/guardrail_audit/workspace`, per-job `TMPDIR`.
When each uncached job writes `timing.json` through
`eval_runner.write_run_artifacts` (or equivalent), that file carries
wall-clock `started_at` and `ended_at` beside `duration_s`.
Keep the per-pass micro-deployment of the skill and the guardrail hub that the
runner's `ARTEFACTS` declaration names for both `--only` and `source_roots_for`. Rewrite README / RUNBOOK. In `tests/AGENTS.md` under `### Parallel workers`,
and in `tests/CLAUDE.md` under `### Parallel workers: default 4 only where
each job has its own sandbox`, rewrite the Pattern A runners on
`eval_runner` at `vendor.DEFAULT_PARALLEL_WORKERS` sentence in place so
`tests/guardrail_audit/evals/run.py` joins that set beside the existing
runners, and supersede the sequential-list bullet
`` `guardrail_audit`, `skill_doctor` — still serial; no isolation sweep
has proven concurrent evals yet. `` so the remaining bullet among that pair
names only `skill_doctor` with its isolation-sweep serial reason; both
files keep their existing bullet-or-prose list shape.

**Out of scope:** Changing audit fixtures or the skill. Live-testing unshipped
editorial plugin harnesses.

## Acceptance

- `run.py --help` shows `--workers` defaulting to 4.
- Frozen `DEFAULT_IDS` is gone; the default run set is every id in `evals.json`.
- `python3 tests/guardrail_audit/evals/run.py` at the default worker count
  prints a graded summary over that set.
- A graded run from `python3 tests/guardrail_audit/evals/run.py` writes its `run-<ts>` directory under the run root named in `## Approach`, `tests/guardrail_audit/workspace`, and `evals/run.py` obtains that path through `eval_runner.resolve_workspace` as the sole run root in place of `WORKSPACE = THIS / "workspace"`.
- Each uncached `timing.json` from one `--workers 4 --force` run of at least
  two uncached evals records `started_at` and `ended_at` beside `duration_s`.
  `tests/guardrail_audit/results/parallel-workers-windows.md` records those
  windows. When two windows overlap, that file records that overlap. When no
  two windows overlap, that file records the windows, the change stays
  incomplete, and the follow-up is one rerun of that same command once the
  pool overlaps.
- In `tests/AGENTS.md` under `### Parallel workers`, and in `tests/CLAUDE.md`
  under `### Parallel workers: default 4 only where each job has its own
  sandbox`, the Pattern A runners on `eval_runner` at
  `vendor.DEFAULT_PARALLEL_WORKERS` sentence names
  `tests/guardrail_audit/evals/run.py` among the parallel runners; the prior
  pool sentence that omitted this runner is superseded in both files.
- In those same two Parallel-workers sections, the prior sequential-list
  bullet `` `guardrail_audit`, `skill_doctor` — still serial; no isolation
  sweep has proven concurrent evals yet. `` is superseded in both files so
  the remaining bullet among that pair names only `skill_doctor` with its
  isolation-sweep serial reason; each file keeps one canonical sequential
  entry for that pair.
