#!/usr/bin/env bash
# Fixture: the round-2 delta re-review is bounded to the cumulative run change.
#
# Round 1 fixes an in-scope defect on a changed line of `report.py`. Round 2's
# pre-seeded delta return carries a finding on `helper.py`, a file the run
# never touched whose behaviour the supplied task file's Goal describes. The
# line-level Scope anchor keeps it outside the subject, so the run lists it as
# a follow-up task proposal with no fix and leaves `helper.py` byte-identical.
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
# The prompt names tasks/demo_subject.md, so the sandbox carries that path. Its
# Goal describes the untouched helper's behaviour, which is exactly the
# behaviour-level claim the line-level Scope anchor must refuse.
seed_task_file "$target" tasks/demo_subject.md \
  "The scaling helper in helper.py returns the documented factor of two, so
scale(value) returns value * 2, without changing the shipped interface."
record_head "$target"
record_index "$target"

cp "$target/repo/helper.py" "$target/.helper.before"

stem="$(stem_for tasks/demo_subject.md)"
preseed_gate "$target" "$stem" 1 "$HERE/gate-r1.txt"
preseed_gate "$target" "$stem" 2 "$HERE/gate-r2.txt"
