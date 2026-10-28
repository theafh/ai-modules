#!/usr/bin/env bash
# Fixture: two consecutive rounds whose qualifying findings all sit in code the
# loop wrote in an earlier round.
#
# The seeded `alpha.py` carries one genuine defect per helper: both document a
# limit of 1 and both return the literal `2`. The task Goal additionally
# requires that limit written once as a module-level `ALPHA_LIMIT` rather than
# repeated as a literal.
#
#   round 1  both helpers return 2 where their docstrings document 1. The fix
#            rewrites both bodies, so `authored.txt` records two hunks: the
#            `alpha_value` body and the `alpha_max` body.
#   round 2  `alpha_value` still repeats the limit as a bare literal, against
#            the Goal's single-constant rule. The fix inserts
#            `ALPHA_LIMIT = 1` above `def alpha_value():`, which shifts every
#            later line, so round 1's recorded hunks are re-anchored to their
#            current lines. The finding sits in round 1's authored hunk.
#   round 3  `alpha_max` still repeats the literal, because round 2's fix named
#            `alpha_value` alone. The finding sits in round 1's re-anchored
#            `alpha_max` hunk, and because round 2's qualifying set also sat
#            entirely in loop-authored code, round 3 closes under **Self-written
#            early close.** with no `auto_fixer_git` write and no gate round.
#
# Each round's finding names a requirement that genuinely still fails in the
# state the preceding round left, so `auto_verifier_git` triage approves it
# instead of refuting a claim the earlier round already satisfied.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/../_common.sh"

target="${1:?target dir required}"
init_repo "$target"
seed_in_scope_change "$target"
(
  cd "$target/repo"
  cat > alpha.py <<'EOF'
def alpha_value():
    """Return the documented limit of 1."""
    return 2


def alpha_max():
    """Return the largest allowed limit of 1."""
    return 2
EOF
  git add alpha.py
  git commit --quiet -m "seed round targets"
  git update-ref refs/remotes/origin/main HEAD
)
cat > "$target/repo/report.py" <<'EOF'
def total(items):
    """Sum the item values."""
    return sum(items) + 10
EOF
seed_task_file "$target" tasks/demo_rounds.md \
  "Both helpers in alpha.py return the limit their docstring documents, and that
limit is written once as a module-level constant named ALPHA_LIMIT rather than
repeated as a literal, without changing the shipped interface."

record_head "$target"
record_index "$target"

stem="$(stem_for tasks/demo_rounds.md)"
preseed_gate "$target" "$stem" 1 "$HERE/gate-r1.txt"
preseed_gate "$target" "$stem" 2 "$HERE/gate-r2.txt"
preseed_gate "$target" "$stem" 3 "$HERE/gate-r3.txt"
