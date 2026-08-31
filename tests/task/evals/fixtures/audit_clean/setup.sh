#!/usr/bin/env bash
# audit_clean fixture: implementation present AND a passing test present —
# every acceptance item is genuinely satisfiable. task_audit must confirm
# full compliance with the exact success line and change nothing.

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
    return a + b
EOF

cat > "$proj/tests/test_calc.py" <<'EOF'
import unittest

from mathutils.calc import add


class AddTests(unittest.TestCase):
    def test_two_plus_three(self):
        self.assertEqual(add(2, 3), 5)


if __name__ == "__main__":
    unittest.main()
EOF

cat > "$proj/tasks/calc_add-function.md" <<EOF
---
description: implement mathutils.calc.add and back it with a test
scope: mathutils
created: $now
updated: $now
status: implemented
reported-by: Test User
implemented-by: Test User
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

git_commit_all "$proj" "seed: calc.add implemented and tested"

echo "audit_clean sandbox staged at $proj"
