#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
# shellcheck disable=SC1091
. "$SCRIPT_DIR/../_common.sh"

target=${1:?target directory required}
repo="$(init_remote_repo "$target" main)"

# The branch rewrites the same tracked file the worktree has modified, so git
# refuses the switch.
push_branch_from_side "$target/origin.git" main rework seed.txt "rework version"

(
    cd "$repo"
    printf 'uncommitted local edit\n' > seed.txt
)

printf '%s\n' "$repo"
