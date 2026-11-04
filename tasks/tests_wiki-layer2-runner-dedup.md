---
description: Point wiki layer-2 at the shared eval-runner pool so Pattern B stops carrying a private copy of the parallel loop.
scope: tests/wiki/layer2
created: 2026-10-04T22:11:10
updated: 2026-11-04T11:49:57
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
`vendor.DEFAULT_PARALLEL_WORKERS`) and already stages each pass into its own
outside-checkout sandbox root through `worker_isolation.create_sandbox_root`.
It still inlines the executor. Agent staging is already settled: each pass
micro-deploys the declared `ARTEFACTS` list (the wiki family skills,
`auto_shaper_wiki`, and `format_markdown`) through `tests/lib/micro_deploy.py`,
and the private `stage_named_agents` is gone. It does not use the Pattern A
verdict cache, and it should not: multi-pass assertion rates are the measurement.

This task consumes [the shared Pattern A eval runner](archive/tests_shared-pattern-a-eval-runner.md).
Provenance and baseline-narrowing stay with
[the wiki harness provenance task](archive/tests_wiki-harness-run-provenance.md).

## Approach

Replace the local executor setup with the shared pool helper, keeping the
existing contract: scenarios concurrent, passes of one scenario sequential,
subset `--scenario` runs restage only those ids. Keep the whole per-pass block
inside the job the pool runs: the outside-checkout sandbox root, restage, prompt
build, `micro_deploy.micro_deploy(...)`, provenance records, and the sandbox
snapshot, so every pass still gets its own scratch home and `checkout_unread`
record. Leave `normalize.py` / `grade.py` / `aggregate.py` in place.

Rewrite the private-pool description in `tests/AGENTS.md` and `tests/CLAUDE.md`
so it names the shared helper, and keep `tests/README.md`'s pointer to those
lists accurate.

**Out of scope:** Migrating wiki to Pattern A. Adding a verdict cache.
Live-testing unshipped editorial plugin harnesses.

## Acceptance

- `tests/wiki/layer2/run.py` imports the shared helper and contains no
  `ThreadPoolExecutor` construction of its own.
- `python3 tests/wiki/layer2/run.py --help` still defaults `--workers` to 4,
  and passes of one scenario stay sequential in the code that the helper
  invokes.
- A default-vendor `--scenario` plumbing run of one scenario with `--workers 1`
  still restages into an outside-checkout root, records `checkout_unread`,
  preserves the `sandbox-snapshot`, grades, and writes `grading_summary.json`,
  and returns the grade-or-aggregate exit. A default-worker full suite is the
  existing parallel path; record a short Cursor subset run under
  `tests/wiki/results/` that shows two scenarios overlapping when more than one
  `--scenario` is passed.
