---
description: "Guard agent_spinner and guardrail_audit against a failed or empty stage, and pin the stage guard in every harness that ships stage.sh."
scope: "local test harnesses"
created: 2026-10-30T23:41:12
updated: 2026-10-31T09:43:24
status: ready
reported-by: Andreas Hoffmann
---

# Guard every eval runner's stage against a failed or empty stage

## Goal

A stage that fails or names no sandbox stops the eval it belongs to, with a
message naming the stage, instead of aborting the whole run with an unhandled
traceback. `tests/lib/check_stage_guard.py` proves the property per runner, and
every harness that ships `evals/stage.sh` runs it from its committed
deterministic surface: the surface that already invokes the check where one
does, else its `script_tests/` where the harness has that layer, else the unit
test beside its runner under `evals/`.

The user-visible outcome: `python3 tests/lib/check_stage_guard.py
tests/agent_spinner/evals` and the same command against
`tests/guardrail_audit/evals` both exit zero, and every harness that ships
`stage.sh` without a committed scenario carries one that goes red when the guard
is removed.

## Context

`TESTING.md` and the tests-tree guides state that a stage naming no sandbox
stops the eval before any worker starts, and `tests/lib/check_stage_guard.py`
exists to prove it. The harnesses that ship `evals/stage.sh` and carry a
`check_stage_guard.py` invocation in their committed deterministic surface
prove it; `ls -d tests/*/evals/stage.sh` lists the harnesses that ship a stage
and `rg -l check_stage_guard tests/*/script_tests tests/*/evals/test_run.py`
lists the committed invocations, so run both to get the current members. `tests/git_auto_review/evals/run.py`
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

**The harnesses that ship `stage.sh` with no committed scenario are found by
selector.** Run `ls -d tests/*/evals/stage.sh` and `rg -l check_stage_guard
tests/*/script_tests tests/*/evals/test_run.py`; every harness in the first
list that the second does not name holds `evals/stage.sh` but no invocation of
`check_stage_guard.py` in its committed deterministic surface. At writing time
that difference is `agent_spinner`, `git_auto_review`, and `guardrail_audit`.
`git_auto_review` passes the check when it is run by hand, so its gap is the
missing pin rather than a broken guard: an edit that drops its `|| exit $?` or
its empty-sandbox test would go unnoticed.

## Approach

Fix the two broken runners against the reference implementation, then pin
every harness the Context selector yields.

1. **Port the guard into `agent_spinner` and `guardrail_audit`.** Give each
   `stage()` the `git_auto_review` shape: run `stage.sh` under `bash -c` with
   `|| exit $?` and the value emission the runner already parses, raise
   `RuntimeError` naming the failed stage and its stderr on a non-zero return,
   and raise again when the sandbox value is empty or not a directory. Keep each
   runner's own emitted field names and its `printf %q` value handling; only the
   failure path changes. Where `run_one` needs to turn that `RuntimeError` into a
   failed eval rather than an aborted suite, add the `except` that records the
   verdict and the message, so one broken fixture costs one eval.
2. **Commit the scenario in every harness the Context selector yields.** For
   each such harness, add a case on the surface the Goal's placement sentence names that invokes
   `tests/lib/check_stage_guard.py` against its own `evals/` directory and
   asserts a zero exit. The check already exercises both
   branches, so one invocation covers the failed stage and the empty stage.
3. **Name the property where the runner is described.** Add one clause to each
   harness's `README.md` runner section saying the runner's `stage()` stops on a
   failed or empty stage and that `script_tests/` proves it, using the wording the
   `skill_doctor/` inventory row already carries, "the eval runner's stop on a
   failed or empty stage".

4. **Repair the operator docs this change falsifies.** In `tests/CLAUDE.md`,
   under `### A failed stage stops the eval: tests/lib/check_stage_guard.py`,
   replace the sentence "`agent_spinner` and `guardrail_audit` call stage.sh
   through `subprocess.check_output`, which already raises on a failed stage."
   in place with: "`agent_spinner`, `guardrail_audit`, and every other runner
   that stages through `stage.sh` run it under `bash -c` with the guard above,
   so a failed or empty stage raises `RuntimeError` in each of them." Add the
   same coverage clause the `git_refresh/` and `skill_doctor/` rows already
   carry, "the eval runner's stop on a failed or empty stage", to the
   `git_auto_review/`, `guardrail_audit/`, and `agent_spinner/` rows in the
   `tests/README.md` inventory, inside each row's own `script_tests/` account.

**Out of scope:** The shared `check_stage_guard.py` itself, which is correct and
needs no change. Any new eval or fixture; this task only adds failure-path
coverage. Count and per-harness file-enumeration drift in `tests/README.md` and
`tests/CLAUDE.md` beyond the stage-guard sentences and the three inventory
rows item 4 repairs, which [the docs-reconcile task](tests_tree-docs-reconcile.md)
owns.

**Co-edits.** Other live tasks touch the same files and must be rebased rather
than re-merged. Find that set at implementation time by grepping `tasks/*.md`
for the live tasks whose bodies name a path this change edits: each target
runner's `evals/run.py`, the `script_tests/run.sh` of each harness the Context
selector yields, the README of each such harness, and the stage-guard rows in
`tests/README.md` and `tests/CLAUDE.md`. Rebase over every live task the grep
names. [The agent_spinner parallel-evals
task](tests_agent-spinner-parallel-evals.md) rewrites
`tests/agent_spinner/evals/run.py` onto the shared helper and may rewrite its
`stage()` call; whichever lands second keeps this task's failure path. [The
agent_spinner runner-modes task](tests_agent-spinner-runner-modes.md) adds
`tests/agent_spinner/evals/test_run.py` and a case in
`tests/agent_spinner/script_tests/run.sh`, so both edit that suite's tail. [The
guardrail_audit parallel-evals task](tests_guardrail-audit-parallel-evals.md)
rewrites `tests/guardrail_audit/evals/run.py` onto the shared helper, including
its `stage()` call, and rewrites `tests/guardrail_audit/README.md`; whichever
lands second keeps this task's failure path and its README clause. [The
task-hub parallel-evals task](tests_task-hub-parallel-evals.md) changes
`tests/task/evals/run.py`'s `stage` signature and its `evals/test_run.py`, which
is the same declaration/stage-guard surface, though a different harness from
the three this task touches. [The agent_spinner run-ledger
task](ai-dev_agent-spinner-run-ledger.md) replaces the check "the skill bundles
no runtime scripts" in `tests/agent_spinner/script_tests/run.sh` — the same
suite tail this task appends its `check_stage_guard.py` case to — and rewrites
in place the `agent_spinner/` bullet in `tests/README.md` that the operator-docs
item adds the stage-guard clause to; whichever lands second keeps both this
task's stage-guard case and its README clause. [The eval-graders
task](tests_eval-graders-bite-on-inert-worker.md) appends its own
`script_tests/` scenario to `tests/git_auto_review/script_tests/run.sh`, the
same suite tail this task appends its `check_stage_guard.py` case to, so
whichever lands second appends rather than rewrites.

## Acceptance

- `python3 tests/lib/check_stage_guard.py tests/agent_spinner/evals` and
  `python3 tests/lib/check_stage_guard.py tests/guardrail_audit/evals` each exit
  zero and print one `ok` line per attempt.
- Every harness the Context selector yields invokes
  `tests/lib/check_stage_guard.py` from its committed `script_tests/` against its
  own `evals/` directory and asserts a zero exit, and each such suite is red when
  its runner's `stage()` is reverted to the `check_output` shape. Re-running the
  selector at Acceptance time leaves no member unhandled.
- Every harness that ships `evals/stage.sh` invokes
  `tests/lib/check_stage_guard.py` against its own `evals/` directory from its
  committed deterministic surface. Find the members at verification time with
  `ls tests/*/evals/stage.sh` and a grep for `check_stage_guard` across
  `tests/`; each harness found carries the invocation on the surface the Goal's
  placement sentence names.
- A stager that exits non-zero or prints no sandbox makes exactly one eval
  report FAIL with a message naming `stage.sh` and the eval id; the run
  continues to the remaining evals and its summary still prints. This is
  observed by hand for `agent_spinner` and `guardrail_audit` and recorded in
  each harness's `results/` as a note naming the command and the output.
- The `README.md` of every harness the Context selector yields states in its
  runner section that `stage()` stops on a failed or empty stage and names
  `script_tests/` as the proof.
- The `tests/CLAUDE.md` stage-guard paragraph describes the `bash -c` guard as
  applying to every runner and no longer names `subprocess.check_output` as a
  passing mechanism, and the `git_auto_review/`, `guardrail_audit/`, and
  `agent_spinner/` rows in `tests/README.md` each name the stage-guard scenario
  inside their own `script_tests/` account. Proof: `rg -n 'check_output'
  tests/CLAUDE.md` returns no match, and each of those three rows carries the
  clause inside its own bullet.
- `make lint` passes.
