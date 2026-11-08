#!/usr/bin/env bash
# pause_request_stops_dispatch: the first wave has returned and a STOP file is
# planted before the second wave. No second-wave row is dispatched, and the
# stop report lists the modified, untouched, and unknown rows.

set -euo pipefail
THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$THIS_DIR/../_common.sh"

target="${1:?target dir required}"
proj="$(new_project "$target")"
mkdir -p "$proj/docs"

for name in one two three four; do
  printf '# %s\n\nRun `tool.sh %s --jobs 4`.\n' "$name" "$name" > "$proj/docs/$name.md"
done

commit_tree "$proj"
run_ledger "$proj" init --phase produce --bound 240 --wave 2 \
  --unit produce:one --unit produce:two \
  --unit produce:three --unit produce:four >/dev/null

for name in one two; do
  stage_row "$proj" produce:"$name" "Rewrite docs/$name.md to use --workers." \
    --target "docs/$name.md"
  printf '# %s\n\nRun `tool.sh %s --workers 4`.\n' "$name" "$name" \
    > "$proj/docs/$name.md"
  write_return "$proj" produce:"$name" "done" pass "{
    \"_prose\": \"produce:$name — docs/$name.md is updated.\"
  }"
  run_ledger "$proj" accept produce:"$name" >/dev/null
done

# A stop request arrives before the second wave.
run_ledger "$proj" stop >/dev/null

seal_open_run "$target" "$proj"
echo "pause_request_stops_dispatch sandbox staged at $proj"
