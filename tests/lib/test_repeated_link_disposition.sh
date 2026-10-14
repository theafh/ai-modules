#!/usr/bin/env bash
# Proves the shared repeated-link disposition helpers bound each check to its
# own finding's record and fail closed on a missing or empty RESPONSE.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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

ROOT="$(mktemp -d "${TMPDIR:-/tmp}/rld.XXXXXX")"
trap 'rm -rf "$ROOT"' EXIT

# shellcheck source=repeated_link_disposition.sh
. "$HERE/repeated_link_disposition.sh"

# --- block ends at its record; a hard-wrapped line yields one whole block ----

RESPONSE="$ROOT/wraps.txt"
cat > "$RESPONSE" <<'EOF'
repeated-link: live.md -> sibling.md, linked from Context,
Approach, regrouped

Next paragraph names surfaced and Acceptance.
EOF

block_is_one_line() {
  local n
  n="$(disposition_blocks | wc -l | tr -d ' ')"
  [[ "$n" == "1" ]]
}
block_excludes_next_paragraph() {
  local block
  block="$(disposition_blocks)"
  grep -qi 'regrouped' <<<"$block" \
    && ! grep -qi 'surfaced' <<<"$block" \
    && ! grep -qi 'Acceptance' <<<"$block"
}
check "a hard-wrapped disposition line yields one whole block" block_is_one_line
check "a paragraph after a blank line stays out of the block" block_excludes_next_paragraph

# --- a heading, a table row, or a list marker also ends the record -----------

# Each boundary line names a disposition, so a record that ran past it would
# lend that word to the bare disposition line above it.
boundary_ends_record() {
  RESPONSE="$ROOT/boundary.txt"
  printf '%s\n%s\n' \
    'repeated-link: edge.md -> t.md, linked from Context and Approach' \
    "$1" > "$RESPONSE"
  local out
  out="$(disposition_of "edge.md" || true)"
  [[ -z "$out" ]]
}
check "a heading ends the record" boundary_ends_record '## Regrouped findings'
check "a table row ends the record" boundary_ends_record '| regrouped | 1 |'
check "a bullet list marker ends the record" \
  boundary_ends_record '- regrouped the account'
check "an ordered list marker ends the record" \
  boundary_ends_record '1. regrouped the account'

# --- indented continuation and trailing-space hard break collapse wraps ------

RESPONSE="$ROOT/indent_wrap.txt"
cat > "$RESPONSE" <<'EOF'
- repeated-link: 1 findings on
  archived tasks, left as they are
EOF

indent_joins_phrase() {
  local block
  block="$(disposition_blocks)"
  grep -qiE 'repeated-link:[[:space:]]*[0-9]+[[:space:]]+findings on archived tasks' \
    <<<"$block"
}
check "an indented continuation joins into one multi-word phrase" indent_joins_phrase

RESPONSE="$ROOT/hard_break.txt"
# Two trailing spaces on the first line are a markdown hard break.
printf '%s  \n%s\n' \
  'repeated-link: live.md -> t.md, linked from Acceptance, surfaced' \
  'because gathering would leave the Acceptance contract nothing to measure.' \
  > "$RESPONSE"

hard_break_reason() {
  local reason
  reason="$(disposition_reason "live.md")"
  grep -qi 'gathering would leave the Acceptance contract nothing to measure' \
    <<<"$reason"
}
check "a trailing-space hard break still yields a multi-word reason" \
  hard_break_reason

# --- fenced block of two disposition lines yields two blocks -----------------

RESPONSE="$ROOT/fence.txt"
cat > "$RESPONSE" <<'EOF'
```text
repeated-link: a.md -> t.md, linked from Goal, surfaced because Goal names the outcome.
repeated-link: b.md -> t.md, linked from Context, surfaced because Context is background.
```
EOF

two_blocks() {
  local n
  n="$(disposition_blocks | wc -l | tr -d ' ')"
  [[ "$n" == "2" ]]
}
each_keeps_own_reason() {
  local r1 r2
  r1="$(disposition_reason "a.md")"
  r2="$(disposition_reason "b.md")"
  grep -qi 'Goal names the outcome' <<<"$r1" \
    && ! grep -qi 'Context is background' <<<"$r1" \
    && grep -qi 'Context is background' <<<"$r2" \
    && ! grep -qi 'Goal names the outcome' <<<"$r2"
}
check "a fenced pair of disposition lines yields two blocks" two_blocks
check "each fenced block keeps its own reason" each_keeps_own_reason

# --- inside a fence, a wrap before a section name stays in its record --------

# The continuation lines start with `## Goal` and `Acceptance`. Outside a fence
# the first would read as a heading and end the record before `surfaced`.
RESPONSE="$ROOT/fence_wrap.txt"
cat > "$RESPONSE" <<'EOF'
```text
repeated-link: wrap.md -> t.md, linked from
  ## Goal and ## Acceptance, surfaced because gathering would change the
  Acceptance contract
```
EOF

fenced_wrap_keeps_word() {
  [[ "$(disposition_of "wrap.md")" == "surfaced" ]]
}
fenced_wrap_keeps_reason() {
  [[ "$(disposition_reason "wrap.md")" == \
    "gathering would change the Acceptance contract" ]]
}
check "a fenced line wrapped before ## Goal keeps its disposition word" \
  fenced_wrap_keeps_word
check "a fenced line wrapped before ## Goal keeps its whole reason" \
  fenced_wrap_keeps_reason

# --- disposition_of uses the line's own word ---------------------------------

RESPONSE="$ROOT/own_word.txt"
cat > "$RESPONSE" <<'EOF'
repeated-link: api_x.md -> sibling.md, linked from Context, regrouped

Later prose says the finding was surfaced instead.
EOF

own_word_is_regrouped() {
  [[ "$(disposition_of "api_x.md")" == "regrouped" ]]
}
no_word_returns_nothing() {
  RESPONSE="$ROOT/no_word.txt"
  printf 'repeated-link: bare.md -> t.md, linked from Context\n' > "$RESPONSE"
  local out
  out="$(disposition_of "bare.md" || true)"
  [[ -z "$out" ]]
}
check "disposition_of returns the line's own word when later prose names another" \
  own_word_is_regrouped
check "disposition_of prints nothing for a record without a disposition word" \
  no_word_returns_nothing

# --- a later line of the record supplies only what the line lacks ------------

RESPONSE="$ROOT/same_record.txt"
cat > "$RESPONSE" <<'EOF'
repeated-link: own.md -> t.md, linked from Context and Approach, regrouped
The other finding was surfaced because it guards the Acceptance contract.
EOF

own_word_inside_record() {
  [[ "$(disposition_of "own.md")" == "regrouped" ]]
}
check "disposition_of keeps the line's own word over a later line of its record" \
  own_word_inside_record

# The documented limit: a line with no word or reason of its own takes both
# from a later line of its record, because that line reads like a hard wrap.
RESPONSE="$ROOT/lend.txt"
printf '%s\n%s\n' \
  'repeated-link: lend.md -> t.md, linked from Context and Acceptance' \
  'The finding was surfaced because the Acceptance contract needs both links.' \
  > "$RESPONSE"

later_line_lends_word_and_reason() {
  [[ "$(disposition_of "lend.md")" == "surfaced" ]] \
    && grep -qi 'the Acceptance contract needs both links' \
      <<<"$(disposition_reason "lend.md")"
}
check "a line lacking a word and reason takes both from a later line of its record" \
  later_line_lends_word_and_reason

# The second documented limit: the disposition line shape carries no closing
# punctuation, so a reason that ends without any runs on into the next line of
# its record and takes that line's words.
RESPONSE="$ROOT/run_on.txt"
printf '%s\n%s\n' \
  'repeated-link: run.md -> t.md, linked from Goal and Acceptance, surfaced because each link helps' \
  'Goal and the Acceptance contract stay as they are.' \
  > "$RESPONSE"

bare_reason_runs_on() {
  grep -qi 'each link helps Goal and the Acceptance contract stay as they are' \
    <<<"$(disposition_reason "run.md")"
}
check "a reason without closing punctuation runs into the next line of its record" \
  bare_reason_runs_on

# --- disposition_words returns one word per matching line --------------------

RESPONSE="$ROOT/words.txt"
cat > "$RESPONSE" <<'EOF'
repeated-link: twice.md -> t.md, linked from Context, regrouped
repeated-link: twice.md -> t.md, linked from Approach, regrouped
EOF

words_two_regrouped() {
  local words
  words="$(disposition_words "twice.md" | sort | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
  [[ "$words" == "regrouped regrouped" ]]
}
check "disposition_words returns one word per line for a finding reported twice" \
  words_two_regrouped

# --- disposition_reason stops at sentence end and table cell -----------------

RESPONSE="$ROOT/reason_sentence.txt"
cat > "$RESPONSE" <<'EOF'
repeated-link: s.md -> t.md, linked from Acceptance, surfaced because each link helps. Goal and Acceptance stay load-bearing.
EOF

reason_stops_at_sentence() {
  local reason
  reason="$(disposition_reason "s.md")"
  grep -qi 'each link helps' <<<"$reason" \
    && ! grep -qi 'Acceptance stay' <<<"$reason"
}
check "disposition_reason stops at the first sentence end" reason_stops_at_sentence

RESPONSE="$ROOT/reason_table.txt"
cat > "$RESPONSE" <<'EOF'
| finding | note |
| repeated-link: cell.md -> t.md, linked from Goal, surfaced because the contract would change | other cell |
EOF

reason_stops_at_cell() {
  local reason
  reason="$(disposition_reason "cell.md")"
  grep -qi 'contract would change' <<<"$reason" \
    && ! grep -qi 'other cell' <<<"$reason"
}
check "disposition_reason stops at a table cell boundary" reason_stops_at_cell

# The period of e.g. or i.e. never ends a reason, while etc. still does.
RESPONSE="$ROOT/reason_abbrev.txt"
cat > "$RESPONSE" <<'EOF'
repeated-link: abbr_eg.md -> t.md, linked from Goal, surfaced because gathering would strip what the item measures (e.g. the Acceptance contract). Later prose.
repeated-link: abbr_ie.md -> t.md, linked from Goal, surfaced because the copy is the check's parameter, i.e. the Acceptance contract. Later prose.
repeated-link: abbr_etc.md -> t.md, linked from Goal, surfaced because splits, groups, etc. Goal stays load-bearing.
EOF

reason_reads_past_eg() {
  local reason
  reason="$(disposition_reason "abbr_eg.md")"
  grep -qF '(e.g. the Acceptance contract)' <<<"$reason" \
    && ! grep -qi 'Later prose' <<<"$reason"
}
reason_reads_past_ie() {
  local reason
  reason="$(disposition_reason "abbr_ie.md")"
  grep -qF 'i.e. the Acceptance contract' <<<"$reason" \
    && ! grep -qi 'Later prose' <<<"$reason"
}
etc_ends_reason() {
  [[ "$(disposition_reason "abbr_etc.md")" == "splits, groups, etc" ]]
}
check "disposition_reason reads past the period of e.g." reason_reads_past_eg
check "disposition_reason reads past the period of i.e." reason_reads_past_ie
check "disposition_reason still ends a reason at the period of etc." etc_ends_reason

# --- every helper fails closed on missing or empty RESPONSE ------------------

missing_blocks() { RESPONSE="$ROOT/missing.txt"; ! disposition_blocks; }
missing_of() { RESPONSE="$ROOT/missing.txt"; ! disposition_of "x"; }
missing_words() { RESPONSE="$ROOT/missing.txt"; ! disposition_words "x"; }
missing_reason() { RESPONSE="$ROOT/missing.txt"; ! disposition_reason "x"; }

: > "$ROOT/empty.txt"
empty_blocks() { RESPONSE="$ROOT/empty.txt"; ! disposition_blocks; }
empty_of() { RESPONSE="$ROOT/empty.txt"; ! disposition_of "x"; }
empty_words() { RESPONSE="$ROOT/empty.txt"; ! disposition_words "x"; }
empty_reason() { RESPONSE="$ROOT/empty.txt"; ! disposition_reason "x"; }

check "disposition_blocks fails on a missing RESPONSE" missing_blocks
check "disposition_of fails on a missing RESPONSE" missing_of
check "disposition_words fails on a missing RESPONSE" missing_words
check "disposition_reason fails on a missing RESPONSE" missing_reason
check "disposition_blocks fails on an empty RESPONSE" empty_blocks
check "disposition_of fails on an empty RESPONSE" empty_of
check "disposition_words fails on an empty RESPONSE" empty_words
check "disposition_reason fails on an empty RESPONSE" empty_reason

printf 'repeated_link_disposition: %s pass, %s fail\n' "$pass" "$fail"
[[ "$fail" -eq 0 ]]
