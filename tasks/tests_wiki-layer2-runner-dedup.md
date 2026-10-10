---
description: Point wiki layer-2 at the shared eval-runner pool so Pattern B stops carrying a private copy of the parallel loop.
scope: tests/wiki/layer2
created: 2026-10-04T22:11:10
updated: 2026-10-09T17:46:37
status: open
reported-by: Andreas Hoffmann
---

# Deduplicate the wiki layer-2 runner onto the shared eval pool

## Goal

`tests/wiki/layer2/run.py` keeps its Pattern B restage-and-grade pipeline and
its already-correct default of 4 concurrent scenarios with sequential passes,
and it drives that pool through the shared helper instead of a private
`ThreadPoolExecutor`. Cursor and Claude stay on `tests/lib/vendor.py`. The
user-visible outcome: wiki layer 2 remains the parallel reference for
scenarios, without a second copy of the pool code.

## Context

Wiki layer 2 already parallelizes (`--workers` default
`vendor.DEFAULT_PARALLEL_WORKERS`) and already isolates each scenario directory.
It still inlines the executor. Agent staging is already settled: each pass
micro-deploys the wiki family skills and `auto_shaper_wiki` through
`tests/lib/micro_deploy.py`, and the private `stage_named_agents` is gone. It
does not use
the Pattern A verdict cache, and it should not: multi-pass assertion rates are
the measurement.

This task consumes [the shared Pattern A eval runner](archive/tests_shared-pattern-a-eval-runner.md).
Provenance and baseline-narrowing stay with
[the wiki harness provenance task](tests_wiki-harness-run-provenance.md).

## Approach

Replace the local executor setup with the shared pool helper, keeping the
existing contract: scenarios concurrent, passes of one scenario sequential,
subset `--scenario` runs restage only those ids. Keep each pass's
`micro_deploy.micro_deploy(...)` block inside the job the pool runs, so every
pass still gets its own scratch home. Leave `normalize.py` / `grade.py` /
`aggregate.py` in place.

Rewrite any README sentence that describes the pool as wiki-only machinery so
it names the shared helper.

**Out of scope:** Migrating wiki to Pattern A. Adding a verdict cache.
Live-testing unshipped editorial plugin harnesses.

## Acceptance

- `tests/wiki/layer2/run.py` imports the shared helper and contains no
  `ThreadPoolExecutor` construction of its own.
- `python3 tests/wiki/layer2/run.py --help` still defaults `--workers` to 4,
  and passes of one scenario stay sequential in the code that the helper
  invokes.
- A default-vendor `--scenario` plumbing run of one scenario with `--workers 1`
  still restages, grades, and writes `grading_summary.json`. A default-worker
  full suite is the existing parallel path; record a short Cursor subset run
  under `tests/wiki/results/` that shows two scenarios overlapping when more
  than one `--scenario` is passed.
