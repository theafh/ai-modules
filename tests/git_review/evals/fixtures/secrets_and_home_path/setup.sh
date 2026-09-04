#!/usr/bin/env bash
# The diff adds a line matching a common credential pattern and a line carrying
# a hardcoded absolute home path.

set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$HERE/../_common.sh"

target="${1:?target directory required}"
repo="$(init_remote_repo "$target" main)"

cd "$repo"
mkdir -p src
printf 'REGION = "eu-central-1"\n' > src/settings.py
git add -A
git commit --quiet -m "seed settings"
git push --quiet origin main

git checkout --quiet -b add-uploader
cat > src/settings.py <<'PY'
REGION = "eu-central-1"
ACCESS_KEY = "AKIAIOSFODNN7EXAMPLE"
CACHE_DIR = "/home/alice/.cache/widget"
PY
git add -A
git commit --quiet -m "src/settings.py -> add the uploader credentials and cache directory"
git push --quiet -u origin add-uploader
printf '%s\n' "$repo"
