#!/usr/bin/env bash
# grade.sh - programmatic grader for task_auto_check behavioral evals.
# shellcheck disable=SC2329
#
# Usage:
#   grade.sh <eval_id> <sandbox_proj>
#
# The grader checks filesystem-verifiable behavior. Transcript-level
# expectations remain as agent-attest notes in grading.txt.

set -uo pipefail

eval_id="${1:?eval id required}"
proj="${2:?sandbox proj path required}"

if [[ ! -d "$proj" ]]; then
  echo "FAIL: $proj is not a directory" >&2
  exit 1
fi

target="$(cd "$proj/.." && pwd)"
marker="$target/.eval_started_at"
if [[ ! -s "$marker" ]]; then
  echo "FAIL: $marker missing or empty (did stage.sh run?)" >&2
  exit 1
fi

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../../.." && pwd)"
LINT="$REPO_ROOT/plugins/ai_dev/skills/task/scripts/lint.py"
TASKS="$proj/tasks"

# Worker transcript written by run.py next to the sandbox; absent when the
# eval is staged operator-driven. Transcript checks run only when present.
RESPONSE="$target/../response.txt"

pass=0
fail=0
failures=()

check() {
  local label="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    pass=$((pass + 1))
    printf '  PASS  %s\n' "$label"
  else
    fail=$((fail + 1))
    printf '  FAIL  %s\n' "$label"
    failures+=("$label")
  fi
}

note_agent_attest() {
  printf '  -     agent-attest  %s\n' "$1"
}

fm_field() {
  sed -n '/^---$/,/^---$/p' "$1" | grep -m1 "^$2:" \
    | sed "s/^$2:[[:space:]]*//; s/^[\"']//; s/[\"']$//"
}

body_text() {
  awk 'BEGIN {front=0; seen=0}
       /^---$/ && seen == 0 {front=1; seen=1; next}
       /^---$/ && front == 1 {front=0; next}
       front == 0 {print}' "$1"
}

task_lints() {
  python3 "$LINT" "$TASKS" >/dev/null 2>&1
}

no_real_repo_writes() {
  # A sandbox escape writes the fixture-namespace task names the worker knows
  # (api_*.md, or the overturn snapshot's name) into the real tree. Scoping
  # the detector to those names keeps it meaningful while immunizing it
  # against the documented false positive: a concurrent session editing
  # unrelated real tasks while an eval runs.
  local hits
  hits="$(find "$REPO_ROOT/tasks" -type f \
    \( -name 'api_*.md' -o -name 'wiki_base-skill-output-contract.md' \) \
    -newer "$marker" 2>/dev/null)"
  [[ -z "$hits" ]]
}

task_count_is() {
  local want="$1" count
  count="$(find "$TASKS" -maxdepth 1 -type f -name '*.md' | wc -l | tr -d ' ')"
  [[ "$count" == "$want" ]]
}

status_is() {
  local file="$1" want="$2"
  [[ "$(fm_field "$file" status)" == "$want" ]]
}

status_is_one_of() {
  local file="$1"
  shift
  local actual want
  actual="$(fm_field "$file" status)"
  for want in "$@"; do
    [[ "$actual" == "$want" ]] && return 0
  done
  return 1
}

check "isolation: no writes to the real repo's tasks/ tree" no_real_repo_writes

case "$eval_id" in
  mechanical_lint_ready)
    f="$TASKS/api_lint-ready.md"
    # ready|checked: the current gate reads the over-budget description as a
    # gate-visible finding and may stamp checked; finalization still fixes it
    # and task_check stays the only status writer (same pattern as the link
    # and frontmatter siblings).
    status_ready() { status_is_one_of "$f" ready checked; }
    description_within_budget() {
      local desc
      desc="$(fm_field "$f" description)"
      [[ "${#desc}" -le 200 ]]
    }
    description_scope_preserved() {
      # Case-insensitive on the scope tokens: a rewrite that names the api
      # docs target, Retry-After, and throttling preserves the scope whatever
      # its casing — demanding a literal uppercase token false-fails a valid
      # rewrite (runbook grader rule).
      local desc
      desc="$(fm_field "$f" description | tr '[:upper:]' '[:lower:]')"
      [[ "$desc" == *api* && "$desc" == *retry-after* && "$desc" == *throttling* ]]
    }
    stale_description_gone() {
      ! grep -q 'overly elaborated explanatory sentence that should disappear' "$f"
    }
    body_preserved() {
      git -C "$proj" show HEAD:tasks/api_lint-ready.md >"$target/.before.md" \
        && body_text "$target/.before.md" >"$target/.before.body" \
        && body_text "$f" >"$target/.after.body" \
        && cmp -s "$target/.before.body" "$target/.after.body"
    }
    updated_changed() { [[ "$(fm_field "$f" updated)" != "2026-01-01T00:00:00" ]]; }
    check "task remains status: ready" status_ready
    check "description is within linter budget" description_within_budget
    check "description preserves API Retry-After throttling scope" description_scope_preserved
    check "stale overlong description wording is gone" stale_description_gone
    check "task body is unchanged by mechanical lint cleanup" body_preserved
    check "updated timestamp changes for the mechanical edit" updated_changed
    check "task lints clean after mechanical finalization" task_lints
    note_agent_attest "response reports one gate call, zero body edit rounds, and one mechanical-lint edit group"
    note_agent_attest "response names the base task linter and reports no remaining target-file lint findings"
    note_agent_attest "response points to task_implement as the next step"
    ;;

  mechanical_lint_link)
    f="$TASKS/api_pagination-ready.md"
    status_ready() { status_is_one_of "$f" ready checked; }
    link_repointed() { grep -Fq '(api_cursor-contract.md)' "$f"; }
    broken_target_gone() { ! grep -Fq '(api_cursor.md)' "$f"; }
    updated_changed() { [[ "$(fm_field "$f" updated)" != "2026-01-01T00:00:00" ]]; }
    check "status stays ready/checked (gate verdict only)" status_ready
    check "broken link is re-pointed to api_cursor-contract.md" link_repointed
    check "missing api_cursor.md target is no longer referenced" broken_target_gone
    check "updated timestamp changes for the mechanical edit" updated_changed
    check "tasks tree lints clean after mechanical finalization" task_lints
    note_agent_attest "response reports one gate call, zero body edit rounds, and one mechanical-lint edit group"
    note_agent_attest "response names the base task linter and reports no remaining target-file lint findings"
    note_agent_attest "response points to task_implement as the next step"
    ;;

  mechanical_lint_frontmatter)
    f="$TASKS/api_timeout-ready.md"
    status_ready() { status_is_one_of "$f" ready checked; }
    created_iso() {
      local c
      c="$(fm_field "$f" created)"
      [[ "$c" != *"/"* && "$c" == 2026-01-01* ]]
    }
    # Goal preservation instead of byte-identity: the max-strictness gate may
    # draw a small verified body refinement on any run, and that is the
    # ordinary repair path working, not the mechanical path rewriting the
    # body. What must hold: the 504 timeout objective survives and the
    # documented edit surfaces stay named (same pattern as the repair-class
    # evals).
    goal_preserved() { grep -q '504' "$f" && grep -qE 'docs/api\.md|src/api/timeout\.py' "$f"; }
    updated_changed() { [[ "$(fm_field "$f" updated)" != "2026-01-01T00:00:00" ]]; }
    check "status stays ready/checked (gate verdict only, no other change)" status_ready
    check "created is normalised to ISO 8601 (2026-01-01)" created_iso
    check "504 timeout objective and edit surfaces are preserved" goal_preserved
    check "updated timestamp changes for the mechanical edit" updated_changed
    check "tasks tree lints clean after mechanical finalization" task_lints
    note_agent_attest "response reports one gate call, zero body edit rounds, and one mechanical-lint edit group"
    note_agent_attest "response names the base task linter and reports no remaining target-file lint findings"
    note_agent_attest "response points to task_implement as the next step"
    ;;

  mechanical_lint_markdown)
    f="$TASKS/api_errors-ready.md"
    # ready|checked: the current gate may hold body findings beyond the
    # wikilink (it doubles as a gate-visible finding); finalization still
    # converts the wikilink and task_check stays the only status writer.
    status_ready() { status_is_one_of "$f" ready checked; }
    no_wikilink() { ! grep -Fq '[[' "$f"; }
    link_converted() { grep -Fq '(api_error-codes.md)' "$f"; }
    updated_changed() { [[ "$(fm_field "$f" updated)" != "2026-01-01T00:00:00" ]]; }
    check "task remains status: ready" status_ready
    check "wikilink syntax is removed from the body" no_wikilink
    check "wikilink is converted to a standard link to api_error-codes.md" link_converted
    check "updated timestamp changes for the mechanical edit" updated_changed
    check "tasks tree lints clean after mechanical finalization" task_lints
    note_agent_attest "response reports one gate call, zero body edit rounds, and one mechanical-lint edit group"
    note_agent_attest "response names the base task linter and reports no remaining target-file lint findings"
    note_agent_attest "response points to task_implement as the next step"
    ;;

  mechanical_lint_oversized_surface)
    f="$TASKS/api_audit-log-ready.md"
    one_task() { task_count_is 1; }
    no_archive_task() { [[ -z "$(find "$TASKS/archive" -type f -name '*.md' 2>/dev/null)" ]]; }
    status_kept() { status_is_one_of "$f" ready checked; }
    enumeration_intact() { [[ "$(grep -c -- '^- field_' "$f")" == "320" ]]; }
    still_oversized() { [[ "$(wc -l < "$f" | tr -d ' ')" -gt 300 ]]; }
    check "no new task file is created" one_task
    check "no split file is archived or moved" no_archive_task
    check "status stays ready/checked (gate stamp only)" status_kept
    check "all 320 field bullets remain (not gutted or collapsed into a pointer)" enumeration_intact
    check "task remains oversized and surfaced rather than auto-fixed" still_oversized
    note_agent_attest "response surfaces the oversize as a split needing human or auto_shaper_task routing"
    note_agent_attest "response does not auto-split or truncate the task and reports zero mechanical-lint edit groups for this file"
    ;;

  already_ready)
    f="$TASKS/api_ready-task.md"
    status_ready() { status_is "$f" ready; }
    one_task() { task_count_is 1; }
    body_preserved() {
      git -C "$proj" show HEAD:tasks/api_ready-task.md >"$target/.before.md" \
        && body_text "$target/.before.md" >"$target/.before.body" \
        && body_text "$f" >"$target/.after.body" \
        && cmp -s "$target/.before.body" "$target/.after.body"
    }
    check "task remains status: ready" status_ready
    check "no extra task files created" one_task
    check "task body is unchanged (zero repair edits)" body_preserved
    check "task lints clean" task_lints
    note_agent_attest "response reports one gate call and zero edit rounds"
    note_agent_attest "response names task_check as the gate and defines no second readiness criterion"
    note_agent_attest "response points to task_implement as the next step"
    ;;

  intent_drift_human_route)
    f="$TASKS/api_search-pagination.md"
    status_open() { status_is "$f" open; }
    one_task() { task_count_is 1; }
    no_archive_task() { [[ -z "$(find "$TASKS/archive" -type f -name '*.md' 2>/dev/null)" ]]; }
    current_body_preserved() {
      grep -Fq 'Document the public API search filter syntax' "$f" \
        && grep -Fq 'Document the supported filter operators' "$f"
    }
    origin_not_restored() { ! grep -Fq 'Add cursor pagination to the public API search endpoint' "$f"; }
    updated_unchanged() { [[ "$(fm_field "$f" updated)" == "2026-01-02T00:00:00" ]]; }
    check "task remains status: open because task_check is not run" status_open
    check "no extra task files created" one_task
    check "no task file is archived or moved" no_archive_task
    check "current filter-documentation body is unchanged" current_body_preserved
    check "committed cursor-pagination Goal is not restored" origin_not_restored
    check "updated timestamp remains unchanged because no edit was applied" updated_unchanged
    check "task lints clean after drift route" task_lints
    note_agent_attest "response invokes auto_drift_task exactly once at freeze time before any task_check gate call"
    note_agent_attest "response surfaces the human intention check about prior Goal drift"
    note_agent_attest "response includes recovered cursor-pagination intent and current filter-documentation intent"
    note_agent_attest "response reports zero gate calls, zero body edit rounds, and zero mechanical-lint edit groups"
    ;;

  repair_to_ready)
    f="$TASKS/api_retry-after.md"
    status_ready() { status_is "$f" ready; }
    goal_preserved() { grep -q 'Retry-After' "$f"; }
    approach_filled() { ! grep -q 'TBD' "$f"; }
    acceptance_flippable() { ! grep -qi 'works properly' "$f" && grep -qiE '429|Retry-After|docs/api\.md|src/api/throttle\.py' "$f"; }
    check "task reaches status: ready" status_ready
    check "original Retry-After objective is preserved" goal_preserved
    check "placeholder approach is replaced" approach_filled
    check "acceptance/context becomes concrete and flippable" acceptance_flippable
    check "task lints clean after repair" task_lints
    note_agent_attest "response shows the original Goal was frozen before edits"
    note_agent_attest "first gate call uses task_check and reports checked issues"
    note_agent_attest "reviewer proposals cite base task <body> repair rules"
    note_agent_attest "verifier keeps only minimum intent-preserving fixes"
    ;;

  scope_split_stuck)
    f="$TASKS/api_combo-auth-billing.md"
    checked_or_open() { status_is_one_of "$f" checked open; }
    one_task() { task_count_is 1; }
    no_archive_task() { [[ -z "$(find "$TASKS/archive" -type f -name '*.md' 2>/dev/null)" ]]; }
    original_scope_kept() { grep -q 'API authentication errors and redesign billing CSV exports' "$f"; }
    check "task remains open/checked rather than ready" checked_or_open
    check "no new task file is created" one_task
    check "no split file is archived or moved" no_archive_task
    check "combined original scope remains in the source task" original_scope_kept
    check "task lints clean" task_lints
    note_agent_attest "response surfaces a split proposal as human-routed or task_auto_shaper-routed"
    note_agent_attest "response does not auto-perform a file-creating split"
    ;;

  fidelity_rejects_drift)
    f="$TASKS/api_rate-limit.md"
    per_user_goal() { grep -q 'each authenticated user' "$f"; }
    no_broad_acceptance() { ! sed -n '/^## Acceptance/,$p' "$f" | grep -qi 'abusive clients'; }
    clarified() { sed -n '/^## Acceptance/,$p' "$f" | grep -qiE 'per-user|authenticated user|100|429|rate-limit'; }
    check "original per-user Goal is preserved" per_user_goal
    check "broad abusive-client acceptance is removed or narrowed" no_broad_acceptance
    check "applied edits clarify the same rate-limit objective" clarified
    check "task lints clean after fidelity-checked edit" task_lints
    note_agent_attest "verifier report includes a frozen-intent or fidelity decision"
    note_agent_attest "broader abuse-prevention wording is rejected or narrowed before application"
    ;;

  no_verified_fix)
    f="$TASKS/api_product-decision.md"
    status_checked() { status_is "$f" checked; }
    decision_not_guessed() {
      grep -q '100 requests per minute or 1000 requests per day' "$f" \
        && ! grep -qiE 'Default without input:[[:space:]]*apply|proceed to implementation|more conservative' "$f"
    }
    human_input_route() {
      grep -qiE 'leave the task checked|request the product decision|requires.*product|product owner.*selected' "$f"
    }
    check "task remains status: checked" status_checked
    check "product quota is not guessed" decision_not_guessed
    check "human-input route remains in the task" human_input_route
    check "task lints clean" task_lints
    note_agent_attest "response says no verified fix remains"
    note_agent_attest "response names the human product input needed to proceed"
    ;;

  cap_override)
    f="$TASKS/api_pathological.md"
    status_checked() { status_is "$f" checked; }
    vague_goal_kept() { grep -q 'Make the API better for enterprise users' "$f"; }
    check "task remains status: checked at the cap" status_checked
    check "pathological objective is not silently rewritten" vague_goal_kept
    check "task lints clean" task_lints
    note_agent_attest "response reports max rounds 2 rather than default cap 5"
    note_agent_attest "response stops at the cap and surfaces remaining issues as stuck"
    ;;

  gate_failure_user_stop)
    f="$TASKS/api_healthcheck.md"
    status_open() { status_is "$f" open; }
    one_task() { task_count_is 1; }
    file_untouched() { git -C "$proj" diff --quiet -- tasks/api_healthcheck.md; }
    updated_unchanged() { [[ "$(fm_field "$f" updated)" == "2026-01-01T00:00:00" ]]; }
    check "task remains status: open (no gate write happened)" status_open
    check "updated timestamp is unchanged" updated_unchanged
    check "task file is byte-for-byte unchanged" file_untouched
    check "no extra task files created" one_task
    check "task lints clean" task_lints
    if [[ -s "$RESPONSE" ]]; then
      names_helper() { grep -qi 'auto_gate_task' "$RESPONSE"; }
      asks_user() { grep -qiE 'how to proceed|proceed|choose|decide|which option' "$RESPONSE"; }
      check "transcript names auto_gate_task in the helper-failure error" names_helper
      check "transcript asks the user how to proceed" asks_user
    else
      note_agent_attest "response surfaces a clear helper-failure error naming auto_gate_task and the spawn failure after the retry"
      note_agent_attest "response lists the options it sees and asks the user how to proceed"
    fi
    note_agent_attest "response computes no readiness verdict in the main context and runs no inline gate automatically"
    ;;

  drift_failure_user_stop)
    f="$TASKS/api_metrics.md"
    status_open() { status_is "$f" open; }
    one_task() { task_count_is 1; }
    file_untouched() { git -C "$proj" diff --quiet -- tasks/api_metrics.md; }
    updated_unchanged() { [[ "$(fm_field "$f" updated)" == "2026-01-01T00:00:00" ]]; }
    check "task remains status: open (task_check never ran)" status_open
    check "updated timestamp is unchanged" updated_unchanged
    check "task file is byte-for-byte unchanged" file_untouched
    check "no extra task files created" one_task
    check "task lints clean" task_lints
    if [[ -s "$RESPONSE" ]]; then
      names_helper() { grep -qi 'auto_drift_task' "$RESPONSE"; }
      asks_user() { grep -qiE 'how to proceed|proceed|choose|decide|which option' "$RESPONSE"; }
      check "transcript names auto_drift_task in the helper-failure error" names_helper
      check "transcript asks the user how to proceed" asks_user
    else
      note_agent_attest "response surfaces a clear helper-failure error naming auto_drift_task and the spawn failure after the retry"
      note_agent_attest "response lists the options it sees and asks the user how to proceed"
    fi
    note_agent_attest "response improvises no drift classification and does not silently proceed to the gate"
    ;;

  verifier_failure_user_stop)
    f="$TASKS/api_quota-headers.md"
    status_checked() { status_is "$f" checked; }
    one_task() { task_count_is 1; }
    placeholder_kept() { grep -q 'TBD' "$f"; }
    vague_acceptance_kept() { grep -qi 'work properly' "$f"; }
    body_preserved() {
      git -C "$proj" show HEAD:tasks/api_quota-headers.md >"$target/.before.md" \
        && body_text "$target/.before.md" >"$target/.before.body" \
        && body_text "$f" >"$target/.after.body" \
        && cmp -s "$target/.before.body" "$target/.after.body"
    }
    check "task remains status: checked (no bypass to ready)" status_checked
    check "unrepaired approach placeholder remains (zero edits applied)" placeholder_kept
    check "unrepaired vague acceptance remains (zero edits applied)" vague_acceptance_kept
    check "task body is byte-identical to the staged body" body_preserved
    check "no extra task files created" one_task
    check "task lints clean" task_lints
    if [[ -s "$RESPONSE" ]]; then
      names_helper() { grep -qi 'auto_verifier_task' "$RESPONSE"; }
      asks_user() { grep -qiE 'how to proceed|proceed|choose|decide|which option' "$RESPONSE"; }
      check "transcript names auto_verifier_task in the helper-failure error" names_helper
      check "transcript asks the user how to proceed" asks_user
    else
      note_agent_attest "response surfaces a clear helper-failure error naming auto_verifier_task, lists the options it sees, and asks the user how to proceed"
    fi
    note_agent_attest "response improvises no verifier verdict and applies no unverified reviewer proposal"
    ;;

  guard_rebaseline_after_gate)
    f="$TASKS/api_idempotency.md"
    status_ready() { status_is "$f" ready; }
    one_task() { task_count_is 1; }
    placeholder_replaced() { ! grep -q 'TBD' "$f"; }
    acceptance_flippable() { ! grep -qi 'works properly' "$f" && grep -qiE 'Idempotency-Key|docs/api\.md|src/api/writes\.py' "$f"; }
    check "task reaches status: ready (no false concurrent-modification stop)" status_ready
    check "approach placeholder is replaced by applied repairs" placeholder_replaced
    check "acceptance becomes concrete and flippable" acceptance_flippable
    check "no extra task files created" one_task
    check "task lints clean after repair" task_lints
    note_agent_attest "response adopts the gate's own status/updated stamp as the expected post-gate baseline"
    note_agent_attest "response does not report a concurrent-modification stop"
    ;;

  interaction_scan_surfaces)
    f="$TASKS/api_page-size-config.md"
    status_ready() { status_is "$f" ready; }
    goal_preserved() { grep -q 'page_size' "$f"; }
    body_names_found_code() { grep -qE 'MAX_PAGE_SIZE|limits\.py' "$f"; }
    # Edit-supersedes proof in Acceptance: the interaction is handled either by
    # superseding the stale cap-ignoring promise (paginate returns 500-item
    # pages — impossible under MAX_PAGE_SIZE=100) with a within-cap value, or by
    # naming the cap concept explicitly. Paired with body_names_found_code (the
    # cap is named in the body), this confirms a genuine repair, not an
    # incidental number match and not a Context-only note that leaves the stale
    # 500-item promise standing.
    acceptance_edit_supersedes() {
      local acc
      acc="$(sed -n '/^## Acceptance/,$p' "$f")"
      ! grep -qiE 'returns?( pages of)? 500 items' <<<"$acc" \
        || grep -qiE 'MAX_PAGE_SIZE|\bcap(s|ped|ping)?\b|clamp' <<<"$acc"
    }
    check "task reaches status: ready" status_ready
    check "configurable page_size Goal is preserved" goal_preserved
    check "refreshed body names the found cap (MAX_PAGE_SIZE or limits.py)" body_names_found_code
    check "Acceptance supersedes the stale cap-ignoring 500-item promise" acceptance_edit_supersedes
    check "task lints clean after repair" task_lints
    note_agent_attest "gate surfaces the cap as a readiness issue with the interacting-code-versus-change juxtaposition (limits.py MAX_PAGE_SIZE vs the task's configured default)"
    note_agent_attest "repository search reaches the unlinked src/api/limits.py through the page_size touch-point"
    note_agent_attest "the run does not require reading the decoy src/api/auth.py"
    note_agent_attest "the Interaction-scan reviewer stance cites the base Interaction scan lens and base body repair rules"
    ;;

  immediate_ready_citations_survive)
    f="$TASKS/api_retry-header.md"
    status_ready() { status_is "$f" ready; }
    one_task() { task_count_is 1; }
    body_preserved() {
      git -C "$proj" show HEAD:tasks/api_retry-header.md >"$target/.before.md" \
        && body_text "$target/.before.md" >"$target/.before.body" \
        && body_text "$f" >"$target/.after.body" \
        && cmp -s "$target/.before.body" "$target/.after.body"
    }
    check "task reaches status: ready" status_ready
    check "task body is unchanged (zero body edits)" body_preserved
    check "no extra task files created" one_task
    check "task lints clean" task_lints
    if [[ -s "$RESPONSE" ]]; then
      trigger_engaged() { grep -qiE 'refut' "$RESPONSE"; }
      citations_survived() { grep -qiE 'surviv' "$RESPONSE"; }
      check "transcript names the immediate-ready refutation pass" trigger_engaged
      check "transcript reports the citations surviving" citations_survived
    else
      note_agent_attest "response reports the immediate-ready refutation trigger firing on the first-call zero-issue ready verdict"
      note_agent_attest "response reports each citation surviving refutation"
    fi
    note_agent_attest "response reports the ready stamp standing and points to task_implement as the next step"
    note_agent_attest "response names task_check as the only readiness gate and defines no second readiness criterion"
    ;;

  immediate_ready_citations_overturn)
    f="$TASKS/wiki_base-skill-output-contract.md"
    status_valid() { status_is_one_of "$f" ready checked; }
    one_task() { task_count_is 1; }
    no_archive_task() { [[ -z "$(find "$TASKS/archive" -type f -name '*.md' 2>/dev/null)" ]]; }
    # A ready outcome is legitimate only when the transcript shows the
    # approval was tested: either the refutation surface was engaged (trigger
    # fired, citations judged — "refuted"/"survived") or the trigger was
    # evaluated and correctly did not fire because the first call surfaced
    # issues ("signature did not hold") and repair rounds preceded the ready.
    # A ready whose transcript never mentions the refutation surface or the
    # signature evaluation is the unchallenged false approval this eval
    # exists to catch. Substance over form: match the evaluation's words,
    # not one keyword — a compliant repair-path report says "signature did
    # not hold" and never needs "refut". The per-run classification
    # (first-call zero-issue? citations refuted?) is the operator-recorded
    # measurement in results/.
    ready_route_challenged() {
      [[ "$(fm_field "$f" status)" != "ready" ]] && return 0
      [[ -s "$RESPONSE" ]] || return 0
      grep -qiE 'refut|surviv|signature' "$RESPONSE"
    }
    check "status is ready or checked, written only by task_check" status_valid
    check "no extra task files created" one_task
    check "no task file is archived or moved" no_archive_task
    check "a ready outcome shows the refutation surface was engaged" ready_route_challenged
    check "task lints clean" task_lints
    note_agent_attest "operator records per run: first-call zero-issue verdict occurred?, citations refuted?, reached ready? — into tests/task_auto_check/results/"
    note_agent_attest "blocking defect: ready reached from a first-call zero-issue verdict whose citations were never challenged"
    ;;

  interaction_scan_no_false_alarm)
    f="$TASKS/api_request-id.md"
    status_ready() { status_is "$f" ready; }
    one_task() { task_count_is 1; }
    body_preserved() {
      git -C "$proj" show HEAD:tasks/api_request-id.md >"$target/.before.md" \
        && body_text "$target/.before.md" >"$target/.before.body" \
        && body_text "$f" >"$target/.after.body" \
        && cmp -s "$target/.before.body" "$target/.after.body"
    }
    check "task remains status: ready" status_ready
    check "no interaction-driven body edit is applied (body unchanged)" body_preserved
    check "no extra task files created" one_task
    check "task lints clean" task_lints
    note_agent_attest "the Interaction scan lens runs and raises no contradiction or unattended-interaction finding for this touch-point-disjoint task"
    note_agent_attest "response reports one gate call and no interaction-driven repair"
    ;;

  *)
    echo "unknown eval id: $eval_id" >&2
    exit 2
    ;;
esac

echo "---"
printf 'eval-%s: %s pass, %s fail\n' "$eval_id" "$pass" "$fail"
if (( fail > 0 )); then
  printf 'failed checks:\n'
  for f in "${failures[@]}"; do printf '  - %s\n' "$f"; done
  exit 1
fi
exit 0
