#!/usr/bin/env bash
# fix_coherence_selector_whole_tree fixture: three live tasks across two scopes
# plus one archived finished sibling, sized for the no-selector default. The
# prompt names no scope and no list, so the selected live set defaults to the
# whole live tree: all three live tasks are assessed, and the archived task
# stays out of it.
#
# The archived sibling is what makes the default meaningful — "whole live tree"
# has to exclude closed work, so a pass that swept tasks/archive/ as well would
# fail the same check that a pass narrowing below the live tree fails.
#
# The prompt asks for the assessment in coherence-report.md as well as in the
# response, because grade.sh never sees the agent's response text; the report
# file is what makes the selected-set boundary deterministically gradeable.

set -euo pipefail
THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$THIS_DIR/../_common.sh"

target="${1:?target dir required}"
proj="$(new_project "$target" --git)"
now="$(now_iso)"

mkdir -p "$proj/core" "$proj/docs"

cat > "$proj/core/cache.py" <<'EOF'
"""In-process cache with a fixed entry ceiling."""

MAX_ENTRIES = 512


def put(store, key, value):
    if len(store) >= MAX_ENTRIES:
        store.pop(next(iter(store)))
    store[key] = value
    return store
EOF

cat > "$proj/docs/cache.md" <<'EOF'
# Cache

The cache holds at most `MAX_ENTRIES` entries and evicts in insertion order.
EOF

cat > "$proj/tasks/archive/core_omega-cache.md" <<EOF
---
description: Raise the cache entry ceiling from 128 to 512 so a warm run stops evicting entries it still needs.
scope: core
created: $now
updated: $now
status: finished
reported-by: Test User
implemented-by: Test User
---

# Raise the cache entry ceiling

## Goal

The cache holds 512 entries, so a warm run stops evicting entries it still
needs.

## Context

The ceiling was 128, which a warm run exceeded within seconds.

## Approach

Raise MAX_ENTRIES in core/cache.py to 512.

## Acceptance

- MAX_ENTRIES in core/cache.py is 512.
EOF

seed_task() {
    local name="$1" scope="$2" title="$3" goal="$4" ctx="$5" approach="$6" acc="$7"
    cat > "$proj/tasks/$name" <<EOF
---
description: $goal
scope: $scope
created: $now
updated: $now
status: ready
reported-by: Test User
---

# $title

## Goal

$goal

## Context

$ctx

## Approach

$approach

## Acceptance

- $acc
EOF
}

seed_task core_alpha-cache.md core "Evict the least recently used entry" \
    "The cache evicts the least recently used entry rather than the oldest inserted one, so a hot entry survives a full cache." \
    "[core/cache.py](../core/cache.py) evicts in insertion order today." \
    "Track access order in core/cache.py and evict the least recently used key when the ceiling is reached." \
    "A cache at its ceiling evicts the least recently used key, not the first inserted one."

seed_task core_beta-cache.md core "Report the cache hit rate" \
    "The cache reports its hit rate, so a reader can tell whether the ceiling is doing any work." \
    "[core/cache.py](../core/cache.py) records no counters today." \
    "Count hits and misses in core/cache.py and expose the ratio through a reader function." \
    "The reader function returns the hit rate over the recorded hits and misses."

seed_task docs_gamma-cache.md docs "Document the eviction policy" \
    "The cache docs name the eviction policy the code implements, so a reader does not have to read the code to learn it." \
    "[docs/cache.md](../docs/cache.md) states insertion-order eviction." \
    "Rewrite the eviction sentence in docs/cache.md so it names the policy the code implements." \
    "docs/cache.md names the eviction policy core/cache.py implements."

git_commit_all "$proj" "seed: live tree plus one archived sibling for the default selector"

echo "fix_coherence_selector_whole_tree sandbox staged at $proj"
