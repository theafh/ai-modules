#!/usr/bin/env bash
# Fixture: one in-scope finding under "What is critical".
#
# Round 1's pre-seeded gate return carries one verified finding under "What is
# critical" at a working-tree location. Round 2's delta return tags it closed
# with no new finding, so the loop fixes it and stops clean.
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
preseed_gate "$target" default 2 "$HERE/gate-r2.txt"
