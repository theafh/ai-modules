#!/usr/bin/env bash
# completion_turn_advances_phase: turn one ends with an open run and one
# dispatched row. The between step writes that row's return file, and turn two
# resumes with a completion notice. The ledger accepts the return and the next
# phase starts or a gate opens.

set -euo pipefail
THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$THIS_DIR/../_common.sh"

target="${1:?target dir required}"
proj="$(new_project "$target")"
mkdir -p "$proj/docs"

printf '# alpha\n\nRun `tool.sh alpha --jobs 4`.\n' > "$proj/docs/alpha.md"

commit_tree "$proj"
run_ledger "$proj" init --phase produce --bound 3600 \
  --unit produce:alpha --unit check:alpha-check \
  --unit-path produce:alpha=docs/alpha.md >/dev/null
run_ledger "$proj" brief produce:alpha --target docs/alpha.md \
  --body "Rewrite docs/alpha.md to use --workers." >/dev/null
run_ledger "$proj" dispatch produce:alpha >/dev/null

seal_open_run "$target" "$proj"
echo "completion_turn_advances_phase sandbox staged at $proj"
