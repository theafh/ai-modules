#!/usr/bin/env bash
# Reproduction for the round-1 finding on `evals/grade.sh`: the
# `gate_reviews_branch_and_worktree` arm's per-defect assertions must read the
# body of the `## Bugs it may introduce` section, not the whole gate return.
#
# Before the fix both assertions ran `has` over the concatenated report text,
# so a defect path that appeared only in the structured verdict's `location:`
# line satisfied a claim that says "reported under Bugs it may introduce".
#
# This script stages a sandbox whose report names each defect path only in the
# verdict block, and a second sandbox that names them inside the section body,
# then grades the arm's own report lines. It exercises the shipped grader
# rather than a copy of its logic.
#
# Exit codes:
#   0  the arm scopes each defect assertion to the section body
#   1  the arm still accepts a verdict-only mention

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
GRADE="$REPO_ROOT/tests/git_auto_review/evals/grade.sh"
EVAL_ID="gate_reviews_branch_and_worktree"
LABEL_COMMITTED="the committed defect is reported under Bugs it may introduce"
LABEL_UNCOMMITTED="the uncommitted defect is reported under Bugs it may introduce"

work="$(mktemp -d "${TMPDIR:-/tmp}/git_auto_review_repro.XXXXXX")"
trap 'rm -rf "$work"' EXIT

fail() {
    printf 'repro: %s\n' "$*" >&2
    exit 1
}

# stage_case <name> <section_body_file> — a sandbox repo whose staged relay
# report carries the given `## Bugs it may introduce` body and a verdict block
# naming both defect paths, so only the section body varies between cases.
stage_case() {
    local dir="$work/$1" body="$2" sha
    mkdir -p "$dir/repo/.git_auto_review/default"
    (
        cd "$dir/repo" || exit 1
        git init --quiet --initial-branch=main
        git config user.name "Repro"
        git config user.email "repro@example.test"
        printf 'def total(items):\n    return sum(items) / 0\n' > report.py
        git add report.py
        git commit --quiet -m "fixture base"
    ) || return 1
    sha="$(git -C "$dir/repo" rev-parse HEAD)"
    printf '%s\n' "$sha" > "$dir/.base.sha"
    printf '%s\n' "$sha" > "$dir/.head.before"
    (cd "$dir/repo" && git for-each-ref) > "$dir/.refs.before"
    (cd "$dir/repo" && printf '%s\n' "$(git worktree list --porcelain)") \
        > "$dir/.worktrees.before"
    cp "$dir/repo/report.py" "$dir/.report.before"

    {
        printf 'Reviewed HEAD on main against origin/main at %s.\n\n' "$sha"
        printf '## What the changes do and implement\n\nA branch defect.\n\n'
        printf '## What it retires\n\nNothing.\n\n'
        printf '## What of the existing workflow changes\n\nNothing.\n\n'
        printf '## Bugs it may introduce\n\n'
        cat "$body"
        printf '\n## What should be fixed though it is not a clear bug\n\nNone.\n\n'
        printf '## Decisions the implementer must make before fixing\n\nNone.\n\n'
        printf '## Can it be structurally merged as it is\n\nYes.\n\n'
        printf '# auto_gate_git verdict\n\n## Findings\n\n'
        printf 'id: 1\nheading: Bugs it may introduce\nlabel: verified\n'
        printf 'location: report.py:4\nlane: working-tree lane\ntag: none\n\n'
        printf 'id: 2\nheading: Bugs it may introduce\nlabel: verified\n'
        printf 'location: report.py:3\nlane: working-tree lane\ntag: none\n'
    } > "$dir/repo/.git_auto_review/default/report.txt"
    printf '%s\n' "$dir"
}

# grade_lines <case_dir> — the arm's two per-defect report lines.
grade_lines() {
    local dir=$1
    RESPONSE_FILE="" bash "$GRADE" "$EVAL_ID" "$dir/repo" "$dir" \
        >"$dir/grade.out" 2>"$dir/grade.err"
    grep -F -- "$LABEL_COMMITTED" "$dir/grade.out" || true
    grep -F -- "$LABEL_UNCOMMITTED" "$dir/grade.out" || true
}

expect_ok() {
    local label=$1 line=$2
    [[ "$line" == *"ok"* ]] || fail "$label: expected ok, got '${line}'"
}

expect_fail() {
    local label=$1 line=$2
    [[ "$line" == *"FAIL"* ]] || fail "$label: expected FAIL, got '${line}'"
}

# Case 1 — each defect path appears only in the verdict block. The claim under
# test is that the report carries it under the heading, so both lines must
# fail; before the fix they passed on the verdict's `location:` line.
printf 'The defect paths are named only in the verdict.\n' > "$work/off_body.txt"
dir="$(stage_case off_body "$work/off_body.txt")" || fail "staging off_body"
lines="$(grade_lines "$dir")"
committed="$(printf '%s\n' "$lines" | grep -F -- "$LABEL_COMMITTED" || true)"
uncommitted="$(printf '%s\n' "$lines" | grep -F -- "$LABEL_UNCOMMITTED" || true)"
expect_fail "verdict-only committed defect" "$committed"
expect_fail "verdict-only uncommitted defect" "$uncommitted"

# Case 2 — the same verdict with both paths inside the section body. Both
# lines must pass, so the scoped check still accepts a real report.
{
    printf '**report.py:4** — the committed defect divides by zero.\n'
    printf '**report.py:3** — the uncommitted defect divides by zero.\n'
} > "$work/in_body.txt"
dir="$(stage_case in_body "$work/in_body.txt")" || fail "staging in_body"
lines="$(grade_lines "$dir")"
committed="$(printf '%s\n' "$lines" | grep -F -- "$LABEL_COMMITTED" || true)"
uncommitted="$(printf '%s\n' "$lines" | grep -F -- "$LABEL_UNCOMMITTED" || true)"
expect_ok "in-body committed defect" "$committed"
expect_ok "in-body uncommitted defect" "$uncommitted"

printf 'repro: both defect assertions read the Bugs it may introduce section body\n'
