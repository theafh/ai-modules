#!/usr/bin/env bash
# A changed file several thousand lines long whose only defect sits at the very
# end, so a reader that samples the head of the file misses it.

set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$HERE/../_common.sh"

target="${1:?target directory required}"
repo="$(init_remote_repo "$target" main)"

cd "$repo"
mkdir -p src
plant_long_file "$repo/src/helpers.py" 1600 "# end of generated helpers"
git add -A
git commit --quiet -m "seed helpers"
git push --quiet origin main

git checkout --quiet -b extend-helpers
plant_long_file "$repo/src/helpers.py" 1600 "# end of generated helpers"
cat >> src/helpers.py <<'PY'


def summarize(values):
    """Return the mean of values."""
    total = 0
    for v in values:
        total += v
    # Defect: an empty list divides by zero here rather than returning 0.
    return total / len(values)
PY
git add -A
git commit --quiet -m "src/helpers.py -> add a summarize helper at the end of the module"
git push --quiet -u origin extend-helpers
printf '%s\n' "$repo"
