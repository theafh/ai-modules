#!/usr/bin/env bash
# Fixture: one non-qualifying finding.
#
# Round 1's pre-seeded gate return carries a single `inferred` finding under
# "Bugs it may introduce", which the Severity floor excludes, so the loop stops
# under the no-qualifying-finding condition with the finding's location file
# byte-identical and the finding listed in the report.
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
