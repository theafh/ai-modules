#!/usr/bin/env bash
# payload_cap: helper reports exceed the stated payload cap. The synthesis
# brief carries the truncation notice and the digest lists the trimmed
# identifiers. One load-bearing finding sits past the cap, so the orchestrator
# must read it from the source and dispose of it.

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

for name in alpha beta; do
  python3 - "$proj/.extras-$name.json" "$name" <<'PY'
import json, sys
path, name = sys.argv[1], sys.argv[2]
extras = {
    "_prose": "survey:%s — 1 finding." % name,
    "notes": "read the heading, the example block, and the flag list again.\n" * 240,
    "findings": [
        {"claim": "docs/%s.md documents --jobs; the command takes --workers." % name,
         "severity": "major",
         "quote": "Run `tool.sh %s --jobs 4`." % name,
         "anchor": "docs/%s.md, under \"# %s\"" % (name, name)},
    ],
}
json.dump(extras, open(path, "w"))
PY
  write_return "$proj" "survey:$name" "done" pass "@$proj/.extras-$name.json"
done

python3 - "$proj/.extras-gamma.json" <<'PY'
import json, sys
extras = {
    "_prose": "survey:gamma — 2 findings.",
    "notes": "read the heading, the example block, and the flag list again.\n" * 240,
    "findings": [
        {"claim": "docs/gamma.md documents --jobs; the command takes --workers.",
         "severity": "major",
         "quote": "Run `tool.sh gamma --jobs 4`.",
         "anchor": "docs/gamma.md, under \"# gamma\""},
        {"claim": "LOADBEARING: docs/gamma.md also documents a retired --jobs=8 form that the command rejects outright.",
         "severity": "blocker",
         "quote": "Run `tool.sh gamma --jobs 8` for the legacy path.",
         "anchor": "docs/gamma.md, under \"# legacy\""},
    ],
}
json.dump(extras, open(sys.argv[1], "w"))
PY
write_return "$proj" survey:gamma "done" pass "@$proj/.extras-gamma.json"
rm -f "$proj/.extras-alpha.json" "$proj/.extras-beta.json" "$proj/.extras-gamma.json"

seal_open_run "$target" "$proj"
echo "payload_cap sandbox staged at $proj"
