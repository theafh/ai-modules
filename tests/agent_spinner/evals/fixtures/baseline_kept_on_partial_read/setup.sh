#!/usr/bin/env bash
# baseline_kept_on_partial_read: an audit baseline marker covers five pages,
# and the ask reads two of those five. The two reads become roster rows and the
# marker stays byte-identical, so the three unexamined pages stay covered.

set -euo pipefail
THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$THIS_DIR/../_common.sh"

target="${1:?target dir required}"
proj="$(new_project "$target")"
mkdir -p "$proj/docs" "$proj/audit"

for name in alpha beta gamma delta epsilon; do
  printf '# %s\n\nRun `tool.sh %s --jobs 4`.\n' "$name" "$name" \
    > "$proj/docs/$name.md"
done

cat > "$proj/audit/BASELINE.md" <<'DOC'
# Audit baseline

Marker: BASELINE-2026-11
Covers: docs/alpha.md, docs/beta.md, docs/gamma.md, docs/delta.md, docs/epsilon.md
DOC

seal "$target" "$proj"
echo "baseline_kept_on_partial_read sandbox staged at $proj"
