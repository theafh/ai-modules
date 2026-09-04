#!/usr/bin/env bash
# The same shape of change in a repository carrying none of the root guardrail
# documents, so the run reviews unchanged and reports no missing-document
# finding.

set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$HERE/../_common.sh"

target="${1:?target directory required}"
repo="$(init_remote_repo "$target" main)"

cd "$repo"
mkdir -p src
cat > src/convert.py <<'PY'
FORMATS = {"csv": 1, "tsv": 2}


def convert(rows, fmt):
    return [r for r in rows if FORMATS[fmt]]
PY
git add -A
git commit --quiet -m "seed converter"
git push --quiet origin main

git checkout --quiet -b add-sync
cat > src/sync.py <<'PY'
import urllib.request


def sync(rows, endpoint):
    """Push rows to an endpoint."""
    urllib.request.urlopen(endpoint, data=b"".join(rows))
PY
git add -A
git commit --quiet -m "src/sync.py -> add a sync command that posts rows to an endpoint"
git push --quiet -u origin add-sync
printf '%s\n' "$repo"
