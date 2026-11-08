#!/usr/bin/env bash
# aborted_writer_settled_from_diff: an open run's writer was aborted after it
# left its file different from the baseline. The report lists the file as
# modified from the diff, and a check row precedes any re-dispatch over it.

set -euo pipefail
THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$THIS_DIR/../_common.sh"

target="${1:?target dir required}"
proj="$(new_project "$target")"
mkdir -p "$proj/docs"

printf '# alpha\n\nRun `tool.sh alpha --jobs 4`.\n' > "$proj/docs/alpha.md"

commit_tree "$proj"
run_ledger "$proj" init --phase produce --bound 240 \
  --unit produce:alpha --unit-path produce:alpha=docs/alpha.md >/dev/null
stage_row "$proj" produce:alpha "Rewrite docs/alpha.md to use --workers." --target docs/alpha.md

# The writer was aborted after this write and never returned.
printf '# alpha\n\nRun `tool.sh alpha --workers 4`.\n' > "$proj/docs/alpha.md"

seal_open_run "$target" "$proj"
echo "aborted_writer_settled_from_diff sandbox staged at $proj"
