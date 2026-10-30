#!/usr/bin/env bash
# Reproduction for the round-2 finding on `tests/git_auto_review/evals/README.md`:
# the eval the round-1 fix added, `declines_on_named_other_branch`, must be
# enumerated in the two harness documents that list evals.
#
# Before the fix the eval was registered in `evals.json` and graded by
# `evals/grade.sh`, yet `evals/README.md`'s `## Signal per eval` table carried no
# row for it and `tests/git_auto_review/README.md`'s branch-target sentence
# undercounted the branch-target evals, so a reader consulting either document
# to learn what the eval measures found no entry for it.
#
# Exit codes:
#   0  both documents enumerate the eval
#   1  either document still omits it

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
EVALS_README="$REPO_ROOT/tests/git_auto_review/evals/README.md"
HARNESS_README="$REPO_ROOT/tests/git_auto_review/README.md"
EVAL_ID="declines_on_named_other_branch"

fail() {
    printf 'repro: %s\n' "$*" >&2
    exit 1
}

[[ -f "$EVALS_README" ]] || fail "evals/README.md not found at $EVALS_README"
[[ -f "$HARNESS_README" ]] || fail "harness README.md not found at $HARNESS_README"

# The `## Signal per eval` table carries a row for the eval, with a signal
# description beside the backticked id. Read only that section so a mention
# anywhere else in the file cannot satisfy the check.
python3 - "$EVALS_README" "$EVAL_ID" <<'PY' || fail "the ## Signal per eval table carries no row for $EVAL_ID"
import sys

path, eval_id = sys.argv[1], sys.argv[2]
lines = open(path, encoding="utf-8").read().splitlines()
start = next((i for i, line in enumerate(lines) if line.strip() == "## Signal per eval"), None)
assert start is not None, "no ## Signal per eval heading"
body = []
for line in lines[start + 1:]:
    if line.startswith("## "):
        break
    body.append(line)
needle = "| `%s` |" % eval_id
rows = [line for line in body if line.startswith(needle)]
assert rows, "no table row for %s" % eval_id
cells = [cell.strip() for cell in rows[0].strip().strip("|").split("|")]
assert len(cells) >= 2 and cells[1], "row for %s carries no signal description" % eval_id
PY

# The harness README's branch-target sentence names the eval alongside the
# other branch-target evals.
python3 - "$HARNESS_README" "$EVAL_ID" <<'PY' || fail "the branch-target sentence does not name $EVAL_ID"
import re
import sys

path, eval_id = sys.argv[1], sys.argv[2]
text = " ".join(open(path, encoding="utf-8").read().split())
match = re.search(r"The branch-target evals cover .*?\(`gate_reviews_branch_and_worktree`\)\.", text)
assert match, "no branch-target sentence ending at gate_reviews_branch_and_worktree"
sentence = match.group(0)
assert "`%s`" % eval_id in sentence, "branch-target sentence omits %s" % eval_id
PY

printf 'repro: both harness documents enumerate %s\n' "$EVAL_ID"
