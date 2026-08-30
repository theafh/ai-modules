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
    git checkout --quiet -b merged-topic
    printf 'merged\n' > merged.txt
    git add merged.txt
    git commit --quiet -m "merged topic"
    git checkout --quiet main
    git merge --quiet --ff-only merged-topic

    git checkout --quiet -b gone-unique
    printf 'unique\n' > unique.txt
    git add unique.txt
    git commit --quiet -m "unique local work"
    git push --quiet -u origin gone-unique
    git push --quiet origin --delete gone-unique
)

printf '%s\n' "$repo"
