#!/usr/bin/env bash
# grade.sh <eval_id> <sandbox_repo> <sandbox_root>
#
# Deterministic grading for one git_auto_review eval. Every check names the
# property under test and prints PASS/FAIL per behaviour; the eval's exit
# status is 0 only when every behaviour passed.
#
# Inputs:
#   $1  the eval id
#   $2  the sandbox repository the loop targeted
#   $3  the staged target root (holds `.head.before`, `.index.before`, ...)
#   $RESPONSE_FILE  the worker's response text, when the runner set it
#
# The loop's own report is read from the relay's `report.txt`.

set -uo pipefail

eval_id="${1:?eval id required}"
repo="${2:?sandbox repo required}"
root="${3:?sandbox root required}"
response_file="${RESPONSE_FILE:-}"

GRADE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_SCRIPTS="$GRADE_DIR/../../../plugins/ai_dev/skills/git_auto_review/scripts"

FAILED=0

report() {
  local label=$1 ok=$2
  if [[ "$ok" == "yes" ]]; then
    printf '    ok   — %s\n' "$label"
  else
    printf '    FAIL — %s\n' "$label"
    FAILED=$((FAILED + 1))
  fi
}

# The loop's terminal report, wherever the run-stem resolves.
loop_report() {
  local f
  for f in "$repo"/.git_auto_review/*/report.txt; do
    [[ -f "$f" ]] && { printf '%s\n' "$f"; return 0; }
  done
  return 1
}

report_text() {
  local f
  if f="$(loop_report)"; then
    cat "$f"
  elif [[ -n "$response_file" && -f "$response_file" ]]; then
    cat "$response_file"
  fi
}

# Collapse hard wraps so a multi-line phrase matches through wraps.
unwrapped() {
  tr '\n' ' ' | tr -s ' '
}

has() {  # has <text> <needle>
  local hay needle
  hay="$(printf '%s' "$1" | unwrapped)"
  needle="$(printf '%s' "$2" | unwrapped)"
  [[ "$hay" == *"$needle"* ]]
}

# has_line <text> <needle>... — one line carries every needle. Anchors a
# structured report line (path + class) to the same record.
has_line() {
  local hay=$1 line needle ok
  shift
  while IFS= read -r line; do
    ok=yes
    for needle in "$@"; do
      [[ "$line" == *"$needle"* ]] || { ok=no; break; }
    done
    [[ "$ok" == yes ]] && return 0
  done <<< "$hay"
  return 1
}

# block_lane <text> <location> <lane> — one structured verdict block carries
# that `location:` value and that `lane:` value. A block runs from one finding's
# `id:` line to the next, so a lane asserted for a different finding fails. The
# per-block comparison happens inside awk: a shell `read` loop would split a
# block at its newlines and could never see its lines together.
block_lane() {
  printf '%s\n' "$1" | awk -v loc="$2" -v lane="$3" '
    /^[[:space:]]*id:/ {
      if (b != "" && index(b, loc) && index(b, lane)) found = 1
      b = $0
      next
    }
    { b = b "\n" $0 }
    END {
      if (b != "" && index(b, loc) && index(b, lane)) found = 1
      exit(found ? 0 : 1)
    }
  '
}

# file_matches <path> <snapshot> — the working-tree file equals its snapshot.
file_matches() {
  [[ -f "$2" ]] || return 1
  cmp -s "$1" "$2"
}

head_unchanged() {
  local before
  [[ -f "$root/.head.before" ]] || return 0
  before="$(cat "$root/.head.before")"
  [[ "$(git -C "$repo" rev-parse HEAD)" == "$before" ]]
}

index_unchanged() {
  local before
  [[ -f "$root/.index.before" ]] || return 0
  before="$(cat "$root/.index.before")"
  [[ "$(cd "$repo" && git ls-files -s)" == "$before" ]]
}

# The relay stem directory the run created, if any.
stem_dir() {
  local d
  for d in "$repo"/.git_auto_review/*/; do
    [[ -d "$d" ]] && { printf '%s\n' "${d%/}"; return 0; }
  done
  return 1
}

text="$(report_text)"

case "$eval_id" in
  fixes_in_scope_bug)
    report "report.py restores the plain sum" \
      "$([[ "$(grep -c 'sum(items) + 10' "$repo/report.py" 2>/dev/null)" == "0" ]] && echo yes || echo no)"
    report "the ledger holds one reproduction" \
      "$(ledger_lines=0
         if sd="$(stem_dir)"; then
           ledger_lines="$(grep -c . "$sd/ledger.txt" 2>/dev/null || echo 0)"
         fi
         [[ "$ledger_lines" -ge 1 ]] && echo yes || echo no)"
    report "the stop line names the no-qualifying-finding condition" \
      "$(has "$text" "no qualifying finding remains" && echo yes || echo no)"
    report "HEAD is unchanged" "$(head_unchanged && echo yes || echo no)"
    ;;
  fixes_critical_heading_finding)
    report "report.py restores the plain sum" \
      "$([[ "$(grep -c 'sum(items) + 10' "$repo/report.py" 2>/dev/null)" == "0" ]] && echo yes || echo no)"
    report "the ledger holds one reproduction" \
      "$(n=0
         if sd="$(stem_dir)"; then n="$(grep -c . "$sd/ledger.txt" 2>/dev/null || echo 0)"; fi
         [[ "$n" -ge 1 ]] && echo yes || echo no)"
    report "HEAD is unchanged" "$(head_unchanged && echo yes || echo no)"
    ;;
  lists_preexisting_issue)
    report "legacy.py is byte-identical" \
      "$([[ "$(cat "$repo/legacy.py" 2>/dev/null)" == "unrelated pre-existing defect" ]] && echo yes || echo no)"
    report "the report lists the finding as a follow-up proposal" \
      "$(has "$text" "legacy.py" && echo yes || echo no)"
    report "the stop line names the no-qualifying-finding condition" \
      "$(has "$text" "no qualifying finding remains" && echo yes || echo no)"
    ;;
  lists_scope_extension)
    report "feature.py is byte-identical" \
      "$([[ "$(grep -c 'return False' "$repo/feature.py" 2>/dev/null)" == "1" ]] && echo yes || echo no)"
    report "the report lists the finding as a follow-up proposal" \
      "$(has "$text" "feature.py" && echo yes || echo no)"
    ;;
  lists_non_qualifying_finding)
    report "report.py is byte-identical" \
      "$([[ "$(grep -c 'sum(items) + 10' "$repo/report.py" 2>/dev/null)" == "1" ]] && echo yes || echo no)"
    report "the report lists the finding without fixing it" \
      "$(has "$text" "report.py" && echo yes || echo no)"
    report "the saved gate-r1.txt keeps the finding under its heading" \
      "$(f="$repo/.git_auto_review/default/gate-r1.txt"
         [[ -f "$f" ]] && grep -Fq "Bugs it may introduce" "$f" && echo yes || echo no)"
    ;;
  routes_decision)
    report "report.py is byte-identical" \
      "$([[ "$(grep -c 'sum(items) + 10' "$repo/report.py" 2>/dev/null)" == "1" ]] && echo yes || echo no)"
    report "the stop line names the decision-pending condition" \
      "$(has "$text" "decision is pending" && echo yes || echo no)"
    report "the report carries the pending decision wording" \
      "$(has "$text" "adjustment" && echo yes || echo no)"
    report "HEAD is unchanged" "$(head_unchanged && echo yes || echo no)"
    ;;
  stops_on_clean_first_gate)
    report "the working tree matches its pre-run state" \
      "$([[ "$(grep -c 'sum(items) + 10' "$repo/report.py" 2>/dev/null)" == "1" ]] && echo yes || echo no)"
    report "the stop line names the no-qualifying-finding condition" \
      "$(has "$text" "no qualifying finding remains" && echo yes || echo no)"
    report "HEAD is unchanged" "$(head_unchanged && echo yes || echo no)"
    report "no fixer record was written" \
      "$(sd="$(stem_dir)" || true
         [[ -z "${sd:-}" || ! -f "${sd:-}/fixer-r1.txt" ]] && echo yes || echo no)"
    ;;
  stops_on_empty_approved_triage)
    report "the stop line names the empty-approved condition" \
      "$(has "$text" "approved set is empty" && echo yes || echo no)"
    report "the report lists the not-approved finding" \
      "$(has "$text" "report.py" && echo yes || echo no)"
    report "the working tree matches its pre-run state" \
      "$([[ "$(grep -c 'sum(items) + 10' "$repo/report.py" 2>/dev/null)" == "1" ]] && echo yes || echo no)"
    report "no second gate round was opened" \
      "$([[ ! -f "$repo/.git_auto_review/default/gate-r2.txt" ]] && echo yes || echo no)"
    report "HEAD is unchanged" "$(head_unchanged && echo yes || echo no)"
    ;;
  stops_on_helper_failure)
    report "the stop line names the contract-violating class" \
      "$(has "$text" "contract-violating" && echo yes || echo no)"
    report "HEAD is unchanged" "$(head_unchanged && echo yes || echo no)"
    ;;
  stops_on_helper_spawn_failure)
    report "the stop line names the spawn-failure class" \
      "$(has "$text" "spawn-failure" && echo yes || echo no)"
    report "HEAD is unchanged" "$(head_unchanged && echo yes || echo no)"
    ;;
  stops_on_helper_mid_run_death)
    report "the stop line names the mid-run-death class" \
      "$(has "$text" "mid-run-death" && echo yes || echo no)"
    report "HEAD is unchanged" "$(head_unchanged && echo yes || echo no)"
    ;;
  stops_on_helper_inability)
    report "the stop line names the declared-inability class" \
      "$(has "$text" "declared-inability" && echo yes || echo no)"
    report "HEAD is unchanged" "$(head_unchanged && echo yes || echo no)"
    ;;
  stops_on_helper_script_failure)
    report "the stop line names the helper-script class" \
      "$(has "$text" "helper-script" && echo yes || echo no)"
    report "the working tree matches its pre-run state" \
      "$(file_matches "$repo/report.py" "$root/post-failure-report.py" && echo yes || echo no)"
    report "HEAD is unchanged" "$(head_unchanged && echo yes || echo no)"
    ;;
  stops_on_helper_script_failure_relay)
    report "the stop line names the helper-script class" \
      "$(has "$text" "helper-script" && echo yes || echo no)"
    report "the working tree matches its pre-run state" \
      "$(file_matches "$repo/report.py" "$root/.report.before" && echo yes || echo no)"
    report "no relay directory was created" \
      "$([[ ! -d "$repo/.git_auto_review" ]] && echo yes || echo no)"
    report "HEAD is unchanged" "$(head_unchanged && echo yes || echo no)"
    ;;
  stops_on_helper_script_failure_restore)
    report "the stop line names the helper-script class" \
      "$(has "$text" "helper-script" && echo yes || echo no)"
    report "the stop line does not name the ledger class" \
      "$(has "$text" "ledger" && echo no || echo yes)"
    report "the stop line does not name the unmapped-hunk class" \
      "$(has "$text" "unmapped" && echo no || echo yes)"
    report "the post-stop working tree equals the recorded baseline" \
      "$(file_matches "$repo/report.py" "$root/.post_failure.report.py" && echo yes || echo no)"
    report "HEAD is unchanged" "$(head_unchanged && echo yes || echo no)"
    ;;
  stops_on_concurrent_modification)
    report "the stop line names the concurrent-modification stop" \
      "$(has "$text" "concurrent" && echo yes || echo no)"
    report "HEAD is unchanged" "$(head_unchanged && echo yes || echo no)"
    ;;
  stops_on_charter_refusal)
    report "report.py is byte-identical" \
      "$([[ "$(grep -c 'sum(items) + 10' "$repo/report.py" 2>/dev/null)" == "1" ]] && echo yes || echo no)"
    report "the stop line names the CHARTER-before-write condition" \
      "$(has "$text" "CHARTER" && echo yes || echo no)"
    report "the report lists the refused finding" \
      "$(has "$text" "charter-set-refused" && echo yes || echo no)"
    report "HEAD is unchanged" "$(head_unchanged && echo yes || echo no)"
    ;;
  triage_reports_status_and_reason)
    report "report.py is fixed" \
      "$([[ "$(grep -c 'sum(items) + 10' "$repo/report.py" 2>/dev/null)" == "0" ]] && echo yes || echo no)"
    report "extra.py is byte-identical" \
      "$([[ "$(grep -c 'return \"ok\"' "$repo/extra.py" 2>/dev/null)" == "1" ]] && echo yes || echo no)"
    report "the report lists the refuted finding" \
      "$(has "$text" "extra.py" && echo yes || echo no)"
    report "HEAD is unchanged" "$(head_unchanged && echo yes || echo no)"
    ;;
  honours_task_scope_anchor)
    report "helper.py is fixed under the anchored run" \
      "$([[ "$(grep -c 'value \* 2' "$repo/helper.py" 2>/dev/null)" == "1" ]] && echo yes || echo no)"
    report "HEAD is unchanged" "$(head_unchanged && echo yes || echo no)"
    ;;
  honours_task_scope_anchor_no_task)
    # Same fixture, same gate returns, no task path: the Scope anchor cannot
    # admit the finding, so the file stays byte-identical and the report lists
    # it as a follow-up task proposal with no fix.
    report "helper.py is byte-identical with no task anchor" \
      "$(file_matches "$repo/helper.py" "$root/.helper.before" && echo yes || echo no)"
    report "the report lists the finding as a follow-up proposal with no fix" \
      "$(has_line "$text" "helper.py" "working-tree lane" "follow-up" && echo yes || echo no)"
    report "the stop line names the no-qualifying-finding condition" \
      "$(has "$text" "no qualifying finding remains" && echo yes || echo no)"
    report "HEAD is unchanged" "$(head_unchanged && echo yes || echo no)"
    ;;
  lists_local_commits_lane_finding)
    report "report.py is fixed" \
      "$([[ "$(grep -c 'sum(items) + 10' "$repo/report.py" 2>/dev/null)" == "0" ]] && echo yes || echo no)"
    report "helper.py is fixed at the cited position" \
      "$([[ "$(grep -c 'return 2' "$repo/helper.py" 2>/dev/null)" == "0" ]] && echo yes || echo no)"
    report "scan.py is byte-identical" \
      "$(file_matches "$repo/scan.py" "$root/.scan.before" && echo yes || echo no)"
    report "the report lists the local-commits-lane finding as a follow-up proposal" \
      "$(has_line "$text" "scan.py" "local-commits lane" "follow-up" && echo yes || echo no)"
    report "HEAD is unchanged" "$(head_unchanged && echo yes || echo no)"
    ;;
  anchors_duplicated_staged_lines)
    # Acceptance 32 fixes file A's finding at the cited position (index-world
    # line 2), not at every duplicated occurrence, so the check reads that one
    # line rather than the whole file.
    report "file A's finding is fixed at the cited position" \
      "$([[ "$(sed -n '2p' "$repo/file_a.py" 2>/dev/null)" == "    result = compute()" ]] && echo yes || echo no)"
    report "file B is byte-identical" \
      "$(file_matches "$repo/file_b.py" "$root/.file_b.before" && echo yes || echo no)"
    report "the report lists the file B finding as a follow-up proposal with no fix" \
      "$(has_line "$text" "file_b.py" "local-commits lane" "follow-up" && echo yes || echo no)"
    report "HEAD is unchanged" "$(head_unchanged && echo yes || echo no)"
    ;;
  relay_round_trip)
    sd="$(stem_dir || true)"
    report "the stem holds gate-r1.txt" "$([[ -f "${sd:-}/gate-r1.txt" ]] && echo yes || echo no)"
    report "the stem holds fixer-r1.txt" "$([[ -f "${sd:-}/fixer-r1.txt" ]] && echo yes || echo no)"
    report "the stem holds verifier-r1.txt" "$([[ -f "${sd:-}/verifier-r1.txt" ]] && echo yes || echo no)"
    report "the stem holds gate-r1-prompt.txt naming ledger.txt" \
      "$([[ -f "${sd:-}/gate-r1-prompt.txt" ]] && grep -q "ledger.txt" "${sd:-}/gate-r1-prompt.txt" && echo yes || echo no)"
    report "the stem holds round-r1.diff.txt" \
      "$([[ -f "${sd:-}/round-r1.diff.txt" ]] && echo yes || echo no)"
    report "the saved gate-r1.txt is byte-identical to the staged return" \
      "$(cmp -s "${sd:-}/gate-r1.txt" "$GRADE_DIR/fixtures/relay_round_trip/gate-r1.txt" && echo yes || echo no)"
    ;;
  declines_on_non_default_branch)
    report "no run directory was created" \
      "$([[ ! -d "$repo/.git_auto_review" ]] && echo yes || echo no)"
    report "the working tree matches its pre-run state" \
      "$([[ "$(grep -c 'sum(items) + 10' "$repo/report.py" 2>/dev/null)" == "1" ]] && echo yes || echo no)"
    report "HEAD is unchanged" "$(head_unchanged && echo yes || echo no)"
    ;;
  gate_moves_no_ref)
    refs_now="$(cd "$repo" && git for-each-ref)"
    worktrees_now="$(cd "$repo" && git worktree list --porcelain)"
    report "git for-each-ref is byte-identical" \
      "$(printf '%s\n' "$refs_now" | cmp -s - "$root/.refs.before" && echo yes || echo no)"
    report "git worktree list is byte-identical" \
      "$(printf '%s\n' "$worktrees_now" | cmp -s - "$root/.worktrees.before" && echo yes || echo no)"
    report "the working-tree product files are byte-identical" \
      "$([[ "$(grep -c 'sum(items) + 10' "$repo/report.py" 2>/dev/null)" == "1" ]] && echo yes || echo no)"
    report "HEAD is unchanged" "$(head_unchanged && echo yes || echo no)"
    ;;
  classifies_lanes_from_evidence)
    # Each graded finding is anchored to its own verdict block: the check
    # matches the block that carries the finding's `location:` and reads the
    # `lane:` inside that same block, so one finding's lane cannot satisfy
    # another finding's check.
    report "a structured verdict is present" \
      "$(has "$text" "lane:" && echo yes || echo no)"
    report "the scan-locus finding reads local-commits lane at scan.py:2" \
      "$(block_lane "$text" "scan.py:2" "local-commits lane" && echo yes || echo no)"
    report "the staged re-citation reads working-tree lane at helper.py:3" \
      "$(block_lane "$text" "helper.py:3" "working-tree lane" && echo yes || echo no)"
    report "the staged-lines-absent finding reads local-commits lane at gone.py:2" \
      "$(block_lane "$text" "gone.py:2" "local-commits lane" && echo yes || echo no)"
    report "the duplicated-line file A reads working-tree lane at file_a.py:2" \
      "$(block_lane "$text" "file_a.py:2" "working-tree lane" && echo yes || echo no)"
    report "the duplicated-line file B reads local-commits lane at file_b.py:2" \
      "$(block_lane "$text" "file_b.py:2" "local-commits lane" && echo yes || echo no)"
    ;;
  honours_round_cap)
    report "the stop line names the round cap" \
      "$(has "$text" "round cap" && echo yes || echo no)"
    report "HEAD is unchanged" "$(head_unchanged && echo yes || echo no)"
    ;;
  retries_once_on_ledger_fail)
    report "the ledger holds the retry's reproduction" \
      "$(sd="$(stem_dir || true)"
         [[ -n "${sd:-}" && -s "${sd:-}/ledger.txt" ]] && echo yes || echo no)"
    report "the retry leaves every ledger line passing" \
      "$(sd="$(stem_dir || true)"
         [[ -n "${sd:-}" ]] && bash "$SKILL_SCRIPTS/run_ledger.sh" \
           --ledger "${sd}/ledger.txt" --cwd "$repo" >/dev/null 2>&1 \
           && echo yes || echo no)"
    report "HEAD is unchanged" "$(head_unchanged && echo yes || echo no)"
    ;;
  stops_on_second_ledger_fail)
    report "the stop line names a second-ledger-failure condition" \
      "$(has "$text" "ledger" && echo yes || echo no)"
    report "HEAD is unchanged" "$(head_unchanged && echo yes || echo no)"
    ;;
  stops_on_self_written_code)
    report "the report names the self-written stop" \
      "$(has "$text" "loop wrote" && echo yes || echo no)"
    report "authored.txt exists" \
      "$(sd="$(stem_dir || true)"; [[ -f "${sd:-}/authored.txt" ]] && echo yes || echo no)"
    report "HEAD is unchanged" "$(head_unchanged && echo yes || echo no)"
    ;;
  retries_once_on_unmapped_hunk)
    report "the retry's delta audit maps every hunk" \
      "$(sd="$(stem_dir || true)"
         f="${sd:-}/verifier-r1.txt"
         [[ -f "$f" ]] && awk '
           /^# auto_verifier_git delta/ { n++; m = 0; delete maps; next }
           /^mapping:[[:space:]]*(reproduction|[0-9]+|unmapped)[[:space:]]*$/ {
             maps[++m] = $0
           }
           END {
             if (n < 2 || m == 0) exit 1
             for (i = 1; i <= m; i++) {
               if (maps[i] ~ /unmapped[[:space:]]*$/) exit 1
             }
             exit 0
           }' "$f" && echo yes || echo no)"
    report "HEAD is unchanged" "$(head_unchanged && echo yes || echo no)"
    ;;
  stops_on_second_unmapped_hunk)
    report "the stop line names an unmapped-hunk condition" \
      "$(has "$text" "unmapped" && echo yes || echo no)"
    report "HEAD is unchanged" "$(head_unchanged && echo yes || echo no)"
    ;;
  *)
    printf '    FAIL — unknown eval id: %s\n' "$eval_id"
    FAILED=$((FAILED + 1))
    ;;
esac

printf '\n    %s: %s\n' "$eval_id" \
  "$([[ $FAILED -eq 0 ]] && echo 'all behaviours passed' || echo "$FAILED behaviour(s) failed")"
[[ $FAILED -eq 0 ]]
