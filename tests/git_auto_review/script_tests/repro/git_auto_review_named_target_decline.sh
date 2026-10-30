#!/usr/bin/env bash
# Reproduction for the round-1 finding on
# `plugins/ai_dev/skills/git_auto_review/SKILL.md`: the named-target decline
# needs a scenario that pins it.
#
# `<inputs>` defines the `branch <ref>` / `pull request <ref>` phrase, and
# `<orient>` declines when that phrase names something other than the
# checked-out branch, naming `git_checkout`. Before the fix no eval covered
# that branch: the fixture `declines_on_named_other_branch`, its `evals.json`
# case, and its grading arm did not exist, so this script failed at the
# unknown-eval-id branch of the grader.
#
# The script stages the fixture into a throwaway sandbox and grades the arm
# twice: once with a response that names `git_checkout` (every behaviour must
# pass) and once with a response that does not (the naming behaviour must
# fail), so the arm proves the property rather than merely running.
#
# Exit codes:
#   0  the new eval exists and its arm grades the decline by substance
#   1  the eval is missing or the arm passes without the required evidence

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
EVALS_DIR="$REPO_ROOT/tests/git_auto_review/evals"
GRADE="$EVALS_DIR/grade.sh"
FIXTURE="$EVALS_DIR/fixtures/declines_on_named_other_branch/setup.sh"
EVAL_ID="declines_on_named_other_branch"
LABEL="the decline names git_checkout as the skill to use"

work="$(mktemp -d "${TMPDIR:-/tmp}/git_auto_review_repro.XXXXXX")"
trap 'rm -rf "$work"' EXIT

fail() {
    printf 'repro: %s\n' "$*" >&2
    exit 1
}

[[ -f "$FIXTURE" ]] || fail "fixture not found at $FIXTURE"

# The eval is registered with the branch-naming prompt.
python3 - "$EVALS_DIR/evals.json" "$EVAL_ID" <<'PY' || fail "eval $EVAL_ID is not registered with a branch-naming prompt"
import json, sys
evals = json.load(open(sys.argv[1]))["evals"]
for e in evals:
    if e["id"] == sys.argv[2]:
        assert "branch " in e["prompt"], "prompt carries no named target"
        assert e["files"], "no fixture declared"
        break
else:
    raise SystemExit(1)
PY

# stage <name> <response_text> — one sandbox from the fixture plus a response.
stage() {
    local name=$1 response=$2 dir
    dir="$work/$name"
    mkdir -p "$dir"
    bash "$FIXTURE" "$dir" >/dev/null 2>&1 || return 1
    printf '%s\n' "$response" > "$dir/response.txt"
    printf '%s\n' "$dir"
}

grade() {
    local dir=$1
    RESPONSE_FILE="$dir/response.txt" bash "$GRADE" "$EVAL_ID" "$dir/repo" "$dir" \
        >"$dir/grade.out" 2>"$dir/grade.err"
    printf '%s\n' "$?"
}

# Case 1 — the decline names git_checkout. Every behaviour must pass.
dir="$(stage declines "I decline this run: branch feature is not the checked-out branch. Use the git_checkout skill to put the repository on it.")" \
    || fail "staging the fixture failed"
rc="$(grade "$dir")"
[[ "$rc" == "0" ]] \
    || { cat "$dir/grade.out" >&2; fail "the arm failed a correct decline"; }
line="$(grep -F -- "$LABEL" "$dir/grade.out" || true)"
[[ "$line" == *"ok"* ]] || fail "expected the naming check to pass, got '${line}'"

# Case 2 — a decline that names no skill. The naming behaviour must fail, so
# the arm reads the response rather than passing unconditionally.
dir="$(stage no_name "I decline this run: the named target is not the checked-out branch.")" \
    || fail "staging the fixture failed"
rc="$(grade "$dir")"
[[ "$rc" != "0" ]] || fail "the arm passed a decline that names no skill"
line="$(grep -F -- "$LABEL" "$dir/grade.out" || true)"
[[ "$line" == *"FAIL"* ]] || fail "expected the naming check to fail, got '${line}'"

printf 'repro: the named-target decline is staged and graded by substance\n'
