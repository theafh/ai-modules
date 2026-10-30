#!/usr/bin/env bash
# Fixture: a committed branch defect and an uncommitted working-tree defect in
# the same file, with the committed one's working-tree lines shifted.
#
# `main` carries a remote-tracking `origin/main` and the
# `refs/remotes/origin/HEAD` symref, so `<orient>` resolves the default branch
# without a fetch. The checked-out `feature` branch commits one unambiguous
# defect at `HEAD`-side line 3, and an uncommitted edit inserts a second,
# different defect at working-tree line 3, so the committed defect's
# working-tree lines differ from its `HEAD`-side lines and the branch-range
# re-cite case has to renumber it. A standalone `auto_gate_git` run must
# therefore collect both evidence sets, report both defects, and assign both
# `working-tree lane`.
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

  # The feature branch commits a division by a zero-valued divisor at HEAD-side
  # line 3, which no caller can read as intended behaviour.
  git checkout --quiet -b feature
  cat > report.py <<'EOF'
def total(items):
    """Sum the item values."""
    return sum(items) / 0
EOF
  git add report.py
  git commit --quiet -m "divide the total by a zero-valued divisor"

  # The uncommitted edit adds a second, different defect earlier in the same
  # file, which pushes the committed defect to working-tree line 4.
  cat > report.py <<'EOF'
def total(items):
    """Sum the item values."""
    offset = 1 / 0
    return sum(items) / 0
EOF
)
record_head "$target"
record_index "$target"
(cd "$target/repo" && git rev-parse origin/main > "$target/.base.sha")
(cd "$target/repo" && git for-each-ref > "$target/.refs.before")
(cd "$target/repo" && printf '%s\n' "$(git worktree list --porcelain)" \
  > "$target/.worktrees.before")
cp "$target/repo/report.py" "$target/.report.before"
