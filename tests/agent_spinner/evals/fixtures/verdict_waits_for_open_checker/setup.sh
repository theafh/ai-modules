#!/usr/bin/env bash
# verdict_waits_for_open_checker: an open run has a dispatched checker with no
# return. The checked artifact's status field stays byte-identical, and the
# report's opening names the pending checker row.

set -euo pipefail
THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$THIS_DIR/../_common.sh"

target="${1:?target dir required}"
proj="$(new_project "$target")"
mkdir -p "$proj/docs"

printf '# report\n\nstatus: draft\n\nBody text under review.\n' > "$proj/docs/report.md"

commit_tree "$proj"
run_ledger "$proj" init --phase check --bound 240 \
  --unit produce:report --unit check:report-check >/dev/null

stage_row "$proj" produce:report "Write the report body." --target docs/report.md
write_return "$proj" produce:report "done" pass '{
  "_prose": "produce:report — the body is written."
}'
run_ledger "$proj" accept produce:report >/dev/null

run_ledger "$proj" brief check:report-check --checker --relay produce:report \
  --target docs/report.md --body "Check docs/report.md against its brief." >/dev/null
run_ledger "$proj" dispatch check:report-check >/dev/null
# check:report-check has not returned.

seal_open_run "$target" "$proj"
echo "verdict_waits_for_open_checker sandbox staged at $proj"
