# git_auto_review regression harness

Regression coverage for the `git_auto_review` skill, its three helper agents,
and its four bundled scripts. The harness is committed and runs locally; it
does not ship inside the plugin.

## Surfaces

| Surface | Where | What it tests |
| :--- | :--- | :--- |
| `script_tests/` | Deterministic shell assertions | The published artefact shape and frontmatter, the pseudo-XML lint, the single-source lane-classification and convergence statements, the carry-over blocks, and the four bundled scripts: `run_relay.sh` (the `.gitignore`, the stem derivation, the `--task` path rejection, the staleness clear, and the marked preseed pairs), `run_ledger.sh` (the exit and per-line contract), `run_snapshot.sh` (the pre-fix pair and the once-only baseline pair), and `run_restore.sh` (reproducing the captured worktree with the index untouched). It also exercises the Makefile's `.git_auto_review` prune on a probe root and checks the shared isolation allowlist. |
| `evals/` | Behavioral eval definitions | Staged git fixtures for the review-and-fix loop: the clean-first-gate and non-qualifying stops, an in-scope fix with its reproduction and the reproduction-only delta finding, the pre-existing and scope-extension follow-ups, the decision and CHARTER stops, the helper-failure and helper-script-failure stops, the concurrent-modification guard, triage status and reason, the scope anchor through a task file and the same fixture with no task path, the local-commits lane, the round cap, and the ledger and unmapped-hunk restore-and-retry stops. |

The authored harness is committed; `tests/.gitignore` keeps run output out.
These tests do not ship inside the plugin, since `make deploy` copies only
the skill directory.

## Commands

```bash
./tests/git_auto_review/run_all.sh
python3 tests/git_auto_review/evals/run.py
python3 tests/git_auto_review/evals/run.py fixes_in_scope_bug
```

`run_all.sh` drives only the deterministic script tests. Behavioral evals live
in `evals/evals.json`; run them out-of-band through `evals/run.py`, which
stages a fresh sandbox per case, spawns a worker on the default Cursor vendor,
captures the response under `workspace/run-*/`, and grades the filesystem
expectations with `evals/grade.sh`.

## Fixture mechanism

Every behavioral eval that needs a specific gate finding shape pre-seeds that
shape as a marked pair under the relay the loop reads: `gate-r1.txt` plus the
empty `gate-r1.preseed` marker beside it, staged before the run. The loop
consumes the pair in place of a gate invocation, so live `git_review` is not
the fixture mechanism and those evals need no forge layer. Multi-round evals
stage one pair per round they expect to drive.

The two direct-agent evals (`gate_moves_no_ref`, `classifies_lanes_from_evidence`)
declare `mode: "agent"` in `evals.json`, so the runner micro-deploys
`auto_gate_git` and runs that agent itself against the sandbox target. Both
the spawn-failure and mid-run-death evals use an environment note in the run
prompt instead of the preseed, matching the loop's helper-failure policy.

See `evals/README.md` for the signal each eval uses, and `RUNBOOK.md` for the
trigger measurement and the lane-classification measurement.
