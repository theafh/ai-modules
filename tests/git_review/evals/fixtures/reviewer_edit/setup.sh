#!/usr/bin/env bash
# A branch with one clear defect, on a repository the user can write to: no
# fork, and no CODEOWNERS entry over the changed path.

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

git checkout --quiet -b feature/mean
cat > src/stats.py <<'PY'
def mean(values):
    """Return the mean of values."""
    total = 0
    for v in values:
        total += v
    # Defect: an empty list divides by zero here rather than returning 0.
    return total / len(values)
PY
git add -A
git commit --quiet -m "src/stats.py -> add a mean helper"
git push --quiet -u origin feature/mean
printf '%s\n' "$repo"
