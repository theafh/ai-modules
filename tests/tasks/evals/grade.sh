#!/usr/bin/env bash
# grade.sh — programmatic grader for task-family behavioral evals.
#
# Usage:
#   grade.sh <eval_id> <sandbox_proj>
#
# Runs the filesystem-verifiable subset of each eval's expectations
# against the post-run sandbox and prints PASS/FAIL per check. Exits 0
# only if every programmatic check passed.
#
# Scope: filesystem + git + suite state only. Output-verdict
# expectations (the literal headers / verdict lines each read-only skill
# must emit) cannot be checked here — they are listed under
# "agent-attest" for the operator to confirm from the transcript and are
# the LLM-graded expectations in evals.json.

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
start_epoch="$(cat "$marker")"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../../.." && pwd)"
LINT="$REPO_ROOT/plugins/ai_dev/skills/task/scripts/lint.py"
TASKS="$proj/tasks"

pass=0
fail=0
failures=()

check() {
  local label="$1"; shift
  if "$@" >/dev/null 2>&1; then
    pass=$((pass+1)); printf '  PASS  %s\n' "$label"
  else
    fail=$((fail+1)); printf '  FAIL  %s\n' "$label"; failures+=("$label")
  fi
}
note_agent_attest() { printf '  -     agent-attest  %s\n' "$1"; }

# --- helpers -----------------------------------------------------------------

# fm_field <file> <field> -> the frontmatter value, quotes stripped.
fm_field() {
  sed -n '/^---$/,/^---$/p' "$1" | grep -m1 "^$2:" \
    | sed "s/^$2:[[:space:]]*//; s/^[\"']//; s/[\"']$//"
}

# iso_epoch <iso> -> epoch seconds (BSD then GNU date form).
iso_epoch() {
  local iso="$1"
  date -j -f "%Y-%m-%dT%H:%M:%S" "$iso" +%s 2>/dev/null \
    || date -d "$iso" +%s 2>/dev/null
}

ISO_RE='^[0-9]{4}-[0-9]{2}-[0-9]{2}([T ][0-9]{2}:[0-9]{2}(:[0-9]{2})?)?$'

lint_no_blocking() { python3 "$LINT" "$TASKS" >/dev/null 2>&1; }   # exit 0 == 0 blocking
lint_archive_no_blocking() { python3 "$LINT" "$TASKS" --include-archive >/dev/null 2>&1; }
# Read-only check: the sandbox content must be unchanged. Ignore Python
# bytecode/cache artifacts (`__pycache__/`, `*.pyc`, `.pytest_cache/`) —
# a read-only audit legitimately RUNS the suite to verify compliance, and
# the interpreter writes those byproducts. They are never a content change
# the skill is responsible for, so they must not fail the read-only check.
git_tree_clean() {
  # shellcheck disable=SC2143  # the ! grep -q form flips this predicate: with no
  # porcelain output at all it reports dirty instead of clean.
  [[ -z "$(git -C "$proj" status --porcelain 2>/dev/null \
            | grep -Ev '(^|/)(__pycache__/|\.pytest_cache/)|\.pyc$')" ]]
}

# body_unchanged <rel-path> -> the task body (H1 onward) is byte-identical to
# the committed seed. A read-only skill may stamp frontmatter (status/updated)
# and nothing else, so this is the sharp read-only assertion for the stamping
# checkers: it catches a body repair the reporting stage is not allowed to make.
body_unchanged() {
  local rel="$1"
  diff <(git -C "$proj" show "HEAD:$rel" 2>/dev/null | sed -n '/^# /,$p') \
       <(sed -n '/^# /,$p' "$proj/$rel")
}

# --- backlog-coherence helpers ------------------------------------------------
# The six fix_coherence* evals ask the agent to write its report to
# coherence-report.md in a machine-readable shape (a `selected:` line and one
# `verdict:` line per task). grade.sh cannot read the agent's response text, so
# that file is the graded surface for the assess-phase verdicts.
REPORT="$proj/coherence-report.md"

report_present() { [[ -s "$REPORT" ]]; }
rep_has() { grep -qiE -- "$1" "$REPORT"; }
# rep_near <anchor-regex> <regex> [window] -> <regex> appears within <window>
# lines of an <anchor-regex> hit, so evidence is attributed to its own task
# rather than to anything anywhere in the report.
rep_near() {
  local anchor="$1" re="$2" win="${3:-10}"
  grep -iE -A"$win" -B"$win" -- "$anchor" "$REPORT" 2>/dev/null | grep -qiE -- "$re"
}
# selected_has / selected_lacks -> membership of the report's `selected:` line.
selected_line() { grep -i '^ *selected:' "$REPORT" | head -1; }
selected_has()   { report_present && selected_line | grep -qi -- "$1"; }
# A missing report must not satisfy an exclusion check vacuously.
selected_lacks() { report_present && ! selected_line | grep -qi -- "$1"; }
# verdict_is <task-substring> <verdict-regex> -> that task's verdict line says so.
# Anchor on the task as the SUBJECT of the line. Matching the name anywhere on a
# verdict line also hits it inside another task's evidence prose ("does not
# conflict with tool_clean-bar-note"), and `head -1` then grades the wrong task.
verdict_line() { grep -iE "^ *verdict: *$1" "$REPORT" | head -1; }
verdict_is() { verdict_line "$1" | grep -qiE -- "$2"; }
# No tracked file changed — the sharp assertion for an assess-only run.
tracked_unmodified() { [[ -z "$(git -C "$proj" diff --name-only HEAD 2>/dev/null)" ]]; }
# unwrapped_file <path> -> the file with hard wraps collapsed. Task bodies are
# hard-wrapped prose, so a line-based grep for a multi-word phrase silently
# misses it when the wrap falls mid-phrase ("so it must\nfollow the rename").
# Any check matching more than one word must read the unwrapped text.
unwrapped_file() { tr '\n' ' ' < "$1" | tr -s ' '; }
# section_unchanged <rel-path> <heading> -> that one section is byte-identical to
# the committed seed, so a surfaced-not-applied candidate can be proven.
section_unchanged() {
  local rel="$1" head="$2"
  diff <(git -C "$proj" show "HEAD:$rel" 2>/dev/null | awk -v h="$head" '$0==h{f=1;next} /^## /{f=0} f{print}') \
       <(awk -v h="$head" '$0==h{f=1;next} /^## /{f=0} f{print}' "$proj/$rel")
}
goal_unchanged() { section_unchanged "$1" '## Goal'; }
# every_goal_unchanged -> no live task's ## Goal moved, whatever else did.
every_goal_unchanged() {
  local rel
  for f in "$TASKS"/*.md; do
    rel="tasks/$(basename "$f")"
    git -C "$proj" cat-file -e "HEAD:$rel" 2>/dev/null || continue
    goal_unchanged "$rel" >/dev/null 2>&1 || return 1
  done
  return 0
}
file_unchanged() { diff <(git -C "$proj" show "HEAD:tasks/$1" 2>/dev/null) "$TASKS/$1" ; }
# no_status_writes -> every live task's status: is byte-identical to the seed.
# A coherence pass flags a re-check in its report and never demotes frontmatter,
# so any status change at all is a finding whichever direction it moves.
no_status_writes() {
  local rel o n
  for f in "$TASKS"/*.md; do
    rel="tasks/$(basename "$f")"
    git -C "$proj" cat-file -e "HEAD:$rel" 2>/dev/null || continue
    o="$(git -C "$proj" show "HEAD:$rel" | grep -m1 '^status:')"
    n="$(grep -m1 '^status:' "$f")"
    [[ "$o" == "$n" ]] || return 1
  done
  return 0
}
updated_bumped() {
  local e; e="$(iso_epoch "$(fm_field "$TASKS/$1" updated)")"
  [[ -n "$e" ]] && (( e >= start_epoch - 120 ))
}

# Isolation fail-safe: the real repo's tasks/ must be untouched.
no_real_repo_writes() {
  local hits
  hits="$(find "$REPO_ROOT/tasks" -type f -newer "$marker" 2>/dev/null)"
  [[ -z "$hits" ]]
}

suite_passes() {
  ( cd "$proj" && python3 -m unittest discover -s tests -p 'test_*.py' ) >/dev/null 2>&1
}

sha_of() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'
  else shasum -a 256 "$1" | awk '{print $1}'; fi
}
# Disposition fail-safe: the mined source must be byte-for-byte unchanged.
# setup.sh snapshotted its sha into $target/.source_sha256 — a mismatch (or
# a missing file) means the skill deleted, moved, overwrote, or truncated
# the source on its own initiative, which the contract forbids.
source_unchanged() {
  local f="$1" want
  want="$(cat "$target/.source_sha256" 2>/dev/null)"
  [[ -f "$f" && -n "$want" && "$(sha_of "$f")" == "$want" ]]
}

# --- universal -----------------------------------------------------------------

check "isolation: no writes to the real repo's tasks/ tree" no_real_repo_writes

# --- per-eval ------------------------------------------------------------------

case "$eval_id" in
  create)
    open_files=( "$TASKS"/*.md )
    one_open_task() { [[ -f "${open_files[0]}" && ${#open_files[@]} -eq 1 ]]; }
    no_archived_task() { [[ -z "$(find "$TASKS/archive" -name '*.md' 2>/dev/null)" ]]; }
    check "exactly one task file created under tasks/ (got ${#open_files[@]})" one_open_task
    check "nothing written under archive/ (create does not archive)" no_archived_task
    check "the new task lints clean" lint_no_blocking
    if one_open_task; then
      f="${open_files[0]}"
      status_open()   { [[ "$(fm_field "$f" status)" == "open" ]]; }
      reported_by_present() { [[ -n "$(fm_field "$f" reported-by)" ]]; }
      created_eq_updated() { [[ "$(fm_field "$f" created)" == "$(fm_field "$f" updated)" ]]; }
      created_is_recent() {
        local c e; c="$(fm_field "$f" created)"; e="$(iso_epoch "$c")"
        [[ -n "$e" ]] && (( e >= start_epoch - 120 && e <= start_epoch + 1800 ))
      }
      check "status is open"                                   status_open
      check "reported-by is populated"                          reported_by_present
      check "created == updated (both stamped once)"           created_eq_updated
      check "created is the real wall clock, not fabricated"   created_is_recent
      description_within_budget() {
        local d; d="$(fm_field "$f" description)"
        [[ -n "$d" ]] && (( ${#d} <= 200 ))
      }
      # Acceptance contract: task-specific gates only — the named generic
      # project gates must not appear as acceptance items.
      acceptance_task_specific() {
        local acc; acc="$(sed -n '/^## Acceptance/,$p' "$f")"
        [[ -n "$acc" ]] && ! grep -qiE 'make lint|dry.run|full test suite' <<<"$acc"
      }
      check "description fits the ~180-char budget (<=200)"     description_within_budget
      check "acceptance has no generic project-gate items"      acceptance_task_specific
    fi
    ;;

  check)
    f="$TASKS/api_make-it-better.md"
    status_checked() { [[ "$(fm_field "$f" status)" == "checked" ]]; }
    check "status stamped checked for a not-ready verdict" status_checked
    note_agent_attest "response leads with '# General assessment'"
    note_agent_attest "response has a '## Issues' section that is NOT 'No issues found.' (the task is under-specified)"
    note_agent_attest "each issue entry carries 'where it sits' — located by label or unambiguous description (heading, tag, quoted phrase), no bare line numbers"
    note_agent_attest "issues are grounded against the repo; any unverifiable suspicion appears as a question in the general assessment, never as a numbered issue"
    ;;

  standing_rules_create)
    src="$proj/notes/packaging-smoke-test-draft.md"
    open_files=( "$TASKS"/*.md )
    one_open_task() { [[ -f "${open_files[0]}" && ${#open_files[@]} -eq 1 ]]; }
    no_family_guardrail_docs() {
      [[ ! -e "$proj/CHARTER.md" && ! -e "$proj/ARCHITECTURE.md" \
        && ! -e "$proj/FEATURES.md" && ! -e "$proj/TESTING.md" ]]
    }
    harness_docs_present() { [[ -f "$proj/CLAUDE.md" && -f "$proj/AGENTS.md" ]]; }
    created_task_has() { [[ -f "${open_files[0]}" ]] && grep -qiE "$1" "${open_files[0]}"; }
    copied_rule_absent() {
      [[ -f "${open_files[0]}" ]] \
        && ! grep -Fq 'Use Make plus POSIX shell for repo automation.' "${open_files[0]}"
    }
    cites_repo_rules() { created_task_has 'standing repo rule|standing repo rules|repo rule|repo rules|standing project instruction|standing instruction'; }
    check "fixture has CLAUDE.md and AGENTS.md"                  harness_docs_present
    check "fixture has no family guardrail docs"                 no_family_guardrail_docs
    check "source note left untouched"                           source_unchanged "$src"
    check "exactly one task file created under tasks/"           one_open_task
    check "created task lints clean"                             lint_no_blocking
    check "created task does not copy the standing rule verbatim" copied_rule_absent
    check "created task cites the standing/repo rule(s)"         cites_repo_rules
    note_agent_attest "task_create's self-check rejected the planted copied rule from the source draft rather than carrying it forward"
    ;;

  standing_rules_check)
    f="$TASKS/build_packaging-smoke.md"
    status_checked() { [[ "$(fm_field "$f" status)" == "checked" ]]; }
    copied_rule_still_present() { grep -Fq 'Use Make plus POSIX shell for repo automation.' "$f"; }
    check "status stamped checked for the restated-rule finding" status_checked
    check "task_check preserved body content while reporting"     copied_rule_still_present
    note_agent_attest "response has a Restated standing rules issue that cites the base <body> corollary as the rule source"
    note_agent_attest "response withholds ready because the task copies a CLAUDE.md rule instead of citing it"
    ;;

  standing_rules_check_control)
    f="$TASKS/build_packaging-smoke.md"
    status_ready() { [[ "$(fm_field "$f" status)" == "ready" ]]; }
    citation_present() { grep -qiE 'standing repo rules|repo rules|standing project instruction|standing instruction' "$f"; }
    copied_rule_absent() { ! grep -Fq 'Use Make plus POSIX shell for repo automation.' "$f"; }
    check "status stamped ready for the cited-rule control" status_ready
    check "control task cites the standing/repo rules"      citation_present
    check "control task does not copy the standing rule"    copied_rule_absent
    note_agent_attest "response has no Restated standing rules issue for the correctly cited control"
    note_agent_attest "response preserves the existing do-not-demand-restatement guard"
    ;;

  explain)
    f="$TASKS/archive/api_retry-after-header.md"
    archived_task_present() { [[ -f "$f" ]]; }
    status_finished() { [[ "$(fm_field "$f" status)" == "finished" ]]; }
    check "read-only: the sandbox git tree is unchanged" git_tree_clean
    check "fixture archived task remains in archive/" archived_task_present
    check "fixture archived task keeps status finished" status_finished
    note_agent_attest "response leads with a compact bottom-line explanation"
    note_agent_attest "orienting frame names tasks/archive/api_retry-after-header.md, status finished, and scope plugins/ai_dev"
    note_agent_attest "response covers What (documentation goal), Why (client-orientation motivation), and How (rewrite plus example response)"
    note_agent_attest "response synthesizes the task instead of reproducing the task sections verbatim"
    ;;

  select)
    check "read-only: the sandbox git tree is unchanged" git_tree_clean
    note_agent_attest "response starts with '# Recommendation'"
    note_agent_attest "recommended task is tasks/api_auth-bug.md"
    note_agent_attest "suggested next action is task_implement because the recommended task is ready"
    note_agent_attest "api scope filter is applied before ranking"
    note_agent_attest "implemented live task, archived task, and out-of-scope infra task are excluded"
    note_agent_attest "alternatives include tasks/api_schema-cleanup.md with an impact/complexity/friction tradeoff"
    note_agent_attest "reasoning explicitly covers impact, implementation complexity, implementation friction, and viable bug-fix priority"
    ;;

  implement)
    calc="$proj/mathutils/calc.py"
    impl_no_stub() { ! grep -q "NotImplementedError" "$calc"; }
    test_exists()  { [[ -n "$(find "$proj/tests" -name 'test_*.py' 2>/dev/null)" ]]; }
    task_implemented() {
      [[ -f "$TASKS/calc_add-function.md" ]] \
        && [[ "$(fm_field "$TASKS/calc_add-function.md" status)" == "implemented" ]] \
        && [[ -n "$(fm_field "$TASKS/calc_add-function.md" implemented-by)" ]]
    }
    not_archived() { [[ ! -f "$TASKS/archive/calc_add-function.md" ]]; }
    check "calc.add implemented (no NotImplementedError left)" impl_no_stub
    check "a test_*.py was written under tests/"               test_exists
    check "the test suite passes (unittest discover, exit 0)"  suite_passes
    check "task is stamped implemented with implemented-by"      task_implemented
    check "task was not moved to archive/"                     not_archived
    ;;

  implement_dep_gate)
    a="$TASKS/render_wire-palette.md"
    b="$TASKS/theme_palette-block.md"
    a_still_ready()       { [[ "$(fm_field "$a" status)" == "ready" ]]; }
    a_no_implemented_by() { [[ -z "$(fm_field "$a" implemented-by)" ]]; }
    b_present_open()      { [[ -f "$b" && "$(fm_field "$b" status)" == "open" ]]; }
    render_untouched()    { grep -q 'COLORS = {' "$proj/src/render.py"; }
    check "gate stopped: sandbox git tree unchanged (no code edit)"  git_tree_clean
    check "task A left status ready (gate made no status change)"    a_still_ready
    check "task A has no implemented-by stamp"                       a_no_implemented_by
    check "prerequisite task B still present and open"               b_present_open
    check "render.py hardcoded COLORS map left intact (not wired)"   render_untouched
    note_agent_attest "response surfaces theme_palette-block.md as task A's hard prerequisite, citing the forward-reference / dependency cross-link evidence"
    note_agent_attest "response lists the prerequisite, asks whether to build render_wire-palette ahead of it, and stops without building (no user green-light in a headless run)"
    ;;

  select_inbound_dep)
    check "read-only: the sandbox git tree is unchanged" git_tree_clean
    note_agent_attest "response names infra_shared-config-loader.md as the prerequisite blocking api_rate-limit-endpoint.md — the INBOUND note in B's body was honored though A is silent and B is outside the api filter"
    note_agent_attest "api_rate-limit-endpoint.md is not offered as an unblocked next task; the outside-scope prerequisite is named as the required next work (api_response-cache.md is the sensible unblocked pick)"
    ;;

  select_dep_regression)
    check "read-only: the sandbox git tree is unchanged" git_tree_clean
    note_agent_attest "creator theme_palette-block.md is ranked AHEAD of consumer render_wire-palette.md (forward-reference hard dependency, creator-before-consumer)"
    note_agent_attest "docs_glossary-page.md and docs_faq-page.md surface as a soft companion relationship with NO forced order between them"
    ;;

  audit_gaps)
    no_test_added() { [[ -z "$(find "$proj/tests" -name 'test_*.py' 2>/dev/null)" ]]; }
    check "read-only: the sandbox git tree is unchanged" git_tree_clean
    check "no test file was added (audit reports, it does not fix)" no_test_added
    note_agent_attest "response contains a 'Gaps:' list naming the missing test"
    ;;

  audit_clean)
    f="$TASKS/calc_add-function.md"
    status_audited() { [[ "$(fm_field "$f" status)" == "audited" ]]; }
    check "status stamped audited after clean verdict" status_audited
    check "fixture sanity: the suite genuinely passes"   suite_passes
    note_agent_attest "response is exactly 'Success: full task compliance confirmed.'"
    ;;

  finish_arch_extended|finish_arch_declined|finish_arch_absent)
    # Which task the eval closes, and what the ARCHITECTURE.md outcome
    # must be. The doc verdict is a git diff against the committed seed,
    # so "edited" and "byte-identical" are both hard assertions.
    case "$eval_id" in
      finish_arch_extended) closing="api_pluggable-storage.md"   ;;
      finish_arch_declined) closing="api_retry-after-header.md"  ;;
      finish_arch_absent)   closing="api_pluggable-storage.md"   ;;
    esac
    archived="$TASKS/archive/$closing"

    moved_to_archive() { [[ -f "$archived" && ! -f "$TASKS/$closing" ]]; }
    status_finished()  { [[ "$(fm_field "$archived" status)" == "finished" ]]; }
    updated_is_iso()   { [[ "$(fm_field "$archived" updated)" =~ $ISO_RE ]]; }
    git_tracks_move() {
      git -C "$proj" ls-files --error-unmatch "tasks/archive/$closing" >/dev/null 2>&1 \
        && ! git -C "$proj" ls-files --error-unmatch "tasks/$closing" >/dev/null 2>&1
    }
    # design-extended must survive the move unchanged — finish consumes
    # the signal, it does not rewrite it.
    signal_preserved() {
      local want
      case "$eval_id" in
        finish_arch_declined) want="false" ;;
        *)                    want="true"  ;;
      esac
      [[ "$(fm_field "$archived" design-extended)" == "$want" ]]
    }
    arch_edited()          { ! diff -q <(git -C "$proj" show HEAD:ARCHITECTURE.md) "$proj/ARCHITECTURE.md" >/dev/null 2>&1; }
    arch_byte_identical()  {   diff -q <(git -C "$proj" show HEAD:ARCHITECTURE.md) "$proj/ARCHITECTURE.md" >/dev/null 2>&1; }
    arch_absent()          { [[ ! -e "$proj/ARCHITECTURE.md" ]]; }
    # The declined eval must leave its sibling task alone.
    sibling_untouched()    { [[ -f "$TASKS/api_pluggable-storage.md" ]]; }

    check "target moved to archive/ (gone from tasks root)" moved_to_archive
    check "archived task status is finished"                status_finished
    check "updated is a valid ISO timestamp"                updated_is_iso
    check "git tracks the move (git mv, not a fresh write)" git_tracks_move
    check "design-extended preserved through the move"      signal_preserved
    case "$eval_id" in
      finish_arch_extended)
        check "ARCHITECTURE.md was refreshed (differs from seed)" arch_edited
        note_agent_attest "the report names the ARCHITECTURE.md disposition as refreshed and says what changed"
        ;;
      finish_arch_declined)
        check "ARCHITECTURE.md is byte-identical to the seed"     arch_byte_identical
        check "the sibling task was left in the tasks root"       sibling_untouched
        note_agent_attest "the report names the disposition as declined and gives the reason (behaviour-ledger material, not a goals/stack/design-decision change)"
        ;;
      finish_arch_absent)
        check "no ARCHITECTURE.md was created (presence gate held)" arch_absent
        note_agent_attest "the report names the ARCHITECTURE.md disposition as the doc being absent"
        ;;
    esac
    check "backlog lints clean after close-out"             lint_no_blocking
    ;;
  finish)
    archived="$TASKS/archive/api_rate-limit.md"
    linker="$TASKS/api_throttle-config.md"
    moved_to_archive() { [[ -f "$archived" && ! -f "$TASKS/api_rate-limit.md" ]]; }
    status_finished() { [[ "$(fm_field "$archived" status)" == "finished" ]]; }
    updated_is_iso() { [[ "$(fm_field "$archived" updated)" =~ $ISO_RE ]]; }
    git_tracks_move() {
      git -C "$proj" ls-files --error-unmatch tasks/archive/api_rate-limit.md >/dev/null 2>&1 \
        && ! git -C "$proj" ls-files --error-unmatch tasks/api_rate-limit.md >/dev/null 2>&1
    }
    inbound_link_repointed() { grep -q "archive/api_rate-limit.md" "$linker"; }
    archived_linker="$TASKS/archive/api_legacy-notes.md"
    # The new both-directories scan: the already-archived task's ../ link
    # must become a same-directory sibling path once the target archives.
    archived_inbound_repointed() {
      [[ -f "$archived_linker" ]] \
        && grep -q "](api_rate-limit.md)" "$archived_linker" \
        && ! grep -q '\.\./api_rate-limit\.md' "$archived_linker"
    }
    check "target moved to archive/ (gone from tasks root)" moved_to_archive
    check "archived task status is finished"                status_finished
    check "updated is a valid ISO timestamp"                updated_is_iso
    check "git tracks the move (git mv, not a fresh write)" git_tracks_move
    check "open-sibling inbound link re-pointed to archive/" inbound_link_repointed
    check "archived-task inbound link re-pointed (../ dropped)" archived_inbound_repointed
    check "backlog lints clean after close-out"             lint_no_blocking
    ;;

  fix)
    legacy_migrated() {
      [[ -f "$TASKS/archive/api_misfiled.md" ]] \
        && [[ "$(fm_field "$TASKS/archive/api_misfiled.md" status)" == "finished" ]]
    }
    baddate_normalised() { [[ "$(fm_field "$TASKS/api_baddate.md" created)" =~ $ISO_RE ]]; }
    huge_not_split() {
      [[ -f "$TASKS/api_huge.md" ]] \
        && (( $(wc -l < "$TASKS/api_huge.md") > 300 ))
    }
    # The new soft-pointer auto-fix: the bare line-number reference is
    # re-anchored to a stable label; the target file stays referenced.
    linepointer_reanchored() {
      local f="$TASKS/api_linepointer.md"
      [[ -f "$f" ]] && ! grep -qiE 'line [0-9]+' "$f" && grep -q 'api_good' "$f"
    }
    check "blocking findings driven to zero in archive mode"      lint_archive_no_blocking
    check "legacy archived status migrated to finished"           legacy_migrated
    check "non-ISO created datetime normalised to ISO"            baddate_normalised
    check "bare line-number reference re-anchored to a label"     linepointer_reanchored
    check "oversized page left intact (split is a judgement call)" huge_not_split
    # Default-on backlog-coherence: this fixture plants no cross-task defect, so
    # the assessment must still appear and report the clean case. It is checked
    # by attestation because grade.sh never sees the agent's response text; the
    # deterministic half is that no coherence repair was written, which the
    # api_good.md and api_huge.md checks above already assert.
    coherence_wrote_nothing() {
      [[ -f "$TASKS/api_good.md" ]] \
        && diff -q <(git -C "$proj" show HEAD:tasks/api_good.md) "$TASKS/api_good.md" >/dev/null
    }
    check "no coherence repair was written on an unaccepted run"    coherence_wrote_nothing
    note_agent_attest "response ends with an 'audit complete — N issues resolved, K flagged for review' line"
    note_agent_attest "the oversized page (api_huge.md) is among the items flagged for review"
    note_agent_attest "the report carries a backlog-coherence assessment section even though the prompt used only health-check phrasing — the assessment is default-on"
    note_agent_attest "that section reports the clean case plainly: this fixture plants no cross-task or premise defect, so the joint read finds nothing to alter or defer"
    ;;

  query)
    check "read-only: the sandbox git tree is unchanged" git_tree_clean
    note_agent_attest "response lists the open tasks grouped by scope (api, infra), leading with open work"
    note_agent_attest "the archived task (api_legacy-auth.md) is NOT surfaced — the query asked for open tasks only"
    ;;

  update)
    f="$TASKS/api_rate-limit.md"
    file_present()  { [[ -f "$f" ]]; }
    not_archived()  { [[ ! -f "$TASKS/archive/api_rate-limit.md" ]]; }
    status_open()   { [[ "$(fm_field "$f" status)" == "open" ]]; }
    created_preserved() { [[ "$(fm_field "$f" created)" == "2020-01-01T00:00:00" ]]; }
    description_changed() { [[ "$(fm_field "$f" description)" != "add request rate limiting to the public API" ]]; }
    updated_bumped() {
      local u e; u="$(fm_field "$f" updated)"; e="$(iso_epoch "$u")"
      [[ -n "$e" ]] && (( e >= start_epoch - 120 && e <= start_epoch + 1800 ))
    }
    git_modified() {
      git -C "$proj" ls-files --error-unmatch tasks/api_rate-limit.md >/dev/null 2>&1 \
        && [[ -n "$(git -C "$proj" status --porcelain tasks/api_rate-limit.md)" ]]
    }
    check "target task still present in tasks/ root"             file_present
    check "task not archived (update is an edit, not close-out)" not_archived
    check "status stays open"                                    status_open
    check "created preserved (update bumps updated, not created)" created_preserved
    check "description was edited (differs from the seed)"       description_changed
    check "updated bumped to the real wall clock"                updated_bumped
    check "tracked file shows a modification (not a fresh write)" git_modified
    check "backlog lints clean after the edit"                   lint_no_blocking
    ;;

  update_contract)
    # The hub <output_contract> eval. Each programmatic check below is the
    # filesystem fact one of the contract's four reported parts must match,
    # so a report that names the wrong path, invents a lifecycle move, or
    # claims a clean lint the tree does not have is contradicted by state.
    rel="tasks/auth_token-rotation.md"
    f="$proj/$rel"
    sib="tasks/auth_session-timeout.md"
    file_present()      { [[ -f "$f" ]]; }
    not_archived()      { [[ ! -f "$TASKS/archive/auth_token-rotation.md" ]]; }
    archive_empty()     { [[ -z "$(find "$TASKS/archive" -name '*.md' 2>/dev/null)" ]]; }
    status_open()       { [[ "$(fm_field "$f" status)" == "open" ]]; }
    created_preserved() { [[ "$(fm_field "$f" created)" == "2020-01-01T00:00:00" ]]; }
    updated_bumped() {
      local u e; u="$(fm_field "$f" updated)"; e="$(iso_epoch "$u")"
      [[ -n "$e" ]] && (( e >= start_epoch - 120 && e <= start_epoch + 1800 ))
    }
    window_recorded()  { grep -qiE '24[[:space:]-]?h(our)?' "$f"; }
    overlap_recorded() { grep -qiE '1[[:space:]-]?h(our)?|60[[:space:]-]?min|one[[:space:]-]hour' "$f"; }
    # Rewrite in place: both unsettled placeholders are superseded, not
    # left standing beside the newly recorded decisions.
    tbd_superseded()   { ! grep -qi 'TBD' "$f"; }
    sibling_untouched() { git -C "$proj" diff --quiet HEAD -- "$sib"; }
    # "Files touched" is only a checkable claim when exactly one file could
    # have been touched. Ignore Python bytecode the way git_tree_clean does.
    only_target_modified() {
      local changed
      changed="$(git -C "$proj" status --porcelain 2>/dev/null \
                  | grep -Ev '(^|/)(__pycache__/|\.pytest_cache/)|\.pyc$' \
                  | awk '{print $NF}' | sort -u)"
      [[ "$changed" == "$rel" ]]
    }
    check "target task still present at $rel"                      file_present
    check "task not archived (update is an edit, not close-out)"   not_archived
    check "archive/ still holds no task (no lifecycle move made)"  archive_empty
    check "status stays open"                                      status_open
    check "created preserved (update bumps updated, not created)"  created_preserved
    check "updated bumped to the real wall clock"                  updated_bumped
    check "the 24-hour rotation window is recorded on disk"        window_recorded
    check "the 1-hour overlap decision is recorded on disk"        overlap_recorded
    check "both TBD placeholders superseded (rewritten in place)"  tbd_superseded
    check "sibling auth_session-timeout.md byte-identical to seed" sibling_untouched
    check "exactly one file changed, and it is $rel"               only_target_modified
    check "backlog lints clean after the edit"                     lint_no_blocking
    note_agent_attest "part 1 — files touched: the report names tasks/auth_token-rotation.md by its project-relative path as the one file edited, and claims no other file changed"
    note_agent_attest "part 2 — lifecycle: the report states that status stayed open and the task stayed in tasks/, i.e. the run made no lifecycle move (no invented 'archived' or 'ready')"
    note_agent_attest "part 3 — linter outcome: the report names what the bundled task linter returned for this run rather than leaving the check unreported"
    note_agent_attest "part 4 — assumptions and judgement calls: the report surfaces the calls it made (where the 1-hour overlap landed, whether the frontmatter description was widened) for the user to correct, or states explicitly that it made none"
    note_agent_attest "all four parts arrive in one closing report, in the shape the hub <output_contract> defines, rather than scattered through the narration"
    ;;

  triage)
    f="$TASKS/api_rate-limit.md"
    file_present()  { [[ -f "$f" ]]; }
    not_archived()  { [[ ! -f "$TASKS/archive/api_rate-limit.md" ]]; }
    status_open()   { [[ "$(fm_field "$f" status)" == "open" ]]; }
    created_preserved() { [[ "$(fm_field "$f" created)" == "2020-01-01T00:00:00" ]]; }
    updated_bumped() {
      local u e; u="$(fm_field "$f" updated)"; e="$(iso_epoch "$u")"
      [[ -n "$e" ]] && (( e >= start_epoch - 120 && e <= start_epoch + 1800 ))
    }
    # 1 accepted: the unverifiable item is replaced by the concrete check.
    accepted_applied() { grep -qi '429' "$f" && ! grep -qi 'works properly' "$f"; }
    # 2 rejected: the Goal sentence stays byte-identical.
    rejected_untouched() { grep -qF 'Protect the public API from abusive clients.' "$f"; }
    # 3 modified: the user's instruction wins over the report's suggestion.
    modified_won() { grep -q 'docs/api.md' "$f" && ! grep -q 'src/api/server.py' "$f"; }
    git_modified() {
      git -C "$proj" ls-files --error-unmatch tasks/api_rate-limit.md >/dev/null 2>&1 \
        && [[ -n "$(git -C "$proj" status --porcelain tasks/api_rate-limit.md)" ]]
    }
    check "target task still present in tasks/ root"               file_present
    check "task not archived (apply round is an edit, not close-out)" not_archived
    check "status stays open"                                      status_open
    check "accepted finding 1 applied (429 in, 'works properly' out)" accepted_applied
    check "rejected finding 2 untouched (Goal byte-identical)"     rejected_untouched
    check "modified finding 3 follows the user (docs/api.md, not server.py)" modified_won
    check "created preserved (round bumps updated, not created)"   created_preserved
    check "updated bumped once to the real wall clock"             updated_bumped
    check "tracked file shows a modification (not a fresh write)"  git_modified
    check "backlog lints clean after the round"                    lint_no_blocking
    note_agent_attest "numbers were read as indexing the report in the conversation (no re-derivation, no guessing)"
    note_agent_attest "the whole round was one update: one updated bump and one re-lint at the end"
    ;;

  lossless_split)
    src="$proj/notes/db-migration-plan.md"
    open_files=( "$TASKS"/*.md )
    # grep the files directly (not `cat ... | grep -q`): under `set -o
    # pipefail` a matching `grep -q` closes the pipe early, cat dies with
    # SIGPIPE, and the pipeline reports failure on a real match.
    covers() { grep -qiE "$1" "$TASKS"/*.md 2>/dev/null; }
    several_tasks() { [[ -f "${open_files[0]}" ]] && (( ${#open_files[@]} >= 2 )); }
    section_pooling() { covers 'pgbouncer|connection pool'; }
    section_replica() { covers 'read replica|replica lag|replication'; }
    section_backup()  { covers 'wal archiving|continuous wal|point-in-time|backup'; }
    # Source-wide preamble (the staging-first / green-canary gate) must land
    # in EVERY derived task, not just one — that is the propagation contract.
    preamble_in_each() {
      [[ -f "${open_files[0]}" ]] || return 1
      local f
      for f in "$TASKS"/*.md; do
        grep -qiE 'canary|staging' "$f" || return 1
      done
      return 0
    }
    check "source doc left untouched (disposition is the user's call)"  source_unchanged "$src"
    check "several tasks derived from the multi-section source (>=2)"   several_tasks
    check "section 'connection pooling' covered (pgbouncer)"            section_pooling
    check "section 'read replicas' covered (replica)"                   section_replica
    check "section 'backup cadence' covered (WAL / point-in-time)"      section_backup
    check "shared preamble propagated into EVERY derived task (canary)" preamble_in_each
    check "derived tasks lint clean"                                    lint_no_blocking
    note_agent_attest "response runs a unit-by-unit coverage pass and reports it before offering to drop the source"
    note_agent_attest "the check fired without the user asking for it (prompt did not request preservation)"
    note_agent_attest "the source's keep/drop disposition is proposed and left to the user"
    ;;

  lossless_single)
    src="$proj/notes/session-cache-bug.md"
    open_files=( "$TASKS"/*.md )
    one_task() { [[ -f "${open_files[0]}" && ${#open_files[@]} -eq 1 ]]; }
    has() { [[ -f "${open_files[0]}" ]] && grep -qiE "$1" "${open_files[0]}"; }
    repro_kept()      { has 'race condition|two tabs'; }
    culprit_kept()    { has 'sessioncache'; }
    constraint_kept() { has 'backward.compat|re-login|on-disk session'; }
    check "source note left untouched (disposition is the user's call)" source_unchanged "$src"
    check "exactly one task derived (the content collapses to one)"     one_task
    check "repro detail preserved (race condition)"                     repro_kept
    check "culprit preserved (SessionCache)"                            culprit_kept
    check "backward-compatibility constraint preserved"                 constraint_kept
    check "the derived task lints clean"                                lint_no_blocking
    note_agent_attest "the single-task outcome did not skip the coverage check"
    note_agent_attest "response reports coverage before offering to drop the source"
    ;;

  check_boundary_contradiction)
    f="$TASKS/cli_json-output-flag.md"
    status_checked() { [[ "$(fm_field "$f" status)" == "checked" ]]; }
    out_of_scope_preserved() { grep -Fq '**Out of scope:**' "$f"; }
    yaml_body_preserved() { grep -Fq 'report --yaml' "$f"; }
    check "status stamped checked for the boundary contradiction" status_checked
    check "read-only stamp: the **Out of scope:** block is preserved" out_of_scope_preserved
    check "read-only stamp: the conflicting --yaml acceptance is preserved" yaml_body_preserved
    note_agent_attest "a numbered issue names the body-versus-boundary contradiction: the '--yaml' acceptance item proves work the **Out of scope:** block excludes"
    note_agent_attest "the issue routes disposition through the base Decide or label reconcile-or-surface rule"
    ;;

  check_boundary_clean)
    f="$TASKS/cli_exit-code-on-error.md"
    file_present() { [[ -f "$f" ]]; }
    no_out_of_scope_block() { ! grep -Fq '**Out of scope:**' "$f"; }
    task_check_ran() { local s; s="$(fm_field "$f" status)"; [[ "$s" == "checked" || "$s" == "ready" ]]; }
    check "control fixture carries no **Out of scope:** block" no_out_of_scope_block
    check "the checked task file is still present"              file_present
    check "task_check ran (status stamped off open to checked/ready, so a no-op cannot pass this control)" task_check_ran
    note_agent_attest "no boundary finding is raised — the missing **Out of scope:** block draws no issue (presence stays optional)"
    note_agent_attest "the verdict is reached on the task's other merits, with the boundary convention invisible when there is nothing to exclude"
    ;;

  implement_boundary_cross)
    a="$TASKS/report_colored-lines.md"
    a_still_ready()       { [[ "$(fm_field "$a" status)" == "ready" ]]; }
    a_no_implemented_by() { [[ -z "$(fm_field "$a" implemented-by)" ]]; }
    theme_untouched()     { grep -Fq 'return text' "$proj/src/theme.py"; }
    report_untouched()    { grep -Fq 'format_line(line) for line in lines' "$proj/src/report.py"; }
    check "backstop held: sandbox git tree unchanged (no crossing edit)"   git_tree_clean
    check "task left status ready (backstop made no status change)"        a_still_ready
    check "task has no implemented-by stamp"                               a_no_implemented_by
    check "src/theme.py left byte-for-byte unchanged (boundary honored)"   theme_untouched
    check "src/report.py left unchanged (work held before crossing)"       report_untouched
    note_agent_attest "response surfaces the body-versus-boundary contradiction: the Goal and the 'format_line wraps its text in ANSI color codes' acceptance require editing src/theme.py, which the **Out of scope:** block rejects"
    note_agent_attest "response quotes the conflicting passages, applies the reconcile-or-surface disposition, and holds without crossing the boundary (no user resolution available in a headless run)"
    ;;

  implement_boundary_agree)
    calc="$proj/mathutils/calc.py"
    add="$TASKS/calc_add-function.md"
    subt="$TASKS/calc_subtract-function.md"
    add_works()      { ( cd "$proj" && python3 -c "from mathutils.calc import add; import sys; sys.exit(0 if add(2,3)==5 else 1)" ); }
    sub_still_stub() { grep -Fq 'sub is not implemented yet' "$calc"; }
    test_exists()    { [[ -n "$(find "$proj/tests" -name 'test_*.py' 2>/dev/null)" ]]; }
    add_implemented() {
      [[ -f "$add" ]] \
        && [[ "$(fm_field "$add" status)" == "implemented" ]] \
        && [[ -n "$(fm_field "$add" implemented-by)" ]]
    }
    add_not_archived()  { [[ ! -f "$TASKS/archive/calc_add-function.md" ]]; }
    sub_task_still_open() { [[ -f "$subt" && "$(fm_field "$subt" status)" == "open" ]]; }
    check "no boundary interruption: calc.add is implemented (returns a+b)" add_works
    check "the deferred calc.sub was correctly skipped (stub intact)"       sub_still_stub
    check "a test_*.py was written under tests/"                            test_exists
    check "the test suite passes (unittest discover, exit 0)"               suite_passes
    check "add task stamped implemented with implemented-by"                add_implemented
    check "add task was not archived"                                       add_not_archived
    check "deferred owner task (calc_subtract-function.md) still open"      sub_task_still_open
    note_agent_attest "response proceeds with no boundary interruption — the **Out of scope:** deferral agrees with the body, so nothing the Goal/Acceptance needs is excluded"
    note_agent_attest "response reports each Acceptance item met and points at task_audit; it does not build the deferred subtraction work"
    ;;

  create_scope_trim)
    open_files=( "$TASKS"/*.md )
    one_open_task() { [[ -f "${open_files[0]}" && ${#open_files[@]} -eq 1 ]]; }
    no_archived_task() { [[ -z "$(find "$TASKS/archive" -name '*.md' 2>/dev/null)" ]]; }
    check "exactly one task file created under tasks/ (got ${#open_files[@]})" one_open_task
    check "nothing written under archive/"                                    no_archived_task
    check "the new task lints clean (no broken deferral link, valid form)"    lint_no_blocking
    if one_open_task; then
      f="${open_files[0]}"
      has_out_of_scope() { grep -Fq '**Out of scope:**' "$f"; }
      # Extract the Out of scope block: the **Out of scope:** label line itself
      # (so an inline "**Out of scope:** <entries>" block is captured, not just
      # a multi-line label-then-bullets block) plus every following line up to
      # the next '## ' heading (or EOF). Acceptance requires the trimmed work to
      # land INSIDE the block, not merely somewhere in the file (else "output
      # JSON, not YAML/CSV" in the Goal would falsely pass).
      oos_block() { awk '/\*\*Out of scope:\*\*/{f=1} /^## /{f=0} f' "$f"; }
      trims_yaml() { oos_block | grep -qi 'yaml'; }
      trims_csv()  { oos_block | grep -qi 'csv'; }
      check "created task carries an **Out of scope:** block"              has_out_of_scope
      check "trimmed --yaml work landed inside the Out of scope block"     trims_yaml
      check "trimmed --csv work landed inside the Out of scope block"      trims_csv
    fi
    note_agent_attest "the trimmed --yaml/--csv work landed as a deferral naming an owner or an explicit rejection inside the **Out of scope:** block"
    note_agent_attest "no prompt was added beyond the existing create flow"
    ;;

  auto_check_boundary)
    f="$TASKS/cli_json-output-flag.md"
    file_present() { [[ -f "$f" ]]; }
    status_valid() { local s; s="$(fm_field "$f" status)"; [[ "$s" == "checked" || "$s" == "ready" ]]; }
    check "the target task file is still present"       file_present
    check "the target task lints clean after the loop"  lint_no_blocking
    check "status is checked (surfaced stuck) or ready (repaired)" status_valid
    note_agent_attest "the Boundary advocate stance handled the finding: either a verifier-approved minimum repair (normalize/reconcile) landed it ready, or it surfaced stuck with options"
    note_agent_attest "an unreconcilable boundary contradiction surfaces through the existing human-routed stuck channel rather than being crossed or dropped silently"
    ;;

  check_exclusion_requirement)
    rel="tasks/build_packaging-smoke.md"
    f="$proj/$rel"
    status_checked() { [[ "$(fm_field "$f" status)" == "checked" ]]; }
    guardrail_entry_preserved() { grep -Fq 'never passes a manifest that lacks a required field' "$f"; }
    meta_note_preserved() { grep -Fq 'is not an exclusion' "$f"; }
    check "status stamped checked for the miscategorized-exclusion finding" status_checked
    check "read-only stamp: the guardrail entry is preserved in the body"    guardrail_entry_preserved
    check "read-only stamp: the meta not-an-exclusion note is preserved"     meta_note_preserved
    check "read-only stamp: the body is byte-identical to the seed"          body_unchanged "$rel"
    check "the task still lints clean"                                      lint_no_blocking
    note_agent_attest "a numbered issue names the guardrail entry ('never passes a manifest that lacks a required field') as an in-scope requirement miscategorized into the **Out of scope:** block, with the fix relocating it to Goal, Approach, or Acceptance"
    note_agent_attest "a numbered issue names the 'is not an exclusion' line as a meta note that belongs out of the block, with the fix dropping it"
    note_agent_attest "both findings are contradiction-rank and route disposition through the base Decide or label rule rather than a newly invented one"
    note_agent_attest "the findings cite the base **Declare exclusions as an Out of scope boundary** rule as the source, not a sibling copy"
    ;;

  check_exclusion_requirement_control)
    rel="tasks/build_packaging-smoke.md"
    f="$proj/$rel"
    status_ready() { [[ "$(fm_field "$f" status)" == "ready" ]]; }
    genuine_exclusions_preserved() {
      grep -Fq 'Type validation of the manifest field values' "$f" \
        && grep -Fq 'A CI workflow that runs the new target on every push' "$f"
    }
    no_meta_note() { ! grep -Fq 'is not an exclusion' "$f"; }
    check "status stamped ready for the genuine-exclusions control" status_ready
    check "control block still holds only work-not-done rejections" genuine_exclusions_preserved
    check "control fixture carries no meta not-an-exclusion note"   no_meta_note
    check "read-only stamp: the body is byte-identical to the seed"  body_unchanged "$rel"
    check "the task still lints clean"                              lint_no_blocking
    note_agent_attest "no miscategorized-exclusion finding is raised — both entries are genuine work-not-done rejections, so the Contradictions extension stays quiet"
    note_agent_attest "the verdict is reached on the task's other merits, confirming the extension does not fire on every **Out of scope:** block it meets"
    ;;

  check_exclusion_waiver)
    rel="tasks/build_packaging-smoke.md"
    f="$proj/$rel"
    status_checked() { [[ "$(fm_field "$f" status)" == "checked" ]]; }
    gate_rule_seeded() { grep -Fq 'Run `make lint` and resolve every finding' "$proj/CLAUDE.md"; }
    no_charter() { [[ ! -e "$proj/CHARTER.md" ]]; }
    waiver_entry_preserved() { grep -Fq "The repo's lint gate for this change" "$f"; }
    check "status stamped checked for the rule-waiving exclusion"      status_checked
    check "fixture sanity: the root CLAUDE.md states the lint gate"     gate_rule_seeded
    check "fixture sanity: no CHARTER.md (ordinary standing-rule path)" no_charter
    check "fixture sanity: the gate is satisfiable (Makefile lint target)" grep -q '^lint:' "$proj/Makefile"
    check "read-only stamp: the waiving entry is preserved in the body" waiver_entry_preserved
    check "read-only stamp: the body is byte-identical to the seed"     body_unchanged "$rel"
    check "the task still lints clean"                                 lint_no_blocking
    note_agent_attest "a numbered Rule-waiving exclusions issue names the **Out of scope:** entry that exempts the task's own work from the repo's make lint gate"
    note_agent_attest "the finding cites the waiver test in **Declare exclusions as an Out of scope boundary** — an exclusion removes work from the task, never a rule from the work that remains"
    note_agent_attest "severity is the ordinary readiness-issue path routed through Decide or label (no CHARTER.md is present, so the Charter check escalation does not apply)"
    note_agent_attest "ready is withheld while the waiver stands"
    ;;

  check_exclusion_waiver_control)
    rel="tasks/build_packaging-smoke.md"
    f="$proj/$rel"
    status_ready() { [[ "$(fm_field "$f" status)" == "ready" ]]; }
    carveout_rule_seeded() { grep -Fq 'The lint surface skips everything under `fixtures/`' "$proj/CLAUDE.md"; }
    carveout_entry_preserved() { grep -Fq 'Hand-formatting the generated manifest fixtures' "$f"; }
    check "status stamped ready for the carve-out control"              status_ready
    check "fixture sanity: the root rule provides the fixtures carve-out" carveout_rule_seeded
    check "fixture sanity: the gate is satisfiable (Makefile lint target)" grep -q '^lint:' "$proj/Makefile"
    check "control entry tracking the carve-out is preserved"           carveout_entry_preserved
    check "read-only stamp: the body is byte-identical to the seed"     body_unchanged "$rel"
    check "the task still lints clean"                                 lint_no_blocking
    note_agent_attest "no Rule-waiving exclusions finding is raised — the entry narrows work the governing rule already leaves out, which the waiver test's carve-out clause blesses"
    note_agent_attest "the verdict distinguishes narrowing work from waiving a rule rather than flagging every standing-rule mention inside an **Out of scope:** block"
    ;;

  check_count_stable)
    rel="tasks/build_manifest-smoke.md"
    f="$proj/$rel"
    status_checked() { [[ "$(fm_field "$f" status)" == "checked" ]]; }
    # The seed wraps both phrases across lines, so match against a
    # whitespace-normalised copy rather than a single physical line.
    unwrapped() { tr '\n' ' ' < "$f" | tr -s ' '; }
    frozen_count_preserved() { unwrapped | grep -Fq 'all 3 plugin manifests under'; }
    measurement_item_preserved() { unwrapped | grep -Fq 'fixed denominator of 6 seeded fixture manifests'; }
    three_manifests_seeded() {
      local m=( "$proj"/plugins/*/plugin.json )
      [[ ${#m[@]} -eq 3 && -f "${m[0]}" ]]
    }
    no_charter() { [[ ! -e "$proj/CHARTER.md" ]]; }
    check "status stamped checked for the count-stable finding"            status_checked
    check "fixture sanity: exactly 3 plugin manifests, so the count is true today" three_manifests_seeded
    check "fixture sanity: no CHARTER.md (ordinary standing-rule path)"     no_charter
    check "read-only stamp: the frozen-count phrase is preserved"           frozen_count_preserved
    check "read-only stamp: the measurement-protocol item is preserved"     measurement_item_preserved
    check "read-only stamp: the body is byte-identical to the seed"         body_unchanged "$rel"
    check "the task still lints clean"                                     lint_no_blocking
    note_agent_attest "a numbered Ambiguity / under-specification issue flags 'all 3 plugin manifests under plugins/*/plugin.json' against the base <markdown_policy> count-stable rule, naming the mutable set the count freezes"
    note_agent_attest "the minimum fix is the selector rewrite — every plugin manifest under plugins/*/plugin.json — rather than refreshing the number"
    note_agent_attest "the finding cites the base count-stable rule rather than restating it in a sibling copy"
    note_agent_attest "the measurement Acceptance item (5 runs over the fixed denominator of 6 seeded fixture manifests) draws NO count-stable finding — its run count and fixed denominator are subject matter the rule keeps legal"
    note_agent_attest "both verdicts appear in one report: the frozen mutable-set count flagged, the measurement-protocol quantity left unflagged"
    note_agent_attest "the count-stable finding is the ONLY blocking issue, so the checked stamp above is attributable to this rule alone (the fixture pairs every other promise with its own Acceptance item)"
    ;;

  fix_coherence)
    # Assess only: the report carries every verdict, and no task file moves.
    check "the assessment report was written to coherence-report.md"   report_present
    check "assess-only: no tracked file was modified"                  tracked_unmodified
    check "the selected live set covers the whole live tree (17 tasks)" \
      bash -c 'n=0; for t in docs_exit-code-table tool_check-docstring-sweep tool_clean-bar-note \
        tool_config-format tool_glob-check-severity tool_json-output tool_loop-exception \
        tool_missing-license-finding tool_path-check-severity tool_quiet-flag \
        tool_register-path-check tool_severity-label-consumer tool_severity-label-docstring \
        tool_severity-label-rename tool_severity-registry tool_drop-legacy-module \
        tool_summary-line; do grep -i "^ *selected:" "'"$REPORT"'" | grep -qi -- "$t" && n=$((n+1)); done; [[ $n -eq 17 ]]'
    # (a) one edit double-owned by two tasks, with a third assuming an owner.
    # The repair shape names ONE owner and leaves the other verify-only, so the
    # alter verdict legitimately lands on either side — requiring it on a
    # named side would fail a correct resolution that picked the other owner.
    check "(a) the double-owned severity_label edit is an alter finding" \
      bash -c 'grep -iE "^ *verdict:" "'"$REPORT"'" \
        | grep -iE "tool_severity-label-(rename|docstring)" | grep -qi alter'
    check "(a) the report names both owners of that one edit" \
      rep_near 'tool_severity-label-rename' 'severity-label-docstring'
    check "(a) the report names the shared edit as the evidence" \
      rep_near 'tool_severity-label-rename' 'severity_label|double|both own|shared (surface|edit)|one owner'
    # (b) a quoted anchor a finished sibling invalidated.
    check "(b) the stale-anchor task is an alter finding" \
      verdict_is tool_clean-bar-note 'alter'
    check "(b) the stale anchor is named as the evidence" \
      rep_near 'tool_clean-bar-note' 'unreachable_clean_bar'
    # (c) a new finding re-blocking a sibling's loop exception. Like (a), the
    # repair legitimately lands on either side: change the offending tier on the
    # license task, or couple the change to the exception task that owns its
    # precondition. Requiring a named side would fail the second shape.
    check "(c) the re-blocking finding is an alter finding" \
      bash -c 'grep -iE "^ *verdict:" "'"$REPORT"'" \
        | grep -iE "tool_(missing-license-finding|loop-exception)" | grep -qi alter'
    check "(c) the report ties it to the loop exception it re-blocks" \
      rep_near 'tool_missing-license-finding' 'loop-exception|clean bar|clean-bar|SEV_WARN'
    # (d) a rule enumerating fewer sites than it implies.
    check "(d) the short sweep is an alter finding" \
      verdict_is tool_check-docstring-sweep 'alter'
    check "(d) the un-enumerated check modules are named" \
      rep_near 'tool_check-docstring-sweep' 'license_check|docstring_check|encoding_check'
    # (e) two siblings answering one severity question oppositely.
    check "(e) the opposed posture is an alter finding" \
      bash -c 'grep -iE "^ *verdict:" "'"$REPORT"'" | grep -iE "tool_(path|glob)-check-severity" | grep -qi alter'
    check "(e) the report names both sides of the posture split" \
      rep_near 'tool_path-check-severity' 'glob-check-severity|SEV_INFO|posture|opposite|inconsist'
    # (f) a genuinely underdetermined fork: labeled, with options and a path.
    check "(f) the underdetermined fork keeps both options on the table" \
      rep_near 'tool_config-format' 'toml'
    check "(f) the fork is surfaced as a decision, not silently settled" \
      rep_near 'tool_config-format' 'open decision|decision|underdetermined|surfac'
    # (f) The joint read owns the cross-task consequence: the sibling whose call
    # shape depends on the unsettled choice is tied to it by name. The fork's own
    # resolution is a per-task readiness matter task_check owns, so the pass is
    # not asked to pick a format.
    check "(f) the dependent sibling is tied to the unsettled fork by name" \
      rep_near 'tool_severity-registry' 'config-format'
    # (g) the clean task, (h) the invalidated premise.
    check "(g) the clean task is ship-as-is"     verdict_is docs_exit-code-table 'ship.as.is'
    check "(h) the invalidated premise is a defer candidate" \
      verdict_is tool_json-output 'defer'
    check "(h) the shipped JSON renderer is named as the evidence" \
      rep_near 'tool_json-output' 'report_json|already|invalidated|exists'
    # (i) and (l): surfaced, never applied.
    # (i) The substance is that the pass surfaced the blocker that makes the
    # fitting repair Goal-level — the settled decision it collides with —
    # rather than quietly applying something. Naming the word "goal" is one way
    # to say that and citing the settled decision is another.
    check "(i) the Goal-altering candidate is surfaced as such" \
      rep_near 'tool_drop-legacy-module' 'goal|objective|narrow|keep-compat-shim|settled|finished decision|deprecat'
    check "(i) that task's ## Goal is untouched" \
      goal_unchanged tasks/tool_drop-legacy-module.md
    check "(l) the Acceptance-altering candidate is surfaced as such" \
      rep_near 'tool_quiet-flag' 'acceptance'
    check "(l) that task's ## Acceptance is untouched" \
      section_unchanged tasks/tool_quiet-flag.md '## Acceptance'
    # (j) the hard ordering pair, placed in order or as one wave.
    # (j) Anchor the ship-order section on its HEADING. Starting it at any line
    # that mentions ordering or a wave catches verdict prose discussing a
    # dependency, and the position comparison then runs over the wrong text.
    # With no such heading, fall back to an explicit ordering statement.
    check "(j) the ship order places the registry before its consumer" \
      bash -c 'sec="$(awk "tolower(\$0) ~ /^#+ .*(ship[ -]?order|ship[ -]?sequence|landing order)/ {f=1; next}
                           f && /^## / {exit} f {print}" "'"$REPORT"'")";
        if [[ -n "$sec" ]]; then
          ra="$(grep -ni "severity-registry" <<<"$sec" | head -1 | cut -d: -f1)"
          rb="$(grep -ni "register-path-check" <<<"$sec" | head -1 | cut -d: -f1)"
          [[ -n "$ra" && -n "$rb" ]] && (( ra <= rb ))
        else
          grep -iE "register-path-check" "'"$REPORT"'" \
            | grep -qiE "after .*severity-registry|severity-registry.*(first|lands)|prerequisite"
        fi'
    check "the backlog still lints clean in archive mode" lint_archive_no_blocking
    note_agent_attest "the response carries the same assessment section, with the mode used ('inline' or 'escalated') for the mechanical pass and no third mode token for coherence"
    note_agent_attest "the assessment ran without coherence phrasing being required — the prompt's ordinary backlog wording was enough"
    note_agent_attest "(k) tool_summary-line.md keeps status ready: an assess-only run writes no repair and no stamp"
    ;;

  fix_coherence_reconcile_escalated)
    check "the report was written to coherence-report.md"              report_present
    check "the run reports the escalated writer mode"                  rep_has 'escalated'
    check "the escalation names auto_shaper_task as the single writer" rep_has 'auto_shaper_task'
    # (a) one owner, with the coordination link on the side whose work the
    # relationship changes. Requiring BOTH directions would demand exactly the
    # reverse-duplicate pointer the base <markdown_policy> cross-link rule drops,
    # so assert the link exists on at least one side.
    check "(a) a coordination link ties the two owners together" \
      bash -c 'grep -qi "severity-label-docstring" "'"$TASKS"'/tool_severity-label-rename.md" \
        || grep -qi "severity-label-rename" "'"$TASKS"'/tool_severity-label-docstring.md"'
    # The counterpart either verifies or declares the order it follows in — the
    # two shapes the ownership lens allows. Which one fits depends on whether the
    # counterpart still owns work of its own (here it owns the docstring), so
    # demanding the verify-only wording alone would fail a correct repair.
    check "(a) one owner is named and the counterpart verifies or follows in order" \
      bash -c 'pat="verif(y|ies|ied|ication)|own(s|er|ed|ing)|follows|runs after|depends on|prerequisite|sequence|(must |should |will |has |have )?land(s|ed|ing)? (first|after|before)|after (this|that) task land(s|ed)?";
        unwrapped_file() { tr "\n" " " < "$1" | tr -s " "; };
        unwrapped_file "'"$TASKS"'/tool_severity-label-docstring.md" | grep -qiE "$pat" \
        || unwrapped_file "'"$TASKS"'/tool_severity-label-rename.md" | grep -qiE "$pat"'
    # (b) the anchor refreshed against the shipped rename.
    check "(b) the stale anchor is gone from the clean-bar note task" \
      bash -c '! grep -q "unreachable_clean_bar" "'"$TASKS"'/tool_clean-bar-note.md"'
    check "(b) the refreshed anchor names the shipped helper" \
      grep -q 'reachable_clean_bar' "$TASKS/tool_clean-bar-note.md"
    check "(b) updated bumped on the edited file"  updated_bumped tool_clean-bar-note.md
    # (c) the parameter change, with its rationale recorded once.
    check "(c) the license-finding severity task was repaired" \
      bash -c '! diff -q <(git -C "'"$proj"'" show HEAD:tasks/tool_missing-license-finding.md) \
        "'"$TASKS"'/tool_missing-license-finding.md" >/dev/null'
    check "(c) the repair records the clean-bar reason or couples the sibling" \
      grep -qiE 'loop-exception|clean bar|clean-bar|SEV_INFO|accepted' "$TASKS/tool_missing-license-finding.md"
    # (d) the enumeration completed to the rule's real site set.
    # (d) A selector over the package closes the short sweep at least as well as
    # a full enumeration, and the base count-stable rule prefers it, so accept
    # either. What must be gone is the two-item subset standing as the site list.
    check "(d) the short sweep is completed by enumeration or by a selector" \
      bash -c 'f="'"$TASKS"'/tool_check-docstring-sweep.md";
        { grep -q license_check "$f" && grep -q docstring_check "$f" && grep -q encoding_check "$f"; } \
        || grep -qiE "(every|each|all) modules? under tool/checks|that (currently )?lacks? one" "$f"'
    # (e) The lens names two dispositions and reconciling the tier is the first
    # of them, so compare the tiers before looking for a recorded reason — an
    # earlier version checked only for the reason and rejected the reconcile.
    check "(e) the posture split is reconciled or its reason recorded" \
      bash -c 'a="'"$TASKS"'/tool_path-check-severity.md"; b="'"$TASKS"'/tool_glob-check-severity.md";
        ta="$(grep -oE "SEV_(WARN|INFO)" "$a" | head -1)"; tb="$(grep -oE "SEV_(WARN|INFO)" "$b" | head -1)";
        unwrapped_file() { tr "\n" " " < "$1" | tr -s " "; };
        # A recorded reason names the counterpart and why the answers differ.
        # Match on that substance rather than on one vocabulary: "to match the
        # existing posture of the parallel glob-check task" records it as surely
        # as the word "because" does.
        pat="glob-check|path-check|because|reason|deliberate|principled|posture|to match|parallel|counterpart|differs";
        [[ -n "$ta" && "$ta" == "$tb" ]] \
        || unwrapped_file "$a" | grep -qiE "$pat" \
        || unwrapped_file "$b" | grep -qiE "$pat"'
    # The gate holds: unaccepted findings stay untouched.
    check "(f) the unaccepted fork is left unresolved"  file_unchanged tool_config-format.md
    check "(i) the Goal-altering candidate is not applied" \
      goal_unchanged tasks/tool_drop-legacy-module.md
    check "(l) the Acceptance-altering candidate is not applied" \
      section_unchanged tasks/tool_quiet-flag.md '## Acceptance'
    check "(k) the unaccepted ready task is untouched"   file_unchanged tool_summary-line.md
    check "no task's status was written by the reconcile pass"        no_status_writes
    check "every edited task's ## Goal is byte-identical to its pre-reconcile Goal" every_goal_unchanged
    check "an archive-inclusive lint run reports zero blocking findings" lint_archive_no_blocking
    note_agent_attest "the report groups the applied repairs by shape — single owner plus verify-only counterpart, refreshed anchor, recorded-rationale parameter change, completed enumeration, reconciled or recorded posture"
    note_agent_attest "the whole accepted set rode ONE writer: auto_shaper_task, with the staleness item (b) inside that escalated write rather than a parallel inline path"
    note_agent_attest "auto_reviewer_task proposed and auto_verifier_task approved backlog-coherence repair shapes, not only splits and relocations"
    ;;

  fix_coherence_reconcile_inline_staleness)
    check "the report was written to coherence-report.md"      report_present
    check "the run reports the inline writer mode"             rep_has 'inline'
    check "no auto_shaper_task escalation ran" \
      bash -c '! grep -qi "auto_shaper_task report\|tree shaping complete" "'"$REPORT"'"'
    # The two accepted staleness repairs land.
    check "(b) the stale anchor is refreshed to the shipped helper" \
      bash -c 'f="'"$TASKS"'/tool_clean-bar-note.md"; ! grep -q unreachable_clean_bar "$f" \
        && grep -q reachable_clean_bar "$f"'
    check "(b) updated bumped on the anchor-refresh file" updated_bumped tool_clean-bar-note.md
    check "(k) the additive Out of scope note landed" \
      grep -Fq '**Out of scope:**' "$TASKS/tool_summary-line.md"
    check "(k) updated bumped on the note file"          updated_bumped tool_summary-line.md
    # The change-significance rule: (k) keeps its ready status.
    check "(k) the ready task stays ready after the additive note" \
      bash -c '[[ "$(sed -n "/^---$/,/^---$/p" "'"$TASKS"'/tool_summary-line.md" \
        | grep -m1 "^status:" | sed "s/^status:[[:space:]]*//")" == "ready" ]]'
    check "(k) its ## Goal is byte-identical"            goal_unchanged tasks/tool_summary-line.md
    # (l) flagged for re-check, not applied and not re-stamped.
    check "(l) the Acceptance-altering repair is not applied" file_unchanged tool_quiet-flag.md
    check "(l) the report flags that task for re-check" \
      rep_near 'tool_quiet-flag' 're-check|recheck|check again|task_check'
    # The judgement calls the prompt withheld stay untouched.
    check "(a) the double-owned edit stays unrepaired (rename side)" file_unchanged tool_severity-label-rename.md
    check "(a) the double-owned edit stays unrepaired (docstring side)" file_unchanged tool_severity-label-docstring.md
    check "(c) the license-finding severity stays unrepaired" file_unchanged tool_missing-license-finding.md
    check "(d) the short sweep stays unrepaired"              file_unchanged tool_check-docstring-sweep.md
    check "(e) the path-check posture stays unrepaired"       file_unchanged tool_path-check-severity.md
    check "(e) the glob-check posture stays unrepaired"       file_unchanged tool_glob-check-severity.md
    check "(f) the fork stays unresolved"                     file_unchanged tool_config-format.md
    check "(i) the Goal-altering candidate is not applied" \
      goal_unchanged tasks/tool_drop-legacy-module.md
    check "no task's status was written by the reconcile pass"        no_status_writes
    check "every edited task's ## Goal is byte-identical to its pre-reconcile Goal" every_goal_unchanged
    check "an archive-inclusive lint run reports zero blocking findings" lint_archive_no_blocking
    note_agent_attest "the report names 'mode used: inline' and states that no escalation ran"
    note_agent_attest "the report flags tool_quiet-flag.md for re-check under the change-significance rule and states that the repair was NOT applied"
    note_agent_attest "no status was re-stamped: readiness stamps stay with task_check / task_auto_check"
    ;;

  fix_coherence_selector_scope)
    check "the assessment report was written to coherence-report.md" report_present
    check "assess-only: no tracked file was modified"                tracked_unmodified
    check "the selected set carries the tool-scope alpha task"       selected_has tool_alpha-flag
    check "the selected set carries the tool-scope beta task"        selected_has tool_beta-flag
    check "the selected set carries the tool-scope gamma task"       selected_has tool_gamma-flag
    check "the docs-scope delta task is outside the selected set"    selected_lacks docs_delta-page
    check "the docs-scope epsilon task is outside the selected set"  selected_lacks docs_epsilon-page
    check "the backlog still lints clean in archive mode"            lint_archive_no_blocking
    note_agent_attest "the report states that the scope filter named in the prompt is what narrowed the selected live set"
    ;;

  fix_coherence_selector_explicit_list)
    check "the assessment report was written to coherence-report.md" report_present
    check "assess-only: no tracked file was modified"                tracked_unmodified
    check "the selected set carries the first named task"            selected_has svc_alpha-retry
    check "the selected set carries the second named task"           selected_has svc_beta-retry
    check "the unnamed gamma task is outside the selected set"       selected_lacks svc_gamma-timeout
    check "the unnamed delta task is outside the selected set"       selected_lacks svc_delta-timeout
    check "the backlog still lints clean in archive mode"            lint_archive_no_blocking
    note_agent_attest "the report states that the explicit list named in the prompt is what fixed the selected live set, not the shared target file every task touches"
    ;;

  fix_coherence_selector_whole_tree)
    check "the assessment report was written to coherence-report.md" report_present
    check "the report assesses the live alpha task"                  selected_has core_alpha-cache
    check "the report assesses the live beta task"                   selected_has core_beta-cache
    check "the report assesses the live gamma task"                  selected_has docs_gamma-cache
    check "the archived sibling stays out of the selected live set"  selected_lacks core_omega-cache
    check "no live task's ## Goal moved"                             every_goal_unchanged
    check "the backlog still lints clean in archive mode"            lint_archive_no_blocking
    note_agent_attest "the prompt named no scope and no list, so the selected live set is the whole live tree by default — the assessment ran without any coherence or consistency phrasing in the prompt"
    note_agent_attest "the report carries a backlog-coherence assessment section beside the mechanical pass, reporting the clean case plainly when the joint read finds nothing"
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
