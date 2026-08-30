#!/usr/bin/env bash
# stage.sh — stage one task-family eval and print the agent-ready inputs.
#
# Usage:
#   stage.sh <eval_id> [target_dir]
#
# Valid eval ids:
#   create  check  standing_rules_create  standing_rules_check
#   standing_rules_check_control  explain  select  implement  audit_gaps
#   audit_clean  finish  fix  query  update  triage  (base `task` hub behaviours)
#   update_contract                   (the hub <output_contract>: one <update>
#                                      run reporting files touched, lifecycle
#                                      move, linter outcome, and assumptions)
#   lossless_split  lossless_single   (source-fidelity on the create path)
#   implement_dep_gate  select_inbound_dep  select_dep_regression
#                                     (dependency-signal behaviours)
#   check_boundary_contradiction  check_boundary_clean
#   implement_boundary_cross  implement_boundary_agree
#   create_scope_trim  auto_check_boundary
#                                     (Out of scope boundary-convention behaviours)
#   check_exclusion_requirement  check_exclusion_requirement_control
#   check_exclusion_waiver  check_exclusion_waiver_control
#                                     (Out of scope not-for behaviours: an
#                                      in-scope requirement filed as an
#                                      exclusion, and an exclusion waiving a
#                                      standing rule — each with its control)
#   check_count_stable                (count-stable reference discipline: one
#                                      body carrying a frozen mutable-set count
#                                      beside a legal measurement-protocol count)
#   finish_arch_extended  finish_arch_declined  finish_arch_absent
#                                     (close-out ARCHITECTURE.md refresh: the
#                                      design-extended signal driving a refresh,
#                                      declining one, and the presence gate)
#   fix_coherence                     (the default backlog-coherence assessment
#                                      over a jointly incoherent live set)
#   fix_coherence_reconcile_escalated
#   fix_coherence_reconcile_inline_staleness
#                                     (the gated reconcile halves, both reusing
#                                      the fix_coherence fixture with distinct
#                                      accept prompts)
#   fix_coherence_selector_scope  fix_coherence_selector_explicit_list
#   fix_coherence_selector_whole_tree
#                                     (the three selector forms: scope filter,
#                                      explicit list, and the no-filter default)
#
# The six backlog-coherence ids ask for the assessment in coherence-report.md as
# well as in the response, with a `selected:` line and one `verdict:` line per
# task. grade.sh never sees the agent's response text, so that structured report
# file is what makes the assess-phase verdicts and the selected-set boundary
# deterministically gradeable; its content is what task_fix's <output_contract>
# already mandates.
#
# Prints name=value lines on stdout, each value already quoted with
# printf %q so the block is safe to `eval`:
#
#   sandbox_proj=<abs path to the project the skill should operate in>
#   skill_name=<the task-family skill the agent should load>
#   skill_path=<abs path to that skill's SKILL.md>
#   prompt=<the user prompt to feed the agent>
#
# Run the agent with $sandbox_proj as its working directory so the
# skill's discover_tasks.sh resolves the sandbox and never the real repo.
# A marker file $target/.eval_started_at records the run-start epoch;
# grade.sh uses it for created-timestamp tolerance and isolation checks.

set -euo pipefail

eval_id="${1:?eval id required (create|check|standing_rules_create|standing_rules_check|standing_rules_check_control|explain|select|implement|implement_dep_gate|select_inbound_dep|select_dep_regression|audit_gaps|audit_clean|finish|fix|query|update|update_contract|triage|lossless_split|lossless_single|check_boundary_contradiction|check_boundary_clean|implement_boundary_cross|implement_boundary_agree|create_scope_trim|auto_check_boundary|check_exclusion_requirement|check_exclusion_requirement_control|check_exclusion_waiver|check_exclusion_waiver_control|check_count_stable|finish_arch_extended|finish_arch_declined|finish_arch_absent|fix_coherence|fix_coherence_reconcile_escalated|fix_coherence_reconcile_inline_staleness|fix_coherence_selector_scope|fix_coherence_selector_explicit_list|fix_coherence_selector_whole_tree)}"
target="${2:-$(mktemp -d "${TMPDIR:-/tmp}/task_eval.XXXXXX")}"
mkdir -p "$target"
target="$(cd "$target" && pwd)"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../../.." && pwd)"
SKILLS="$REPO_ROOT/plugins/ai_dev/skills"

skill_for() { printf '%s/%s/SKILL.md' "$SKILLS" "$1"; }

# Shared tail for the six backlog-coherence prompts: it asks for the report on
# disk in a machine-readable shape so grade.sh can assert the selected set and
# the per-task verdicts, which it cannot read out of the agent's response.
REPORT_CONTRACT='Write your full report to coherence-report.md in the project root as well as answering here, and make its backlog-coherence assessment section machine-readable: one line "selected: <comma-separated task filenames>" naming exactly the selected live set, one line per selected task in the form "verdict: <task filename> - <ship-as-is|alter|defer-candidate> - <the evidence>", and a "## Ship order" section naming each wave and the tasks in it.'

case "$eval_id" in
  create)
    "$HERE/fixtures/create/setup.sh"      "$target" >/dev/null
    skill_name="task_create"
    prompt="Make a task for adding request rate limiting to the public API: requests over 100 per minute should receive an HTTP 429."
    ;;
  check)
    "$HERE/fixtures/check/setup.sh"       "$target" >/dev/null
    skill_name="task_check"
    prompt="Is the task tasks/api_make-it-better.md ready to hand to an implementer? Check it."
    ;;
  standing_rules_create)
    "$HERE/fixtures/standing_rules_create/setup.sh" "$target" >/dev/null
    skill_name="task_create"
    prompt="Make a task from notes/packaging-smoke-test-draft.md."
    ;;
  standing_rules_check)
    "$HERE/fixtures/standing_rules_check/setup.sh" "$target" >/dev/null
    skill_name="task_check"
    prompt="Is the task tasks/build_packaging-smoke.md ready to hand to an implementer? Check it."
    ;;
  standing_rules_check_control)
    "$HERE/fixtures/standing_rules_check_control/setup.sh" "$target" >/dev/null
    skill_name="task_check"
    prompt="Is the task tasks/build_packaging-smoke.md ready to hand to an implementer? Check it."
    ;;
  explain)
    "$HERE/fixtures/explain/setup.sh"     "$target" >/dev/null
    skill_name="task_explain"
    prompt="Explain tasks/archive/api_retry-after-header.md at a high level: what it is about, why it was done, and how it was achieved."
    ;;
  select)
    "$HERE/fixtures/select/setup.sh"      "$target" >/dev/null
    skill_name="task_select"
    prompt="What api task should I work on next? Rank the candidates and recommend the next action."
    ;;
  implement)
    "$HERE/fixtures/implement/setup.sh"   "$target" >/dev/null
    skill_name="task_implement"
    prompt="Implement the task tasks/calc_add-function.md."
    ;;
  implement_dep_gate)
    "$HERE/fixtures/implement_dep_gate/setup.sh" "$target" >/dev/null
    skill_name="task_implement"
    prompt="Implement the task tasks/render_wire-palette.md."
    ;;
  select_inbound_dep)
    "$HERE/fixtures/select_inbound_dep/setup.sh" "$target" >/dev/null
    skill_name="task_select"
    prompt="What api task should I work on next? Rank the candidates and recommend the next action."
    ;;
  select_dep_regression)
    "$HERE/fixtures/select_dep_regression/setup.sh" "$target" >/dev/null
    skill_name="task_select"
    prompt="What task should I work on next? Rank all the candidates and recommend the next action."
    ;;
  audit_gaps)
    "$HERE/fixtures/audit_gaps/setup.sh"  "$target" >/dev/null
    skill_name="task_audit"
    prompt="Audit tasks/calc_add-function.md — is the work actually complete and backed by tests?"
    ;;
  audit_clean)
    "$HERE/fixtures/audit_clean/setup.sh" "$target" >/dev/null
    skill_name="task_audit"
    prompt="Audit tasks/calc_add-function.md against the code — is it fully done?"
    ;;
  finish)
    "$HERE/fixtures/finish/setup.sh"      "$target" >/dev/null
    skill_name="task_finish"
    prompt="Mark tasks/api_rate-limit.md implemented and archive it — the work is already merged and verified."
    ;;
  fix)
    "$HERE/fixtures/fix/setup.sh"         "$target" >/dev/null
    skill_name="task_fix"
    prompt="Health-check and clean up the tasks backlog in this project — fix what is mechanical and flag the rest for review."
    ;;
  query)
    "$HERE/fixtures/query/setup.sh"       "$target" >/dev/null
    skill_name="task"
    prompt="List my open tasks, grouped by scope."
    ;;
  update)
    "$HERE/fixtures/update/setup.sh"      "$target" >/dev/null
    skill_name="task"
    prompt="Update the description on the api_rate-limit task to also mention that rejected requests get a Retry-After header."
    ;;
  update_contract)
    "$HERE/fixtures/update_contract/setup.sh" "$target" >/dev/null
    skill_name="task"
    prompt="Update the token rotation task: we settled on a 24-hour rotation window, and a rotated token keeps authenticating for a 1-hour overlap after its replacement is issued."
    ;;
  triage)
    "$HERE/fixtures/triage/setup.sh"      "$target" >/dev/null
    skill_name="task"
    prompt="The latest task_check report on tasks/api_rate-limit.md lists these issues: 1. **Unverifiable acceptance** — in '## Acceptance', the item 'the rate limiter works properly' cannot be verified; minimum fix: replace it with 'requests over 100 per minute receive HTTP 429'. 2. **Goal names no mechanism** — in '## Goal', 'Protect the public API from abusive clients.' names no throttle mechanism; minimum fix: reword to 'Throttle the public API with a fixed-window rate limit.'. 3. **Empty Context** — '## Context' carries no pointers; minimum fix: add a pointer to src/api/server.py where the middleware lives. My triage: apply 1 as suggested; reject 2 — the goal stays as it is; for 3, point at docs/api.md instead of src/api/server.py."
    ;;
  lossless_split)
    "$HERE/fixtures/lossless_split/setup.sh"  "$target" >/dev/null
    skill_name="task"
    prompt="Turn the migration plan in notes/db-migration-plan.md into backlog tasks."
    ;;
  lossless_single)
    "$HERE/fixtures/lossless_single/setup.sh" "$target" >/dev/null
    skill_name="task_create"
    prompt="Make a task from the bug report in notes/session-cache-bug.md."
    ;;
  check_boundary_contradiction)
    "$HERE/fixtures/check_boundary_contradiction/setup.sh" "$target" >/dev/null
    skill_name="task_check"
    prompt="Is the task tasks/cli_json-output-flag.md ready to hand to an implementer? Check it."
    ;;
  check_boundary_clean)
    "$HERE/fixtures/check_boundary_clean/setup.sh" "$target" >/dev/null
    skill_name="task_check"
    prompt="Is the task tasks/cli_exit-code-on-error.md ready to hand to an implementer? Check it."
    ;;
  implement_boundary_cross)
    "$HERE/fixtures/implement_boundary_cross/setup.sh" "$target" >/dev/null
    skill_name="task_implement"
    prompt="Implement the task tasks/report_colored-lines.md."
    ;;
  implement_boundary_agree)
    "$HERE/fixtures/implement_boundary_agree/setup.sh" "$target" >/dev/null
    skill_name="task_implement"
    prompt="Implement the task tasks/calc_add-function.md."
    ;;
  create_scope_trim)
    "$HERE/fixtures/create_scope_trim/setup.sh" "$target" >/dev/null
    skill_name="task_create"
    prompt="Make a task to add a --json output flag to the report command. We also want --yaml and --csv output eventually, but not as part of this — those are separate, later work."
    ;;
  auto_check_boundary)
    "$HERE/fixtures/check_boundary_contradiction/setup.sh" "$target" >/dev/null
    skill_name="task_auto_check"
    prompt="Auto-check the task tasks/cli_json-output-flag.md until it is ready, without implementing it."
    ;;
  check_exclusion_requirement)
    "$HERE/fixtures/check_exclusion_requirement/setup.sh" "$target" >/dev/null
    skill_name="task_check"
    prompt="Is the task tasks/build_packaging-smoke.md ready to hand to an implementer? Check it."
    ;;
  check_exclusion_requirement_control)
    "$HERE/fixtures/check_exclusion_requirement_control/setup.sh" "$target" >/dev/null
    skill_name="task_check"
    prompt="Is the task tasks/build_packaging-smoke.md ready to hand to an implementer? Check it."
    ;;
  check_exclusion_waiver)
    "$HERE/fixtures/check_exclusion_waiver/setup.sh" "$target" >/dev/null
    skill_name="task_check"
    prompt="Is the task tasks/build_packaging-smoke.md ready to hand to an implementer? Check it."
    ;;
  check_exclusion_waiver_control)
    "$HERE/fixtures/check_exclusion_waiver_control/setup.sh" "$target" >/dev/null
    skill_name="task_check"
    prompt="Is the task tasks/build_packaging-smoke.md ready to hand to an implementer? Check it."
    ;;
  check_count_stable)
    "$HERE/fixtures/check_count_stable/setup.sh" "$target" >/dev/null
    skill_name="task_check"
    prompt="Is the task tasks/build_manifest-smoke.md ready to hand to an implementer? Check it."
    ;;
  finish_arch_extended)
    "$HERE/fixtures/finish_arch_present/setup.sh" "$target" >/dev/null
    skill_name="task_finish"
    prompt="Close out tasks/api_pluggable-storage.md and archive it — the work is merged and verified."
    ;;
  finish_arch_declined)
    "$HERE/fixtures/finish_arch_present/setup.sh" "$target" >/dev/null
    skill_name="task_finish"
    prompt="Close out tasks/api_retry-after-header.md and archive it — the work is merged and verified."
    ;;
  finish_arch_absent)
    "$HERE/fixtures/finish_arch_absent/setup.sh" "$target" >/dev/null
    skill_name="task_finish"
    prompt="Close out tasks/api_pluggable-storage.md and archive it — the work is merged and verified."
    ;;
  fix_coherence)
    "$HERE/fixtures/fix_coherence/setup.sh" "$target" >/dev/null
    skill_name="task_fix"
    prompt="Health-check the tasks backlog in this project. Should these tasks all ship as they are, or do some need altering or deferring to stay coherent with each other and with the current code? Assess only — apply no coherence repair, since I have accepted nothing yet. $REPORT_CONTRACT"
    ;;
  fix_coherence_reconcile_escalated)
    "$HERE/fixtures/fix_coherence/setup.sh" "$target" >/dev/null
    skill_name="task_fix"
    prompt="Health-check the tasks backlog in this project and assess whether these tasks stay coherent with each other and with the current code. I accept these five findings up front, so reconcile them in this run: the severity_label edit that two tasks both own, the stale unreachable_clean_bar anchor, the license-check severity that re-blocks the accepted-info clean-bar exception a sibling establishes, the check-module docstring sweep that enumerates fewer modules than its own rule implies, and the opposed path-check and glob-check severity postures. Resolve that accepted set autonomously through the task tree shaper. Leave every finding I have not accepted alone. $REPORT_CONTRACT"
    ;;
  fix_coherence_reconcile_inline_staleness)
    "$HERE/fixtures/fix_coherence/setup.sh" "$target" >/dev/null
    skill_name="task_fix"
    prompt="Health-check the tasks backlog in this project and assess whether these tasks stay coherent with each other and with the current code. I accept only the staleness repairs: refresh the stale unreachable_clean_bar anchor in the clean-bar note task, and add the out-of-scope note the run-summary task needs. Leave the judgement calls unrepaired — the double-owned severity_label edit, the license-check severity, the check-module docstring sweep, and the opposed path and glob postures all stay as they are, and do not escalate to the task tree shaper. For the quiet-flag task, flag it for re-check in the report instead of applying the repair that would change what its Acceptance requires. $REPORT_CONTRACT"
    ;;
  fix_coherence_selector_scope)
    "$HERE/fixtures/fix_coherence_selector_scope/setup.sh" "$target" >/dev/null
    skill_name="task_fix"
    prompt="Check backlog coherence for the tool scope. Assess only — apply no coherence repair. $REPORT_CONTRACT"
    ;;
  fix_coherence_selector_explicit_list)
    "$HERE/fixtures/fix_coherence_selector_explicit_list/setup.sh" "$target" >/dev/null
    skill_name="task_fix"
    prompt="Do tasks/svc_alpha-retry.md and tasks/svc_beta-retry.md ship together, or does either need altering? Assess just those two. Apply no coherence repair. $REPORT_CONTRACT"
    ;;
  fix_coherence_selector_whole_tree)
    "$HERE/fixtures/fix_coherence_selector_whole_tree/setup.sh" "$target" >/dev/null
    skill_name="task_fix"
    prompt="Health-check and clean up the tasks backlog in this project — fix what is mechanical and flag the rest for review. $REPORT_CONTRACT"
    ;;
  *)
    echo "unknown eval id: $eval_id" >&2
    exit 2
    ;;
esac

sandbox_proj="$target/proj"
skill_path="$(skill_for "$skill_name")"

# Marker = run-start epoch. grade.sh reads it for created-timestamp
# tolerance and "nothing newer outside the sandbox" isolation checks.
date +%s > "$target/.eval_started_at"

printf 'sandbox_proj=%s\n' "$(printf %q "$sandbox_proj")"
printf 'skill_name=%s\n'   "$(printf %q "$skill_name")"
printf 'skill_path=%s\n'   "$(printf %q "$skill_path")"
printf 'prompt=%s\n'       "$(printf %q "$prompt")"
