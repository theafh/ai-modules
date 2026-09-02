#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
# shellcheck disable=SC1091
. "$SCRIPT_DIR/../_common.sh"

target=${1:?target directory required}
repo="$(init_remote_repo "$target" main)"

# Pushed after this clone's last fetch, so the remote-tracking ref is absent
# until the run fetches.
push_branch_from_side "$target/origin.git" main feature/search search.txt "search"

printf '%s\n' "$repo"
