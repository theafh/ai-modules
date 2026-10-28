#!/usr/bin/env bash
# Fixture: a scope-extension finding.
#
# The change touches `report.py`. `feature.py` is untouched, and the finding
# asks the run to cover behaviour outside the change's intent, so it never meets
# the Scope anchor and goes to the report as a follow-up task proposal.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/../_common.sh"

target="${1:?target dir required}"
init_repo "$target"
seed_in_scope_change "$target"
(
  cd "$target/repo"
  cat > feature.py <<'EOF'
def flag():
    return False
EOF
  git add feature.py
  git commit --quiet -m "seed feature"
  git update-ref refs/remotes/origin/main HEAD
)
record_head "$target"
record_index "$target"

preseed_gate "$target" default 1 "$HERE/gate-r1.txt"
