---
description: "Fail an eval pass whose worker reads a copy of a test harness's evals tree anywhere outside its sandbox project, the way checkout_unread fails a read inside the checkout."
scope: tests/lib
created: 2026-11-15T10:49:59Z
updated: 2026-11-17T10:06:07Z
status: open
reported-by: Andreas Hoffmann
---

# Fail an eval pass that reads a harness copy outside the checkout

## Goal

`tests/lib/micro_deploy.py` records a read check beside `checkout_unread` that fails the pass when the worker, or a helper it spawned, reads a path that looks like a harness evals tree (`tests/<harness>/evals/`) outside the sandbox project. A worker that finds a leftover copy of the eval fixtures, grader, or `evals.json` in a shared temp folder then fails as plainly as one that reads the checkout.

## Context

- **What happened.** In a Cursor run of `regroup_same_paragraph_ready` on 2026-11-15:
  - The worker listed the system temp folder that holds every sandbox root.
  - It found leftover directories from other sessions holding copies of `tests/task_auto_check/evals`, read `evals.json` and several fixtures' `setup.sh` there, then searched the home directory and reached the checkout's fixtures.
  - `checkout_unread` failed the pass for the last step only, because the temp copies lie outside the checkout. The run's ordered read list in `timing.json` under `artefacts_read_from_micro_deployment` shows the sequence.
  - The same day's Cursor runs of both regroup evals repeated it. The `regroup_same_paragraph_ready` worker read a leftover temp copy's `evals.json`, `stage.sh`, and fixture `setup.sh` files and stayed out of the checkout, so its pass failed on grader checks alone. The `regroup_immediate_ready` worker searched the home directory and read the checkout's copies, so `checkout_unread` failed a pass whose 14 grader checks all passed.
- **Deleting the copies is not enough.** The two copies these runs read and a third full checkout copy were deleted from the temp folder on 2026-11-15. Any session or script that copies the checkout there leaves a new one, so the check is still needed.
- **Why the checkout check misses it.** `classify_inside_checkout` in `micro_deploy.py` flags a path only when it resolves inside the repository root. A copy elsewhere carries the same answer key: the expected outcome in a fixture's comments, the grader's checks, and each eval's `expected_output`.
- **False positives to avoid.** `tests/CLAUDE.md`'s model-policy section notes that a sandbox fixture tree can share the shape of a repository path, so the check exempts every path under the sandbox project and the scratch home. Some sandboxes stage a project that holds its own `tests/` directory.
- **Shared verdict surface.** `micro_deploy.py` is one of `eval_cache.VERDICT_HELPERS`, so this change moves every eval's cache key once, as the leak fix to the deploy log and `PWD` did.

## Approach

1. In `micro_deploy.py`, add a classifier beside `classify_inside_checkout` that flags a read path outside the sandbox project and the scratch home whose segments contain `tests/<name>/evals`, where `<name>` is any directory under the checkout's `tests/`. Record its result as `harness_copy_unread` in each pass, and make `read_checks_passed` fail on it.
2. In every runner that passes `checkout_unread` to `eval_runner.write_run_artifacts` today, pass the new record beside it, so it lands in `timing.json` through that function's extra timing fields.
3. Add unit tests in `tests/lib/test_micro_deploy.py`. A temp-folder copy of `tests/task_auto_check/evals/fixtures/<id>/setup.sh` is flagged. The same shape inside the sandbox project is not flagged, and neither is a scratch-home path.
4. Describe the check beside `checkout_unread` in `tests/CLAUDE.md` and `tests/AGENTS.md`, keeping the two in lockstep.

## Acceptance

1. `python3 tests/lib/test_micro_deploy.py` passes with the new cases, and a mutation that disables the classifier makes the flagged-copy case fail.
2. `make test` passes.
3. A `tests/lib/test_micro_deploy.py` case feeds the classifier the ordered read list of a pass that visited a temp-folder harness copy before the checkout, and the copy's paths are flagged while the checkout paths are not.
