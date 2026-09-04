#!/usr/bin/env bash
# The target branch exists only on the remote and the worktree carries an
# uncommitted edit the switch would overwrite, so git_checkout blocks and the
# review still completes from the remote ref.

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

# The side branch rewrites core.txt, so a local uncommitted edit to it blocks
# the switch rather than travelling across.
push_branch_from_side "$target/origin.git" main feature/search core.txt "core rewritten on the search branch"
git fetch --quiet origin

printf 'core with local uncommitted work\n' > core.txt
printf '%s\n' "$repo"
