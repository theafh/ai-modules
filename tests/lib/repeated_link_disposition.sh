#!/usr/bin/env bash
# Record-bounded readers for repeated-link disposition lines in a worker report.
#
# Contract: the sourcing grader sets RESPONSE to the absolute path of the
# worker's response.txt before sourcing this file. Every helper here reads
# that path and returns non-zero when it is missing or empty.
#
# A disposition check must grade only its own finding's record. These helpers
# join hard wraps inside a record, collapse whitespace runs so a multi-word
# match still finds a phrase split by an indent or a trailing-space hard break,
# and end the record at a blank line or a code fence, and outside a fence also
# at a heading, a table row, or a list marker, so prose past one of those
# boundaries never lends a disposition line a word it lacks. Inside a fence
# those markdown boundaries stay off, because a fenced line that wraps before a
# section name such as `## Goal` would otherwise read as a heading and end the
# record before its disposition word. Inside a record a hard wrap and a following
# sentence look alike, so every later line joins the disposition line's block.
# A line keeps its own disposition word, because the helpers read the first
# word, but a line that lacks one takes it from a later line of the same
# record. A reason runs from `surfaced because` to its first sentence end, and
# the disposition line shape carries no closing punctuation, so a reason that
# ends without any runs on into the next line of its record and takes that
# line's words, the way a line with no reason of its own takes a later line's.
# A reason check therefore confirms through `disposition_of` that the line
# itself reads surfaced before it reads the reason, and it still cannot tell
# a reason from a sentence that follows it in the same record. A record that
# holds several disposition lines (a fenced block) is split on the
# `repeated-link:` lead-in so each finding keeps its own fields.
#
# Usage from a grader at tests/<name>/evals/grade.sh:
#
#     RESPONSE="${RESPONSE_FILE:-$target/../response.txt}"
#     # shellcheck source=../../lib/repeated_link_disposition.sh
#     . "$HERE/../../lib/repeated_link_disposition.sh"

# disposition_blocks -> one block per `repeated-link:` lead-in, with that
# finding's hard wraps joined and whitespace runs collapsed, ending where its
# record ends or the next lead-in starts.
disposition_blocks() {
  [[ -s "${RESPONSE:-}" ]] || return 1
  awk '
    function flush(    rest, i, after, j, seg) {
      if (rec == "") return
      rest = rec
      while ((i = index(tolower(rest), "repeated-link:")) > 0) {
        rest = substr(rest, i)
        after = substr(rest, 15)
        j = index(tolower(after), "repeated-link:")
        if (j > 0) {
          seg = substr(rest, 1, 14 + j - 1)
          rest = substr(after, j)
        } else {
          seg = rest
          rest = ""
        }
        gsub(/[[:space:]]+/, " ", seg)
        sub(/[[:space:]]+$/, "", seg)
        if (seg != "") print seg
      }
      rec = ""
    }
    /^[[:space:]]*```/ { fence = !fence; flush(); next }
    /^[[:space:]]*$/ { flush(); next }
    !fence && /^[[:space:]]*(#|\||[-*+][[:space:]]|[0-9]+[.)][[:space:]])/ { flush() }
    { rec = (rec == "" ? $0 : rec " " $0) }
    END { flush() }' "$RESPONSE"
}

# disposition_of <needle> -> the first disposition word (regrouped, surfaced,
# or kept) on the first block naming the needle.
disposition_of() {
  [[ -s "${RESPONSE:-}" ]] || return 1
  local block word
  block="$(disposition_blocks | grep -iE -- "repeated-link:.*$1" | head -1)" || true
  [[ -n "$block" ]] || return 1
  word="$(grep -oiE 'regrouped|surfaced|kept' <<<"$block" | head -1 \
    | tr '[:upper:]' '[:lower:]')"
  [[ -n "$word" ]] || return 1
  printf '%s\n' "$word"
}

# disposition_words <needle> -> that word for every block naming the needle,
# one per line.
disposition_words() {
  [[ -s "${RESPONSE:-}" ]] || return 1
  disposition_blocks | grep -iE -- "repeated-link:.*$1" \
    | while IFS= read -r block; do
        grep -oiE 'regrouped|surfaced|kept' <<<"$block" | head -1 \
          | tr '[:upper:]' '[:lower:]'
      done
}

# disposition_reason <needle> -> a surfaced block's reason, from
# `surfaced because` to its first sentence end or table cell boundary. The
# periods of e.g., i.e., vs., and cf. never end a reason, since none of them
# closes a sentence. etc. keeps its period as a sentence end, because it often
# closes one, and running a reason on into the next sentence would lend it
# that sentence's words.
disposition_reason() {
  [[ -s "${RESPONSE:-}" ]] || return 1
  disposition_blocks | awk -v needle="$1" '
    {
      if (index(tolower($0), tolower(needle)) == 0) next
      i = index(tolower($0), "surfaced because")
      if (i == 0) next
      reason = substr($0, i + 16)
      # Find the end on a copy whose abbreviation periods are masked. The
      # mask keeps every length, so the end found there cuts the reason.
      masked = tolower(reason)
      while (match(masked, /(^|[^[:alnum:]])(e\.g|i\.e|vs|cf)\./)) {
        seg = substr(masked, RSTART, RLENGTH)
        gsub(/\./, "_", seg)
        masked = substr(masked, 1, RSTART - 1) seg substr(masked, RSTART + RLENGTH)
      }
      n = match(masked, /[.;!?]([[:space:]]|$)|[[:space:]]\|/)
      if (n > 0) reason = substr(reason, 1, n - 1)
      sub(/^[[:space:]]+/, "", reason)
      sub(/[[:space:]]+$/, "", reason)
      print reason
      exit
    }'
}
