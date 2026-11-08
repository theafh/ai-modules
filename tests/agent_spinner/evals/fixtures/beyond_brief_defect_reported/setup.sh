#!/usr/bin/env bash
# beyond_brief_defect_reported: a writer return carries a defect outside its
# brief. The run records it as a flag record and the report quotes it with its
# path.

set -euo pipefail
THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$THIS_DIR/../_common.sh"

target="${1:?target dir required}"
proj="$(new_project "$target")"
mkdir -p "$proj/docs"

printf '# alpha\n\nRun `tool.sh alpha --workers 4`.\n' > "$proj/docs/alpha.md"
printf '# Old heading\n\nStale text nobody updated.\n' > "$proj/docs/other.md"

commit_tree "$proj"
run_ledger "$proj" init --phase produce --bound 240 \
  --unit produce:alpha --unit-path produce:alpha=docs/alpha.md >/dev/null
stage_row "$proj" produce:alpha "Rewrite docs/alpha.md to use --workers." --target docs/alpha.md
write_return "$proj" produce:alpha "done" pass '{
  "_prose": "produce:alpha — docs/alpha.md is updated.",
  "beyond_brief": [
    {"path": "docs/other.md", "claim": "docs/other.md carries a stale heading outside my brief.",
     "quote": "# Old heading"}
  ]
}'

seal_open_run "$target" "$proj"
echo "beyond_brief_defect_reported sandbox staged at $proj"
