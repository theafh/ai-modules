# Loose reproduction dispositions

The reproduction scripts that earlier `git_auto_review` runs left under
`tests/*/script_tests/repro*` each ran only when someone called it by hand.
This file records where each check now lives before the scripts were removed
with `git rm`. The selector was `git ls-files 'tests/*/script_tests/repro*'`,
run before the deletion, and every path it returned appears below once.

- `tests/deployment/script_tests/repro/git_auto_review_hook_merge_shape.sh` — the existing scenarios in `tests/deployment/script_tests/hook_merge_run.sh` (the non-object `hooks` value, the array and string values, the event list with a non-object member, and the hook script that still lands after the foreign config), driven by `tests/deployment/run_all.sh`.
- `tests/deployment/script_tests/repro/git_auto_review_manifest_forgetting.sh` — the existing item 18 scenario in `tests/deployment/script_tests/hook_merge_run.sh` (a redeploy keeps the owned entry in its `@entries:` manifest, and an uninstall over a hand-edited event claims no removal it did not make).
- `tests/deployment/script_tests/repro/git_auto_review_uninstall_empty_hooks.sh` — the existing item 16 scenario in `tests/deployment/script_tests/hook_merge_run.sh` (an empty hooks list, a string value, and an array value all survive the uninstall).
- `tests/deployment/script_tests/repro/git_auto_review_uninstall_foreign_event.sh` — the existing item 17 scenario in `tests/deployment/script_tests/hook_merge_run.sh` (an uninstall beside a non-array event value reports its line removed and drops its log line).
- `tests/git_auto_review/script_tests/repro/git_auto_review_grade_section_scope.sh` — the new scenario `s21_grade_section_scope` in `tests/git_auto_review/script_tests/run.sh`.
- `tests/git_auto_review/script_tests/repro/git_auto_review_ledger_per_finding.sh` — the new scenario `s22_grade_ledger_per_finding` in `tests/git_auto_review/script_tests/run.sh`.
- `tests/git_auto_review/script_tests/repro/git_auto_review_named_target_decline.sh` — the eval grader arm `declines_on_named_other_branch` in `tests/git_auto_review/evals/grade.sh`.
- `tests/git_auto_review/script_tests/repro/git_auto_review_named_target_documented.sh` — the new scenario `s23_eval_docs_inventory` in `tests/git_auto_review/script_tests/run.sh`.
- `tests/git_auto_review/script_tests/repro/git_auto_review_runbook_deployed_root.sh` — the new scenario `s23_eval_docs_inventory` in `tests/git_auto_review/script_tests/run.sh`.
- `tests/git_auto_review/script_tests/repro/git_auto_review_triage_row_class.sh` — the new scenario `s23_eval_docs_inventory` in `tests/git_auto_review/script_tests/run.sh`.
- `tests/git_auto_review/script_tests/repro/git_auto_review_wiki_log_entry.sh` — the new scenario `c1_wiki_log_and_updated_contract` in `tests/wiki/layer1/run.sh`, the wiki harness's deterministic runner (it has no `script_tests/` directory).
- `tests/git_auto_review/script_tests/repro/git_auto_review_wiki_page_updated.sh` — the new scenario `c1_wiki_log_and_updated_contract` in `tests/wiki/layer1/run.sh`, the wiki harness's deterministic runner (it has no `script_tests/` directory).
- `tests/git_auto_review/script_tests/repro_newline_untracked_path.sh` — the new scenario `s20_newline_untracked_path` in `tests/git_auto_review/script_tests/run.sh`.
- `tests/git_auto_review/script_tests/repro_rotation_mv_fallback.sh` — the new scenario `c2_rotation_move_contract` in `tests/wiki/layer1/run.sh`, the wiki harness's deterministic runner (it has no `script_tests/` directory).
