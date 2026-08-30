#!/usr/bin/env bash
# implement fixture: a tiny runnable Python project with a stubbed
# function and an open task whose Acceptance is a passing test suite.
# task_implement must write the code AND a test, leave the suite green,
# and leave the task open (it implements; it does not archive).

set -euo pipefail
THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$THIS_DIR/../_common.sh"

target="${1:?target dir required}"
proj="$(new_project "$target" --git)"
now="$(now_iso)"

mkdir -p "$proj/mathutils" "$proj/tests"
: > "$proj/mathutils/__init__.py"

cat > "$proj/mathutils/calc.py" <<'EOF'
"""Small arithmetic helpers."""


def add(a, b):
    raise NotImplementedError("add is not implemented yet")
EOF

cat > "$proj/tasks/calc_add-function.md" <<EOF
---
description: implement mathutils.calc.add and back it with a test
scope: mathutils
created: $now
updated: $now
status: ready
reported-by: Test User
---

# Implement calc.add

## Goal

\`mathutils.calc.add(a, b)\` currently raises \`NotImplementedError\`. Make
it return the sum of its two arguments.

## Approach

Replace the stub body in \`mathutils/calc.py\` with a real implementation.

## Acceptance

- \`add(2, 3)\` returns \`5\`.
- A test under \`tests/\` covers \`add\` (at least the \`2 + 3\` case).
- Running \`python3 -m unittest discover -s tests -p 'test_*.py'\` from the
  project root exits 0.
EOF

git_commit_all "$proj" "seed: stubbed calc.add and its task"

echo "implement sandbox staged at $proj"
