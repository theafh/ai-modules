#!/usr/bin/env bash
# Fixture: a pending decision.
#
# The change introduces a user-facing choice. Round 1's pre-seeded gate return
# carries one entry under "Decisions the implementer must make before fixing"
# and one finding held under that decision, so the loop stops for the user with
# no fixer write and the governed file byte-identical.
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
