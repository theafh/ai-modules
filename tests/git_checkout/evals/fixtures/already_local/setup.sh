#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
# shellcheck disable=SC1091
. "$SCRIPT_DIR/../_common.sh"

target=${1:?target directory required}
repo="$(init_remote_repo "$target" main)"

(
    cd "$repo"
    git checkout --quiet -b local-notes
    printf 'notes\n' > notes.txt
    git add notes.txt
    git commit --quiet -m "local notes"
    git checkout --quiet main
)

printf '%s\n' "$repo"
