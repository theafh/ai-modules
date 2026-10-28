#!/usr/bin/env bash
# Fixture: one verified in-scope bug, fixed over two rounds.
#
# Round 1's pre-seeded gate return carries one verified finding under "Bugs it
# may introduce" at a working-tree location. Round 2's pre-seeded delta return
# tags that finding closed and adds one delta finding whose location sits only
# in the reproduction the fixer added, so the loop must stop clean without
# further writes.
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
