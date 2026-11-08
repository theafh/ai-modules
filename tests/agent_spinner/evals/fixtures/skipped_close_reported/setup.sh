#!/usr/bin/env bash
# skipped_close_reported: an open run whose close never ran, plus a request to
# report it. The run stays open and the report's opening says no clean close
# exists.

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
stage_row "$proj" survey:alpha "Survey docs/alpha.md."
write_return "$proj" survey:alpha "done" pass '{
  "_prose": "survey:alpha — 1 finding.",
  "findings": [
    {"claim": "docs/alpha.md documents --jobs.", "severity": "major",
     "quote": "Run `tool.sh alpha --jobs 4`.", "anchor": "docs/alpha.md"}
  ]
}'
run_ledger "$proj" accept survey:alpha >/dev/null

# An unanswered user gate keeps the run open; close refuses until the user
# answers, and the run has not closed.
run_ledger "$proj" dispose --open-gate gate-1 \
  --question "Widen the run to the excluded pages?" >/dev/null

seal_open_run "$target" "$proj"
echo "skipped_close_reported sandbox staged at $proj"
