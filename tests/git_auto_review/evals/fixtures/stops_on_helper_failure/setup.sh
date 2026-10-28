#!/usr/bin/env bash
# Fixture: a contract-violating pre-seeded gate return.
#
# Round 1's pre-seeded pair carries a truncated return whose structured verdict
# field list is absent, so the loop reads a contract-violating helper return in
# place of a gate invocation and stops under the helper-failure policy.
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
