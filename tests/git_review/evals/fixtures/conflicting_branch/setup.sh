#!/usr/bin/env bash
# A feature branch whose change to config.ini conflicts with a change the base
# took after the branch left it, so the test merge reports that file.

set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$HERE/../_common.sh"

target="${1:?target directory required}"
repo="$(init_remote_repo "$target" main)"

cd "$repo"
printf 'timeout = 30\nretries = 2\n' > config.ini
git add config.ini
git commit --quiet -m "seed config"
git push --quiet origin main

git checkout --quiet -b tune-timeout
printf 'timeout = 90\nretries = 2\n' > config.ini
git add config.ini
git commit --quiet -m "config.ini -> raise the timeout to 90 seconds"
git push --quiet -u origin tune-timeout

git checkout --quiet main
printf 'timeout = 15\nretries = 2\n' > config.ini
git add config.ini
git commit --quiet -m "config.ini -> lower the timeout to 15 seconds"
git push --quiet origin main

git checkout --quiet tune-timeout
printf '%s\n' "$repo"
