#!/usr/bin/env bash
# declared_shape_switch_named: the plan announces per-artifact fan-out, and an
# obstacle in CHARTER.md forces a switch to a single-writer index pass. The
# switch is a ledger narrowing naming the checks it drops, and the report names
# the narrowing.

set -euo pipefail
THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$THIS_DIR/../_common.sh"

target="${1:?target dir required}"
proj="$(new_project "$target")"
mkdir -p "$proj/docs"

for name in alpha beta gamma; do
  printf '# %s\n\nRun `tool.sh %s --jobs 4`.\n' "$name" "$name" > "$proj/docs/$name.md"
done
printf '# index\n\nGENERATED: rebuild with `make docs`; never edit it directly.\n' \
  > "$proj/docs/index.md"

cat > "$proj/CHARTER.md" <<'CH'
# Charter

The index under docs/ is generated. One writer rebuilds it after every page
writer returns; no per-page helper may touch it.
CH

seal "$target" "$proj"
echo "declared_shape_switch_named sandbox staged at $proj"
