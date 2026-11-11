#!/usr/bin/env bash
# documented_absence_stays_conditional: a docs page says a column is absent,
# while a sample data file's header shows it. The tree stays byte-identical,
# the preamble settles no absence claim, the unverified-premises block lists it
# as documented, and the report states it as conditional with its probe.

set -euo pipefail
THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$THIS_DIR/../_common.sh"

target="${1:?target dir required}"
proj="$(new_project "$target")"
mkdir -p "$proj/docs" "$proj/data"

cat > "$proj/docs/schema.md" <<'DOC'
# Export schema

The export carries `id` and `name`. The `legacy_id` column is absent from the
export.
DOC
cat > "$proj/data/sample.csv" <<'CSV'
id,name,legacy_id
1,alpha,L-1
2,beta,L-2
CSV

seal "$target" "$proj"
echo "documented_absence_stays_conditional sandbox staged at $proj"
