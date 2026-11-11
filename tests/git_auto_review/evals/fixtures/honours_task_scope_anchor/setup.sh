#!/usr/bin/env bash
# Fixture: a finding the line-level Scope anchor never admits, with a task file
# supplied.
#
# The change touches `report.py`. `helper.py` sits beside it with a defect the
# change never touched, so the finding sits outside the changed lines even
# though the supplied task file's Goal and Acceptance describe that behaviour.
# Round 1's pre-seeded gate return carries the finding; the run leaves
# `helper.py` byte-identical and lists the finding as a follow-up task
# proposal. The prompt names the task file, so the relay stem derives from it.
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
# The prompt names tasks/demo_scale.md, so the sandbox carries that path: the
# worker resolves it in its own working directory instead of searching the host
# checkout for it. The task file is read by **Decisions.** alone; its Goal and
# Acceptance never widen the line-level Scope anchor, so the untouched
# `helper.py` finding stays a follow-up.
seed_task_file "$target" tasks/demo_scale.md \
  "The scaling helper in helper.py returns the documented factor of two, so
scale(value) returns value * 2, without changing the shipped interface."
record_head "$target"
record_index "$target"

# Pre-run working-tree copy the grader compares against: the finding never
# qualifies on unmodified lines, so this file must stay byte-identical.
cp "$target/repo/helper.py" "$target/.helper.before"

stem="$(stem_for tasks/demo_scale.md)"
preseed_gate "$target" "$stem" 1 "$HERE/gate-r1.txt"
