#!/usr/bin/env bash
# Eval 8 fixture: an agent-directed obligation this commit does not implicate.
#
# The sandbox's AGENTS.md plants a standing pre-commit rule that runs a
# Python verification gate over src/. The only working-tree change is a
# documentation edit under docs/, so the subject matter the obligation
# governs and the paths this commit changes do not intersect: git_commit's
# pre-flight relevance test must SKIP the obligation and state the grounds,
# and the commit must still land.
#
# The gate is observable — tools/verify_python.sh writes .eval/markers/
# verify_python when it runs — and .eval/ is gitignored, so the marker
# never reaches git status or the commit.

set -euo pipefail
THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$THIS_DIR/../_common.sh"

target="${1:?target dir required}"
init_sandbox "$target"
target="$(cd "$target" && pwd)"

plant_obligation_scaffold "$target" verify_python \
'Run `./tools/verify_python.sh` before creating any commit. It type-checks and
unit-tests the Python package under `src/`, and a full run takes several
minutes.'

# The change under review: documentation only. Nothing under src/ moves, so
# the Python gate exercises nothing this commit touches.
(
    cd "$target"
    printf '\nThe handbook now documents the release steps.\n' >> docs/handbook.md
)

echo "Eval 8 sandbox staged at $target"
echo "  obligation: tools/verify_python.sh (governs src/) — expected SKIPPED"
echo "  changed path: docs/handbook.md"
