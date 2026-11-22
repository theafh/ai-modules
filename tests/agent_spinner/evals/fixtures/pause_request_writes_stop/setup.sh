#!/usr/bin/env bash
# pause_request_writes_stop: the first wave has returned, its returns and their
# checks are accepted, and the second wave's rows are still pending. No STOP
# file is planted: a pause request in the second turn must write one, and no
# dispatch may follow that request.

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
  --unit produce:three --unit produce:four \
  --unit check:docs-one.md --unit check:docs-two.md >/dev/null

for name in one two; do
  stage_row "$proj" produce:"$name" "Rewrite docs/$name.md to use --workers." \
    --target "docs/$name.md"
  printf '# %s\n\nRun `tool.sh %s --workers 4`.\n' "$name" "$name" \
    > "$proj/docs/$name.md"
  write_return "$proj" produce:"$name" "done" pass "{
    \"_prose\": \"produce:$name — docs/$name.md is updated.\"
  }"
  run_ledger "$proj" accept produce:"$name" >/dev/null
  # The first wave's check keeps its written path covered, so the next writer
  # dispatch is not held behind an unchecked write.
  stage_row "$proj" check:docs-"$name".md "Check docs/$name.md against the brief." \
    --target "docs/$name.md"
  write_return "$proj" check:docs-"$name".md "done" pass '{}'
  run_ledger "$proj" accept check:docs-"$name".md >/dev/null
done

seal_open_run "$target" "$proj"
echo "pause_request_writes_stop sandbox staged at $proj"
