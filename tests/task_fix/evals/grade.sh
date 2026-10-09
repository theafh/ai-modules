#!/usr/bin/env bash
# grade.sh - programmatic grader for the task_fix repeated-link evals.
#
# Usage:
#   grade.sh <eval_id> <sandbox_proj>
#
# Two graded surfaces, because the base `<lint>` repeated-link react protocol
# obliges both. The task file's bytes are read from the sandbox: a regroup must
# land, and a surfaced finding must leave the file exactly as staged.
# The per-finding disposition line exists only in the run's report, read from
# $RESPONSE_FILE when the runner exports it and otherwise from the conventional
# `<sandbox_proj>/../../response.txt` that run.py's workspace layout puts it at.
# A report check with no readable response FAILS rather than passing vacuously.
#
# Judgements that stay prose - whether the gathered sentence reads well, whether
# a surfaced reason is the *right* reason - are the `expectations` in evals.json
# and the agent-attest notes below.

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
# shellcheck source=../../lib/host_tasks_guard.sh
. "$HERE/../../lib/host_tasks_guard.sh"
LINT="$REPO_ROOT/plugins/ai_dev/skills/task/scripts/lint.py"
TASKS="$proj/tasks"
RESPONSE="${RESPONSE_FILE:-$target/../response.txt}"

pass=0
fail=0
failures=()

check() {
  local label="$1"; shift
  if "$@" >/dev/null 2>&1; then
    pass=$((pass + 1)); printf '  PASS  %s\n' "$label"
  else
    fail=$((fail + 1)); printf '  FAIL  %s\n' "$label"; failures+=("$label")
  fi
}
note_agent_attest() { printf '  -     agent-attest  %s\n' "$1"; }

# --- helpers -----------------------------------------------------------------

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

# byte_identical <repo-relative task path> -> the file is exactly as staged.
# The staged tree is one commit, so HEAD is the fixture's own bytes.
byte_identical() {
  local rel="$1"
  git -C "$proj" show "HEAD:$rel" >"$target/.staged.md" 2>/dev/null \
    && cmp -s "$target/.staged.md" "$proj/$rel"
}

tree_lints() { python3 "$LINT" "$TASKS" --include-archive >/dev/null 2>&1; }

# no_repeated_link_finding <abs task file> -> the file carries no repeated-link
# warn. The protocol makes the gathered material, not the surviving link count,
# the measure of a resolved finding; in these fixtures everything the repeated
# links carry belongs in one passage, so a genuine reorganization necessarily
# clears the warn. Reading the linter's verdict keeps the check off any
# sentence the regroup happened to write.
no_repeated_link_finding() {
  ! python3 "$LINT" "$TASKS" --file "$1" 2>/dev/null | grep -q 'repeated-link'
}

# sections_naming <file> <needle> -> how many H2 sections name the needle, so
# "the account sits in one place" is checked as a section count rather than as
# a match on prose the run chose.
sections_naming() {
  body_text "$1" | awk -v n="$2" '
    /^## / { sec=$0 }
    index($0, n) > 0 && sec != "" { seen[sec]=1 }
    END { c=0; for (k in seen) c++; print c }'
}

# section_body <file> <heading> -> one H2 section's text, unwrapped.
section_body() {
  body_text "$1" | awk -v h="$2" '
    $0 == h { f=1; next }
    /^## / { f=0 }
    f { print }' | tr '\n' ' ' | tr -s ' '
}

# section_holding <file> <needle> -> the H2 heading of the first section whose
# text contains the needle, so a check can follow a link to wherever the run
# placed it instead of assuming one section.
section_holding() {
  body_text "$1" | awk -v n="$2" '
    /^## / { sec=$0; next }
    index($0, n) > 0 && sec != "" { print sec; exit }'
}

# sections_matching <file> <ERE> -> the H2 headings whose text matches the ERE,
# one per line. Single-token patterns only, since lines are read as wrapped.
sections_matching() {
  body_text "$1" | awk -v re="$2" '
    /^## / { sec=$0; next }
    sec != "" && $0 ~ re { seen[sec]=1 }
    END { for (k in seen) print k }'
}

response_readable() { [[ -s "$RESPONSE" ]]; }
response_has() { response_readable && grep -qiE -- "$1" "$RESPONSE"; }

# disposition_blocks -> one line per `repeated-link:` lead-in, with that line's
# own wrapping collapsed. A report hard-wraps a disposition line across several
# physical lines, often inside a fenced block, so a line-based grep misses a
# perfectly well-formed line. Splitting on the lead-in keeps one finding's
# fields from bleeding into the next finding's, and the 400-character cap stops
# the last block from swallowing whatever prose follows it.
disposition_blocks() {
  response_readable || return 1
  tr '\n' ' ' < "$RESPONSE" | tr -s ' ' \
    | sed 's/repeated-link:/\n&/g' \
    | awk 'NR>1 { print substr($0, 1, 400) }'
}

# disposition_line <needle-for-the-target> <disposition> -> the report carries
# one shared-shape line naming this target with this disposition. Anchored on
# the `repeated-link:` lead-in the base block fixes, so a passing report is one
# that used the shape rather than one that merely mentioned the words.
disposition_line() {
  disposition_blocks | grep -qiE -- "repeated-link:.*$1.*$2"
}

# disposition_of <needle-for-the-target> -> the disposition that finding's line
# reports, read as the first disposition word on it. The shape puts the
# disposition after the file, target, and sections, none of which carry one of
# those words, so the first match is the field itself and a surfaced reason
# that happens to say "kept" later on cannot be mistaken for a kept line.
disposition_of() {
  disposition_blocks | grep -iE -- "repeated-link:.*$1" | head -1 \
    | grep -oiE 'regrouped|surfaced|kept' | head -1 | tr '[:upper:]' '[:lower:]'
}

no_real_repo_writes() {
  # Fixture names from this sandbox, compared with the isolated copy taken at
  # stage. A concurrent session editing some other real task stays outside
  # the comparison. A host tasks/api_*.md file newer than the marker still fails
  # when that name is one this sandbox staged.
  host_fixture_writes_clean "$target" "$REPO_ROOT" "$TASKS" "$marker"
}

# --- universal ---------------------------------------------------------------

# no_real_tasks_moved -> fixture-named paths and bytes still match the isolated
# copy taken at stage. A parallel session that moves some other real task
# changes the live tree and leaves this check green.
no_real_tasks_moved() {
  host_fixture_copy_clean "$target" "$REPO_ROOT" "$TASKS"
}

check "isolation: no writes to the real repo's tasks/ tree" no_real_repo_writes
check "isolation: the real repo's tasks/ tree is unmoved" no_real_tasks_moved
check "tasks tree lints clean, archive included"            tree_lints

# --- per-eval ----------------------------------------------------------------

case "$eval_id" in
  regroup_live_skip_archived)
    live="$TASKS/api_export-gzip.md"
    warn_cleared() { no_repeated_link_finding "$live"; }
    account_in_context_only() {
      [[ "$(sections_naming "$live" "api_export-schema")" == "1" ]] \
        && section_body "$live" "## Context" | grep -q 'api_export-schema'
    }
    goal_still_delivers() {
      section_body "$live" "## Goal" | grep -qiE 'gzip|compress'
    }
    handoff_survives() { grep -q 'api_export-schema' "$live"; }
    updated_bumped() {
      [[ "$(fm_field "$live" updated)" != "2026-01-01T00:00:00" ]]
    }
    link_target_untouched() { byte_identical "tasks/api_export-schema.md"; }
    archived_untouched() { byte_identical "tasks/archive/api_legacy-export.md"; }
    archived_pair_untouched() { byte_identical "tasks/archive/api_legacy-columns.md"; }
    live_line_regrouped() { disposition_line "api_export-gzip" "regrouped"; }
    no_archived_count_line() {
      ! disposition_blocks | grep -qiE 'repeated-link:[[:space:]]*[0-9]+[[:space:]]+findings on archived tasks'
    }
    check "the live task's repeated-link warn is cleared"        warn_cleared
    check "the gathered account sits in ## Context only"         account_in_context_only
    check "## Goal still states what the task delivers"          goal_still_delivers
    check "the handoff account survives the regroup"             handoff_survives
    check "the live task's updated stamp is bumped"              updated_bumped
    check "the live link target is byte-identical"               link_target_untouched
    check "the archived task is byte-identical"                  archived_untouched
    check "the archived link target is byte-identical"           archived_pair_untouched
    check "the report is readable"                               response_readable
    check "the report carries the live finding's line as regrouped" live_line_regrouped
    check "the report carries no archived-count line"            no_archived_count_line
    note_agent_attest "the regrouped finding is counted in the closing line's N issues resolved"
    note_agent_attest "the gathered Context sentence reads as one account rather than two stitched clauses"
    ;;

  regroup_state_and_edit_site)
    f="$TASKS/api_webhook-timestamp.md"
    link='(../docs/webhooks.md)'
    warn_cleared() { no_repeated_link_finding "$f"; }
    one_link() { [[ "$(grep -oF "$link" "$f" | wc -l | tr -d ' ')" == "1" ]]; }
    # The passage the one surviving link sits in. The run may gather into
    # Approach, which carries the edit, or into Context, which carries the
    # page's current state, so the checks follow the link rather than pick.
    linked_section() { section_holding "$f" "$link"; }
    # The page's current state is the part Context staged: what its ## Delivery
    # and ## Verification sections say today and that neither mentions replay.
    # The edit is the freshness window this task adds under ## Verification.
    state_and_edit_together() {
      local sec text
      sec="$(linked_section)"
      [[ -n "$sec" ]] || return 1
      text="$(section_body "$f" "$sec")"
      grep -q 'Verification' <<<"$text" \
        && grep -qi 'freshness' <<<"$text" \
        && grep -qE 'Delivery|re-?comput|replay' <<<"$text"
    }
    # outside_linked_and_acceptance <ERE> -> a section other than the linked
    # one and ## Acceptance matches. Acceptance keeps its own contract copy.
    outside_linked_and_acceptance() {
      local sec
      sec="$(linked_section)"
      [[ -n "$sec" ]] || return 0
      sections_matching "$f" "$1" | grep -vxF -e "$sec" -e '## Acceptance' | grep -q .
    }
    state_not_elsewhere() { ! outside_linked_and_acceptance 'Delivery|re-?comput'; }
    edit_not_elsewhere() { ! outside_linked_and_acceptance '[Ff]reshness'; }
    goal_preserved() {
      section_body "$f" "## Goal" | grep -qi 'timestamp' \
        && section_body "$f" "## Goal" | grep -qi 'replay'
    }
    acceptance_preserved() {
      local acc
      acc="$(section_body "$f" "## Acceptance")"
      grep -q 'webhooks\.py' <<<"$acc" && grep -qi 'timestamp' <<<"$acc" \
        && grep -q 'docs/webhooks\.md' <<<"$acc" && grep -qi 'freshness' <<<"$acc"
    }
    updated_bumped() {
      [[ "$(fm_field "$f" updated)" != "2026-01-01T00:00:00" ]]
    }
    page_untouched() { byte_identical "docs/webhooks.md"; }
    regrouped_line() { [[ "$(disposition_of "api_webhook-timestamp")" == "regrouped" ]]; }
    no_kept_line() {
      response_readable && [[ "$(disposition_of "api_webhook-timestamp")" != "kept" ]]
    }
    check "the repeated-link warn is cleared"                          warn_cleared
    check "the body links the reference page exactly once"             one_link
    check "the linked passage holds the page's state and its edit"     state_and_edit_together
    check "no other section restates the page's current state"         state_not_elsewhere
    check "no other section restates the edit outside Acceptance"      edit_not_elsewhere
    check "## Goal still states the timestamp header and replay"       goal_preserved
    check "## Acceptance keeps both items"                             acceptance_preserved
    check "the task's updated stamp is bumped"                         updated_bumped
    check "the reference page is byte-identical"                       page_untouched
    check "the report is readable"                                     response_readable
    check "the report's line for this finding reads regrouped"         regrouped_line
    check "no disposition line for this finding reads kept"            no_kept_line
    note_agent_attest "the regrouped finding is counted in the closing line's N issues resolved"
    note_agent_attest "the gathered passage reads as one account of the page: what it says today, then the edit"
    ;;

  surfaced_acceptance_contract)
    f="$TASKS/api_retirement-audit-log.md"
    body_unchanged() { byte_identical "tasks/api_retirement-audit-log.md"; }
    link_target_untouched() { byte_identical "tasks/api_token-rotation.md"; }
    # The escape the base protocol's link rule closes: each link moves with the
    # material it carried, so stripping link syntax from a clause whose
    # material stayed resolves nothing.
    acceptance_link_intact() {
      [[ "$(grep -c '(api_token-rotation\.md)' "$f")" == "2" ]]
    }
    surfaced_line() { disposition_line "api_retirement-audit-log" "surfaced"; }
    reason_names_acceptance() {
      disposition_blocks \
        | grep -qiE 'repeated-link:.*api_retirement-audit-log.*surfaced.*(acceptance|goal|outcome|contract|retention window)'
    }
    check "the task file is byte-identical"                        body_unchanged
    check "the link target is byte-identical"                      link_target_untouched
    check "both links stand, neither downgraded to plain text"     acceptance_link_intact
    check "the report is readable"                                 response_readable
    check "the report's line for this finding reads surfaced"      surfaced_line
    check "the surfaced reason names the contract it protects"     reason_names_acceptance
    note_agent_attest "the surfaced finding is counted in the closing line's K flagged for review"
    note_agent_attest "the reason states that gathering the account out would leave the Acceptance item nothing to measure"
    ;;

  regroup_same_paragraph)
    f="$TASKS/api_export-gzip.md"
    staged="$target/.staged_gzip.md"
    git -C "$proj" show HEAD:tasks/api_export-gzip.md >"$staged" 2>/dev/null
    warn_cleared() { no_repeated_link_finding "$f"; }
    one_link() {
      [[ "$(grep -oF '(api_export-schema.md)' "$f" | wc -l | tr -d ' ')" == "1" ]]
    }
    # The repeat sits inside one Context paragraph, so the one surviving link
    # stays there and no other section takes up the sibling.
    named_in_context_only() {
      [[ "$(sections_naming "$f" "api_export-schema")" == "1" ]] \
        && section_body "$f" "## Context" | grep -q 'api_export-schema'
    }
    # Both facts the paragraph carried survive the plain-text naming: the
    # sibling fixes the column order, and this task lands after it.
    context_keeps_both_facts() {
      local ctx
      ctx="$(section_body "$f" "## Context")"
      grep -qi 'order' <<<"$ctx" \
        && grep -qiE 'after|before|first|wait|depend|follow|land' <<<"$ctx"
    }
    # The one-paragraph case moves no material, so every other section reads
    # exactly as staged once its hard wraps are collapsed.
    section_as_staged() {
      [[ "$(section_body "$f" "$1")" == "$(section_body "$staged" "$1")" ]]
    }
    other_sections_as_staged() {
      section_as_staged "## Goal" && section_as_staged "## Approach" \
        && section_as_staged "## Acceptance"
    }
    updated_bumped() {
      [[ "$(fm_field "$f" updated)" != "2026-01-01T00:00:00" ]]
    }
    link_target_untouched() { byte_identical "tasks/api_export-schema.md"; }
    regrouped_line() { [[ "$(disposition_of "api_export-gzip")" == "regrouped" ]]; }
    # Every line the report carries for this finding reads regrouped, so a
    # second line reading kept or surfaced fails even when the first passes.
    every_line_regrouped() {
      local words
      words="$(disposition_blocks | grep -iE -- 'repeated-link:.*api_export-gzip' \
        | while IFS= read -r l; do grep -oiE 'regrouped|surfaced|kept' <<<"$l" | head -1; done \
        | tr '[:upper:]' '[:lower:]' | sort -u)"
      [[ "$words" == "regrouped" ]]
    }
    check "the repeated-link warn is cleared"                          warn_cleared
    check "the body links the sibling exactly once"                    one_link
    check "only ## Context names the sibling"                          named_in_context_only
    check "## Context keeps the column order and the landing order"    context_keeps_both_facts
    check "## Goal, ## Approach, and ## Acceptance read as staged"     other_sections_as_staged
    check "the task's updated stamp is bumped"                         updated_bumped
    check "the link target is byte-identical"                          link_target_untouched
    check "the report is readable"                                     response_readable
    check "the report's line for this finding reads regrouped"         regrouped_line
    check "no line for this finding reads kept or surfaced"            every_line_regrouped
    note_agent_attest "the regrouped finding is counted in the closing line's N issues resolved"
    note_agent_attest "the paragraph still reads as one account after the second mention lost its link syntax"
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
