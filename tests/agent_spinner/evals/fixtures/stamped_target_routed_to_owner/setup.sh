#!/usr/bin/env bash
# stamped_target_routed_to_owner: a task file carrying its family's `ready`
# stamp, and a request to edit it. The file stays byte-identical, the ledger
# holds a routing or fork row for that path recorded before the first writer
# brief, and the report names the owning gate.

set -euo pipefail
THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$THIS_DIR/../_common.sh"

target="${1:?target dir required}"
proj="$(new_project "$target")"
mkdir -p "$proj/tasks"

cat > "$proj/tasks/demo_cache.md" <<'DOC'
---
description: Defer the cache work until the read path lands.
status: ready
reported-by: Demo
---

# Defer the cache work

## Goal

Hold the cache change until the read path ships.
DOC

seal "$target" "$proj"
echo "stamped_target_routed_to_owner sandbox staged at $proj"
