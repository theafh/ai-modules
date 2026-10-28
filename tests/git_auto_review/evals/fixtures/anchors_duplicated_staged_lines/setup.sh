#!/usr/bin/env bash
# Fixture: the duplicated-staged-line pair Acceptance 32 names.
#
# `file_a.py` carries a staged-diff-cited finding whose added line still appears
# in the working-tree file, once at the cited index-world position and once
# later, so lane case 4 rewrites the location to that match and case 7 assigns
# working-tree lane; the run fixes it there. `file_b.py` carries a staged-diff
# citation whose added line leaves several content matches in the working-tree
# file and none at the cited index-world position, so case 3 keeps the cited
# location, assigns local-commits lane, lists it as a follow-up task proposal,
# and makes no fix. Round 2's delta return tags `file_a.py` closed and leaves
# `file_b.py` listed, so the run stops clean with `file_b.py` byte-identical.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/../_common.sh"

target="${1:?target dir required}"
init_repo "$target"
seed_in_scope_change "$target"

(
  cd "$target/repo"
  # Commit both files at their base content.
  cat > file_a.py <<'EOF'
def a():
    return compute()
EOF
  cat > file_b.py <<'EOF'
def b():
    return compute()
EOF
  git add file_a.py file_b.py
  git commit --quiet -m "seed file A and file B"
  git update-ref refs/remotes/origin/main HEAD

  # file_a.py: stage the defect line at index-world line 2, then leave that same
  # line in the working tree at line 2 (the cited position) and again at line 6.
  cat > file_a.py <<'EOF'
def a():
    result = compute() - 1
    return result
EOF
  git add file_a.py
  cat > file_a.py <<'EOF'
def a():
    result = compute() - 1
    return result

def a2():
    result = compute() - 1
    return result
EOF

  # file_b.py: stage the same defect line at index-world line 2, then move every
  # working-tree occurrence away from line 2 (to lines 5 and 9).
  cat > file_b.py <<'EOF'
def b():
    result = compute() - 1
    return result
EOF
  git add file_b.py
  cat > file_b.py <<'EOF'
def b():
    return compute()

def b2():
    result = compute() - 1
    return result

def b3():
    result = compute() - 1
    return result
EOF
)
record_head "$target"
record_index "$target"

# Pre-run copy the grader compares against for the file that must not change.
cp "$target/repo/file_b.py" "$target/.file_b.before"

preseed_gate "$target" default 1 "$HERE/gate-r1.txt"
preseed_gate "$target" default 2 "$HERE/gate-r2.txt"
