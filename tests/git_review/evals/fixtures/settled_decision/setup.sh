#!/usr/bin/env bash
# The branch leaves one design question apparently open, and a wiki page in the
# repository records the owner's decision on exactly that question.

set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$HERE/../_common.sh"

target="${1:?target directory required}"
repo="$(init_remote_repo "$target" main)"

cd "$repo"
mkdir -p src docs
cat > src/cache.py <<'PY'
CACHE = {}


def store(key, value):
    CACHE[key] = value
PY
cat > docs/decisions.md <<'MD'
# Decisions

## Cache eviction, decided 2026-08-14 by the module owner

The cache stays unbounded in this release. We measured the working set at
under 2000 entries, and an eviction policy would add a tuning knob we do not
want yet. Revisit only when a profile shows the cache above 50 MB.
MD
git add -A
git commit --quiet -m "seed cache and decisions"
git push --quiet origin main

git checkout --quiet -b cache-metrics
cat > src/cache.py <<'PY'
CACHE = {}
HITS = 0


def store(key, value):
    # No eviction policy: the cache grows for the life of the process.
    CACHE[key] = value


def load(key):
    global HITS
    if key in CACHE:
        HITS += 1
    return CACHE.get(key)
PY
git add -A
git commit --quiet -m "src/cache.py -> count cache hits alongside the existing store path"
git push --quiet -u origin cache-metrics
printf '%s\n' "$repo"
