#!/usr/bin/env bash
# unreturned_bound: one helper passes its stated wall-clock bound with no
# return. The run stops waiting at that bound and reports the item as
# unreturned rather than as a clean pass. The fixture stages the row in the
# state `accept --wait` reaches past the bound, without waiting out the poll.

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

commit_tree "$proj"
run_ledger "$proj" init --phase survey --bound 240 \
  --unit survey:alpha --unit survey:beta --unit survey:gamma >/dev/null
for label in survey:alpha survey:beta survey:gamma; do
  stage_row "$proj" "$label" "Survey docs/${label#survey:}.md against bin/tool.sh."
done

write_return "$proj" survey:alpha "done" pass '{
  "_prose": "survey:alpha — 1 finding. docs/alpha.md documents --jobs; the command takes --workers.",
  "findings": [
    {"claim": "docs/alpha.md documents --jobs", "severity": "major",
     "quote": "Run `tool.sh alpha --jobs 4`.", "anchor": "docs/alpha.md, under \"# alpha\""}
  ]
}'
write_return "$proj" survey:beta "done" pass '{
  "_prose": "survey:beta — 1 finding. docs/beta.md documents --jobs; the command takes --workers.",
  "findings": [
    {"claim": "docs/beta.md documents --jobs", "severity": "major",
     "quote": "Run `tool.sh beta --jobs 4`.", "anchor": "docs/beta.md, under \"# beta\""}
  ]
}'

# survey-gamma.md is deliberately absent: that helper is still out, past its
# bound. Record the row the way `accept --wait` settles it.
ledger_set_state "$proj" survey:gamma unreturned "$(python3 - <<'PY'
import datetime
print((datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(seconds=300)).replace(microsecond=0).isoformat())
PY
)"

seal_open_run "$target" "$proj"
echo "unreturned_bound sandbox staged at $proj"
