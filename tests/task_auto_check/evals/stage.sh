#!/usr/bin/env bash
# stage.sh - stage one task_auto_check eval and print agent-ready inputs.
#
# Usage:
#   stage.sh <eval_id> [target_dir]
#
# Valid eval ids:
#   mechanical_lint_ready  mechanical_lint_link  mechanical_lint_frontmatter
#   mechanical_lint_markdown  mechanical_lint_oversized_surface
#   already_ready  repair_to_ready  scope_split_stuck
#   intent_drift_human_route  fidelity_rejects_drift
#   no_verified_fix  cap_override
#   gate_failure_user_stop  drift_failure_user_stop
#   verifier_failure_user_stop  guard_rebaseline_after_gate
#   interaction_scan_surfaces  interaction_scan_no_false_alarm
#   immediate_ready_citations_survive  immediate_ready_citations_overturn

set -euo pipefail

eval_id="${1:?eval id required}"
target="${2:-$(mktemp -d "${TMPDIR:-/tmp}/task_auto_check_eval.XXXXXX")}"
mkdir -p "$target"
target="$(cd "$target" && pwd)"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../../.." && pwd)"
SKILL_MD="$REPO_ROOT/plugins/ai_dev/skills/task_auto_check/SKILL.md"

case "$eval_id" in
  mechanical_lint_ready)
    "$HERE/fixtures/mechanical_lint_ready/setup.sh" "$target" >/dev/null
    prompt="Run task_auto_check on tasks/api_lint-ready.md."
    ;;
  mechanical_lint_link)
    "$HERE/fixtures/mechanical_lint_link/setup.sh" "$target" >/dev/null
    prompt="Run task_auto_check on tasks/api_pagination-ready.md."
    ;;
  mechanical_lint_frontmatter)
    "$HERE/fixtures/mechanical_lint_frontmatter/setup.sh" "$target" >/dev/null
    prompt="Run task_auto_check on tasks/api_timeout-ready.md."
    ;;
  mechanical_lint_markdown)
    "$HERE/fixtures/mechanical_lint_markdown/setup.sh" "$target" >/dev/null
    prompt="Run task_auto_check on tasks/api_errors-ready.md."
    ;;
  mechanical_lint_oversized_surface)
    "$HERE/fixtures/mechanical_lint_oversized_surface/setup.sh" "$target" >/dev/null
    prompt="Run task_auto_check on tasks/api_audit-log-ready.md."
    ;;
  already_ready)
    "$HERE/fixtures/already_ready/setup.sh" "$target" >/dev/null
    prompt="Run task_auto_check on tasks/api_ready-task.md."
    ;;
  intent_drift_human_route)
    "$HERE/fixtures/intent_drift_human_route/setup.sh" "$target" >/dev/null
    prompt="Run task_auto_check on tasks/api_search-pagination.md."
    ;;
  repair_to_ready)
    "$HERE/fixtures/repair_to_ready/setup.sh" "$target" >/dev/null
    prompt="Run task_auto_check on tasks/api_retry-after.md and stop when task_check reports ready."
    ;;
  scope_split_stuck)
    "$HERE/fixtures/scope_split_stuck/setup.sh" "$target" >/dev/null
    prompt="Run task_auto_check on tasks/api_combo-auth-billing.md."
    ;;
  fidelity_rejects_drift)
    "$HERE/fixtures/fidelity_rejects_drift/setup.sh" "$target" >/dev/null
    prompt="Run task_auto_check on tasks/api_rate-limit.md."
    ;;
  no_verified_fix)
    "$HERE/fixtures/no_verified_fix/setup.sh" "$target" >/dev/null
    prompt="Run task_auto_check on tasks/api_product-decision.md."
    ;;
  cap_override)
    "$HERE/fixtures/cap_override/setup.sh" "$target" >/dev/null
    prompt="Run task_auto_check on tasks/api_pathological.md with max rounds 2."
    ;;
  gate_failure_user_stop)
    "$HERE/fixtures/gate_failure_user_stop/setup.sh" "$target" >/dev/null
    prompt="Run task_auto_check on tasks/api_healthcheck.md. Environment note: the auto_gate_task helper agent is broken in this harness. Do not invoke auto_gate_task at all; treat its invocation and the single retry as already failed with a spawn error, and follow the skill's agent-failure policy from there. All other helper agents work normally."
    ;;
  drift_failure_user_stop)
    "$HERE/fixtures/drift_failure_user_stop/setup.sh" "$target" >/dev/null
    prompt="Run task_auto_check on tasks/api_metrics.md. Environment note: the auto_drift_task helper agent is broken in this harness. Do not invoke auto_drift_task at all; treat its invocation and the single retry as already failed with a spawn error, and follow the skill's agent-failure policy from there. All other helper agents work normally."
    ;;
  verifier_failure_user_stop)
    "$HERE/fixtures/verifier_failure_user_stop/setup.sh" "$target" >/dev/null
    prompt="Run task_auto_check on tasks/api_quota-headers.md. Environment note: the auto_verifier_task helper is broken in this harness. Do not invoke auto_verifier_task at all; treat its invocation and the single retry as already failed with a spawn error, so no verifier result can be produced this run, and follow the skill's agent-failure policy from there. All other helper agents work normally."
    ;;
  guard_rebaseline_after_gate)
    "$HERE/fixtures/guard_rebaseline_after_gate/setup.sh" "$target" >/dev/null
    prompt="Run task_auto_check on tasks/api_idempotency.md and stop when task_check reports ready."
    ;;
  interaction_scan_surfaces)
    "$HERE/fixtures/interaction_scan_surfaces/setup.sh" "$target" >/dev/null
    prompt="Run task_auto_check on tasks/api_page-size-config.md and stop when task_check reports ready."
    ;;
  interaction_scan_no_false_alarm)
    "$HERE/fixtures/interaction_scan_no_false_alarm/setup.sh" "$target" >/dev/null
    prompt="Run task_auto_check on tasks/api_request-id.md."
    ;;
  immediate_ready_citations_survive)
    "$HERE/fixtures/immediate_ready_citations_survive/setup.sh" "$target" >/dev/null
    prompt="Run task_auto_check on tasks/api_retry-header.md."
    ;;
  immediate_ready_citations_overturn)
    "$HERE/fixtures/immediate_ready_citations_overturn/setup.sh" "$target" >/dev/null
    prompt="Run task_auto_check on tasks/wiki_base-skill-output-contract.md."
    ;;
  *)
    echo "unknown eval id: $eval_id" >&2
    exit 2
    ;;
esac

sandbox_proj="$target/proj"
skill_name="task_auto_check"
skill_path="$SKILL_MD"

date +%s > "$target/.eval_started_at"

printf 'sandbox_proj=%s\n' "$(printf %q "$sandbox_proj")"
printf 'skill_name=%s\n' "$(printf %q "$skill_name")"
printf 'skill_path=%s\n' "$(printf %q "$skill_path")"
printf 'prompt=%s\n' "$(printf %q "$prompt")"
