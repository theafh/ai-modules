---
description: Point language_humanizer's already-parallel, isolated pool at the shared eval-runner helper without changing the five-pass measurement.
scope: tests/language_humanizer/evals
created: 2026-10-04T22:11:10
updated: 2026-10-08T22:56:55
status: open
reported-by: Andreas Hoffmann
---

# Deduplicate the language_humanizer pool onto the shared eval runner

## Goal

`tests/language_humanizer/evals/run.py` keeps its fixed-denominator concurrent
passes at default 4 workers and drives them through the shared helper instead
of a private `ThreadPoolExecutor`. Isolation, vendor, and judge behavior stay
as the isolation task left them. The user-visible outcome: this harness remains
the Pattern A parallel reference without a second copy of the pool.

## Context

This runner already parallelizes (`vendor.DEFAULT_PARALLEL_WORKERS`) and
deliberately skips the verdict cache because repeated draws are the
measurement. [The isolation task](archive/tests_language-humanizer-worker-isolation.md)
already runs each pass and the judge under `tests/lib/worker_isolation.py`, and
[the shared Pattern A eval runner](archive/tests_shared-pattern-a-eval-runner.md)
shipped as `tests/lib/eval_runner.py`, so the pool can switch now.

The `ai_editorial` plugin ships this skill, and the isolated five-pass Cursor
measurement is recorded in
`tests/language_humanizer/results/isolation-comparison.md`, so this task
changes only how the pool runs.

## Approach

Replace the local executor with the shared pool helper. Keep `--passes`,
`--workers` default 4, per-pass sandbox ownership, and
the judge call. Do not add `eval_cache`. Rewrite the module docstring so the
pool is the shared helper rather than a private executor.

**Out of scope:** Changing grader rubrics, the five-pass contract, or plugin
shipping. A five-pass live cursor re-measure, which the isolation task owns.

## Acceptance

- `evals/run.py` imports the shared helper and contains no
  `ThreadPoolExecutor` construction of its own.
- `run.py --help` still defaults `--workers` to 4 and `--passes` to 5.
- `python3 tests/lib/test_eval_runner.py` still passes after this import.
- A `--passes 1 --workers 1 --vendor cursor` plumbing run of one scenario
  still writes `verdict.json` under the run dir.
