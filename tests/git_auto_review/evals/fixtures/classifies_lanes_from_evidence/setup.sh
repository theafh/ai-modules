#!/usr/bin/env bash
# Fixture: the five evidence shapes Acceptance 44 grades.
#
# The default-branch uncommitted target carries one genuine defect per shape the
# item names, so a standalone `auto_gate_git` run has to walk the ordered cases
# and land a terminal `lane` and `location` on every one of them. Each staged or
# working-tree defect is real: it divides by a zero-valued divisor, so a review
# that reads the line finds an actual fault rather than a benign edit it would
# have no reason to report. Line positions are the anchors the grader asserts.
#
#   scan.py    an index-only credential line the scan cites with the `(staged)`
#              suffix at scan.py:2 (case 1 -> local-commits lane, follow-up)
#   helper.py  a `### staged` citation whose added line still appears in the
#              working-tree file at line 3 (case 4 -> case 7, working-tree lane)
#   gone.py    a `### staged` citation whose added lines no longer appear in
#              the working-tree file at that path, cited at gone.py:2 (case 2
#              -> local-commits lane, follow-up, no fix)
#   file_a.py  a duplicated staged line with one occurrence at the cited
#              index-world position, file_a.py:2 (case 4 anchors there, case 7
#              assigns working-tree lane at line 2)
#   file_b.py  a duplicated staged line with several content matches and none
#              at the cited position, cited at file_b.py:2 (case 3 keeps the
#              citation, local-commits lane, follow-up, no fix)
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/../_common.sh"

target="${1:?target dir required}"
init_repo "$target"
seed_in_scope_change "$target"

(
  cd "$target/repo"
  # Commit every fixture file at its base content.
  cat > helper.py <<'EOF'
def helper():
    return 1
EOF
  cat > scan.py <<'EOF'
def scan():
    return None
EOF
  cat > gone.py <<'EOF'
def gone():
    return 1
EOF
  cat > file_a.py <<'EOF'
def a():
    return compute()
EOF
  cat > file_b.py <<'EOF'
def b():
    return compute()
EOF
  git add helper.py scan.py gone.py file_a.py file_b.py
  git commit --quiet -m "seed the lane fixture files"
  git update-ref refs/remotes/origin/main HEAD

  # scan.py: stage an index-only credential line, then drop it from the working
  # tree, so the index alone holds it and the scan cites it `(staged)` (case 1).
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

  # helper.py: stage a line that divides by a zero-valued divisor at index-world
  # line 2, then edit the working tree so that same line appears there at
  # working-tree line 3 (case 4 -> case 7).
  cat > helper.py <<'EOF'
def helper():
    return 1 / 0
EOF
  git add helper.py
  cat > helper.py <<'EOF'
def helper():
    # tweaked after staging
    return 1 / 0
EOF

  # gone.py: stage a line that divides by a zero-valued divisor at index-world
  # line 2, then remove it from the working-tree file entirely, so no
  # working-tree line carries it (case 2).
  cat > gone.py <<'EOF'
def gone():
    marker = 1 / 0
    return 1
EOF
  git add gone.py
  cat > gone.py <<'EOF'
def gone():
    return 1
EOF

  # file_a.py: stage the defect line at index-world line 2, then leave that same
  # line in the working tree at line 2 (the cited position) and again at line 6,
  # so case 4 anchors the cited occurrence (case 4 -> case 7, line 2).
  cat > file_a.py <<'EOF'
def a():
    result = compute() / 0
    return result
EOF
  git add file_a.py
  cat > file_a.py <<'EOF'
def a():
    result = compute() / 0
    return result

def a2():
    result = compute() / 0
    return result
EOF

  # file_b.py: stage the same defect line at index-world line 2, then move every
  # working-tree occurrence away from line 2 (to lines 5 and 9), so several
  # content matches exist and none at the cited position (case 3).
  cat > file_b.py <<'EOF'
def b():
    result = compute() / 0
    return result
EOF
  git add file_b.py
  cat > file_b.py <<'EOF'
def b():
    return compute()

def b2():
    result = compute() / 0
    return result

def b3():
    result = compute() / 0
    return result
EOF
)
record_head "$target"
record_index "$target"
(cd "$target/repo" && git for-each-ref > "$target/.refs.before")
(cd "$target/repo" && git worktree list --porcelain > "$target/.worktrees.before")
