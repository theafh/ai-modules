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
# The prompt names tasks/demo_decision.md, so the sandbox carries that path and
# the relay derives the `demo_decision` stem from it. The seed commit lands
# before record_head, so the recorded HEAD is the one head_unchanged compares.
seed_task_file "$target" tasks/demo_decision.md
record_head "$target"
record_index "$target"

preseed_gate "$target" "$(stem_for tasks/demo_decision.md)" 1 "$HERE/gate-r1.txt"
