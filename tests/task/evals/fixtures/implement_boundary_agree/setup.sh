#!/usr/bin/env bash
# implement_boundary_agree fixture (control): a ready task to implement
# calc.add, carrying an `**Out of scope:**` DEFERRAL that pushes calc.sub to a
# live sibling task (calc_subtract-function.md, open). The boundary and the
# body agree — nothing the Goal or Acceptance needs is excluded — so
# task_implement proceeds with NO boundary interruption: it builds add, writes
# a test, runs the suite, stamps implemented, and correctly SKIPS the deferred
# subtraction (leaves calc.sub a stub, leaves the sibling task open).

set -euo pipefail
THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$THIS_DIR/../_common.sh"

target="${1:?target dir required}"
proj="$(new_project "$target" --git)"
now="$(now_iso)"

mkdir -p "$proj/mathutils" "$proj/tests"
cat > "$proj/mathutils/__init__.py" <<'EOF'
EOF
cat > "$proj/mathutils/calc.py" <<'EOF'
"""Arithmetic helpers."""


def add(a, b):
    raise NotImplementedError("add is not implemented yet")


def sub(a, b):
    raise NotImplementedError("sub is not implemented yet")
EOF

# The deferral target must exist on disk so the cross-link resolves (the linter
# blocks a broken relative link). It owns the subtraction work.
cat > "$proj/tasks/calc_subtract-function.md" <<EOF
---
description: Implement calc.sub to return a - b, with a covering test.
scope: mathutils
created: $now
updated: $now
status: open
reported-by: Test User
---

# Implement calc.sub

## Goal

Make \`mathutils.calc.sub\` return \`a - b\`.

## Context

\`mathutils/calc.py\` has a \`sub\` stub that raises \`NotImplementedError\`.

## Approach

Replace the \`sub\` stub with \`return a - b\`.

## Acceptance

- \`calc.sub(5, 2)\` returns \`3\`.
- A test under \`tests/\` covers \`sub\`.
EOF

cat > "$proj/tasks/calc_add-function.md" <<EOF
---
description: Implement calc.add to return a + b, with a covering test; subtraction is deferred to its own task.
scope: mathutils
created: $now
updated: $now
status: ready
reported-by: Test User
---

# Implement calc.add

## Goal

Make \`mathutils.calc.add\` return \`a + b\`.

## Context

\`mathutils/calc.py\` has an \`add\` stub that raises \`NotImplementedError\`.

## Approach

Replace the \`add\` stub with \`return a + b\` and add a covering test under \`tests/\`.

**Out of scope:**

- Implementing \`calc.sub\` — deferred to [the subtraction task](calc_subtract-function.md), which owns that work.

## Acceptance

- \`calc.add(2, 3)\` returns \`5\`.
- A test under \`tests/\` covers \`add\` and \`python3 -m unittest discover -s tests\` passes.
EOF

git_commit_all "$proj" "seed: implement calc.add; calc.sub deferred out of scope to its owner task"

echo "implement_boundary_agree sandbox staged at $proj"
