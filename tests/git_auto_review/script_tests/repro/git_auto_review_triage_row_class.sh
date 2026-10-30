#!/usr/bin/env bash
# Reproduction for the round-1 finding on `evals/README.md`: the
# `triage_reports_status_and_reason` row of the per-eval signal table must name
# the `triage-not-approved` class on the refuted finding's line.
#
# Before the fix the row read "One finding fixed, the refuted one's file
# byte-identical and listed", while the eval's `grade.sh` arm requires the
# `extra.py` line to carry the class `triage-not-approved`. The row understated
# the check it documents, in the table that is the per-eval signal inventory.
#
# The row is checked as a whole: the grader anchors the class to the same line
# that names the file, so a row naming the class on some other line does not
# satisfy the check it documents. This script reads the committed README and
# fails when that row is absent, does not name the file, or carries no
# `triage-not-approved` class.
#
# Exit codes:
#   0  the row names the refuted finding's class
#   1  the row is absent or understates the check

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
README="$REPO_ROOT/tests/git_auto_review/evals/README.md"
EVAL_ID="triage_reports_status_and_reason"
CLASS="triage-not-approved"

[[ -f "$README" ]] || {
    printf 'repro: README not found: %s\n' "$README" >&2
    exit 1
}

row="$(grep -F -- "| \`$EVAL_ID\` |" "$README" || true)"
[[ -n "$row" ]] || {
    printf 'repro: no signal-table row for %s\n' "$EVAL_ID" >&2
    exit 1
}

[[ "$row" == *"$CLASS"* ]] || {
    printf 'repro: the %s row does not name the %s class\n' "$EVAL_ID" "$CLASS" >&2
    printf '  row: %s\n' "$row" >&2
    exit 1
}

printf 'repro: the %s row names the %s class\n' "$EVAL_ID" "$CLASS"
