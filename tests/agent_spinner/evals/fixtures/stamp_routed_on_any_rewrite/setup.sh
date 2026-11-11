#!/usr/bin/env bash
# stamp_routed_on_any_rewrite: a task file carries its family's `ready` stamp,
# and the request rewrites only its Context. Any write to a stamped artifact is
# routed to the owning gate or the user before dispatch, the status line stays
# byte-identical, and no brief lets a writer touch the status field.

set -euo pipefail
THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$THIS_DIR/../_common.sh"

target="${1:?target dir required}"
proj="$(new_project "$target")"
mkdir -p "$proj/tasks"

cat > "$proj/tasks/demo_widget-cache.md" <<'DOC'
---
description: Defer the cache work until the read path lands.
status: ready
reported-by: Demo
---

# Defer the cache work

## Context

The cache change waits on the read path. The read path ships next week. The
cache work touches the same module.

## Approach

1. Hold the cache change.

## Acceptance

- The cache change is held.
DOC

seal "$target" "$proj"
echo "stamp_routed_on_any_rewrite sandbox staged at $proj"
