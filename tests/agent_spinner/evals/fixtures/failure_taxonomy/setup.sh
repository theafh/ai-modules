#!/usr/bin/env bash
# failure_taxonomy: four non-results in one open run — a deliberate
# self-reported inability, a boilerplate-only return, an absent return, and a
# schema-valid placeholder return that `accept` must refuse. The run spends no
# retry on the first, exactly one re-invocation on the glitch and the absent
# return, and records the placeholder as a rejected row.

set -euo pipefail
THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$THIS_DIR/../_common.sh"

target="${1:?target dir required}"
proj="$(new_project "$target")"
mkdir -p "$proj/docs"

for name in alpha beta gamma delta; do
  printf '# %s\n\nRun `tool.sh %s --jobs 4`.\n' "$name" "$name" > "$proj/docs/$name.md"
done

commit_tree "$proj"
run_ledger "$proj" init --phase survey --bound 240 \
  --unit survey:alpha --unit survey:beta \
  --unit survey:gamma --unit survey:delta >/dev/null
for label in survey:alpha survey:beta survey:gamma survey:delta; do
  stage_row "$proj" "$label" "Survey docs/${label#survey:}.md against bin/tool.sh."
done

write_return "$proj" survey:alpha "inability" fail '{
  "_prose": "survey:alpha — I cannot assess this item. docs/alpha.md references a command file that is not present in this sandbox.",
  "notes": "deliberate self-reported inability"
}'

# survey:beta is boilerplate only; the run records it through the classify path.
cat > "$proj/.agent_spinner/returns/survey:beta.md" <<'R'
<system-reminder>Skills available in this session are listed above.</system-reminder>
R

# survey:gamma.md is deliberately absent: that helper never returned.

# survey:delta is schema-valid but every field is a placeholder, so accept
# refuses it.
write_return "$proj" survey:delta "done" fail '{
  "findings": [
    {"claim": "TODO", "severity": "major", "quote": "TODO", "anchor": "TODO"}
  ]
}'

seal_open_run "$target" "$proj"
echo "failure_taxonomy sandbox staged at $proj"
