#!/usr/bin/env bash
# grade.sh — programmatic grader for the task_create open-decision evals.
#
# Usage:
#   grade.sh <eval_id> <sandbox_proj>
#
# Runs the deterministically checkable subset of each eval's expectations
# against the post-run sandbox and prints PASS/FAIL per check. Exits 0 only if
# every check passed.
#
# Two graded surfaces, because the rule under test has two halves. The written
# task file is read from the sandbox. The user-facing turn is read from the
# runner's captured `response.txt`: $RESPONSE_FILE when the runner exports it,
# otherwise the conventional `<sandbox_proj>/../../response.txt` that run.py's
# workspace layout puts it at. The dual written-and-surfaced obligation is not
# provable from the filesystem alone, so a surface check with no readable
# response FAILS rather than passing vacuously.
#
# Judgements that stay prose — whether a why-open clause is *true*, whether a
# recorded resolution is the *right* one — are the LLM-graded `expectations` in
# evals.json and the agent-attest notes below.

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
RESPONSE="${RESPONSE_FILE:-$target/../response.txt}"

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

iso_epoch() {
  local iso="$1"
  date -j -f "%Y-%m-%dT%H:%M:%S" "$iso" +%s 2>/dev/null \
    || date -d "$iso" +%s 2>/dev/null
}

lint_no_blocking() { python3 "$LINT" "$TASKS" >/dev/null 2>&1; }
lint_archive_no_blocking() { python3 "$LINT" "$TASKS" --include-archive >/dev/null 2>&1; }

# unwrapped <path> -> the file with hard wraps collapsed. Task bodies are
# hard-wrapped prose, so a line-based grep for a multi-word phrase silently
# misses it when the wrap falls mid-phrase. Any check matching more than one
# word reads the unwrapped text.
unwrapped() { tr '\n' ' ' < "$1" | tr -s ' '; }

# label_window <file> -> the unwrapped text from the "Open decision:" label to
# the next '## ' heading (or EOF), so options/default/why-open evidence is
# attributed to the label itself rather than to anything anywhere in the body.
#
# The containing section, not the label's first paragraph, is the right window.
# A conformant label is a multi-block structure — the labeled sentence, then an
# options list, then "Suggested default: ...", then the why-open clause — and a
# paragraph-bounded window sees only the first of those and fails a label that
# carries every part the rule requires. Same boundary the task-family harness
# uses to extract an **Out of scope:** block.
label_lines() { awk '/Open decision:/{f=1} /^## /{f=0} f' "$1"; }
label_window() { label_lines "$1" | tr '\n' ' ' | tr -s ' '; }

# enum_count <file> -> how many alternatives the label enumerates, read from
# whichever enumeration form the author used: bullet lines, "Option A"/"Option
# B" markers, or inline "(a)"/"(b)" markers. Takes the largest of the three
# rather than summing, so one bullet reading "- **Option A**" counts once.
#
# Structure, not vocabulary. Earlier passes of this grader asserted a
# particular phrasing of a particular option and failed conformant labels that
# said the same thing differently; what the rule actually requires is that the
# label put more than one path on the page.
enum_count() {
  local w bullets opts alpha
  bullets=$(label_lines "$1" | grep -cE '^[[:space:]]*[-*][[:space:]]')
  w=$(label_window "$1")
  opts=$(grep -oiE 'option [a-z0-9]\b' <<<"$w" | sort -uf | wc -l | tr -d ' ')
  alpha=$(grep -oE '\([a-d1-4]\)' <<<"$w" | sort -u | wc -l | tr -d ' ')
  printf '%s\n' "$bullets" "$opts" "$alpha" | sort -rn | head -1
}

# why_open_clause <file> -> the label carries a clause about the FORK being
# open, not merely reason language somewhere in the window.
#
# Anchoring on the subject matters. A bare reason-connective search matches
# "Suggested default: (a) stateless, because it keeps this task scoped ..." —
# the default explaining itself — and so passes a label whose why-open clause
# was deleted outright. The rule requires a clause saying why *this fork* is
# genuinely open, so the check looks for that subject: an explicit "Why open"
# lead-in, or a sentence whose subject is the fork or the decision.
#
# The tradeoff is deliberate. A conformant clause phrased without either
# subject marker would false-fail here; the operator then reads the label in
# grading.txt, and evals.json's expectations carry the judgement of whether the
# clause is true. Erring toward a check that can be missed beats one that
# cannot be failed.
why_open_clause() {
  window_has "$1" 'why open|why it is open|why this is open|open because|genuinely open|this fork|the fork (is|rests|remains|stays)|this decision (is|rests|remains|stays)|the decision (is|rests|remains|stays)|left (for|to) the user|user-owned'
}
window_has() { label_window "$1" | grep -qiE -- "$2"; }

# open_decision_count <file> -> how many "Open decision:" labels the body has.
open_decision_count() { grep -co 'Open decision:' "$1" 2>/dev/null || echo 0; }
has_no_open_decision() { ! grep -q 'Open decision:' "$1"; }
has_one_open_decision() { [[ "$(open_decision_count "$1")" -eq 1 ]]; }

# Surface half of the dual obligation: the user-facing turn is readable and
# carries the decision plus the resolve-now / defer offer step 9 makes.
response_readable() { [[ -s "$RESPONSE" ]]; }
response_has() { response_readable && grep -qiE -- "$1" "$RESPONSE"; }
response_surfaces_decision() { response_has 'open decision'; }
# The surface is an ask, not a mention: the turn names a suggested path and
# hands the choice back. Match the substance rather than step 9's literal
# "resolve it now or defer it" phrasing — a turn that offers the same choice in
# its own words has met the obligation, and grading the wording would score
# surface form over what the rule requires.
response_names_suggestion() { response_has 'suggest|default|recommend'; }
response_invites_the_user() {
  response_has "resolve|defer|say so|let me know|tell me|your call|if you (want|prefer|would rather|take|choose)"
}

file_untouched() {
  local f="$1"
  [[ -f "$f" ]] && [[ -z "$(find "$f" -newer "$marker" 2>/dev/null)" ]]
}

# Isolation fail-safe: the real repo's tasks/ must be untouched.
no_real_repo_writes() {
  [[ -z "$(find "$REPO_ROOT/tasks" -type f -newer "$marker" 2>/dev/null)" ]]
}

# --- universal ---------------------------------------------------------------

check "isolation: no writes to the real repo's tasks/ tree" no_real_repo_writes

open_files=( "$TASKS"/*.md )
one_open_task() { [[ -f "${open_files[0]}" && ${#open_files[@]} -eq 1 ]]; }
check "exactly one task file created under tasks/ (got ${#open_files[@]})" one_open_task
check "the new task lints clean"                                          lint_no_blocking

if one_open_task; then
  f="${open_files[0]}"
  status_open() { [[ "$(fm_field "$f" status)" == "open" ]]; }
  created_is_recent() {
    local e; e="$(iso_epoch "$(fm_field "$f" created)")"
    [[ -n "$e" ]] && (( e >= start_epoch - 120 && e <= start_epoch + 1800 ))
  }
  check "status is open"                                 status_open
  check "created is the real wall clock, not fabricated" created_is_recent
fi

# --- per-eval ----------------------------------------------------------------

case "$eval_id" in
  reconcile-recorded)
    check "the seeded archived precedent still lints clean" lint_archive_no_blocking
    check "TESTING.md untouched"    file_untouched "$proj/TESTING.md"
    check "render.py untouched"     file_untouched "$proj/src/report/render.py"
    if one_open_task; then
      f="${open_files[0]}"
      # The settled fork leaves no label at all: the tiers agreed, so this is a
      # reconciliation the body records rather than a decision it surfaces.
      records_stub_mechanism() {
        unwrapped "$f" | grep -qiE 'sys\.modules|patch\.dict|mock\.patch|stub'
      }
      cites_standing_rule() {
        unwrapped "$f" | grep -qiE 'TESTING\.md|standing repo rule|standing repo rules|testing guardrail|standing gate'
      }
      copied_rule_absent() {
        ! grep -Fq 'Leave the production import where it is' "$f"
      }
      check "the created task carries NO labeled open decision"        has_no_open_decision "$f"
      check "the body records the settled stubbing mechanism"          records_stub_mechanism
      check "the body cites the standing testing rule as its evidence" cites_standing_rule
      check "the standing rule is cited, not copied verbatim"          copied_rule_absent
    fi
    note_agent_attest "the response reports no open-decision residue in one line and finishes without prompting, per the create path's **Offer open-decision reconciliation** step"
    note_agent_attest "the recorded resolution is the one the evidence actually settles (stub the backend in sys.modules), not an arbitrary pick that happens to leave no label"
    ;;

  labeled-why-open)
    no_invented_guardrails() {
      [[ ! -e "$proj/CHARTER.md" && ! -e "$proj/ARCHITECTURE.md" \
        && ! -e "$proj/FEATURES.md" && ! -e "$proj/TESTING.md" ]]
    }
    check "no guardrail doc was invented to manufacture evidence" no_invented_guardrails
    if one_open_task; then
      f="${open_files[0]}"
      # The pivot concept plus more than one enumerated path.
      names_both_options() { window_has "$f" 'disabl' && [[ "$(enum_count "$f")" -ge 2 ]]; }
      names_a_default() { window_has "$f" 'default|suggest|recommend|starting point'; }
      carries_why_open() { why_open_clause "$f"; }
      check "exactly one labeled \"Open decision:\" in the body" has_one_open_decision "$f"
      check "the label names both options"                      names_both_options
      check "the label names a suggested default"               names_a_default
      check "the label carries a why-open clause"               carries_why_open
    fi
    check "the decision reached the user (response readable)"   response_readable
    check "the response surfaces the open decision"             response_surfaces_decision
    check "the response names a suggested path"                 response_names_suggestion
    check "the response hands the choice back to the user"      response_invites_the_user
    note_agent_attest "the why-open clause is true: the tiers really are silent on how aggressive the disable policy should be, and the clause says so rather than reciting the rule"
    note_agent_attest "the named default is a suggestion among evidence-equal options, not a path the evidence already picked"
    ;;

  guardrail-bound-surface)
    check "CHARTER.md untouched"      file_untouched "$proj/CHARTER.md"
    check "ARCHITECTURE.md untouched" file_untouched "$proj/ARCHITECTURE.md"
    if one_open_task; then
      f="${open_files[0]}"
      names_boundary_conflict() { window_has "$f" 'CHARTER|charter|guardrail|boundary'; }
      names_both_paths() {
        window_has "$f" 'rich' && window_has "$f" 'ANSI|escape'
      }
      # Reason-giving clause AND a named boundary, so this stays a distinct
      # assertion from names_boundary_conflict rather than a duplicate of it.
      carries_why_open() {
        why_open_clause "$f" && window_has "$f" 'CHARTER|ARCHITECTURE|guardrail|boundary'
      }
      check "exactly one labeled \"Open decision:\" in the body" has_one_open_decision "$f"
      check "the label names the guardrail boundary in play"     names_boundary_conflict
      check "the label names both crossing paths (rich / ANSI)"  names_both_paths
      check "the label carries a guardrail-bound why-open clause" carries_why_open
    fi
    check "the decision reached the user (response readable)"    response_readable
    check "the response surfaces the open decision"              response_surfaces_decision
    check "the response names a suggested path"                  response_names_suggestion
    check "the response hands the choice back to the user"       response_invites_the_user
    note_agent_attest "the fork was surfaced rather than auto-resolved — the agent did not silently pick a side on the strength of CHARTER.md outranking ARCHITECTURE.md"
    note_agent_attest "no guardrail doc was edited to clear the conflict; the decision is handed to the user with the boundary named"
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
