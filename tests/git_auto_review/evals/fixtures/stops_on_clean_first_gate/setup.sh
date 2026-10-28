#!/usr/bin/env bash
# Fixture: a clean first gate.
#
# The repository carries one uncommitted in-scope change, and round 1's gate
# return is pre-seeded as a clean verdict: no findings, no decisions. The loop
# must stop under the no-qualifying-finding condition with no fixer write.
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
