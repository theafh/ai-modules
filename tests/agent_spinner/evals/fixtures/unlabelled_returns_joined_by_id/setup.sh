#!/usr/bin/env bash
# unlabelled_returns_joined_by_id: returns arrive out of dispatch order and
# their records carry no item label of their own. The synthesis joins by the
# echoed identifier, or stops and names the missing ids.

set -euo pipefail
THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$THIS_DIR/../_common.sh"

target="${1:?target dir required}"
proj="$(new_project "$target")"
mkdir -p "$proj/docs"

for name in alpha beta; do
  printf '# %s\n\nRun `tool.sh %s --jobs 4`.\n' "$name" "$name" > "$proj/docs/$name.md"
done

commit_tree "$proj"
run_ledger "$proj" init --phase survey --bound 240 \
  --unit survey:alpha --unit survey:beta >/dev/null
stage_row "$proj" survey:alpha "Survey docs/alpha.md."
stage_row "$proj" survey:beta "Survey docs/beta.md."

# beta's return lands first, then alpha's: arrival order differs from dispatch
# order, and neither finding carries an item label.
write_return "$proj" survey:beta "done" pass '{
  "findings": [
    {"claim": "docs/beta.md documents --jobs.", "severity": "major",
     "quote": "Run `tool.sh beta --jobs 4`.", "anchor": "docs/beta.md"}
  ]
}'
write_return "$proj" survey:alpha "done" pass '{
  "findings": [
    {"claim": "docs/alpha.md documents --jobs.", "severity": "major",
     "quote": "Run `tool.sh alpha --jobs 4`.", "anchor": "docs/alpha.md"}
  ]
}'

seal_open_run "$target" "$proj"
echo "unlabelled_returns_joined_by_id sandbox staged at $proj"
