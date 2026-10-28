#!/usr/bin/env bash
# Fixture: the same repository state as `honours_task_scope_anchor`, with no
# task file supplied.
#
# The change touches `report.py`. `helper.py` sits beside it with a defect the
# change never touched, so with no anchoring task file the Scope anchor cannot
# admit it: the run leaves `helper.py` byte-identical and lists the finding as
# a follow-up task proposal. The prompt names no task path, so the relay stem
# is `default`.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/../_common.sh"

target="${1:?target dir required}"
init_repo "$target"
seed_in_scope_change "$target"
(
  cd "$target/repo"
  cat > helper.py <<'EOF'
def scale(value):
    return value * 4
EOF
  git add helper.py
  git commit --quiet -m "seed helper"
  git update-ref refs/remotes/origin/main HEAD
)
record_head "$target"
record_index "$target"

# Pre-run working-tree copy the grader compares against: with no task anchor
# the finding never qualifies, so this file must stay byte-identical.
cp "$target/repo/helper.py" "$target/.helper.before"

# Round 1 alone: with no qualifying finding the run closes on the
# no-qualifying-finding condition and never opens a second gate round.
preseed_gate "$target" default 1 "$HERE/gate-r1.txt"
