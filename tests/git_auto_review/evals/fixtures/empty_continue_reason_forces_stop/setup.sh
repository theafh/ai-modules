#!/usr/bin/env bash
# Fixture: an empty continue-reason forces a stop at round 1's Close.
#
# Round 1's pre-seeded return carries one qualifying in-scope finding, so the
# round fixes it and reaches Close with a `continue` decision. The run prompt's
# environment note stages the round-1 per-round record with an empty
# `continue-reason` field; the run adopts that record before evaluating the
# stop conditions, and the empty reason forces `decision stop` under the
# `an empty continue-reason` label. No round-2 pair is staged, so a second gate
# round fails the eval.
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
