#!/usr/bin/env bash
# Fixture: two findings, one fixed and one refuted in triage.
#
# Round 1's pre-seeded gate return carries two qualifying findings. The second
# names a change that is not real (it asks for a rewrite the defect does not
# require), so refute-by-default triage rejects it. `extra.py` lands in the
# working tree as an untracked file, so its cited line is a line the change
# adds and the Scope anchor admits the finding, which reaches triage. Round 2's
# delta return tags the first closed with no new finding.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/../_common.sh"

target="${1:?target dir required}"
init_repo "$target"
seed_in_scope_change "$target"
(
  cd "$target/repo"
  cat > extra.py <<'EOF'
def label():
    return "ok"
EOF
)
record_head "$target"
record_index "$target"

preseed_gate "$target" default 1 "$HERE/gate-r1.txt"
preseed_gate "$target" default 2 "$HERE/gate-r2.txt"
