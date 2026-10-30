#!/usr/bin/env bash
# Fixture: an inferred bug and a should-fix finding, both fixed.
#
# Round 1's pre-seeded gate return carries an `inferred` finding under "Bugs it
# may introduce" and a text-only finding under "What should be fixed though it
# is not a clear bug". The text-only defect sits in `notes.md`, which lands in
# the working tree as an untracked new file, so its cited line is a line the
# change adds and the Scope anchor admits it. Both findings qualify, both are
# fixed, and round 2's delta return tags both closed so the loop stops under the
# no-qualifying-finding condition.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/../_common.sh"

target="${1:?target dir required}"
init_repo "$target"
seed_in_scope_change "$target"
(
  cd "$target/repo"
  cat > notes.md <<'EOF'
# Ledger notes

The regression ledger stores one reproduction per finding in `report.txt`.
EOF
)
record_head "$target"
record_index "$target"

preseed_gate "$target" default 1 "$HERE/gate-r1.txt"
preseed_gate "$target" default 2 "$HERE/gate-r2.txt"
