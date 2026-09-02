#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
# shellcheck disable=SC1091
. "$SCRIPT_DIR/../_common.sh"

target=${1:?target directory required}
rm -rf "$target"
mkdir -p "$target"

seed_bare "$target/origin.git" main
push_branch_from_side "$target/origin.git" main hotfix/tls hotfix.txt "hotfix"

# A single-branch clone restricts the fetch refspec to main, so the branch's
# remote-tracking ref never arrives however often the clone fetches.
git clone --quiet --single-branch --branch main "$target/origin.git" "$target/repo" 2>/dev/null
(
    cd "$target/repo"
    setup_identity
)

printf '%s\n' "$target/repo"
