#!/usr/bin/env bash
# Fixture: a finding the Scope anchor admits only through a supplied task file.
#
# The change touches `report.py`. `helper.py` sits beside it with a defect the
# change never touched, so the finding qualifies only when the supplied task
# file's Goal and Acceptance cover that behaviour. Round 1's pre-seeded gate
# return carries the finding; round 2's delta return tags it closed.
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
# checkout for it. Its Goal admits the `helper.py` scaling behaviour the gate
# return cites, which the changed lines alone never cover; a narrower anchor
# makes triage refuse the set as a scope extension.
seed_task_file "$target" tasks/demo_scale.md \
  "The scaling helper in helper.py returns the documented factor of two, so
scale(value) returns value * 2, without changing the shipped interface."
record_head "$target"
record_index "$target"

stem="$(stem_for tasks/demo_scale.md)"
preseed_gate "$target" "$stem" 1 "$HERE/gate-r1.txt"
preseed_gate "$target" "$stem" 2 "$HERE/gate-r2.txt"
