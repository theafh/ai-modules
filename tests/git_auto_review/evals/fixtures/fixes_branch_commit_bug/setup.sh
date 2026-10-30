#!/usr/bin/env bash
# Fixture: a verified bug committed on a checked-out feature branch.
#
# `main` carries a remote-tracking `origin/main` and the
# `refs/remotes/origin/HEAD` symref, so `<orient>` resolves the default branch
# without a fetch. The checked-out `feature` branch commits one in-scope
# verified bug with a clean working tree, so the branch target's subject is the
# branch commit alone. Round 1's pre-seeded gate return cites that bug at its
# committed lines, and round 2's delta return tags it closed, so the loop fixes
# it in the working tree, uncommitted, and stops clean with the branch ref and
# HEAD unchanged.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/../_common.sh"

target="${1:?target dir required}"
init_repo "$target"

(
  cd "$target/repo"
  cat > report.py <<'EOF'
def total(items):
    """Sum the item values."""
    return sum(items)
EOF
  git add report.py
  git commit --quiet -m "fixture base"
  git update-ref refs/remotes/origin/main HEAD

  # The feature branch commits the in-scope defect, then leaves a clean
  # working tree, so the branch-mode evidence carries the finding and the
  # working-tree evidence carries nothing.
  git checkout --quiet -b feature
  cat > report.py <<'EOF'
def total(items):
    """Sum the item values."""
    return sum(items) + 10
EOF
  git add report.py
  git commit --quiet -m "add a constant to the total"
)
record_head "$target"
record_index "$target"
(cd "$target/repo" && git rev-parse refs/heads/feature > "$target/.feature.before")

preseed_gate "$target" default 1 "$HERE/gate-r1.txt"
preseed_gate "$target" default 2 "$HERE/gate-r2.txt"
