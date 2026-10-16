# Parallel worker measurement

Recorded evidence for the task_auto_check parallel runner.

- **Vendor:** Cursor default (`agent -p`, model `auto`), no `--vendor`.
- **Isolated pool:** default `--workers` 4. The serial nested-loop set runs after that pool at 1 worker.
- **Workers-1 run:** `python3 tests/task_auto_check/evals/run.py --force --workers 1 already_ready mechanical_lint_ready`
- **Workers-1 run dir:** `tests/task_auto_check/workspace/run-20261016-123228-96875`
- **Workers-1 result:** `graded: 2/2 evals passed (0 from cache)`
- **Default run:** `python3 tests/task_auto_check/evals/run.py --force`
- **Default run dir:** `tests/task_auto_check/workspace/run-20261016-125642-95903`
- **Default result:** `graded: 15/32 evals passed (0 from cache)`, covering every id in `evals.json`.

## Comparison with the 15 October cache

The latest verdict-cache record for each of the 32 ids with `graded_at` before 2026-10-16 shows 27 passes. This run's graded summary is 15 of 32. Six evals in this run ended at their timeout ceiling with `worker_rc` -1, so those six grades are inconclusive under the RUNBOOK rule for that rc. The cache still holds the earlier records for those six, because this run did not write a cache entry for them.

| Eval | Pool | 15 October cache | 16 October run |
| --- | --- | --- | --- |
| `no_verified_fix` | isolated | pass, 830s | timeout at the 2305s ceiling |
| `fidelity_rejects_drift` | isolated | fail, rc 0, 1359s | timeout at the 2305s ceiling |
| `repair_to_ready` | serial | pass, 1000s | timeout at the 2305s ceiling |
| `guard_rebaseline_after_gate` | serial | fail, rc 0, 497s | timeout at the 2305s ceiling |
| `interaction_scan_surfaces` | serial | pass, 1171s | timeout at the 2305s ceiling |
| `immediate_ready_citations_overturn` | serial | pass, 2445s | timeout at its 3600s budget |

`repair_to_ready`, `interaction_scan_surfaces`, and `immediate_ready_citations_overturn` already ran one at a time and still moved from a 15 October pass to a ceiling kill. `already_ready`, outside the serial set, moved from 276s on 15 October to 543s in this run's isolated pool. The serial set in `evals/run.py` stays as recorded: this run shows a slower day across both pools, and it does not separate that slowdown from parallel load.

## Workers 1 windows

Both evals are outside the serial nested-loop set. The second `started_at` is after the first `ended_at`, so the windows do not overlap.

| Eval | started_at | ended_at | worker_rc |
| --- | ---: | ---: | ---: |
| `already_ready` | 1792146763.865851 | 1792147723.317785 | 0 |
| `mechanical_lint_ready` | 1792147724.296964 | 1792148182.417367 | 0 |

## Default-vendor windows

Unix epoch seconds from each workspace `timing.json`. Isolated rows overlap (54 overlapping pairs). Serial rows are pairwise disjoint, and every serial `started_at` is at or after every isolated `ended_at` (latest isolated end 1792153152.587351, earliest serial start 1792153153.402160).

| Eval | Pool | started_at | ended_at | worker_rc |
| --- | --- | ---: | ---: | ---: |
| `mechanical_lint_ready` | isolated | 1792148224.000071 | 1792148846.245427 | 0 |
| `mechanical_lint_link` | isolated | 1792148224.000301 | 1792150221.722825 | 0 |
| `mechanical_lint_frontmatter` | isolated | 1792148224.015444 | 1792149075.218812 | 0 |
| `mechanical_lint_markdown` | isolated | 1792148223.999597 | 1792150060.005636 | 0 |
| `mechanical_lint_oversized_surface` | isolated | 1792148847.219747 | 1792149648.706655 | 0 |
| `already_ready` | isolated | 1792149076.111154 | 1792149619.594341 | 0 |
| `intent_drift_human_route` | isolated | 1792149620.516430 | 1792150224.571762 | 0 |
| `drift_gate_narrowing_clean` | isolated | 1792149649.482862 | 1792150362.527683 | 0 |
| `drift_gate_refinement_clean` | isolated | 1792150060.967625 | 1792150746.103195 | 0 |
| `drift_gate_broadening_drift` | isolated | 1792150222.644422 | 1792150844.762503 | 0 |
| `drift_gate_committed_broadening_clean` | isolated | 1792150225.513907 | 1792151013.605344 | 0 |
| `repair_to_ready` | serial | 1792153153.402160 | 1792155460.302112 | -1 |
| `relay_by_path` | serial | 1792155461.336433 | 1792157212.216382 | 0 |
| `stray_hunk_reverted` | serial | 1792157213.350779 | 1792158265.977957 | 0 |
| `scope_split_stuck` | isolated | 1792150363.409199 | 1792150968.268513 | 0 |
| `fidelity_rejects_drift` | isolated | 1792150746.899984 | 1792153053.887939 | -1 |
| `no_verified_fix` | isolated | 1792150845.561549 | 1792153152.587351 | -1 |
| `cap_override` | isolated | 1792150969.170918 | 1792152959.878991 | 0 |
| `gate_failure_user_stop` | isolated | 1792151014.450905 | 1792151268.634140 | 0 |
| `drift_failure_user_stop` | isolated | 1792151269.487267 | 1792151354.889596 | 0 |
| `verifier_failure_user_stop` | isolated | 1792151355.807121 | 1792151931.738143 | 0 |
| `guard_rebaseline_after_gate` | serial | 1792158267.000578 | 1792160573.991479 | -1 |
| `interaction_scan_surfaces` | serial | 1792160574.934587 | 1792162881.770934 | -1 |
| `immediate_ready_citations_survive` | isolated | 1792151932.714696 | 1792152581.812769 | 0 |
| `immediate_ready_citations_overturn` | serial | 1792162882.821581 | 1792166485.144448 | -1 |
| `interaction_scan_no_false_alarm` | isolated | 1792152582.745836 | 1792153130.073198 | 0 |
| `regroup_via_reviewer` | serial | 1792166486.123390 | 1792167699.380310 | 0 |
| `regroup_immediate_ready` | serial | 1792167700.475537 | 1792168682.073476 | 0 |
| `regroup_same_paragraph_ready` | serial | 1792168683.186476 | 1792169715.536566 | 0 |
| `committed_rule_deletion_routed` | serial | 1792169716.897543 | 1792170875.162669 | 0 |
| `last_call_ready_refuted` | serial | 1792170876.398534 | 1792172390.106117 | 0 |
| `regate_isolated` | serial | 1792172391.322091 | 1792173553.554077 | 0 |

Each `timing.json` also carries `skill_name`, `artefacts_read_from_micro_deployment`, `checkout_unread`, and `duration_s`.
