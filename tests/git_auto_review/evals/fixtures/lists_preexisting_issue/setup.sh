#!/usr/bin/env bash
# Fixture: a pre-existing defect beside the change.
#
# The change touches `report.py`. A separate defect lives in `legacy.py` at a
# line the change never touched. Round 1's pre-seeded gate return lists the
# defect as a pre-existing issue outside the Scope anchor, so the loop must
# leave `legacy.py` byte-identical and list the finding as a follow-up proposal.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/../_common.sh"

target="${1:?target dir required}"
init_repo "$target"
seed_in_scope_change "$target"
record_head "$target"
record_index "$target"

preseed_gate "$target" default 1 "$HERE/gate-r1.txt"
