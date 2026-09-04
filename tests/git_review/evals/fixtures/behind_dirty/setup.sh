#!/usr/bin/env bash
# The checked-out branch is behind its remote and the tree carries an
# uncommitted edit to the same file, so the review runs from a detached scratch
# worktree and the tree stays exactly as it is.

set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$HERE/../_common.sh"

target="${1:?target directory required}"
repo="$(init_remote_repo "$target" main)"

cd "$repo"
printf 'one\n' > notes.txt
git add notes.txt
git commit --quiet -m "seed notes"
git push --quiet origin main

git checkout --quiet -b topic
printf 'one\ntwo\n' > notes.txt
git add notes.txt
git commit --quiet -m "notes.txt -> add the second note"
git push --quiet -u origin topic

push_commit_from_side "$target/origin.git" topic notes.txt 'one
two
three' "notes.txt -> add the third note"
git fetch --quiet origin

# The uncommitted edit the run must leave untouched.
printf 'one\ntwo\nlocal work in progress\n' > notes.txt
printf '%s\n' "$repo" > "$target/.expected_repo"
printf '%s\n' "$repo"
