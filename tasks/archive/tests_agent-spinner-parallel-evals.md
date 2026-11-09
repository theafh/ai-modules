---
description: Run agent_spinner evals at default 4 workers with a per-eval host git-status escape guard that stays attributable under overlap, using the shared helper.
scope: tests/agent_spinner/evals
created: 2026-10-04T20:11:10Z
updated: 2026-11-06T22:28:09Z
status: finished
reported-by: Andreas Hoffmann
implemented-by: Andreas Hoffmann
design-extended: false
---

# Parallelize the agent_spinner behavioral evals with an attributable escape guard

## Goal

`python3 tests/agent_spinner/evals/run.py` runs spinner evals concurrently at
default 4 workers. A sandbox escape still fails the eval that caused it.
Cursor and Claude stay on the same runner path, and this sweep adds no new
vendor branch. The user-visible outcome: every staged eval in `evals.json` — twenty-six
today, 21 behavioural plus 5 smoke — overlaps instead of walking the suite in
single file, while the escape guard compares only the names each eval's sandbox
owns.

## Context

The runner brackets every eval with `git status --porcelain` of the host
checkout. Sequential execution makes attribution trivial. Concurrent evals
race that snapshot unless each job is isolated well enough that the host tree
cannot move. `WORKSPACE` is `tests/agent_spinner/evals/workspace`. Ids already
come from `evals.json`. The shipped runner modes (resume, inline body, tool-call
record) and Cursor spawn-tool withholding stay as they are; this task preserves
them while changing only how the pool runs.

This task consumes [the shared Pattern A eval runner](tests_shared-pattern-a-eval-runner.md),
including its serialized host-status hooks. The helper runs each before/after
pair one call at a time on that job's own thread, but serialization cannot
attribute a change: an after hook also sees what a still-running sibling
changed since its own before snapshot, so a guard that claims every new change
blames whichever eval finishes first.

## Approach

Rewrite `evals/run.py` onto the shared helper: `--workers` 4, workspace
`tests/agent_spinner/workspace` from `eval_runner.resolve_workspace(THIS)`,
per-job `TMPDIR` applied to `md.env` and passed as `env` to the `stage.sh` and
`grade.sh` calls, the pattern `tests/guardrail_audit/evals/run.py::_apply_job_temp`
already ships, with `eval_runner` left unchanged, and host-status hooks around
each `run_one` whose guard compares only the names that eval's sandbox owns, as
TESTING.md's **Stage a sandbox per scenario** principle describes, which keeps
blame on the escaping eval while siblings overlap. The owned-name set is derived
from the `index` the helper already passes to both hooks: the before hook stores
the full host `git status --porcelain`, and the after hook maps `index` to
`ids[index]`, reads the `run_dir / ids[index] / "sandbox"` copy that
`worker_isolation.preserve_sandbox_copy` leaves behind in the job's `finally`,
and blames the eval only for new host paths whose basename appears in that copy.
An eval with no sandbox copy owns no names and stays green; the shared helper's
hook contract stays unchanged. Move the existing `evals/workspace/run-*`
directories to `tests/agent_spinner/workspace/` and re-point every recorded run
path in `evals/README.md` to `../workspace/run-…`. Preserve the shipped runner
modes and micro-deployment path, and keep `STAGE` and `stage()` module-level in
`evals/run.py` with both error strings (`stage.sh failed for`, `stage.sh staged
no sandbox`), so `tests/lib/check_stage_guard.py` — which imports the module,
patches `run.STAGE`, and calls `run.stage` from `script_tests/run.sh` — keeps
passing unchanged; `stage()` may take the optional `env` mapping that guard
already supplies. `evals/test_run.py` stays the plumbing test `run_all.sh` runs,
with its patched seams (`WORKSPACE`, `load_evals`, `preflight_resume`, `GRADE`,
`eval_cache.EvalCache`) intact; pass `--workers 1` in `case_withheld`'s two-id
invocation so its shared stub `count` and `log.jsonl` stay order-independent, or
make that stub concurrency-safe. Keep fixture-specific prompt extras
(`extra_reads`, declared spawn absence) as harness callbacks the helper does not
need to understand. Rewrite the shipped passages that still describe the serial
whole-host guard in place, replacing each claim where it stands rather than
appending a note beside it: the `run.py` paragraph under `## What "outside the
sandbox" means here` in `tests/agent_spinner/README.md`, the `agent_spinner`
entry under `## Current harnesses` in `tests/README.md`, and the `agent_spinner`
row of the inventory table in `tests/CLAUDE.md`. Each then reads the owned-name
guard, the default 4 workers, and the eval set by its selector (every id in
`evals.json`, with 26 today as an example) rather than a fixed count. In the
`### Parallel workers` block of `tests/CLAUDE.md` and `tests/AGENTS.md`, add
`tests/agent_spinner/evals/run.py` to the Pattern A `eval_runner` sentence,
remove the `agent_spinner` bullet from the sequential list, and delete the
block's opening whole-host clause "and an escape guard that reads the whole host
checkout, such as `agent_spinner`'s `git status`", with its leading comma, so
the sequential-subset list ends at the `task` Approach serial set and the block
reads one guard story. Leave the block's other entries as they are; the
`skill_doctor` bullet was already removed by [the archived skill_doctor
task](tests_skill-doctor-parallel-evals.md).

Prove with a hermetic hook test from the shared helper plus a Cursor default
run whose overlapping `timing.json` windows carry `started_at` / `ended_at` and
sit next to a clean host `git status` recorded in `tests/agent_spinner/results/`.

**Out of scope:** New runner modes (resume, inline body, tool-call record),
which [the runner-modes task](tests_agent-spinner-runner-modes.md) shipped and
audited. Live-testing unshipped editorial plugin harnesses.

## Acceptance

- `run.py --help` shows `--workers` defaulting to 4.
- `python3 tests/agent_spinner/evals/run.py` at the default worker count
  prints a graded summary over every id in `evals.json`.
- A `--workers 4 --force` run of at least two uncached evals overlaps in
  `timing.json` through `started_at` / `ended_at`, writes its run directory
  under `tests/agent_spinner/workspace/`, ends with a clean host
  `git status --porcelain` relative to the pre-run snapshot, and records that
  run in a tracked file at
  `tests/agent_spinner/results/parallel-workers-windows.md`, written after the
  final host snapshot. The name avoids `tests/.gitignore`'s
  `**/results/run-*.md`, `run-*.json`, and `*.log` patterns, so the proof
  surface is prepared for commit.
- An eval that writes one of its own sandbox names into the host checkout
  fails that eval's grade, not an unrelated sibling, proven by a case in
  `tests/agent_spinner/evals/test_run.py` that drives `run.py`'s own guard
  with two overlapping stub jobs, writes a canary outside one job's sandbox,
  and asserts only that job's verdict fails.
- `python3 tests/agent_spinner/evals/test_run.py` passes, including its Cursor
  and Claude cases, proving the resume, inline-body, tool-call-record, and
  micro-deployment paths and the fixture prompt extras through one runner
  path.
- `bash tests/agent_spinner/run_all.sh` passes, including
  `tests/lib/check_stage_guard.py` against `evals/`, so the module-level
  `stage()` / `STAGE` guard stays intact.
- A two-job overlap case in `evals/test_run.py` asserts a distinct `TMPDIR` on
  each job's worker env and on each job's grade env.
- A grep over the doc sites named in `## Approach` shows the default-4-worker
  sentence and the per-eval owned-name guard wording, with no remaining
  whole-host-guard or serial-suite claim for `agent_spinner`, and each count
  site names the eval set by its `evals.json` selector.
- `tests/agent_spinner/evals/workspace/` no longer holds a `run-*` directory,
  the same `run-*` directory names appear under
  `tests/agent_spinner/workspace/`, and every `workspace/run-…` path recorded
  in `tests/agent_spinner/evals/README.md` resolves under `../workspace/`.
