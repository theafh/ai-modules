---
description: Run git_review evals at default 4 workers through the shared helper, isolate per-eval temp files, and treat model contention as a timeout-tuning problem rather than a serial requirement.
scope: tests/git_review/evals
created: 2026-10-04T22:11:10
updated: 2026-10-04T22:11:10
status: open
reported-by: Andreas Hoffmann
---

# Parallelize the git_review behavioral evals at default four workers

## Goal

`python3 tests/git_review/evals/run.py` runs isolated review evals concurrently
with `--workers` defaulting to 4. Per-eval timeout stays the deadline that fails
one slow worker, not a reason to serialize the suite. Cursor is the measurement
vendor; Claude remains a compatibility vendor through the same helper. The
user-visible outcome: a large review sweep overlaps workers instead of running
one eval at a time because two jobs might contend for the model.

## Context

`tests/git_review/evals/run.py` is sequential on purpose: "two review workers on
one machine contend for the model and both slow past the per-eval timeout."
Default `--timeout` is 600s. `evals/grade.sh` already stages per-eval sandboxes
and writes a Python snippet under `${TMPDIR:-/tmp}/git_review_grade.XXXXXX.py`.
`tests/git_review/RUNBOOK.md` repeats the sequential instruction.

Contention can still lengthen a job. That is a timeout and `--workers` tuning
concern. Isolated sandboxes already exist, so correctness does not require a
single-file walk.

This task consumes [the shared Pattern A eval runner](archive/tests_shared-pattern-a-eval-runner.md).
[The timeout-crash task](tests_eval-runner-timeout-crash.md) still owns the
`task_auto_check` timing band, not this harness.

## Approach

Rewrite `evals/run.py` onto the shared helper: `--workers` default 4, per-job
`TMPDIR` so grade.sh's `mktemp` cannot collide, workspace at
`tests/git_review/workspace`. Keep vendor resolution on `tests/lib/vendor.py`.
Rewrite the sequential comment and the RUNBOOK sentence that forbids concurrent
review workers.

If a `--vendor cursor --workers 4` `--force` sample of a representative subset
shows `duration_s` crowding the 600s default, raise this harness's `--timeout`
default above the observed ceiling with the same headroom shape
`task_auto_check` uses, and record the band in the RUNBOOK. `--workers 1`
remains the latency reading.

**Out of scope:** Adding review evals. Changing `collect_review_evidence.sh`.
Live-testing unshipped editorial plugin harnesses.

## Acceptance

- `run.py --help` shows `--workers` defaulting to 4 and still documents
  `--timeout`.
- `python3 tests/git_review/evals/run.py --vendor cursor` at the default worker
  count prints a graded summary over every id in `evals.json` (or a named
  subset plus a second `--force` pair that proves overlap), with no TypeError
  on a timeout path.
- A `--workers 4 --force` run of at least two uncached evals writes overlapping
  `timing.json` windows, recorded under `tests/git_review/results/`.
- `RUNBOOK.md` and `evals/run.py` no longer instruct sequential-only runs as
  the correctness rule; they name `--workers 1` as the serial opt-in.
