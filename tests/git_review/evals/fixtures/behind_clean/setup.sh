#!/usr/bin/env bash
# The checked-out branch is behind its remote on a clean tree, so the run can
# fast-forward it and say so.

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

# A later commit lands on the remote from a side clone, so this clone's topic
# is behind while its tree stays clean.
push_commit_from_side "$target/origin.git" topic notes.txt 'one
two
three' "notes.txt -> add the third note"
git fetch --quiet origin
printf '%s\n' "$repo"
