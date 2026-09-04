#!/usr/bin/env bash
# A clone whose default branch is named trunk rather than main, so the base has
# to come from the remote HEAD rather than from a hardcoded name.

set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$HERE/../_common.sh"

target="${1:?target directory required}"
repo="$(init_remote_repo "$target" trunk)"

cd "$repo"
printf 'version = 1\n' > app.cfg
git add app.cfg
git commit --quiet -m "seed app config"
git push --quiet origin trunk

git checkout --quiet -b bump-version
printf 'version = 2\n' > app.cfg
git add app.cfg
git commit --quiet -m "app.cfg -> bump the version to 2"
git push --quiet -u origin bump-version
printf '%s\n' "$repo"
