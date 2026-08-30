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
    git checkout --quiet -b gone-merged
    printf 'gone merged\n' > gone-merged.txt
    git add gone-merged.txt
    git commit --quiet -m "gone merged"
    git push --quiet -u origin gone-merged
    git checkout --quiet main
    git merge --quiet --ff-only gone-merged
    git push --quiet origin main
    git push --quiet origin --delete gone-merged

    git checkout --quiet -b gone-unique
    printf 'gone unique\n' > gone-unique.txt
    git add gone-unique.txt
    git commit --quiet -m "gone unique"
    git push --quiet -u origin gone-unique
    git push --quiet origin --delete gone-unique
    git checkout --quiet main
)

printf '%s\n' "$repo"
