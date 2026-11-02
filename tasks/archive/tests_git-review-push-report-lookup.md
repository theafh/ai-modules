---
description: "Grade git_review eval 41's push warning from report.md in every evidence directory the run's collector calls used, logged by the run.py shim, so a worker's --out outside the target still grades."
scope: tests/git_review
created: 2026-11-01T09:49:38
updated: 2026-11-02T22:06:22
status: finished
reported-by: Andreas Hoffmann
implemented-by: Andreas Hoffmann
design-extended: false
---

# Grade eval 41's push warning from the evidence directories the run used

## Goal

Eval 41 (`push_approval`) in the `git_review` harness proves the warning came before the push by comparing the `report.md` draft's modification time with the push line's epoch in `gh_calls.log`. After this task, the grader finds that draft in every evidence directory the run's collector calls used, wherever the worker put it, and eval 41 passes again on the current Cursor CLI. The task delivers that general lookup rather than a special case for one directory name: the `run.py` logging shim records each successful collector call's evidence directory in `script_calls.log`, and the warning-order check reads `report.md` from those directories as well as from the eval target.

## Context

[The push-order proof task](tests_git-review-push-order-proof.md) built today's mechanism. The `push_approval` fixture (`tests/git_review/evals/fixtures/push_approval/setup.sh`) adds a `TMPDIR` line to its `gh_env` that points into the eval target, so the collector's default evidence directory (`mktemp -d "${TMPDIR:-/tmp}/git_review.XXXXXX"` in `collect_review_evidence.sh`) lands there, and `warning_before_push()` in `tests/git_review/evals/grade.sh` finds the draft with `target.rglob("report.md")`. The skill's `<draft_the_report_to_a_file>` writes `report.md` "inside the evidence directory `<collect>` used", and the collector accepts `--out <dir>`, so the skill lets the worker choose any directory.

That mechanism fails on Cursor CLI 2026.10.22. Every eval 41 run on that version on 2026-11-01, through both the pooled `run.py` and the sequential `run.py` from commit `5504360`, failed only `the warning was emitted before the push ran`, with the worker exiting 0. In each of those runs, `script_calls.log` shows the worker calling the collector with its own `--out` directory, either under `/tmp` (`/tmp/git_review_evidence_*`) or under the macOS per-user temp directory (`tmp.*` names from a bare `mktemp -d`), so `report.md` landed outside the eval target. Earlier passing runs on Cursor CLI 2026.10.01 and 2026.10.14 either omitted `--out` or passed a directory inside the target's `tmp/`. The bare `mktemp -d` results also show that the worker's shell does not always see the fixture's `TMPDIR`, so the collector's default directory can land outside the target as well. `tests/git_review/results/parallel-tmpdir-windows.md` records those runs.

The logging shim comes from `shim_deployed_scripts()` in `tests/git_review/evals/run.py`. It writes each deployed `scripts/*.sh` as a bash wrapper that appends `<script> <args>` to `<target>/script_calls.log` and then `exec`s an unshimmed copy, so it sees the arguments but never the collector's output. The collector's usage text promises that on exit 0 "the evidence directory is complete; its path is the last stdout line". `stage.sh` writes an empty `script_calls.log` and the `.eval_started_at` marker once per staged target, and `script_called()` in `grade.sh` greps that log with `grep -qF`. The grader's script test is `s23_push_approval_order_proofs` in `tests/git_review/script_tests/run.sh`, which stages eval 41 and drives every warning-order branch with synthetic epochs.

## Approach

1. Rewrite the shim that `shim_deployed_scripts()` writes for `collect_review_evidence.sh`. After the invocation line, it runs the unshimmed collector with stdout and exit status passed through unchanged and, when the collector exits 0, appends one line `evidence_dir <path>` to `script_calls.log`, where `<path>` is the collector's last stdout line. Every other deployed script keeps today's log-then-`exec` shim.
2. Rewrite each description of `script_calls.log` in place so it says the log also carries an `evidence_dir` line per successful collector call: the `shim_deployed_scripts()` docstring, the logging-shim step of the `run.py` module docstring, the `$target/script_calls.log` line in the `stage.sh` header comment, and the RUNBOOK passage that begins "Staging prepares the fixture and an empty `$target/script_calls.log`". Rewrite the `run.py` comment beside `_apply_job_temp(md.env, env)` that says `push_approval` points `TMPDIR` at the eval target "so report.md's mtime is gradeable", so it says the fixture's `TMPDIR` places the collector's default directory in the target when the worker's shell honours it.
3. Rewrite `warning_before_push()` in `grade.sh` in place. Its candidate drafts are every `report.md` under the eval target plus `<path>/report.md` for each `evidence_dir <path>` line in `$target/script_calls.log`. A candidate outside the eval target counts only when its `st_mtime` is later than the `st_mtime` of `$target/.eval_started_at`, so a stale draft that an earlier run left in a reused directory cannot pass. The check passes when at least one counted candidate contains both the approval wording and the dismissal wording the current check requires and has an `st_mtime` strictly less than the push-line epoch.
4. Extend `s23_push_approval_order_proofs` with the branches Acceptance names, keeping its existing branches. Add a script scenario that drives `shim_deployed_scripts()` from Python with a stand-in handle whose `path_map` maps every `ARTEFACTS` name to a `SKILL.md` path inside a temporary skill directory, the shape `micro_deploy._deployed_path()` returns so that `.parent` is the skill directory, and whose `scratch_home` is a temporary directory, with only the `git_review` stand-in carrying a `scripts/collect_review_evidence.sh`.
5. Rewrite in place the eval 41 expectation in `evals.json` that places "a report.md under the eval target", the order-proof sentence under `### 41: push_approval` in `tests/git_review/evals/README.md`, and the `push_approval` row of that file's fixture table, so each names an evidence directory logged in `script_calls.log`, or the eval target, as where the draft is found.
6. Run eval 41 once on the default vendor and record it as Acceptance describes.

**Out of scope:**

- Changing the `git_review` skill's `<collect>` or `<draft_the_report_to_a_file>` wording, since the skill already lets the worker choose the evidence directory.
- Removing the fixture's `TMPDIR` line from `gh_env`, which still places the collector's default directory in the target when the worker's shell honours it.
- Diagnosing why the worker's shell under Cursor CLI 2026.10.22 does not always see the fixture's `TMPDIR`.

## Acceptance

1. A script scenario in `tests/git_review/script_tests/run.sh` runs the shim that `shim_deployed_scripts()` writes for `collect_review_evidence.sh` against a stand-in collector. When the stand-in prints several lines ending in a directory path and exits 0, the shim's stdout matches the stand-in's, its exit status is 0, and `script_calls.log` gains the invocation line followed by `evidence_dir <that path>`. When the stand-in exits non-zero, the shim exits with that status and appends no `evidence_dir` line.
2. `s23_push_approval_order_proofs` grades the warning-order check PASS for a sandbox whose only `report.md` sits in a directory outside the eval target that an `evidence_dir` line names, carrying the warning wording, with an `st_mtime` after `.eval_started_at`'s and before the push epoch.
3. In that scenario, the same outside draft fails the warning-order check when no `evidence_dir` line names its directory, and fails it when its `st_mtime` is not later than `.eval_started_at`'s.
4. `rg -n 'report.md under the eval target|modification time under the eval target|mtime is gradeable' tests/git_review/evals/evals.json tests/git_review/evals/README.md tests/git_review/evals/run.py` returns nothing, and the eval 41 expectation, the `### 41: push_approval` order-proof sentence, and the `push_approval` fixture row each name an `evidence_dir` line in `script_calls.log` as a place the draft is found.
5. The `shim_deployed_scripts()` docstring, the `run.py` module docstring's logging-shim step, the `stage.sh` header line for `script_calls.log`, and the RUNBOOK staging passage each mention the `evidence_dir` line, and the `stage.sh` line no longer describes the log as only "every bundled-script invocation, one per line".
6. One `python3 tests/git_review/evals/run.py --force 41` run on the default Cursor vendor is recorded in `tests/git_review/results/eval-41-evidence-dir.md` with its run directory, the `agent --version` output, the `evidence_dir` lines from that run's `script_calls.log`, and the graded result. When it passes, the file says so. When it fails the warning-order check while a `report.md` carrying the warning sits in a logged evidence directory, the grader change is incomplete, so fix it and re-run. When neither a logged directory nor the eval target holds a `report.md`, the file records that the worker skipped the draft, and that skill-behaviour finding goes to a new task.
