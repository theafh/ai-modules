#!/usr/bin/env bash
# The forge reports a head SHA that differs from the checked-out HEAD, so the
# lead names the mismatch and the review uses the forge head.

set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$HERE/../_common.sh"

target="${1:?target directory required}"
repo="$(init_remote_repo "$target" main)"

cd "$repo"
mkdir -p src
printf 'def convert(rows):\n    return rows\n' > src/convert.py
git add -A
git commit --quiet -m "seed converter"
git push --quiet origin main
make_remote_look_like_github "$repo" "$target/origin.git"

git checkout --quiet -b feature/export
printf 'def convert(rows):\n    return rows\n\n\ndef export(rows):\n    return list(rows)\n' > src/convert.py
git add -A
git commit --quiet -m "src/convert.py -> add a first export helper"
git push --quiet -u origin feature/export
local_head="$(git rev-parse HEAD)"

# A newer commit lands on the remote branch, so the forge head runs ahead of
# this clone's checked-out HEAD.
push_commit_from_side "$target/origin.git" feature/export src/convert.py \
    'def convert(rows):
    return rows


def export(rows):
    return sorted(rows)' \
    "src/convert.py -> sort the exported rows"
git fetch --quiet origin
forge_head="$(git rev-parse refs/remotes/origin/feature/export)"

payloads="$target/payloads"
default_pr_payloads "$payloads" "$forge_head"
printf '%s\n' "$local_head" > "$target/.local_head"
printf '%s\n' "$forge_head" > "$target/.forge_head"
install_gh_stub "$target" "$payloads" >/dev/null
write_gh_env "$target" "$payloads"
printf '%s\n' "$repo"
