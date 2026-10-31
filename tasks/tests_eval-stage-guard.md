---
description: "Guard agent_spinner and guardrail_audit against a failed or empty stage, and pin the stage guard in every harness that ships stage.sh."
scope: "local test harnesses"
created: 2026-10-30T23:41:12
updated: 2026-10-30T23:41:12
status: open
reported-by: Andreas Hoffmann
---

# Guard every eval runner's stage against a failed or empty stage

## Goal

A stage that fails or names no sandbox stops the eval it belongs to, with a
message naming the stage, instead of aborting the whole run with an unhandled
traceback. `tests/lib/check_stage_guard.py` proves the property per runner, and
every harness that ships `evals/stage.sh` runs it from its committed
`script_tests/`.

The user-visible outcome: `python3 tests/lib/check_stage_guard.py
tests/agent_spinner/evals` and the same command against
`tests/guardrail_audit/evals` both exit zero, and all three harnesses that ship
`stage.sh` without a committed scenario carry one that goes red when the guard
is removed.

## Context

`TESTING.md` and the tests-tree guides state that a stage naming no sandbox
stops the eval before any worker starts, and `tests/lib/check_stage_guard.py`
exists to prove it. Nine runners invoke it. `tests/git_auto_review/evals/run.py`
carries the reference implementation: it runs `stage.sh` under `bash -c` with
an explicit `|| exit $?`, raises `RuntimeError` naming the failed stage on a
non-zero return, and raises again when the sandbox path is empty or is not a
directory.

Measured on 2026-10-30 at commit `54680e4`.

**Two runners fail the guard outright.** `python3
tests/lib/check_stage_guard.py tests/agent_spinner/evals` exits 1 with a
`subprocess.CalledProcessError` from a stand-in stager that exits 3, and
`python3 tests/lib/check_stage_guard.py tests/guardrail_audit/evals` exits 1 the
same way. Both `stage()` functions are the pre-guard shape:

```python
out = subprocess.check_output(
    ["bash", str(STAGE), eval_id, str(target)],
    text=True,
)
```

`check_output` propagates the stager's failure as `CalledProcessError` rather
than the `RuntimeError` the check expects, and an exit-0 stager that prints
nothing returns an empty `env` dict, so `run_one` reaches
`staged["sandbox_proj"]` and raises `KeyError`. Neither path fails the one
eval: the exception escapes `run_one`, so a single broken fixture aborts the
whole suite and leaves no per-eval verdict. `agent_spinner`'s `run_one` has a
`finally` that releases its sandbox root, but no `except` that turns the stage
failure into a failed eval.

**Three harnesses ship `stage.sh` with no committed scenario.**
`agent_spinner`, `git_auto_review`, and `guardrail_audit` each hold
`evals/stage.sh` (21, 35, and 6 fixture directories respectively) but no
invocation of `check_stage_guard.py` in their `script_tests/`. `git_auto_review`
passes the check when it is run by hand, so its gap is the missing pin rather
than a broken guard: an edit that drops its `|| exit $?` or its empty-sandbox
test would go unnoticed.

## Approach

Fix the two broken runners against the reference implementation, then pin all
three.

1. **Port the guard into `agent_spinner` and `guardrail_audit`.** Give each
   `stage()` the `git_auto_review` shape: run `stage.sh` under `bash -c` with
   `|| exit $?` and the value emission the runner already parses, raise
   `RuntimeError` naming the failed stage and its stderr on a non-zero return,
   and raise again when the sandbox value is empty or not a directory. Keep each
   runner's own emitted field names and its `printf %q` value handling; only the
   failure path changes. Where `run_one` needs to turn that `RuntimeError` into a
   failed eval rather than an aborted suite, add the `except` that records the
   verdict and the message, so one broken fixture costs one eval.
2. **Commit the scenario in all three harnesses.** Add to
   `tests/agent_spinner/script_tests/run.sh`,
   `tests/git_auto_review/script_tests/run.sh`, and
   `tests/guardrail_audit/script_tests/run.sh` a case that invokes
   `tests/lib/check_stage_guard.py` against that harness's own `evals/`
   directory and asserts a zero exit. The check already exercises both
   branches, so one invocation covers the failed stage and the empty stage.
3. **Name the property where the runner is described.** Add one clause to each
   harness's `README.md` runner section saying the runner's `stage()` stops on a
   failed or empty stage and that `script_tests/` proves it, matching the wording
   the nine covered harnesses already use.

**Out of scope:** The shared `check_stage_guard.py` itself, which is correct and
needs no change. Any new eval or fixture; this task only adds failure-path
coverage. Count and lockstep drift in `tests/README.md` and `tests/CLAUDE.md`,
which [the docs-reconcile task](tests_tree-docs-reconcile.md) owns.

**Co-edits.** Three sibling tasks add scenarios to the same files and must be
rebased rather than re-merged. [The agent_spinner parallel-evals
task](tests_agent-spinner-parallel-evals.md) rewrites
`tests/agent_spinner/evals/run.py` onto the shared helper and may rewrite its
`stage()` call; whichever lands second keeps this task's failure path. [The
agent_spinner runner-modes task](tests_agent-spinner-runner-modes.md) adds
`tests/agent_spinner/evals/test_run.py` and a case in
`tests/agent_spinner/script_tests/run.sh`, so both edit that suite's tail. [The
task-hub parallel-evals task](tests_task-hub-parallel-evals.md) changes
`tests/task/evals/run.py`'s `stage` signature and its `evals/test_run.py`, which
is the same declaration/stage-guard surface, though a different harness from
the three this task touches.

## Acceptance

- `python3 tests/lib/check_stage_guard.py tests/agent_spinner/evals` and
  `python3 tests/lib/check_stage_guard.py tests/guardrail_audit/evals` each exit
  zero and print one `ok` line per attempt.
- `tests/agent_spinner/script_tests/run.sh`,
  `tests/git_auto_review/script_tests/run.sh`, and
  `tests/guardrail_audit/script_tests/run.sh` each invoke
  `tests/lib/check_stage_guard.py` against their own `evals/` directory and
  assert a zero exit, and each suite is red when its runner's `stage()` is
  reverted to the `check_output` shape.
- A stager that exits non-zero or prints no sandbox makes exactly one eval
  report FAIL with a message naming `stage.sh` and the eval id; the run
  continues to the remaining evals and its summary still prints. This is
  observed by hand for `agent_spinner` and `guardrail_audit` and recorded in
  each harness's `results/` as a note naming the command and the output.
- The `agent_spinner`, `git_auto_review`, and `guardrail_audit` `README.md`
  runner sections each state that `stage()` stops on a failed or empty stage and
  name `script_tests/` as the proof.
- `make lint` passes.
