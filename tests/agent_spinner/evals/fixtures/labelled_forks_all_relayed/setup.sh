#!/usr/bin/env bash
# labelled_forks_all_relayed: one return carries three labelled forks. All
# three become open fork records and all three reach the report.

set -euo pipefail
THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$THIS_DIR/../_common.sh"

target="${1:?target dir required}"
proj="$(new_project "$target")"
mkdir -p "$proj/docs"

printf '# alpha\n\nRun `tool.sh alpha --jobs 4`.\n' > "$proj/docs/alpha.md"

commit_tree "$proj"
run_ledger "$proj" init --phase survey --bound 240 \
  --unit survey:alpha >/dev/null
stage_row "$proj" survey:alpha "Survey docs/alpha.md and surface every fork."
write_return "$proj" survey:alpha "done" pass '{
  "_prose": "survey:alpha — three forks.",
  "forks": [
    {"issue": "FORK_ALPHA: rewrite the page now or defer it",
     "options": [
       {"id": "rewrite_now", "text": "rewrite now", "cost": "one page edit in this run"},
       {"id": "defer", "text": "defer to the next run", "cost": "the page stays stale until the next run"}
     ],
     "preferred": "rewrite now"},
    {"issue": "FORK_BETA: keep the old flag as an alias or drop it",
     "options": [
       {"id": "keep_alias", "text": "keep the alias", "cost": "two spellings of one flag to document"},
       {"id": "drop_alias", "text": "drop it", "cost": "scripts that pass the old flag break"}
     ],
     "preferred": "keep the alias"},
    {"issue": "FORK_GAMMA: widen the run to the three excluded pages or not",
     "options": [
       {"id": "widen", "text": "widen", "cost": "three more pages to survey and check"},
       {"id": "stay_narrow", "text": "stay narrow", "cost": "the excluded pages stay unchecked"}
     ],
     "preferred": "stay narrow"}
  ]
}'

seal_open_run "$target" "$proj"
echo "labelled_forks_all_relayed sandbox staged at $proj"
