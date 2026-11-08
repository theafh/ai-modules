#!/usr/bin/env bash
# verifier_rows_from_findings: a find return carries three findings. Three
# verify rows are made from the records before any verifier brief.

set -euo pipefail
THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$THIS_DIR/../_common.sh"

target="${1:?target dir required}"
proj="$(new_project "$target")"
mkdir -p "$proj/docs"

printf '# alpha\n\nRun `tool.sh alpha --jobs 4`.\n' > "$proj/docs/alpha.md"

commit_tree "$proj"
run_ledger "$proj" init --phase find --bound 240 \
  --unit survey:alpha >/dev/null
stage_row "$proj" survey:alpha "Survey docs/alpha.md and report every finding."
write_return "$proj" survey:alpha "done" pass '{
  "findings": [
    {"claim": "FINDING_ONE: docs/alpha.md documents --jobs.", "severity": "major",
     "quote": "Run `tool.sh alpha --jobs 4`.", "anchor": "docs/alpha.md"},
    {"claim": "FINDING_TWO: docs/alpha.md omits --workers.", "severity": "minor",
     "quote": "Run `tool.sh alpha --jobs 4`.", "anchor": "docs/alpha.md"},
    {"claim": "FINDING_THREE: docs/alpha.md has a stale heading.", "severity": "minor",
     "quote": "# alpha", "anchor": "docs/alpha.md"}
  ]
}'
run_ledger "$proj" accept survey:alpha >/dev/null

seal_open_run "$target" "$proj"
echo "verifier_rows_from_findings sandbox staged at $proj"
