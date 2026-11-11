#!/usr/bin/env bash
# merged_deliverable_checked: three drafts merge into one spec file. The write
# that lands gets its own check row, and the report names that check's verdict.

set -euo pipefail
THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$THIS_DIR/../_common.sh"

target="${1:?target dir required}"
proj="$(new_project "$target")"
mkdir -p "$proj/drafts"

cat > "$proj/drafts/scope.md" <<'DOC'
# Scope

The cache serves the public read path.
DOC
cat > "$proj/drafts/limits.md" <<'DOC'
# Limits

The cache holds at most ten thousand entries.
DOC
cat > "$proj/drafts/failure.md" <<'DOC'
# Failure

An unreachable origin returns the last known value.
DOC

seal "$target" "$proj"
echo "merged_deliverable_checked sandbox staged at $proj"
