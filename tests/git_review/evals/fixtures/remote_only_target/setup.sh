#!/usr/bin/env bash
# The target branch exists only on the remote and this clone has fetched it, so
# a review-only run can read it without moving HEAD.

set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$HERE/../_common.sh"

target="${1:?target directory required}"
repo="$(init_remote_repo "$target" main)"

cd "$repo"
printf 'core\n' > core.txt
git add core.txt
git commit --quiet -m "seed core"
git push --quiet origin main

push_branch_from_side "$target/origin.git" main feature/search search.txt "search implementation"
git fetch --quiet origin
printf '%s\n' "$repo"
