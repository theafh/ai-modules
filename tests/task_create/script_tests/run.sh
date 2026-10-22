#!/usr/bin/env bash
# Grader-level checks for tests/task_create/evals/grade.sh. Each grader case
# stages an eval with evals/stage.sh outside the checkout, installs a chosen
# task body under the sandbox's tasks/ (or leaves it empty), grades it, and
# reads one check's PASS or FAIL line from the grader's output.
#
# These cases back grader edits with evidence in the tree, as TESTING.md asks.
# The bodies carry the label forms recorded worker draws produced, so the forms
# stay covered after the workspace runs that showed them are gone: a widened
# check carries a case the old check failed although the property held, next to
# a control showing the check still fails a body that lacks the property.
# Further checks cover every fixture's git identity and the eval runner's stop
# on a failed or empty stage.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EVALS="$HERE/../evals"

pass=0
fail=0
check() {
  local label="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    pass=$((pass + 1))
    printf '  PASS  %s\n' "$label"
  else
    fail=$((fail + 1))
    printf '  FAIL  %s\n' "$label"
  fi
}

ROOT="$(mktemp -d "${TMPDIR:-/tmp}/task_create_script_tests.XXXXXX")"
trap 'rm -rf "$ROOT"' EXIT
BODIES="$ROOT/bodies"
mkdir -p "$BODIES"

# A task name the host backlog never carries, so the grader's host-tree guard
# has nothing to compare it against.
TASK_NAME="report_grader-case.md"

# install_task <dest> <body file> -> a task file with valid frontmatter whose
# body is the named body file.
install_task() {
  local dest=$1 body=$2 stamp
  stamp="$(date +%Y-%m-%dT%H:%M:%S)"
  {
    printf -- '---\n'
    printf 'description: "Grader case body for the task_create script tests."\n'
    printf 'scope: "grader case"\n'
    printf 'created: %s\n' "$stamp"
    printf 'updated: %s\n' "$stamp"
    printf 'status: open\n'
    printf 'reported-by: Evals\n'
    printf -- '---\n\n'
    cat "$body"
  } > "$dest"
}

# grade_output <eval_id> <body file|-> -> the grader's output on a freshly
# staged sandbox carrying that body as its one task file, or no task file for
# "-". No response is readable, so the response checks fail; no case here
# reads them.
grade_output() {
  local eval_id=$1 body=$2 target
  target="$(mktemp -d "$ROOT/$eval_id.XXXXXX")"
  bash "$EVALS/stage.sh" "$eval_id" "$target" >/dev/null || return 1
  if [[ "$body" != "-" ]]; then
    install_task "$target/proj/tasks/$TASK_NAME" "$body"
  fi
  RESPONSE_FILE="$ROOT/no-response.txt" bash "$EVALS/grade.sh" "$eval_id" "$target/proj" 2>&1
}

# grader_says <eval_id> <body file|-> <check label> <PASS|FAIL> -> the grader
# prints that verdict for that check, matched on the whole line.
grader_says() {
  local eval_id=$1 body=$2 label=$3 want=$4 got
  got="$(grade_output "$eval_id" "$body" \
    | awk -v l="$label" '$0 == "  PASS  " l { print "PASS" } $0 == "  FAIL  " l { print "FAIL" }')"
  [[ "$got" == "$want" ]]
}

ONE_LABEL="exactly one labeled open-decision lead-in in the body"
NO_LABEL="the created task carries NO labeled open decision"
BOTH_OPTIONS="the label names both options"
GB_WHY_OPEN="the label carries a guardrail-bound why-open clause"
WHY_OPEN="the label carries a why-open clause"
BOTH_PATHS="the label names both crossing paths (rich / non-rich styling)"
ZERO_FILES="exactly one task file created under tasks/ (got 0)"

# --- bodies ------------------------------------------------------------------

# Shared Goal and Context for the guardrail-bound-surface bodies.
gb_head() {
  cat <<'EOF'
# Add coloured severity markers to the report output

## Goal

Warnings and errors in the report command's output carry a colour marker, so
they stand out from the ordinary rows.

## Context

`src/report/cli.py` writes plain rows today, and `CHARTER.md` and
`ARCHITECTURE.md` both constrain how colour can enter that output.
EOF
}

# One real Approach label with the guardrail-bound reason, and an Acceptance
# line that mentions the label mid-sentence.
{
  gb_head
  cat <<'EOF'

## Approach

**Open decision (guardrail-bound):** how the markers get their colour.

- (A) Add `rich` and hand it markup from `cli` (crosses `CHARTER.md`
  **No third-party runtime dependency.**).
- (B) Write raw ANSI codes from `cli` itself (crosses `ARCHITECTURE.md`
  **Presentation**).

Suggested default: (B), with the Presentation rule rewritten to allow it.
(guardrail-bound: every path crosses a boundary or rewrites a guardrail doc)

## Acceptance

- The tree matches the path chosen in the open decision: either no new
  third-party runtime dependency appears, or the amended guardrail doc names
  the approved path.
EOF
} > "$BODIES/acceptance_pointer.md"

# One real Approach label, preceded by a Context bullet pointing at it.
{
  cat <<'EOF'
# Add coloured severity markers to the report output

## Goal

Warnings and errors in the report command's output carry a colour marker, so
they stand out from the ordinary rows.

## Context

- `src/report/cli.py` writes plain rows today.
- Open decision: how the colour path is chosen (see Approach).

## Approach

Open decision: how the markers get their colour.

- (A) Add `rich` and hand it markup from `cli` (crosses `CHARTER.md`
  **No third-party runtime dependency.**).
- (B) Write raw ANSI codes from `cli` itself (crosses `ARCHITECTURE.md`
  **Presentation**).

Suggested default: (B).
(guardrail-bound: every path crosses a boundary or rewrites a guardrail doc)

## Acceptance

- Warning and error rows carry a colour marker, and ordinary rows stay plain.
EOF
} > "$BODIES/context_pointer.md"

# A Context bullet whose "(see Approach)" pointer sits on its wrapped
# continuation line, beside one real Approach label.
{
  gb_head
  cat <<'EOF'

- Open decision: how the colour path is chosen, which the label
  in Approach carries (see Approach).

## Approach

Open decision: how the markers get their colour.

- (A) Add `rich` and hand it markup from `cli` (crosses `CHARTER.md`
  **No third-party runtime dependency.**).
- (B) Write raw ANSI codes from `cli` itself (crosses `ARCHITECTURE.md`
  **Presentation**).

Suggested default: (B).
(guardrail-bound: every path crosses a boundary or rewrites a guardrail doc)

## Acceptance

- Warning and error rows carry a colour marker, and ordinary rows stay plain.
EOF
} > "$BODIES/wrapped_context_pointer.md"

# The label as an ATX heading of level 3.
{
  gb_head
  cat <<'EOF'

## Approach

### Open decision: how the markers get their colour

- (A) Add `rich` and hand it markup from `cli` (crosses `CHARTER.md`
  **No third-party runtime dependency.**).
- (B) Write raw ANSI codes from `cli` itself (crosses `ARCHITECTURE.md`
  **Presentation**).

Suggested default: (B). Why open: guardrail-bound, every path crosses a
boundary or rewrites a guardrail doc.

## Acceptance

- Warning and error rows carry a colour marker, and ordinary rows stay plain.
EOF
} > "$BODIES/heading_label.md"

# The guardrail-bound reason as the label's only why-open text, with no
# pointer anywhere, in the list-item form of the lead-in.
{
  gb_head
  cat <<'EOF'

## Approach

- **Open decision:** how the markers get their colour. (A) Add `rich` and
  hand it markup (crosses `CHARTER.md` **No third-party runtime
  dependency.**); (B) write raw ANSI codes from `cli` (crosses
  `ARCHITECTURE.md` **Presentation**). Suggested default: (B)
  (guardrail-bound: every path crosses a boundary or rewrites a guardrail doc).

## Acceptance

- Warning and error rows carry a colour marker, and ordinary rows stay plain.
EOF
} > "$BODIES/gb_reason_only.md"

# A qualified lead-in whose only reason-like text is the default explaining
# itself: the qualifier names the ground without stating it.
{
  gb_head
  cat <<'EOF'

## Approach

**Open decision (guardrail-bound):** how the markers get their colour.

- (A) Add `rich` and hand it markup from `cli` (crosses `CHARTER.md`
  **No third-party runtime dependency.**).
- (B) Write raw ANSI codes from `cli` itself (crosses `ARCHITECTURE.md`
  **Presentation**).

Suggested default: (B), because it keeps the package dependency-free.

## Acceptance

- Warning and error rows carry a colour marker, and ordinary rows stay plain.
EOF
} > "$BODIES/gb_default_only.md"

# gb_paths_body <file> <option B line> -> a guardrail-bound body whose label
# names `rich` as option A and the given text as option B.
gb_paths_body() {
  local out=$1 option_b=$2
  {
    gb_head
    cat <<'EOF'

## Approach

**Open decision (guardrail-bound):** how the markers get their colour.

- (A) Add `rich` and hand it markup from `cli` (crosses `CHARTER.md`
  **No third-party runtime dependency.**).
EOF
    printf '%s\n' "$option_b"
    cat <<'EOF'

Suggested default: (B). Why open: guardrail-bound, every path crosses a
boundary or rewrites a guardrail doc.

## Acceptance

- Warning and error rows carry a colour marker, and ordinary rows stay plain.
EOF
  } > "$out"
}

gb_paths_body "$BODIES/paths_csi.md" \
  '- (B) Wrap the warning label in CSI `33m` … `0m` from `cli` itself (crosses `ARCHITECTURE.md` **Presentation**).'
gb_paths_body "$BODIES/paths_stdlib_presentation.md" \
  '- (B) Stdlib or in-repo presentation only, and rewrite `ARCHITECTURE.md` `## Presentation` so `cli` may style its own rows.'
gb_paths_body "$BODIES/paths_presentation_rewrite.md" \
  '- (B) Amend `ARCHITECTURE.md` **Presentation** so `cli` may colour its own rows, then colour them there.'

# A label whose every option is a `rich` path. It cites the charter's
# stock-interpreter wording and the Presentation rule by name without naming
# styling that leaves `rich` out.
{
  gb_head
  cat <<'EOF'

## Approach

**Open decision (guardrail-bound):** how `rich` enters the package.

- (A) Declare `rich` as a runtime dependency (crosses `CHARTER.md`, which
  keeps the tool on a stock interpreter).
- (B) Vendor `rich` into the package (crosses the same boundary).

Suggested default: (A), because `ARCHITECTURE.md` **Presentation** already
names the `rich` adapter. Why open: guardrail-bound, every path crosses a
boundary.

## Acceptance

- Warning and error rows carry a colour marker, and ordinary rows stay plain.
EOF
} > "$BODIES/paths_rich_only.md"

# A label whose every option is a `rich` path, one of them saying `rich` is not
# in the stdlib.
{
  gb_head
  cat <<'EOF'

## Approach

**Open decision (guardrail-bound):** how `rich` enters the package.

- (A) Declare `rich` as a runtime dependency, since it is not in the stdlib
  (crosses `CHARTER.md` **No third-party runtime dependency.**).
- (B) Vendor `rich` into the package (crosses the same boundary).

Suggested default: (A). Why open: guardrail-bound, every path crosses a
boundary.

## Acceptance

- Warning and error rows carry a colour marker, and ordinary rows stay plain.
EOF
} > "$BODIES/paths_rich_only_stdlib.md"

# Rich-only labels whose second `rich` option mentions the stdlib, the stock
# interpreter, or the standard library beside a styling word without naming
# styling that leaves `rich` out.
gb_paths_body "$BODIES/rich_only_stdlib_no_colour.md" \
  '- (B) Vendor `rich` into the package, because the stdlib has no colour support.'
gb_paths_body "$BODIES/rich_only_stdlib_styling_unavailable.md" \
  '- (B) Vendor `rich`, crossing the same boundary, because stdlib styling is unavailable.'
gb_paths_body "$BODIES/rich_only_stock_can_style.md" \
  '- (B) Vendor `rich` so the stock interpreter can style the markers.'
gb_paths_body "$BODIES/rich_only_standard_library_no_colour.md" \
  '- (B) Vendor `rich`, since the standard library offers no colour support.'
gb_paths_body "$BODIES/rich_only_colour_on_standard.md" \
  '- (B) Route the markup through `rich` and colour on the standard console adapter.'

# One sentence carrying the lead-in, both options, and a default explaining
# itself with "because every other path crosses …": the default's rationale,
# not the ground's own clause.
{
  gb_head
  cat <<'EOF'

## Approach

**Open decision (guardrail-bound):** how the markers get their colour — (A)
add `rich` and hand it markup (crosses `CHARTER.md` **No third-party runtime
dependency.**), or (B) write raw ANSI codes from `cli` (crosses
`ARCHITECTURE.md` **Presentation**) — suggested default (B), because every
other path crosses the hard charter boundary.

## Acceptance

- Warning and error rows carry a colour marker, and ordinary rows stay plain.
EOF
} > "$BODIES/gb_one_sentence_default.md"

# The label as a level-2 heading section of its own.
{
  gb_head
  cat <<'EOF'

## Approach

Colour the severity column in `emit` along the path the decision below picks.

## Open decision (guardrail-bound): how the markers get their colour

- (A) Add `rich` and hand it markup from `cli` (crosses `CHARTER.md`
  **No third-party runtime dependency.**).
- (B) Write raw ANSI codes from `cli` itself (crosses `ARCHITECTURE.md`
  **Presentation**).

Suggested default: (B). Why open: guardrail-bound, every path crosses a
boundary or rewrites a guardrail doc.

## Acceptance

- Warning and error rows carry a colour marker, and ordinary rows stay plain.
EOF
} > "$BODIES/heading2_label.md"

# Shared Goal for the labeled-why-open bodies.
lwo_goal() {
  cat <<'EOF'
# Retry outbound webhook delivery with exponential backoff

## Goal

`send` in `src/hooks/sender.py` retries a failed delivery on an exponential
backoff schedule instead of giving up after one attempt.
EOF
}

# lwo_label <question> <option a> <option b> <tail> -> one labeled open
# decision in the plain-paragraph form.
lwo_label() {
  printf 'Open decision: %s\n\n- (a) %s\n- (b) %s\n\n%s\n' "$1" "$2" "$3" "$4"
}

# Two real labels, both in Approach.
{
  lwo_goal
  printf '\n## Context\n\nThe sender attempts each delivery once today.\n\n## Approach\n\n'
  lwo_label "whether an endpoint that keeps failing gets auto-disabled." \
    "Auto-disable it after five consecutive failures." \
    "Keep retrying it on the backoff schedule." \
    "Suggested default: (b). Why open: the call rests on the user's own risk appetite."
  printf '\n'
  lwo_label "how long the backoff cap is." "One minute." "Ten minutes." \
    "Suggested default: (a). Why open: no evidence tier names a cap."
  printf '\n## Acceptance\n\n- A failed delivery is retried on the backoff schedule.\n'
} > "$BODIES/two_labels.md"

# A real label in Context that names no Approach home, beside the Approach
# label: two labels, so the pointer rule leaves the Context one counted.
{
  lwo_goal
  printf '\n## Context\n\n'
  printf -- '- Open decision: whether each retry is logged. (a) Log every attempt; (b) log only the final failure. Suggested default: (b).\n'
  printf '\n## Approach\n\n'
  lwo_label "whether an endpoint that keeps failing gets auto-disabled." \
    "Auto-disable it after five consecutive failures." \
    "Keep retrying it on the backoff schedule." \
    "Suggested default: (b). Why open: the call rests on the user's own risk appetite."
  printf '\n## Acceptance\n\n- A failed delivery is retried on the backoff schedule.\n'
} > "$BODIES/context_label_and_approach_label.md"

# A lone Context lead-in naming Approach as its home while Approach holds no
# lead-in: it points at nothing, so it stays the body's one label.
{
  lwo_goal
  printf '\n## Context\n\n'
  printf -- '- Open decision: whether an endpoint that keeps failing gets auto-disabled (see Approach). (a) Auto-disable it after five consecutive failures; (b) keep retrying it. Suggested default: (b).\n'
  printf '\n## Approach\n\nAdd the backoff loop around the single `urlopen` call in `send`.\n'
  printf '\n## Acceptance\n\n- A failed delivery is retried on the backoff schedule.\n'
} > "$BODIES/lone_context_lead_in.md"

# A label whose only reason-like text is the suggested default explaining
# itself.
{
  lwo_goal
  printf '\n## Context\n\nThe sender attempts each delivery once today.\n\n## Approach\n\n'
  lwo_label "whether an endpoint that keeps failing gets auto-disabled." \
    "Auto-disable it after five consecutive failures." \
    "Keep retrying it on the backoff schedule." \
    "Suggested default: (a), because it keeps a dead endpoint from consuming retries."
  printf '\n## Acceptance\n\n- A failed delivery is retried on the backoff schedule.\n'
} > "$BODIES/lwo_default_only.md"

# lwo_inline_body <file> <label paragraph> -> a labeled-why-open body whose
# Approach holds the given one-paragraph label and nothing else, so no bullet
# reaches the label window.
lwo_inline_body() {
  local out=$1 label=$2
  {
    lwo_goal
    printf '\n## Context\n\nThe sender attempts each delivery once today.\n\n## Approach\n\n'
    printf '%s\n' "$label"
    printf '\n## Acceptance\n\n- A failed delivery is retried on the backoff schedule.\n'
  } > "$out"
}

# Uppercase inline markers, as three recorded draws wrote them, without an
# "either" so the markers alone carry the count.
lwo_inline_body "$BODIES/options_upper_markers.md" \
  '**Open decision:** what happens after a run of consecutive failed deliveries for one endpoint: (A) auto-disable that endpoint so later `send` calls skip it until it is re-enabled, or (B) leave the endpoint registered and eligible so future deliveries keep retrying with backoff. Suggested default: (B), because the registry today has no enabled flag or failure counter. Why open: the choice is ops risk appetite the authoring material cannot settle.'

# A prose "Either …, or …" sentence with no markers, as one recorded draw wrote
# it.
lwo_inline_body "$BODIES/options_either_or.md" \
  '**Open decision:** Either auto-disable an endpoint after five consecutive deliveries that exhaust the schedule, recording that on the endpoint so `send` returns `None` without calling `urlopen` until `register` replaces that name, or leave every registered endpoint eligible so each later delivery runs the schedule again. Suggested default: leave the endpoint eligible. Why open: the requester reserved this choice, and it is a risk-appetite call on which the standing repo rules and the current sender and registry are silent.'

# A label that names only one path.
lwo_inline_body "$BODIES/options_one_path.md" \
  '**Open decision:** whether to auto-disable an endpoint that keeps failing. Suggested default: auto-disable it after five consecutive failures. Why open: the call rests on the user'"'"'s own risk appetite.'

# A one-path label whose reason uses the "either way" idiom with a later "or".
lwo_inline_body "$BODIES/options_either_way.md" \
  '**Open decision:** whether to auto-disable an endpoint that keeps failing. Suggested default: auto-disable it after five consecutive failures. Why open: the sender works either way, so the call rests on the user'"'"'s risk appetite or on an operator rule.'

# A one-path label followed, in the same Approach section, by an unrelated
# either-or about where the code goes.
lwo_inline_body "$BODIES/options_either_or_elsewhere.md" \
  '**Open decision:** whether to auto-disable an endpoint that keeps failing. Suggested default: auto-disable it after five consecutive failures. Why open: the call rests on the user'"'"'s own risk appetite.

Put the backoff loop in either `send` or a new `retry` helper.'

# A real Context label carrying its own options and default that also mentions
# Approach, beside the Approach label: two labels.
{
  lwo_goal
  printf '\n## Context\n\n'
  printf -- '- Open decision: whether each retry is logged, which the logging step in Approach follows. (a) Log every attempt; (b) log only the final failure. Suggested default: (b).\n'
  printf '\n## Approach\n\n'
  lwo_label "whether an endpoint that keeps failing gets auto-disabled." \
    "Auto-disable it after five consecutive failures." \
    "Keep retrying it on the backoff schedule." \
    "Suggested default: (b). Why open: the call rests on the user's own risk appetite."
  printf '\n## Acceptance\n\n- A failed delivery is retried on the backoff schedule.\n'
} > "$BODIES/context_label_mentions_approach.md"

# A real Context decision whose options and default sit in blocks after the
# lead-in paragraph that names Approach as where implementation follows, beside
# the Approach label: two labels. The pointer rule must read the full structure,
# not the lead-in paragraph alone, or the Context decision is discarded.
{
  lwo_goal
  printf '\n## Context\n\n'
  printf 'Open decision: whether retries are logged, which the implementation in Approach will follow.\n\n'
  printf -- '- (A) Log every attempt.\n'
  printf -- '- (B) Log only final failures.\n\n'
  printf 'Suggested default: (B). Why open: no evidence tier settles the logging policy.\n'
  printf '\n## Approach\n\n'
  lwo_label "whether an endpoint that keeps failing gets auto-disabled." \
    "Auto-disable it after five consecutive failures." \
    "Keep retrying it on the backoff schedule." \
    "Suggested default: (b). Why open: the call rests on the user's own risk appetite."
  printf '\n## Acceptance\n\n- A failed delivery is retried on the backoff schedule.\n'
} > "$BODIES/context_multiblock_label.md"

# Shared Goal and Context for the reconcile-recorded bodies, which must carry
# no label at all.
rr_head() {
  cat <<'EOF'
# Test the report helpers without installing the chart backend

## Goal

`format_severity` and `truncate_cell` in `src/report/render.py` are covered
by unit tests that run under the standing offline gate.

## Context

`src/report/render.py` imports the chart backend at module scope.
EOF
}

# A level-2 heading label.
{
  rr_head
  cat <<'EOF'

## Approach

Register a stub for the backend in `sys.modules` before importing the module.

## Open decision: whether the tests live in one file or two

- (a) One test file for both helpers.
- (b) One test file per helper.

Suggested default: (a).

## Acceptance

- Both helpers are covered by passing unit tests.
EOF
} > "$BODIES/rr_heading2_label.md"

# A label line running on directly after a list item, with no blank line.
{
  rr_head
  cat <<'EOF'

## Approach

- Register a stub for the backend in `sys.modules` before the import.
Open decision: whether the tests live in one file or two. (a) One test file
for both helpers; (b) one test file per helper. Suggested default: (a).

## Acceptance

- Both helpers are covered by passing unit tests.
EOF
} > "$BODIES/rr_run_on_label.md"

# --- the one-label count reads only block-start lead-ins ---------------------

check "an Acceptance line naming the label mid-sentence leaves one label" \
  grader_says guardrail-bound-surface "$BODIES/acceptance_pointer.md" "$ONE_LABEL" PASS
check "a Context bullet pointing at the Approach label leaves one label" \
  grader_says guardrail-bound-surface "$BODIES/context_pointer.md" "$ONE_LABEL" PASS
check "two real labels in Approach fail the one-label check" \
  grader_says labeled-why-open "$BODIES/two_labels.md" "$ONE_LABEL" FAIL
check "a real Context label beside the Approach label fails the one-label check" \
  grader_says labeled-why-open "$BODIES/context_label_and_approach_label.md" "$ONE_LABEL" FAIL
check "a lone Context lead-in with no Approach label stays the one label" \
  grader_says labeled-why-open "$BODIES/lone_context_lead_in.md" "$ONE_LABEL" PASS
check "a Context pointer wrapped onto its continuation line leaves one label" \
  grader_says guardrail-bound-surface "$BODIES/wrapped_context_pointer.md" "$ONE_LABEL" PASS
check "a level-3 heading label counts as the one label" \
  grader_says guardrail-bound-surface "$BODIES/heading_label.md" "$ONE_LABEL" PASS
check "a level-3 heading label opens the window for the why-open check" \
  grader_says guardrail-bound-surface "$BODIES/heading_label.md" "$GB_WHY_OPEN" PASS
check "a real Context label that mentions Approach still counts as a second label" \
  grader_says labeled-why-open "$BODIES/context_label_mentions_approach.md" "$ONE_LABEL" FAIL
check "a multi-block Context decision beside Approach fails the one-label check" \
  grader_says labeled-why-open "$BODIES/context_multiblock_label.md" "$ONE_LABEL" FAIL
check "a level-2 heading label counts as the one label" \
  grader_says guardrail-bound-surface "$BODIES/heading2_label.md" "$ONE_LABEL" PASS
check "a level-2 heading label opens the window for the why-open check" \
  grader_says guardrail-bound-surface "$BODIES/heading2_label.md" "$GB_WHY_OPEN" PASS
check "a level-2 heading label fails the no-label check" \
  grader_says reconcile-recorded "$BODIES/rr_heading2_label.md" "$NO_LABEL" FAIL
check "a label running on after a list item fails the no-label check" \
  grader_says reconcile-recorded "$BODIES/rr_run_on_label.md" "$NO_LABEL" FAIL

# --- the both-options check reads every recorded enumeration form ------------

check "uppercase (A)/(B) inline markers pass the both-options check" \
  grader_says labeled-why-open "$BODIES/options_upper_markers.md" "$BOTH_OPTIONS" PASS
check "an either-or sentence passes the both-options check" \
  grader_says labeled-why-open "$BODIES/options_either_or.md" "$BOTH_OPTIONS" PASS
check "a label naming one path fails the both-options check" \
  grader_says labeled-why-open "$BODIES/options_one_path.md" "$BOTH_OPTIONS" FAIL
check "an either-way idiom in a one-path label fails the both-options check" \
  grader_says labeled-why-open "$BODIES/options_either_way.md" "$BOTH_OPTIONS" FAIL
check "an either-or outside the lead-in block fails the both-options check" \
  grader_says labeled-why-open "$BODIES/options_either_or_elsewhere.md" "$BOTH_OPTIONS" FAIL

# --- the why-open check accepts the guardrail-bound ground -------------------

check "the guardrail-bound reason passes why-open beside an Acceptance mention" \
  grader_says guardrail-bound-surface "$BODIES/acceptance_pointer.md" "$GB_WHY_OPEN" PASS
check "the guardrail-bound reason passes why-open behind a Context pointer" \
  grader_says guardrail-bound-surface "$BODIES/context_pointer.md" "$GB_WHY_OPEN" PASS
check "the guardrail-bound reason alone passes the why-open check" \
  grader_says guardrail-bound-surface "$BODIES/gb_reason_only.md" "$GB_WHY_OPEN" PASS
check "a default explaining itself fails the why-open check" \
  grader_says labeled-why-open "$BODIES/lwo_default_only.md" "$WHY_OPEN" FAIL
check "a guardrail-bound qualifier with a self-explaining default fails why-open" \
  grader_says guardrail-bound-surface "$BODIES/gb_default_only.md" "$GB_WHY_OPEN" FAIL
check "a one-sentence label whose default explains itself fails why-open" \
  grader_says guardrail-bound-surface "$BODIES/gb_one_sentence_default.md" "$GB_WHY_OPEN" FAIL

# --- the both-paths check reads the non-rich path by substance ---------------

check "rich and a CSI 33m path pass the both-paths check" \
  grader_says guardrail-bound-surface "$BODIES/paths_csi.md" "$BOTH_PATHS" PASS
check "rich and a stdlib path rewriting Presentation pass the both-paths check" \
  grader_says guardrail-bound-surface "$BODIES/paths_stdlib_presentation.md" "$BOTH_PATHS" PASS
check "rich and an amended Presentation rule pass the both-paths check" \
  grader_says guardrail-bound-surface "$BODIES/paths_presentation_rewrite.md" "$BOTH_PATHS" PASS
check "a label naming only rich paths fails the both-paths check" \
  grader_says guardrail-bound-surface "$BODIES/paths_rich_only.md" "$BOTH_PATHS" FAIL
check "a rich-only label saying rich is not in the stdlib fails the both-paths check" \
  grader_says guardrail-bound-surface "$BODIES/paths_rich_only_stdlib.md" "$BOTH_PATHS" FAIL
check "rich-only: the stdlib has no colour support fails the both-paths check" \
  grader_says guardrail-bound-surface "$BODIES/rich_only_stdlib_no_colour.md" "$BOTH_PATHS" FAIL
check "rich-only: stdlib styling is unavailable fails the both-paths check" \
  grader_says guardrail-bound-surface "$BODIES/rich_only_stdlib_styling_unavailable.md" "$BOTH_PATHS" FAIL
check "rich-only: so the stock interpreter can style fails the both-paths check" \
  grader_says guardrail-bound-surface "$BODIES/rich_only_stock_can_style.md" "$BOTH_PATHS" FAIL
check "rich-only: the standard library offers no colour fails the both-paths check" \
  grader_says guardrail-bound-surface "$BODIES/rich_only_standard_library_no_colour.md" "$BOTH_PATHS" FAIL
check "rich-only: colour on the standard console adapter fails the both-paths check" \
  grader_says guardrail-bound-surface "$BODIES/rich_only_colour_on_standard.md" "$BOTH_PATHS" FAIL

# --- an empty sandbox reports zero files -------------------------------------

check "a sandbox with no task file fails the one-file check with (got 0)" \
  grader_says labeled-why-open - "$ZERO_FILES" FAIL
# The grader exits 1 on its failed checks, so its output is captured before the
# match rather than piped, where pipefail would report that exit status.
reaches_summary() {
  local out
  out="$(grade_output labeled-why-open -)"
  grep -qE '^eval-labeled-why-open: [0-9]+ pass, [0-9]+ fail$' <<<"$out"
}
check "the grader runs to its summary line on an empty sandbox" reaches_summary

# --- every fixture gives its sandbox a git identity --------------------------

# fixture_identity_clean <eval_id> -> the staged sandbox is a git repo whose
# user.name is Evals and whose tree is fully committed, so the create path's
# name chain resolves reported-by without asking.
fixture_identity_clean() {
  local eval_id=$1 target
  target="$(mktemp -d "$ROOT/identity-$eval_id.XXXXXX")"
  bash "$EVALS/stage.sh" "$eval_id" "$target" >/dev/null || return 1
  [[ "$(git -C "$target/proj" config user.name)" == "Evals" ]] \
    && [[ -z "$(git -C "$target/proj" status --porcelain)" ]]
}

eval_ids="$(python3 -c 'import json, sys
for e in json.load(open(sys.argv[1]))["evals"]:
    print(e["id"])' "$EVALS/evals.json")"
while IFS= read -r eval_id; do
  [[ -n "$eval_id" ]] || continue
  check "the $eval_id sandbox has git identity Evals and a clean tree" \
    fixture_identity_clean "$eval_id"
done <<<"$eval_ids"

# The eval runner's stage() raises on a stage.sh that fails, and on one that
# exits 0 without naming a sandbox project, before any worker could start.
check "the eval runner's stage() raises on a failed or empty stage" \
  python3 "$HERE/../../lib/check_stage_guard.py" "$EVALS"

printf 'task_create script_tests: %s pass, %s fail\n' "$pass" "$fail"
[[ "$fail" -eq 0 ]]
