---
description: "Fail an eval pass whose worker reads a copy of a test harness's evals tree anywhere outside its sandbox project, the way checkout_unread fails a read inside the checkout."
scope: tests/lib
created: 2026-11-15T10:49:59Z
updated: 2026-11-24T00:26:15Z
status: implemented
reported-by: Andreas Hoffmann
implemented-by: Andreas Hoffmann
design-extended: false
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

1. In `micro_deploy.py`, add a classifier beside `classify_inside_checkout` that flags a read path that resolves outside the sandbox project, outside the scratch home, and outside the repository checkout, and whose segments contain `tests/<name>/evals`, where `<name>` is any directory under the checkout's `tests/`. A path resolving inside the checkout stays with `checkout_unread` alone, so a checkout read is never reported twice. Record its result as `harness_copy_unread` beside `checkout_unread_record`, with `passed` plus the list of flagged paths as its keys the way that record carries `passed` and `inside_checkout`. Settle the verdict route as a required argument: `provenance_records` returns the new record as a third element beside its two, and `read_checks_passed(integrity, checkout_unread, harness_copy_unread)` takes it as a required third argument that fails the pass when its flagged-path list is non-empty (`passed` false), so a runner that omits it fails loudly instead of silently skipping the check. Update every `provenance_records` unpacking site, `tests/lib/test_micro_deploy.py` included, every `read_checks_passed` call site, and the stubs that pin the two-argument shapes: `tests/task/evals/test_run.py`, `tests/task_fix/evals/test_run.py`, `tests/task_create/evals/test_run.py` (each patches both functions), and `tests/language_humanizer/evals/test_run.py`'s `fake_provenance`.
2. Record the new check beside `checkout_unread` in the pass artefact each runner already writes it to: `timing.json` in every runner that writes one, and `verdict.json` in `tests/natural_language/evals/run.py`, which writes no `timing.json` and carries `checkout_unread` as a top-level `verdict.json` key. That covers every runner that records `checkout_unread` today: the runners that pass it to `eval_runner.write_run_artifacts`, and the runners that write it by hand — `tests/agent_spinner/evals/run.py` (through `combined_provenance`), `tests/language_humanizer/evals/run.py`, `tests/natural_language/evals/run.py`, and `tests/wiki/layer2/run.py`. Every by-hand runner that computes its pass from `all(integrity.values())` rather than calling `read_checks_passed` — `tests/language_humanizer/evals/run.py` and `tests/natural_language/evals/run.py` — also sets `integrity["harness_copy_unread"] = harness_copy_unread["passed"]` beside its existing `integrity["checkout_unread"]` line, so a flagged path fails that pass instead of only appearing in the artifact the runner writes. `tests/wiki/layer2/grade.py` reads the new record from `timing.json` and fails a pass on it beside `checkout_unread`.
3. Add unit tests in `tests/lib/test_micro_deploy.py`. A temp-folder copy of `tests/task_auto_check/evals/fixtures/<id>/setup.sh` is flagged. The same shape inside the sandbox project is not flagged, and neither is a scratch-home path.
4. Describe the check beside `checkout_unread` in `tests/CLAUDE.md` and `tests/AGENTS.md`, keeping the two in lockstep.

## Acceptance

1. `python3 tests/lib/test_micro_deploy.py` passes with the new cases, and a mutation that disables the classifier makes the flagged-copy case fail.
2. `make test` passes.
3. A `tests/lib/test_micro_deploy.py` case feeds the classifier the ordered read list of a pass that visited a temp-folder harness copy before the checkout, and the copy's paths are flagged while the checkout paths are not.
4. A `tests/lib/test_micro_deploy.py` case passes a `harness_copy_unread` record that flags one path to `read_checks_passed` and asserts it returns false, and asserts true when that record and the other two records all pass.
5. `grep -L harness_copy_unread $(grep -l checkout_unread tests/*/evals/run.py tests/*/run.py tests/*/*/run.py)` prints nothing, and `tests/wiki/layer2/grade.py` carries `harness_copy_unread` and fails a pass whose `timing.json` reports it as not passed, and `tests/natural_language/evals/run.py` writes `harness_copy_unread` as a top-level key in each pass's `verdict.json` beside `checkout_unread`.
6. `tests/CLAUDE.md` and `tests/AGENTS.md` each describe `harness_copy_unread` in the passage that begins `Each pass records` and runs to the line before `Each runner declares`, and those two extracted passages are identical once line wrapping is ignored, so the twins stay in lockstep and the new check reads beside `checkout_unread` in one rewritten passage rather than an appended copy.
7. Every runner that folds `checkout_unread` into its own per-pass `integrity` dict folds `harness_copy_unread` there too and still computes its pass with `all(integrity.values())`: `grep -L 'integrity\["harness_copy_unread"\]' $(grep -l 'integrity\["checkout_unread"\]' tests/*/evals/run.py tests/*/run.py tests/*/*/run.py)` prints nothing, and each file the inner grep lists carries `all(integrity.values())` in its pass computation.
