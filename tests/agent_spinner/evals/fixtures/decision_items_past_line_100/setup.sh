#!/usr/bin/env bash
# decision_items_past_line_100: three long returns carry one decision item each
# past the hundredth line, and each self-tally says it found nothing. The run
# imports one ledger record per item, disposes each, and reports counts that
# match the records rather than the self-tallies.

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

for name in alpha beta gamma; do
  python3 - "$proj/.extras-$name.json" "$name" <<'PY'
import json, sys
path, name = sys.argv[1], sys.argv[2]
extras = {
    "_prose": "survey:%s — 0 findings." % name,
    "_late": ["findings"],
    "notes": "read the heading, the example block, and the flag list again.\n" * 160,
    "findings": [
        {"claim": "DECISION: docs/%s.md documents --jobs; choose whether to rewrite it to --workers." % name,
         "severity": "major",
         "quote": "Run `tool.sh %s --jobs 4`." % name,
         "anchor": "docs/%s.md, under \"# %s\"" % (name, name)},
    ],
}
json.dump(extras, open(path, "w"))
PY
  write_return "$proj" "survey:$name" "done" pass "@$proj/.extras-$name.json"
  rm -f "$proj/.extras-$name.json"
done

seal_open_run "$target" "$proj"
echo "decision_items_past_line_100 sandbox staged at $proj"
