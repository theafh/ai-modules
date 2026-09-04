#!/usr/bin/env bash
# The clone sits on its default branch with staged, unstaged, and untracked
# changes, and one local commit the upstream has not seen.

set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$HERE/../_common.sh"

target="${1:?target directory required}"
repo="$(init_remote_repo "$target" main)"

cd "$repo"
printf 'alpha\n' > alpha.txt
printf 'beta\n' > beta.txt
git add -A
git commit --quiet -m "seed alpha and beta"
git push --quiet origin main

# One local commit ahead of the upstream.
printf 'gamma\n' > gamma.txt
git add gamma.txt
git commit --quiet -m "gamma.txt -> add the gamma stage"

# Staged, unstaged, and untracked working-tree changes on top.
printf 'alpha changed and staged\n' > alpha.txt
git add alpha.txt
printf 'beta changed and left unstaged\n' > beta.txt
printf 'delta is untracked\n' > delta.txt
printf '%s\n' "$repo"
