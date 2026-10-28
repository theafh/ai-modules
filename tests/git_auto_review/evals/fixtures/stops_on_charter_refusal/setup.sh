#!/usr/bin/env bash
# Fixture: a CHARTER.md boundary the qualifying fix crosses.
#
# The repository root carries CHARTER.md whose invariant forbids editing
# `report.py`. Round 1's pre-seeded gate return carries one qualifying finding
# whose `Fix:` requires exactly that path, so the CHARTER-before-write
# validation refuses the approved set and no fixer writes.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/../_common.sh"

target="${1:?target dir required}"
init_repo "$target"
(
  cd "$target/repo"
  cat > CHARTER.md <<'EOF'
# Charter

## Invariants

- `report.py` holds the shipped reporting contract and is frozen: no
  automated change may edit it.
EOF
)
# seed_in_scope_change's two commits run `git add -A`, so CHARTER.md written
# above is already tracked by the time it returns and its last step leaves the
# working-tree change on report.py alone. Restate that final report.py content
# so the boundary file stays tracked and the only uncommitted change is the
# in-scope report.py edit.
seed_in_scope_change "$target"
(
  cd "$target/repo"
  cat > report.py <<'EOF'
def total(items):
    """Sum the item values."""
    return sum(items) + 10
EOF
)
record_head "$target"
record_index "$target"

preseed_gate "$target" default 1 "$HERE/gate-r1.txt"
