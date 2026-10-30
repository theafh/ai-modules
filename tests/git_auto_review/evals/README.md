# git_auto_review behavioral evals

These eval definitions cover the model-mediated behavior of
`git_auto_review`. They use the same Pattern A convention as the other
newer harnesses in this repo: `evals.json` carries prompts and
expectations, and `fixtures/*/setup.sh` stages sandboxes for a worker to
run in.

The deterministic `script_tests/` surface verifies the four bundled scripts
and the static contract. These evals verify loop behavior when a worker
actually loads the skill and drives the round lifecycle on a staged
repository.

```bash
python3 tests/git_auto_review/evals/run.py
python3 tests/git_auto_review/evals/run.py fixes_in_scope_bug stops_on_clean_first_gate
```

The runner captures each worker transcript and deterministic grade under
`../workspace/run-*/<eval-id>/`.

## Canned gate results

Almost every eval stages the gate result it needs as a marked preseed pair
under the relay stem the loop derives: `gate-r{round}.txt` plus an empty
`gate-r{round}.preseed` beside it. The loop treats a marked pair as that
round's gate return and consumes it verbatim, so those evals never invoke
live `git_review` and stay cheap and deterministic. `stops_on_clean_first_gate`
for example stages a round-1 verdict with no findings, and `fixes_in_scope_bug`
stages a round-2 delta verdict that tags the fixed finding closed.

Every eval declaring a non-empty `agent` key is a direct-agent eval: it
stages no preseed, so the runner micro-deploys that agent and runs it against
the sandbox target. Those evals measure the gate itself, not the loop around it.

## Signal per eval

| Eval | Evidence graded |
| :--- | :--- |
| `fixes_in_scope_bug` | `report.py` restored, a reproduction landed in the ledger, the delta finding outside the Scope anchor listed without a fix, and a clean stop under "no qualifying finding remains" |
| `fixes_critical_heading_finding` | One "What is critical" finding fixed, its reproduction landed, and a clean stop |
| `lists_preexisting_issue` | The pre-existing defect's file byte-identical and the finding listed as a follow-up proposal |
| `lists_scope_extension` | The untouched feature file byte-identical and the finding listed as a follow-up proposal |
| `fixes_inferred_and_should_fix_findings` | The inferred bug and the should-fix text defect both fixed, one ledger reproduction per finding, and a clean stop |
| `routes_decision` | The decision-pending stop, no fixer write, and the decision wording carried in the report |
| `stops_on_clean_first_gate` | No fixer write, the pre-run tree intact, and the no-qualifying stop named |
| `stops_on_empty_approved_triage` | The empty-approved stop, the not-approved reason listed, and no second gate round |
| `stops_on_helper_failure` | The contract-violating return stop |
| `stops_on_helper_inability` | The declared-inability stop distinct from the contract-violating one |
| `stops_on_helper_spawn_failure` / `stops_on_helper_mid_run_death` | The spawn-failure and mid-run-death stops through the environment-note seam |
| `stops_on_helper_script_failure` | The helper-script failure stop with the pre-run tree intact |
| `stops_on_helper_script_failure_relay` | The relay-init failure stop with no relay directory and the pre-run tree intact |
| `stops_on_helper_script_failure_restore` | The restore failure stop with the post-failure baseline intact |
| `stops_on_concurrent_modification` | The concurrent-modification stop after an external write |
| `stops_on_charter_refusal` | The CHARTER-before-write refusal with `charter-set-refused` listing |
| `triage_reports_status_and_reason` | One finding fixed, the refuted one's file byte-identical and listed with the `triage-not-approved` class on its line |
| `honours_task_scope_anchor` | The task-anchored finding fixed and HEAD unchanged |
| `honours_task_scope_anchor_no_task` | The same fixture with no task path: the finding's file byte-identical and the finding listed as a follow-up proposal |
| `lists_local_commits_lane_finding` | The local-commits-lane finding's locations byte-identical and listed |
| `anchors_duplicated_staged_lines` | The no-match staged finding's file byte-identical and listed |
| `relay_round_trip` | The stem holding the gate, fixer, and verifier round records, the gate prompt, and the round diff, with the saved return byte-identical |
| `declines_on_detached_head` | The decline on a detached `HEAD` before any gate call, with no run artefacts |
| `fixes_branch_commit_bug` | A committed branch defect fixed in the working tree and uncommitted, `HEAD` and `refs/heads/feature` unchanged, one ledger reproduction, and a clean stop |
| `gate_reviews_branch_and_worktree` | The gate's report headings and base-SHA lead, both a committed and an uncommitted defect listed in `working-tree lane` at their working-tree lines, and refs, worktrees, product files, and `HEAD` byte-identical |
| `gate_moves_no_ref` | Refs, worktrees, product files, and HEAD byte-identical around a standalone gate run |
| `classifies_lanes_from_evidence` | Each finding's lane and location matching the skill's case rules |
| `honours_round_cap` | The round-cap stop for the override and default runs |
| `retries_once_on_ledger_fail` | The ledger restore-and-retry leaving the reproduction passing |
| `stops_on_second_ledger_fail` | The second-ledger-failure stop with the pre-fix tree restored |
| `stops_on_self_written_code` | The self-written stop with `authored.txt` holding the cumulative hunks |
| `retries_once_on_unmapped_hunk` | The unmapped-hunk restore-and-retry leaving the delta audit clean |
| `stops_on_second_unmapped_hunk` | The second-unmapped-hunk stop with the pre-fix tree restored |

`eval_runner.load_eval_ids` derives `DEFAULT_IDS` from `evals.json`, so new
entries join the ordinary suite automatically.
