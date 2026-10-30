#!/usr/bin/env bash
# Reproduction for the round-1 finding on `tests/git_auto_review/RUNBOOK.md`:
# the trigger measurement table must record the deployed root in its
# `~/.claude/skills/git_review` form and keep the absolute home path out of the
# committed file.
#
# Before the fix the `deployed_root:` row carried one developer's full home
# path, which CHARTER.md's Intentional Constraints ask published artefacts to
# leave out and which every later reader would take as the shape to reproduce.
#
# Exit codes:
#   0  the table records the `~` form and the file carries no home path
#   1  an absolute home path is still recorded

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
RUNBOOK="$REPO_ROOT/tests/git_auto_review/RUNBOOK.md"

fail() {
    printf 'repro: %s\n' "$*" >&2
    exit 1
}

[[ -f "$RUNBOOK" ]] || fail "RUNBOOK.md not found at $RUNBOOK"

# The row the finding cites records the tilde form.
row="$(grep -F '`deployed_root:` line' "$RUNBOOK" || true)"
[[ -n "$row" ]] || fail "no deployed_root row in RUNBOOK.md"
[[ "$row" == *'`~/.claude/skills/git_review`'* ]] \
    || fail "the deployed_root row does not record ~/.claude/skills/git_review: $row"

# No home path survives anywhere in the committed file.
if grep -nE '/Users/[^/]+/' "$RUNBOOK"; then
    fail "RUNBOOK.md still records an absolute home path"
fi

printf 'repro: the trigger table records the deployed root in its ~ form\n'
