#!/usr/bin/env bash
# One changed path is unreadable in the working tree, so the run has to name the
# unread remainder rather than call the change approvable.

set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$HERE/../_common.sh"

target="${1:?target directory required}"
repo="$(init_remote_repo "$target" main)"

cd "$repo"
mkdir -p src
printf 'readable = 1\n' > src/readable.py
printf 'locked = 1\n' > src/locked.py
git add -A
git commit --quiet -m "seed sources"
git push --quiet origin main

git checkout --quiet -b widen
printf 'readable = 2\n' > src/readable.py
printf 'locked = 2\nsecret_flag = True\n' > src/locked.py
git add -A
git commit --quiet -m "src -> widen both modules"
git push --quiet -u origin widen

# Remove every read permission from the one file, so reading it fails while the
# diff still names it as changed.
chmod 000 src/locked.py
printf '%s\n' "$repo"
