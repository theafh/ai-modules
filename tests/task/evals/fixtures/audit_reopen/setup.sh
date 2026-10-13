#!/usr/bin/env bash
# audit_reopen fixture: an `audited` task whose acceptance-mandated test is
# MISSING. A re-audit must emit `Gaps:`, re-open the task by writing
# `status: implemented` with a bumped `updated` (the base skill's re-audit
# re-open), route the gap to task_implement on the same task, and file no new
# task. `updated` is seeded in the past so the bump is observable.

set -euo pipefail
THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$THIS_DIR/../_common.sh"

target="${1:?target dir required}"
proj="$(new_project "$target" --git)"
seeded="2026-01-05T09:00:00"

mkdir -p "$proj/mathutils"
: > "$proj/mathutils/__init__.py"

cat > "$proj/mathutils/calc.py" <<'EOF'
"""Small arithmetic helpers."""


def add(a, b):
    return a + b
EOF

cat > "$proj/tasks/calc_add-function.md" <<EOF
---
description: implement mathutils.calc.add and back it with a test
scope: mathutils
created: $seeded
updated: $seeded
status: audited
reported-by: Test User
implemented-by: Test User
design-extended: false
---

# Implement calc.add

## Goal

\`mathutils.calc.add(a, b)\` returns the sum of its two arguments.

## Approach

Implement the function and cover it with a test.

## Acceptance

- \`add(2, 3)\` returns \`5\`.
- A test under \`tests/\` covers \`add\`.
- Running \`python3 -m unittest discover -s tests -p 'test_*.py'\` from the
  project root exits 0.
EOF

git_commit_all "$proj" "seed: calc.add audited but its test is missing"

echo "audit_reopen sandbox staged at $proj"
