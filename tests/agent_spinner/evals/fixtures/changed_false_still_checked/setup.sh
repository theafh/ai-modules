#!/usr/bin/env bash
# changed_false_still_checked: a writer return claims changed=false for a file
# that differs from the baseline. The diff is the authority, so a check row and
# brief exist for the file and the report lists it as changed.

set -euo pipefail
THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$THIS_DIR/../_common.sh"

target="${1:?target dir required}"
proj="$(new_project "$target")"
mkdir -p "$proj/docs"

printf '# alpha\n\nRun `tool.sh alpha --jobs 4`.\n' > "$proj/docs/alpha.md"

commit_tree "$proj"
run_ledger "$proj" init --phase produce --bound 240 \
  --unit produce:alpha --unit-path produce:alpha=docs/alpha.md >/dev/null
stage_row "$proj" produce:alpha "Rewrite docs/alpha.md to use --workers." --target docs/alpha.md

# The writer did change the file, but its return says otherwise.
printf '# alpha\n\nRun `tool.sh alpha --workers 4`.\n' > "$proj/docs/alpha.md"
write_return "$proj" produce:alpha "done" pass '{
  "_prose": "produce:alpha — changed=false.",
  "notes": "changed=false"
}'

seal_open_run "$target" "$proj"
echo "changed_false_still_checked sandbox staged at $proj"
