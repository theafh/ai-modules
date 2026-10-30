#!/usr/bin/env bash
# Fixture: one working-tree-lane bug, one staged-then-edited finding, and one
# `(staged)` scan-locus finding the lane rules assign local-commits lane.
#
# Acceptance 25 names three findings: a verified in-scope working-tree-lane bug
# in `report.py`, a verified in-scope finding on a change staged and then edited
# again in `helper.py` (lane case 4 rewrites the location, case 8 assigns
# working-tree lane), and a `(staged)` scan-locus citation on an index-only line
# in `scan.py` (case 1, local-commits lane). Round 1's pre-seeded gate return
# carries all three; round 2's delta return tags the two fixed findings closed
# and leaves the scan-locus finding listed as a follow-up proposal, so the run
# stops clean with `scan.py` byte-identical.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/../_common.sh"

target="${1:?target dir required}"
init_repo "$target"
seed_in_scope_change "$target"

# Commit the two fixture files at their base content, then stage an edit on
# each and edit the working tree again, so the index carries content the
# working-tree file no longer matches.
(
  cd "$target/repo"
  cat > helper.py <<'EOF'
def helper():
    return 1
EOF
  cat > scan.py <<'EOF'
def scan():
    return None
EOF
  git add helper.py scan.py
  git commit --quiet -m "seed helper and scan"
  git update-ref refs/remotes/origin/main HEAD

  # helper.py: stage `return 2`, then edit the working tree so the staged added
  # line still appears there (lane case 4 -> case 8, working-tree lane).
  cat > helper.py <<'EOF'
def helper():
    return 2
EOF
  git add helper.py
  cat > helper.py <<'EOF'
def helper():
    # tweaked after staging
    return 2
EOF

  # scan.py: stage an index-only line, then drop it from the working tree, so
  # the index alone holds it and the scan cites it with the `(staged)` suffix
  # (lane case 1, local-commits lane).
  cat > scan.py <<'EOF'
def scan():
    token = "AKIAIOSFODNN7EXAMPLE"
    return None
EOF
  git add scan.py
  cat > scan.py <<'EOF'
def scan():
    return None
EOF
)
record_head "$target"
record_index "$target"

# Pre-run working-tree copies the grader compares against for the files that
# must and must not change.
cp "$target/repo/helper.py" "$target/.helper.before"
cp "$target/repo/scan.py" "$target/.scan.before"

preseed_gate "$target" default 1 "$HERE/gate-r1.txt"
preseed_gate "$target" default 2 "$HERE/gate-r2.txt"
