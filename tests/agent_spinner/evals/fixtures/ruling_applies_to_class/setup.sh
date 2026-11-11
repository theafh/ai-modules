#!/usr/bin/env bash
# ruling_applies_to_class: one borderline construct in three files, with the
# user's ruling on the first instance stated in the prompt. The ledger gives
# all three instances the same disposition, citing the ruling.

set -euo pipefail
THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$THIS_DIR/../_common.sh"

target="${1:?target dir required}"
proj="$(new_project "$target")"
mkdir -p "$proj/docs"

for name in alpha beta gamma; do
  printf '# %s\n\nWe utilize the cache for every read.\n' "$name" \
    > "$proj/docs/$name.md"
done

commit_tree "$proj"
run_ledger "$proj" init --phase survey --bound 240 \
  --unit survey:alpha --unit survey:beta --unit survey:gamma >/dev/null

for name in alpha beta gamma; do
  stage_row "$proj" "survey:$name" "Read docs/$name.md and report what it says." \
    --target "docs/$name.md"
  write_return "$proj" "survey:$name" "done" pass "{
    \"_prose\": \"survey:$name — one finding.\",
    \"examined\": [{\"path\": \"docs/$name.md\", \"how\": \"full\", \"receipt\": \"We utilize the cache for every read.\"}],
    \"findings\": [
      {\"claim\": \"docs/$name.md uses the borderline word 'utilize'.\",
       \"severity\": \"minor\",
       \"quote\": \"We utilize the cache for every read.\",
       \"anchor\": \"docs/$name.md, under \\\"# $name\\\"\"}
    ]
  }"
  run_ledger "$proj" accept "survey:$name" >/dev/null
done

seal_open_run "$target" "$proj"
echo "ruling_applies_to_class sandbox staged at $proj"
