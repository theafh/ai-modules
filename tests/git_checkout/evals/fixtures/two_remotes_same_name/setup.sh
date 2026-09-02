#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
# shellcheck disable=SC1091
. "$SCRIPT_DIR/../_common.sh"

target=${1:?target directory required}
repo="$(init_remote_repo "$target" main)"

seed_bare "$target/fork.git" main
(
    cd "$repo"
    git remote add fork "$target/fork.git"
)

# The same branch name on both remotes, carrying different work.
push_branch_from_side "$target/origin.git" main release-prep origin-prep.txt "origin prep"
push_branch_from_side "$target/fork.git" main release-prep fork-prep.txt "fork prep"

printf '%s\n' "$repo"
