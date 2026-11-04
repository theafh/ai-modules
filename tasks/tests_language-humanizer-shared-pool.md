---
description: Point language_humanizer's already-parallel, isolated pool at the shared eval-runner helper without changing the five-pass measurement.
scope: tests/language_humanizer/evals
created: 2026-10-04T22:11:10
updated: 2026-11-04T11:49:57
status: open
reported-by: Andreas Hoffmann
---

# Deduplicate the language_humanizer pool onto the shared eval runner

## Goal

`tests/language_humanizer/evals/run.py` keeps its fixed-denominator concurrent
passes at default 4 workers and drives them through the shared helper instead
of a private `ThreadPoolExecutor`. The current isolation, micro-deployment,
Cursor-default vendor, and judge behavior stay unchanged. The user-visible
outcome: this harness remains the Pattern A parallel reference without a second
copy of the pool.

## Context

This runner already parallelizes (`vendor.DEFAULT_PARALLEL_WORKERS`) and
deliberately skips the verdict cache because repeated draws are the
measurement. [The isolation task](archive/tests_language-humanizer-worker-isolation.md)
already runs each pass and the judge under `tests/lib/worker_isolation.py`; each
pass now also runs through `tests/lib/micro_deploy.py` and records
`checkout_unread`. [The shared Pattern A eval runner](archive/tests_shared-pattern-a-eval-runner.md)
shipped as `tests/lib/eval_runner.py`, so the pool can switch now.

The `ai_editorial` plugin ships this skill. The isolated five-pass Cursor
measurement is recorded in
`tests/language_humanizer/results/isolation-comparison.md` and predates the
2026-10-10 micro-deployment; the pool swap leaves that measurement unchanged,
so this task changes only how the pool runs.

## Approach

Replace the local executor with the shared pool helper. Keep `--passes`,
`--workers` default 4, per-pass sandbox ownership, and
the judge call. Do not add `eval_cache`. Rewrite the module docstring so the
pool is the shared helper rather than a private executor.

**Out of scope:** Changing grader rubrics, the five-pass contract, or plugin
shipping. A five-pass live Cursor re-measure, since the pool swap leaves the
recorded measurement unchanged and the isolation task already shipped it.

## Acceptance

- `evals/run.py` imports the shared helper and contains no
  `ThreadPoolExecutor` construction of its own.
- `run.py --help` still defaults `--workers` to 4 and `--passes` to 5.
- `python3 tests/lib/test_eval_runner.py` still passes after this import.
- A `--passes 1 --workers 1` plumbing run of one scenario still writes
  `verdict.json` under the run dir.
- The private-pool lists in `tests/CLAUDE.md` and `tests/AGENTS.md` move
  `tests/language_humanizer/evals/run.py` to the `eval_runner` set, and
  `tests/README.md`'s pointer to those lists stays accurate.
