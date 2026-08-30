#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
# shellcheck disable=SC1091
. "$SCRIPT_DIR/../_common.sh"

target=${1:?target directory required}
repo="$(init_remote_repo "$target" master)"

(
    cd "$repo"
    git checkout --quiet -b merged-topic
    printf 'merged\n' > merged.txt
    git add merged.txt
    git commit --quiet -m "merged topic"
    git checkout --quiet master
    git merge --quiet --ff-only merged-topic
)

upstream="$target/upstream"
git clone --quiet "$target/origin.git" "$upstream"
(
    cd "$upstream"
    setup_identity
    printf 'upstream\n' > upstream.txt
    git add upstream.txt
    git commit --quiet -m "upstream"
    git push --quiet origin master
)

printf '%s\n' "$repo"
