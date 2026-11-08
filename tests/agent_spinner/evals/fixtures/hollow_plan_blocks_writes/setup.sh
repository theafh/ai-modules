#!/usr/bin/env bash
# hollow_plan_blocks_writes: the planner return holds one placeholder task
# against five target files. `accept` refuses it, the planner row is a contract
# violation, and the five files stay byte-identical.

set -euo pipefail
THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$THIS_DIR/../_common.sh"

target="${1:?target dir required}"
proj="$(new_project "$target")"
mkdir -p "$proj/docs"

for name in one two three four five; do
  printf '# %s\n\nRun `tool.sh %s --jobs 4`.\n' "$name" "$name" > "$proj/docs/$name.md"
done

commit_tree "$proj"
run_ledger "$proj" init --phase plan --bound 240 \
  --unit produce:plan >/dev/null
stage_row "$proj" produce:plan "Plan the rewrite of the five pages under docs/."
write_return "$proj" produce:plan "done" pass '{
  "_prose": "produce:plan — one task.",
  "checklist": [
    {"verdict": "pass", "span": "TODO"}
  ]
}'

seal_open_run "$target" "$proj"
echo "hollow_plan_blocks_writes sandbox staged at $proj"
