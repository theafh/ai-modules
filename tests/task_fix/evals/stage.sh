#!/usr/bin/env bash
# stage.sh - stage one task_fix eval and print agent-ready inputs.
#
# Usage:
#   stage.sh <eval_id> [target_dir]
#
# Valid eval ids:
#   regroup_live_skip_archived  a live task narrates one handoff in Goal and
#                               Context with a link at each site, and an
#                               archived task links one target twice: the live
#                               account gathers into Context, the archived body
#                               stays as archived and draws no finding
#   regroup_state_and_edit_site Context describes what a reference page says
#                               today and Approach edits one of its sections:
#                               the page's state and its edit belong together,
#                               so they gather into one passage under one link
#                               and the finding is reported as regrouped
#   surfaced_acceptance_contract
#                               an `## Acceptance` item's copy of the account is
#                               the check's own parameter, so gathering it out
#                               would leave the item nothing to measure: the
#                               body is left alone and the finding is surfaced
#                               with that reason
#   regroup_same_paragraph      one Context paragraph links a sibling twice and
#                               nothing else names it: the material is already
#                               gathered, so the run names the sibling again in
#                               plain text inside that paragraph and the
#                               finding is reported as regrouped
#
# Prints printf-%q-quoted `name=value` lines, safe to `eval` in bash:
#
#   sandbox_proj=<abs path to the project the skill should operate in>
#   skill_name=<the skill the agent should load>
#   skill_path=<abs path to that skill's SKILL.md>
#   prompt=<the user prompt to feed the agent>
#
# Run the agent with $sandbox_proj as its working directory so the skill's
# discover_tasks.sh resolves the sandbox and never the real repo. The marker
# file $target/.eval_started_at records the run-start epoch for grade.sh's
# isolation checks.

set -euo pipefail

eval_id="${1:?eval id required}"
target="${2:-$(mktemp -d "${TMPDIR:-/tmp}/task_fix_eval.XXXXXX")}"
mkdir -p "$target"
target="$(cd "$target" && pwd)"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../../.." && pwd)"
# shellcheck source=../../lib/host_tasks_guard.sh
. "$HERE/../../lib/host_tasks_guard.sh"
SKILL_MD="$REPO_ROOT/plugins/ai_dev/skills/task_fix/SKILL.md"

case "$eval_id" in
  regroup_live_skip_archived)
    "$HERE/fixtures/regroup_live_skip_archived/setup.sh" "$target" >/dev/null
    prompt="Health-check and clean up the tasks backlog."
    ;;
  regroup_state_and_edit_site)
    "$HERE/fixtures/regroup_state_and_edit_site/setup.sh" "$target" >/dev/null
    prompt="Health-check and clean up the tasks backlog."
    ;;
  surfaced_acceptance_contract)
    "$HERE/fixtures/surfaced_acceptance_contract/setup.sh" "$target" >/dev/null
    prompt="Health-check and clean up the tasks backlog."
    ;;
  regroup_same_paragraph)
    "$HERE/fixtures/regroup_same_paragraph/setup.sh" "$target" >/dev/null
    prompt="Health-check and clean up the tasks backlog."
    ;;
  *)
    echo "unknown eval id: $eval_id" >&2
    exit 2
    ;;
esac

sandbox_proj="$target/proj"
skill_name="task_fix"
skill_path="$SKILL_MD"

date +%s > "$target/.eval_started_at"
# Isolated copy of the host tasks tree. Grade compares the live tree to this
# copy only for the sandbox's fixture names, so a parallel session that moves
# some other real task does not fail the check.
snapshot_isolated_host_tasks "$target" "$REPO_ROOT"
record_sandbox_task_names "$target" "$sandbox_proj/tasks"


printf 'sandbox_proj=%s\n' "$(printf %q "$sandbox_proj")"
printf 'skill_name=%s\n'   "$(printf %q "$skill_name")"
printf 'skill_path=%s\n'   "$(printf %q "$skill_path")"
printf 'prompt=%s\n'       "$(printf %q "$prompt")"
