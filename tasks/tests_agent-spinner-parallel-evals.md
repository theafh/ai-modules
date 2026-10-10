---
description: Run agent_spinner evals at default 4 workers with a per-eval host git-status escape guard that stays attributable under overlap, using the shared helper.
scope: tests/agent_spinner/evals
created: 2026-10-04T22:11:10
updated: 2026-10-09T18:10:40
status: open
reported-by: Andreas Hoffmann
---

# Parallelize the agent_spinner behavioral evals with an attributable escape guard

## Goal

`python3 tests/agent_spinner/evals/run.py` runs spinner evals concurrently at
default 4 workers. A sandbox escape still fails the eval that caused it.
Cursor and Claude stay on the same runner path except for `tests/lib/vendor.py`.
The user-visible outcome: twenty-one isolated fixtures overlap instead of
walking the suite in single file so a whole-run `git status` stays simple.

## Context

The runner brackets every eval with `git status --porcelain` of the host
checkout. Sequential execution makes attribution trivial. Concurrent evals
race that snapshot unless each job is isolated well enough that the host tree
cannot move. `WORKSPACE` is `tests/agent_spinner/evals/workspace`. Ids already
come from `evals.json`. Cursor spawn-tool withholding is a runner-mode
concern, not this parallel sweep.

This task consumes [the shared Pattern A eval runner](archive/tests_shared-pattern-a-eval-runner.md),
including its serialized host-status hooks. The helper runs each before/after
pair one call at a time on that job's own thread, but serialization cannot
attribute a change: an after hook also sees what a still-running sibling
changed since its own before snapshot, so a guard that claims every new change
blames whichever eval finishes first.

## Approach

Rewrite `evals/run.py` onto the shared helper: `--workers` 4, workspace
`tests/agent_spinner/workspace`, per-job `TMPDIR`, and host-status hooks
around each `run_one` whose guard compares only the names that eval's sandbox
owns, as TESTING.md's **Stage a sandbox per scenario** principle describes,
which keeps blame on the escaping eval while siblings overlap. Keep
fixture-specific prompt extras (`extra_reads`, declared spawn absence) as
harness callbacks the helper does not need to understand. Rewrite README /
RUNBOOK sequential assumptions.

Prove with a hermetic hook test from the shared helper plus a Cursor default
run whose overlapping `timing.json` windows sit next to a clean host
`git status` recorded in `tests/agent_spinner/results/`.

**Out of scope:** New runner modes (resume, inline body, tool-call record),
which [the runner-modes task](tests_agent-spinner-runner-modes.md) owns.
Live-testing unshipped editorial plugin harnesses.

## Acceptance

- `run.py --help` shows `--workers` defaulting to 4.
- `python3 tests/agent_spinner/evals/run.py` at the default worker count
  prints a graded summary over every id in `evals.json`.
- A `--workers 4 --force` run of at least two uncached evals overlaps in
  `timing.json`, ends with a clean host `git status --porcelain` relative to
  the pre-run snapshot, and is recorded under `tests/agent_spinner/results/`.
- An eval that writes one of its own sandbox names into the host checkout
  fails that eval's grade, not an unrelated sibling, proven by the shared
  helper's hook test or a harness fixture that writes such a canary outside
  the sandbox.
