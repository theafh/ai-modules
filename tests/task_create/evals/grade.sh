#!/usr/bin/env bash
# grade.sh — programmatic grader for the task_create Decide-or-label and
# prior-art Novel evals.
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

# collapse_prose_wraps <path> -> the file with each block on one line: a
# hard-wrapped paragraph is joined, and so is a list item with its continuation
# lines, indented or lazy, the way CommonMark reads them. Headings, blank
# lines, and the frontmatter fence stay on their own lines, and every list
# item starts a new line, so a label window can still start at a lead-in, count
# bullets, and stop at the next heading. Joining the item matters because a
# wrapped Context bullet can carry its "(see Approach)" pointer on its
# continuation line, and the pointer test reads the whole block. A line that
# opens with a capitalised "Open decision:" lead-in also starts a new line
# when it runs on directly after a list item or a paragraph line with no blank
# line between, because an author who writes that lead-in at the start of a
# line is opening a label; a mid-sentence mention is lowercase and stays
# joined.
collapse_prose_wraps() {
  awk '
    function flush() { if (hold != "") print hold; hold = "" }
    /^#+[[:space:]]/ || /^---$/ || /^[[:space:]]*$/ {
      flush()
      print
      next
    }
    /^[[:space:]]*([-*+]|[0-9]+[.)])[[:space:]]/ || /^[[:space:]]*[*_]*Open decision[*_]*([[:space:]]*[(][^)]*[)])?[[:space:]]*[*_]*[[:space:]]*:/ {
      flush()
      hold = $0
      next
    }
    {
      if (hold == "") { hold = $0; next }
      line = $0
      sub(/^[[:space:]]+/, "", line)
      hold = hold " " line
    }
    END { flush() }
  ' "$1"
}

# OPEN_DECISION_LEAD_IN matches a labeled open-decision lead-in by substance,
# read case-insensitively against a line of collapse_prose_wraps output: the
# bare form "Open decision:" and a qualified form such as
# "**Open decision (guardrail-bound):**", with the colon after an optional
# parenthetical qualifier and optional emphasis. A lead-in opens a block, so the
# pattern is anchored to the start of the line after optional indentation, an
# ATX heading marker of level 2 or deeper, a blockquote marker, a list marker,
# and emphasis: "- **Open decision:**", "## Open decision:", "### Open
# decision:", and a paragraph opening "Open decision:" count, while a
# mid-sentence mention such as the Acceptance line "the path chosen in the open
# decision: either ..." is a pointer to the label and does not. Every real label
# in the recorded draws opens a line this way. Bracket expressions stand in for
# backslash escapes so the pattern survives awk's `-v` escape processing
# unchanged.
OPEN_DECISION_LEAD_IN='^[[:space:]]*([#][#]+[[:space:]]+)?(>[[:space:]]*)?([-*+][[:space:]]+|[0-9]+[.)][[:space:]]+)?[*_]*open decision[*_]*([[:space:]]*[(][^)]*[)])?[[:space:]]*[*_]*[[:space:]]*:'

# POINTS_AT_APPROACH matches a lead-in block that names the Approach section as
# the decision's home, such as the Context bullet
# "- Open decision: how colour is introduced (see Approach)." It is read
# case-sensitively, so the capitalised section name carries the match and the
# common noun "approach" does not.
POINTS_AT_APPROACH='(see|in|under|per|at)[[:space:]]+(the[[:space:]]+)?[*`#[:space:]]*Approach|Approach[*`]*[[:space:]]+(below|section|owns|carries|holds)'

# OWN_LABEL_PARTS matches, in a lowercased decision structure with the "either
# way" idiom removed, the options or default a label carries of its own:
# lettered or numbered markers, "Option A", an either-or, or a suggested or
# recommended default. The structure is the lead-in plus every following block
# until the next level-2 heading. A structure carrying any of them labels a
# decision of its own, whatever the lead-in says about Approach.
OWN_LABEL_PARTS='[(][a-d1-4][)]|option[[:space:]]+[a-d1-4]([^a-z]|$)|(^|[^a-z])either[[:space:]]|suggest|recommend|default[[:space:]]*:|default[[:space:]]+(is|would)'

# lead_in_kinds <file> -> every line of collapse_prose_wraps output, prefixed
# with its kind and a tab: "L" for a labeled open-decision lead-in, "P" for a
# pointer lead-in, "-" for any other line. A pointer is a lead-in outside
# `## Approach` that defers to Approach, naming it as the decision's home and
# carrying no options or default of its own, in a body whose `## Approach`
# section holds a lead-in for it to point at. It restates where the label lives
# rather than labeling a second decision, so it is no label. Without an
# Approach lead-in such a block points at nothing, and it stays the body's
# label. Options and a default often sit in blocks after the lead-in paragraph
# — bullets, then "Suggested default:" — so the own-parts test reads the whole
# structure from the lead-in to the next level-2 heading, the same span a
# label window would cover, rather than the lead-in line alone. A level-2
# heading that opens with the lead-in is a label and also starts its own
# section.
lead_in_kinds() {
  collapse_prose_wraps "$1" \
    | awk -v lead="$OPEN_DECISION_LEAD_IN" -v ptr="$POINTS_AT_APPROACH" -v own="$OWN_LABEL_PARTS" '
        function carries_own_parts(s) {
          s = tolower(s)
          gsub(/either[[:space:]]+way/, " ", s)
          return s ~ own
        }
        # Text from the lead-in through every following block until the next
        # level-2 heading (or EOF): the full decision structure.
        function structure_text(start,    j, t) {
          t = line[start]
          for (j = start + 1; j <= NR; j++) {
            if (line[j] ~ /^## /) break
            t = t " " line[j]
          }
          return t
        }
        { line[NR] = $0 }
        END {
          sec = ""; approach_holds_lead_in = 0
          for (i = 1; i <= NR; i++) {
            if (line[i] ~ /^## /) { sec = tolower(line[i]); continue }
            if (sec ~ /^## +approach/ && tolower(line[i]) ~ lead) approach_holds_lead_in = 1
          }
          sec = ""
          for (i = 1; i <= NR; i++) {
            kind = "-"
            if (line[i] ~ /^## /) sec = tolower(line[i])
            if (tolower(line[i]) ~ lead) {
              kind = "L"
              if (approach_holds_lead_in && sec !~ /^## +approach/ && line[i] ~ ptr &&
                  !carries_own_parts(structure_text(i))) kind = "P"
            }
            print kind "\t" line[i]
          }
        }'
}

# label_window <file> -> the unwrapped text from a labeled open-decision
# lead-in to the next '## ' heading (or EOF), so options/default/why-open
# evidence is attributed to the label itself rather than to anything anywhere
# in the body. The window starts only at an "L" line of lead_in_kinds, so a
# Context pointer or a mid-sentence mention never opens it. A '## ' heading
# closes the window before the label test runs, so a level-2 heading label
# opens its own window and every other '## ' heading ends one.
#
# The containing section, not the label's first paragraph, is the right window.
# A conformant label is a multi-block structure — the labeled sentence, then an
# options list, then "Suggested default: ...", then the why-open clause — and a
# paragraph-bounded window sees only the first of those and fails a label that
# carries every part the rule requires. Same boundary the task-family harness
# uses to extract an **Out of scope:** block.
label_lines() {
  lead_in_kinds "$1" \
    | awk '{ kind = substr($0, 1, 1); text = substr($0, 3) }
           text ~ /^## / { f = 0 }
           kind == "L" { f = 1 }
           f { print text }'
}
label_window() { label_lines "$1" | tr '\n' ' ' | tr -s ' '; }

# EITHER_OR_CLAUSE matches a two-path "either … or …" clause inside one
# sentence, such as the recorded label "Either auto-disable an endpoint after
# five consecutive deliveries …, or leave every registered endpoint eligible
# …". `([^.]|\.[^[:space:]])*` keeps the match inside one sentence while
# letting a file name such as `sender.py` sit in it. enum_count reads it only in
# the label's own lead-in block, where every recorded either-or label states
# its two paths, and only after removing the "either way" idiom, so a
# one-path label whose reason says "it works either way … or …" and an
# unrelated either-or later in the section add no options.
EITHER_OR_CLAUSE='(^|[^a-z])either[[:space:]]([^.]|\.[^[:space:]])*[^a-z]or[[:space:]]'

# lead_in_blocks <file> -> the "L" lines of lead_in_kinds, lowercased, with the
# "either way" idiom removed: the label's own lead-in block, the one place an
# either-or names the label's two paths.
lead_in_blocks() {
  lead_in_kinds "$1" \
    | awk 'substr($0, 1, 1) == "L" { s = tolower(substr($0, 3)); gsub(/either[[:space:]]+way/, " ", s); print s }'
}

# enum_count <file> -> how many alternatives the label enumerates, read from
# whichever enumeration form the author used: bullet lines, "Option A"/"Option
# B" markers (including bold `**Option A ...**` lead-ins), inline lettered or
# numbered markers in either case ("(a)"/"(b)" or "(A)"/"(B)"), or a two-path
# "either … or …" clause in the lead-in block, which names two options. Takes
# the largest of these rather than summing, so one bullet reading
# "- **Option A**" counts once.
#
# Structure, not vocabulary. Earlier passes of this grader asserted a
# particular phrasing of a particular option and failed conformant labels that
# said the same thing differently; what the rule actually requires is that the
# label put more than one path on the page. Recorded draws put both options on
# the page as uppercase "(A) … or (B) …" markers and as an "Either …, or …"
# sentence, and a reader counts two options in each, so both forms count here;
# a label naming one path in none of these forms still counts below two.
enum_count() {
  local w bullets opts alpha blocks either_or=0
  bullets=$(label_lines "$1" | grep -cE '^[[:space:]]*[-*][[:space:]]')
  w=$(label_window "$1")
  opts=$(grep -oiE '\*{0,2}option[[:space:]]+[a-z0-9]' <<<"$w" | sort -uf | wc -l | tr -d ' ')
  alpha=$(grep -oiE '\([a-d1-4]\)' <<<"$w" | sort -uf | wc -l | tr -d ' ')
  blocks=$(lead_in_blocks "$1")
  if grep -qE -- "$EITHER_OR_CLAUSE" <<<"$blocks"; then either_or=2; fi
  printf '%s\n' "$bullets" "$opts" "$alpha" "$either_or" | sort -rn | head -1
}

# why_open_clause <file> -> the label carries a clause saying why the fork is
# open. Match the part that must be present: a clause about the fork, the
# decision, the evidence, or the user's call — not a particular phrasing.
#
# Anchoring on that subject keeps a bare reason-connective search from matching
# "Suggested default: (a) stateless, because it keeps this task scoped ..." —
# the default explaining itself — and so passing a label whose why-open clause
# was deleted outright. Evidence-phrased clauses ("the evidence base does not
# settle it", "this is the user's call") satisfy the same part, and so does the
# guardrail-bound ground stated in its own terms: "guardrail-bound" followed
# directly by its own clause saying every or each path or option crosses a
# boundary, rewrites a guardrail document, or routes around one, as in
# "(guardrail-bound: every path crosses a boundary or rewrites a guardrail
# doc)" or "Why open: guardrail-bound — every path in play crosses …". Only a
# colon, comma, or dash, emphasis, and an optional "because" may sit between
# the ground's name and that clause. A "(guardrail-bound)" qualifier on the
# lead-in names the ground without stating it, and a default explaining itself
# with "because every other path crosses the charter boundary" in the same
# sentence is the default's rationale rather than the ground's own clause, so
# neither matches. `([^.;]|\.[^[:space:]])*` keeps the rest of the clause
# inside one sentence while letting a file name such as `CHARTER.md` sit in it.
WHY_OPEN_GUARDRAIL_BOUND='guardrail.?bound[)*_]*[[:space:]]*(:|,|—|–|-)?[)*_]*[[:space:]]*((because|since|as)[[:space:]]+)?(every|each|all|both|any)[[:space:]]+([a-z-]+[[:space:]]+){0,2}(path|option|route|choice)s?([^.;]|\.[^[:space:]])*(cross|rewrit|rout|break|violat)'
why_open_clause() {
  window_has "$1" "why open|why it is open|why this is open|open because|genuinely open|this fork|the fork (is|rests|remains|stays)|this decision (is|rests|remains|stays)|the decision (is|rests|remains|stays)|left (for|to) the user|user-owned|user.?s call|evidence (base )?(does not|cannot|fails to|will not) settle|evidence.*(silent|insufficient)|tiers.*(silent|do not settle|cannot settle)|does not settle|$WHY_OPEN_GUARDRAIL_BOUND"
}
window_has() { label_window "$1" | grep -qiE -- "$2"; }

# A label legitimately *names* a path in order to say it is unavailable
# ("because stdlib styling is unavailable"). Drop negated sentences before
# deciding, so only a surviving sentence counts as a path the label offers.
# Same shape as agent_spinner / guardrail_audit graders; "unavailable" /
# "lacks" join the shared negation set because a rejected styling path often
# uses those words rather than "no" / "not".
NEGATED='(^|[^a-z])(no|not|never|nor|neither)([^a-z]|$)|without|rather than|instead of|refus|declin|avoid|unavailab|lacks?|n'"'"'t|do(es)? not|cannot'
window_sentences() {
  label_window "$1" | sed -E 's/[[:space:]]+/ /g; s/([.!?]) /\1\n/g'
}
window_has_unnegated() {
  window_sentences "$1" | grep -Ei -- "$2" | grep -Eiqv -- "$NEGATED"
}

# open_decision_count <file> -> how many labeled open-decision lead-ins the
# body has, including a qualified lead-in, read from the "L" lines of
# lead_in_kinds. A mid-sentence mention and a Context pointer to the Approach
# label are not labels, so neither adds to the count. A body that surfaces no
# decision still reports zero.
open_decision_count() {
  local n
  n="$(lead_in_kinds "$1" | grep -c '^L' || true)"
  printf '%s\n' "${n:-0}"
}
has_no_open_decision() { [[ "$(open_decision_count "$1")" -eq 0 ]]; }
has_one_open_decision() { [[ "$(open_decision_count "$1")" -eq 1 ]]; }

# Surface half of the dual obligation: the user-facing turn is readable and
# carries the decision plus the resolve-now / defer offer step 9 makes.
response_readable() { [[ -s "$RESPONSE" ]]; }
response_has() {
  response_readable && unwrapped "$RESPONSE" | grep -qiE -- "$1"
}
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

# Isolation fail-safe: fixture names from this sandbox stay clear of the host
# tasks tree. The baseline is the isolated copy stage.sh took in the eval temp
# dir. A parallel edit of some other live task is outside the comparison.
no_real_repo_writes() {
  host_fixture_writes_clean "$target" "$REPO_ROOT" "$TASKS" "$marker" \
    && host_fixture_copy_clean "$target" "$REPO_ROOT" "$TASKS"
}

# --- universal ---------------------------------------------------------------

check "isolation: no writes to the real repo's tasks/ tree" no_real_repo_writes

# nullglob scoped to this one expansion, so a sandbox with no task file yields
# an empty list and reports "(got 0)" instead of keeping the unexpanded
# pattern as one element. Every read of the first element tests the count
# first or defaults, because a bare "${open_files[0]}" on an empty list aborts
# under `set -u`.
shopt -s nullglob
open_files=( "$TASKS"/*.md )
shopt -u nullglob
one_open_task() { (( ${#open_files[@]} == 1 )) && [[ -f "${open_files[0]:-}" ]]; }
check "exactly one task file created under tasks/ (got ${#open_files[@]})" one_open_task
check "the new task lints clean"                                          lint_no_blocking

if one_open_task; then
  f="${open_files[0]:-}"
  status_open() { [[ "$(fm_field "$f" status)" == "open" ]]; }
  created_is_recent() {
    local e; e="$(iso_epoch "$(fm_field "$f" created)")"
    [[ -n "$e" ]] && (( e >= start_epoch - 120 && e <= start_epoch + 1800 ))
  }
  check "status is open"                                 status_open
  check "created is the real wall clock, not fabricated" created_is_recent
  description_is_double_quoted() {
    local line
    line="$(awk 'BEGIN{n=0} /^---$/{n++; next} n==1 && /^description:/{print; exit}' "$f")"
    [[ "$line" =~ ^description:[[:space:]]*\".*\"[[:space:]]*$ ]]
  }
  check "description is written in double quotes"       description_is_double_quoted
fi

# --- per-eval ----------------------------------------------------------------

case "$eval_id" in
  reconcile-recorded)
    check "the seeded archived precedent still lints clean" lint_archive_no_blocking
    check "TESTING.md untouched"    file_untouched "$proj/TESTING.md"
    check "render.py untouched"     file_untouched "$proj/src/report/render.py"
    if one_open_task; then
      f="${open_files[0]:-}"
      # The settled fork leaves no label at all: the tiers agreed, so this is a
      # reconciliation the body records rather than a decision it surfaces.
      records_stub_mechanism() {
        unwrapped "$f" | grep -qiE 'sys\.modules|patch\.dict|mock\.patch|stub'
      }
      cites_standing_rule() {
        unwrapped "$f" | grep -qiE 'TESTING\.md|standing repo rule|standing repo rules|testing guardrail|standing gate'
      }
      copied_rule_absent() {
        ! unwrapped "$f" | grep -Fq 'Leave the production import where it is'
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
      f="${open_files[0]:-}"
      # The pivot concept plus more than one enumerated path.
      names_both_options() { window_has "$f" 'disabl' && [[ "$(enum_count "$f")" -ge 2 ]]; }
      names_a_default() { window_has "$f" 'default|suggest|recommend|starting point'; }
      carries_why_open() { why_open_clause "$f"; }
      check "exactly one labeled open-decision lead-in in the body" has_one_open_decision "$f"
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
      f="${open_files[0]:-}"
      names_boundary_conflict() { window_has "$f" 'CHARTER|charter|guardrail|boundary'; }
      # The second crossing path is styling without `rich`, and a label may
      # name it by any of its forms: raw ANSI or escape codes, CSI or SGR
      # sequences, a literal `\033` / `\x1b` / `\e[`, stdlib or
      # stock-interpreter styling, or a rewrite of ARCHITECTURE.md's
      # Presentation rule so `cli` may style its own output. Each form is tied
      # to styling or to that rewrite by adjacency, so a rich-only label that
      # merely says `rich` is not in the stdlib, that the stock interpreter or
      # the standard library has no colour support, that stdlib styling is
      # unavailable, cites the charter's "stock interpreter" wording, or names
      # the Presentation rule still fails. A stdlib or stock word counts only
      # as the modifier of a styling word ("stdlib or in-repo presentation",
      # "stock-interpreter terminal colouring") or as the source a styling
      # verb draws from ("colour from stock Python"), and only in an
      # affirmative sentence: window_has_unnegated drops a sentence that names
      # the form only to reject it.
      NON_RICH_PATH='ANSI|escape|(^|[^a-z])(csi|sgr)([^a-z]|$)|\\033|\\x1b|\\e\[|(stdlib|standard[ -]library|stock[ -](interpreter|python))([-/[:space:]]+(only|or|in-repo|terminal))*[-/[:space:]]+(styl|colou?r|presentation|ansi|escape)|(styl|colou?r)[a-z]*[[:space:]]+(from|with|via|using)[[:space:]]+(the[[:space:]]+)?(stdlib|standard[ -]library|stock[ -](interpreter|python))|(rewrit|amend|revis|relax|edit)[a-z]*[[:space:]]+(the[[:space:]]+)?([^[:space:]]*architecture[^[:space:]]*[[:space:]]+((doc|document)[^[:space:]]*[[:space:]]+)?)?[`*#[:space:]]*presentation'
      names_both_paths() {
        window_has "$f" 'rich' && window_has_unnegated "$f" "$NON_RICH_PATH"
      }
      # Reason-giving clause AND a named boundary, so this stays a distinct
      # assertion from names_boundary_conflict rather than a duplicate of it.
      carries_why_open() {
        why_open_clause "$f" && window_has "$f" 'CHARTER|ARCHITECTURE|guardrail|boundary'
      }
      check "exactly one labeled open-decision lead-in in the body" has_one_open_decision "$f"
      check "the label names the guardrail boundary in play"     names_boundary_conflict
      check "the label names both crossing paths (rich / non-rich styling)" names_both_paths
      check "the label carries a guardrail-bound why-open clause" carries_why_open
    fi
    check "the decision reached the user (response readable)"    response_readable
    check "the response surfaces the open decision"              response_surfaces_decision
    check "the response names a suggested path"                  response_names_suggestion
    check "the response hands the choice back to the user"       response_invites_the_user
    note_agent_attest "the fork was surfaced rather than auto-resolved — the agent did not silently pick a side on the strength of CHARTER.md outranking ARCHITECTURE.md"
    note_agent_attest "no guardrail doc was edited to clear the conflict; the decision is handed to the user with the boundary named"
    ;;

  related-precedent-novel)
    check "the seeded archived precedent still lints clean" lint_archive_no_blocking
    check "TESTING.md untouched"    file_untouched "$proj/TESTING.md"
    check "render.py untouched"     file_untouched "$proj/src/report/render.py"
    if one_open_task; then
      f="${open_files[0]:-}"
      # ## Context must carry a markdown link to the archived precedent. Match
      # the link target by the archived filename so any link text that points
      # at that file passes, and read only the Context section so a mention
      # elsewhere does not satisfy the cross-link obligation.
      context_links_precedent() {
        awk '
          /^## / { in_ctx = ($0 ~ /^##[[:space:]]+Context[[:space:]]*$/) }
          in_ctx { print }
        ' "$f" | tr '\n' ' ' | tr -s ' ' \
          | grep -qE '\[[^]]+\]\([^)]*report_format-severity-test\.md\)'
      }
      check "Context links the archived related precedent" context_links_precedent
    fi
    note_agent_attest "the prior-art gate classified the hit as Novel and wrote the task rather than stopping with a Partially covered ask"
    note_agent_attest "the Context link is to the archived format_severity precedent, not a relatedness-only plain-text mention"
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
