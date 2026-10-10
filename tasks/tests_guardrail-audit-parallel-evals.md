---
description: Run guardrail_audit evals at default 4 workers through the shared helper, derive ids from evals.json, and prove isolation with a Cursor default run.
scope: tests/guardrail_audit/evals
created: 2026-10-04T22:11:10
updated: 2026-10-09T18:10:40
status: open
reported-by: Andreas Hoffmann
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

This task consumes [the shared Pattern A eval runner](archive/tests_shared-pattern-a-eval-runner.md).

## Approach

Rewrite `evals/run.py` onto the shared helper: derive ids from `evals.json`,
`--workers` 4, workspace `tests/guardrail_audit/workspace`, per-job `TMPDIR`.
Keep the per-pass micro-deployment of the skill and the guardrail hub that the
runner's `ARTEFACTS` declaration names for both `--only` and `source_roots_for`. Rewrite README / RUNBOOK. Drop the "until an
isolation sweep" sentence wherever this harness still carries it after the
shared-runner docs land.

**Out of scope:** Changing audit fixtures or the skill. Live-testing unshipped
editorial plugin harnesses.

## Acceptance

- `run.py --help` shows `--workers` defaulting to 4.
- Frozen `DEFAULT_IDS` is gone; the default run set is every id in `evals.json`.
- `python3 tests/guardrail_audit/evals/run.py` at the default worker count
  prints a graded summary over that set.
- A `--workers 4 --force` run of at least two uncached evals overlaps in
  `timing.json`, recorded under `tests/guardrail_audit/results/`.
