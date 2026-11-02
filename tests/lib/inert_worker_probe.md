# Inert-worker probe

The probe stages every behavioral eval in the named harnesses, writes an empty
response file, and grades the untouched sandbox. An eval that still grades PASS
did so with the worker contributing nothing, which is the defect this probe
measures.

```bash
python3 tests/lib/inert_worker_probe.py
python3 tests/lib/inert_worker_probe.py --harness task_auto_check
```

Harness set: `git_checkout`, `git_review`, `git_refresh`, `git_auto_review`,
`task`, `task_auto_check`, `natural_language`, and `wiki`. The first seven
stage through their own `evals/stage.sh`; `wiki` grades a synthetic
`L2-1/pass-1/response.txt` run directory because that harness's grader reads a
run directory rather than one eval.

The probe exits 1 when any eval grades PASS, and an inert pass outranks an
unmeasured harness: it exits 2 when a harness could not be measured and no eval
graded PASS, and 0 when every graded eval fails.
The script tests run the same command as a pin, so a later edit that removes a
positive check turns the pin red.

## Measurement, 2026-11-02

The `2026-10-30` reading in the task named one inert pass for
`git_auto_review`; re-running the probe found a second (`gate_moves_no_ref`),
and both were repaired.

| Harness | Inert-PASS before | Inert-PASS after | Total |
| --- | --- | --- | --- |
| `git_checkout` | 4 | 0 | 7 |
| `git_review` | 2 | 0 | 48 |
| `git_refresh` | 1 | 0 | 4 |
| `git_auto_review` | 2 | 0 | 36 |
| `task` | 8 | 0 | 46 |
| `task_auto_check` | 11 | 0 | 33 |
| `natural_language` | 1 | 0 | 2 |
| `wiki` | 1 | 0 | 1 |

## Pin red-to-green results

Each pin was added and run against its harness's unedited grader before that
grader's edit. The recorded red result names the pin's exit status and the eval
ids the unedited grader scored PASS; the same pin is green after the edit.

| Harness | Pin | Red result | Eval ids that passed unedited |
| --- | --- | --- | --- |
| `git_checkout` | `script_tests/run.sh` `s16` | exit 1 | 3, 5, 6, 7 |
| `git_review` | `script_tests/run.sh` `s36` | exit 1 | 7, 36 |
| `git_refresh` | `script_tests/run.sh` `s13` | exit 1 | 4 |
| `git_auto_review` | `script_tests/run.sh` `s24` | exit 1 | `declines_on_detached_head`, `gate_moves_no_ref` |
| `task` | `script_tests/run.sh` `eg1` | exit 1 | `explain`, `select`, `implement_dep_gate`, `select_inbound_dep`, `select_dep_regression`, `audit_gaps`, `query`, `implement_boundary_cross` |
| `task_auto_check` | `script_tests/run.sh` `s16` | exit 1 | `mechanical_lint_oversized_surface`, `already_ready`, `intent_drift_human_route`, `drift_gate_narrowing_clean`, `drift_gate_refinement_clean`, `drift_gate_broadening_drift`, `drift_gate_committed_broadening_clean`, `scope_split_stuck`, `gate_failure_user_stop`, `drift_failure_user_stop`, `interaction_scan_no_false_alarm` |
| `natural_language` | `evals/test_grade.py` empty-delivery case | exit 1 (case failed) | `chat_brevity` |
| `wiki` | `layer1/run.sh` `g1` | scenario failed, `layer2/grade.py` exit 0 | `L2-1` synthetic empty pass |

The green runs are the probe's `after` column above and the same pins in
`make test`.
