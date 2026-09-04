#!/usr/bin/env bash
# An ordinary pull request with the stub gh available, used by the publishing
# evals: the slice extraction, the wording constraints, and the refrain-from-
# posting default.

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
cat > src/export.py <<'PY'
def export(rows, destination):
    """Write rows to destination."""
    handle = open(destination, "w")
    for i in range(len(rows)):
        handle.write(str(rows[i]) + str(rows[i + 1]))
    return destination


def chunk(rows):
    return [rows[i:i + 512] for i in range(0, len(rows), 512)]
PY
git add -A
git commit --quiet -m "src/export.py -> add the export path and a chunk helper"
git push --quiet -u origin feature/export
head_oid="$(git rev-parse HEAD)"

payloads="$target/payloads"
default_pr_payloads "$payloads" "$head_oid"
install_gh_stub "$target" "$payloads" >/dev/null
write_gh_env "$target" "$payloads" reviewer
printf '%s\n' "$repo"
