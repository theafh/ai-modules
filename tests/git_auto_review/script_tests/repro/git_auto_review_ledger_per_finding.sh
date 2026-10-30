#!/usr/bin/env bash
# Reproduction for the round-1 finding on `evals/grade.sh`: the
# `fixes_inferred_and_should_fix_findings` arm's ledger check must key its
# assertion per finding and must report a clean "no" on an empty ledger.
#
# Before the fix the arm counted non-empty ledger lines globally and passed on
# a count of two, so a ledger whose two lines both served one finding passed
# under a claim that says "one reproduction per finding". The empty-ledger path
# also misfired: `grep -c` printed `0` and exited non-zero, `|| echo 0`
# appended a second `0`, and the arithmetic test on the two-line value raised
# `arithmetic syntax error in expression`, so the report line arrived blank
# rather than reading "no".
#
# This script stages each case in a throwaway sandbox outside the host
# repository and grades the arm's own report line, so it exercises the shipped
# grader rather than a copy of its logic.
#
# Exit codes:
#   0  the arm keys its ledger check per finding and reads an empty ledger cleanly
#   1  either property failed

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
GRADE="$REPO_ROOT/tests/git_auto_review/evals/grade.sh"
EVAL_ID="fixes_inferred_and_should_fix_findings"
LABEL="the ledger holds one reproduction per finding"

work="$(mktemp -d "${TMPDIR:-/tmp}/git_auto_review_repro.XXXXXX")"
trap 'rm -rf "$work"' EXIT

fail() {
    printf 'repro: %s\n' "$*" >&2
    exit 1
}

# stage_case <name> — a sandbox repo whose product files already carry both
# fixes and whose run report stops under the no-qualifying condition, so the
# arm's other four checks pass and the ledger check is the one under test.
stage_case() {
    local dir="$work/$1"
    mkdir -p "$dir/repo/.git_auto_review/default"
    printf 'def total(items):\n    return sum(items)\n' > "$dir/repo/report.py"
    printf '# Ledger notes\n\nThe regression ledger stores one reproduction per finding in `ledger.txt`.\n' \
        > "$dir/repo/notes.md"
    printf 'no qualifying finding remains\n' > "$dir/response.txt"
    : > "$dir/repo/.git_auto_review/default/ledger.txt"
    printf '%s\n' "$dir"
}

# write_record <case_dir> <repro1> <repro2> — the fixer record the arm reads
# its reproduction paths from, in the agent's `## Writes` block order.
write_record() {
    local dir=$1 r1=$2 r2=$3
    {
        printf '# auto_fixer_git record\n\n## Writes\n\n'
        printf 'path: repro/one.sh\nfinding: 1\nkind: reproduction\n\n'
        printf 'path: repro/two.sh\nfinding: 2\nkind: reproduction\n\n'
        printf '## Ledger\n\n'
        printf 'line: %s\tbash %s\n' "$r1" "$r1"
        printf 'line: %s\tbash %s\n' "$r2" "$r2"
    } > "$dir/repo/.git_auto_review/default/fixer-r1.txt"
}

# grade_line <case_dir> — the arm's report line for the ledger check, with the
# grader's stderr kept so an arithmetic error stays visible.
grade_line() {
    local dir=$1
    RESPONSE_FILE="$dir/response.txt" \
        bash "$GRADE" "$EVAL_ID" "$dir/repo" "$dir" \
        >"$dir/grade.out" 2>"$dir/grade.err"
    grep -F -- "$LABEL" "$dir/grade.out" || true
}

expect_ok() {
    local label=$1 line=$2
    [[ "$line" == *"ok"* ]] || fail "$label: expected ok, got '${line}'"
}

expect_fail() {
    local label=$1 line=$2
    [[ "$line" == *"FAIL"* ]] || fail "$label: expected FAIL, got '${line}'"
}

# Case 1 — the ledger the eval's own fixture produces: one line per finding,
# each path matching the reproduction that finding's record names.
dir="$(stage_case per_finding)"
write_record "$dir" "repro/one.sh" "repro/two.sh"
{
    printf 'repro/one.sh\tbash repro/one.sh\n'
    printf 'repro/two.sh\tbash repro/two.sh\n'
} > "$dir/repo/.git_auto_review/default/ledger.txt"
line="$(grade_line "$dir")"
expect_ok "one line per finding" "$line"

# Case 2 — both lines serve finding 1 and finding 2 has none. The global count
# is two, so the pre-fix arm passed here; the per-finding assertion must fail.
dir="$(stage_case both_for_finding_one)"
write_record "$dir" "repro/one.sh" "repro/two.sh"
{
    printf 'repro/one.sh\tbash repro/one.sh\n'
    printf 'repro/one.sh\tbash repro/one.sh\n'
} > "$dir/repo/.git_auto_review/default/ledger.txt"
line="$(grade_line "$dir")"
expect_fail "two lines for one finding" "$line"

# Case 3 — an empty ledger. The arm must report "no" cleanly, with no
# arithmetic syntax error from a doubled zero.
dir="$(stage_case empty_ledger)"
write_record "$dir" "repro/one.sh" "repro/two.sh"
line="$(grade_line "$dir")"
expect_fail "empty ledger" "$line"
if grep -Fq "arithmetic syntax error" "$dir/grade.err" "$dir/grade.out"; then
    fail "empty ledger: the arm raised an arithmetic syntax error"
fi

printf 'repro: the ledger check is keyed per finding and reads an empty ledger cleanly\n'
