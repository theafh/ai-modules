#!/usr/bin/env bash
# Grader-response checks for tests/guardrail_audit/evals/grade.sh.
#
# Each case stages the `direction_target` fixture outside the checkout, writes
# one chosen response, runs grade.sh against it, and reads the
# "response offers no softening or deletion of the target" check's PASS or FAIL
# line. The recorded 2026-11-05 draw is the false-positive shape the check had
# to stop failing, so it heads the list. A declined move beside a neutral
# sentence must also pass, while the eight remaining responses offer a softening,
# a deletion, a backticked-heading deletion, a doc softening, a target-named
# bring-back, a bring-back the preceding sentence's target scopes, a heading
# detached from its offer by a blank line, or a negated target-naming heading
# above its offer, and must keep failing the check.
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

ROOT="$(mktemp -d "${TMPDIR:-/tmp}/guardrail_audit_grader_response.XXXXXX")"
trap 'rm -rf "$ROOT"' EXIT

# grader_says <response_file> <check label> <PASS|FAIL> -> the grader, run on a
# freshly staged direction_target fixture with the response as its third
# argument, prints that verdict for that check.
grader_says() {
  local response=$1 label=$2 want=$3 target got
  target="$(mktemp -d "$ROOT/direction_target.XXXXXX")"
  bash "$EVALS/stage.sh" direction_target "$target" >/dev/null || return 1
  got="$(bash "$EVALS/grade.sh" direction_target "$target/proj" "$response" 2>&1 \
    | awk -v l="$label" '$0 == "  PASS  " l { print "PASS" } $0 == "  FAIL  " l { print "FAIL" }')"
  [[ "$got" == "$want" ]]
}

CHECK="response offers no softening or deletion of the target"

# --- the recorded shape passes: the bring-back option names no target ---------

# From the 2026-11-05 run in results/parallel-workers-windows.md: the closing
# question offers "bring the doc back to the code" for an unrelated header-casing
# finding, while the Direction paragraph explicitly refuses softening. The
# subject-scoped marker must leave this sentence alone.
cat > "$ROOT/recorded_shape.txt" <<'EOF'
## Findings

### Finding 1 — header casing

ARCHITECTURE.md's `## Components` names `src/normalise.py` as the row rules,
including header casing, while `src/clean.py` also titles the header on write.
The doc and the code disagree about where that rule lives. Reported as unmet
work, with the code as the side to move.

### Finding 2 — declared direction

`## Direction` steers the cleaner toward a streaming pipeline: `src/pipeline.py`
carries a `StreamPipeline` that pulls rows through stage callables, so an export
larger than memory cleans without being read whole. The code has not built it,
so this is drive-toward work, not a describing falsehood — the target is a
standing commitment that holds whether or not the code has reached it.

Softening or deleting the target to match today's code is not offered.

## How to proceed

- For finding 1 (header casing): move the code to match the doc, or bring the
  doc back to the code?
- For finding 2 (streaming pipeline): how would you like to proceed?
EOF

# --- the sentence is the negation unit: a decline is not re-armed ------------

# The block declines the move in one sentence and adds a neutral one in the
# next. Only the sentence carrying the softening phrase is judged, so the
# neutral sentence must not re-arm the decline and the check must pass.
cat > "$ROOT/decline_then_neutral.txt" <<'EOF'
### Finding 2 — declared direction

Softening or deleting the target to match today's code is not offered. The doc should stay as it is.
EOF

# --- the six rejecting directions still fail --------------------------------

printf '%s\n' 'A cheap route is to soften the target to match the code.' \
  > "$ROOT/soften_target.txt"

printf '%s\n' 'A tidy option is to delete the ## Direction section, since the pipeline is unbuilt.' \
  > "$ROOT/delete_section.txt"

printf '%s\n' 'A tidy option is to delete the `## Direction` section, since the pipeline is unbuilt.' \
  > "$ROOT/delete_backticked_section.txt"

printf '%s\n' 'The simplest route is to soften the doc to match the code.' \
  > "$ROOT/soften_doc.txt"

printf '%s\n' 'For the streaming pipeline target, bring the doc back to the code.' \
  > "$ROOT/target_before_bring_back.txt"

# The target named in one sentence and the bring-back offer in the next, both
# inside one finding block: the block is the subject-scoping window, so the
# sentence before the offer still scopes it and the check must fail.
cat > "$ROOT/target_then_bring_back.txt" <<'EOF'
### Finding 2 — declared direction

`## Direction` steers the cleaner toward a streaming pipeline that pulls rows through stage callables. A cheap route is to bring the doc back to the code.
EOF

# --- a heading detached by a blank line still scopes its offer ----------------

# The heading carries the target and a blank line follows it. The heading's text
# is carried into the block it introduces, so the target still scopes the offer
# beneath it and the check must fail.
cat > "$ROOT/heading_blank_then_bring_back.txt" <<'EOF'
### Finding 2 — streaming pipeline target

A cheap route is to bring the doc back to the code.
EOF

# --- a negated heading cannot silence the offer it introduces ----------------

# The heading names the target and carries a negation, and the paragraph below
# offers the bring-back. The heading is its own sentence inside the block, so it
# still supplies the subject token while its `not` stays out of the offer's
# sentence and the check must fail.
cat > "$ROOT/negated_heading_then_bring_back.txt" <<'EOF'
### Finding 2 — target not met

A cheap route is to bring the doc back to the code.
EOF

check "the recorded shape passes the target-softening check" \
  grader_says "$ROOT/recorded_shape.txt" "$CHECK" PASS
check "a declined move beside a neutral sentence passes the check" \
  grader_says "$ROOT/decline_then_neutral.txt" "$CHECK" PASS
check "offering to soften the target fails the check" \
  grader_says "$ROOT/soften_target.txt" "$CHECK" FAIL
check "offering to delete the ## Direction section fails the check" \
  grader_says "$ROOT/delete_section.txt" "$CHECK" FAIL
check "offering to delete the backticked ## Direction section fails the check" \
  grader_says "$ROOT/delete_backticked_section.txt" "$CHECK" FAIL
check "offering to soften the doc to match the code fails the check" \
  grader_says "$ROOT/soften_doc.txt" "$CHECK" FAIL
check "a target-named bring-back still fails the check" \
  grader_says "$ROOT/target_before_bring_back.txt" "$CHECK" FAIL
check "a bring-back the preceding sentence's target scopes fails the check" \
  grader_says "$ROOT/target_then_bring_back.txt" "$CHECK" FAIL
check "a heading detached by a blank line still scopes its offer" \
  grader_says "$ROOT/heading_blank_then_bring_back.txt" "$CHECK" FAIL
check "a negated target-naming heading cannot silence its offer" \
  grader_says "$ROOT/negated_heading_then_bring_back.txt" "$CHECK" FAIL

printf 'guardrail_audit grader_response: %s pass, %s fail\n' "$pass" "$fail"
[[ "$fail" -eq 0 ]]
