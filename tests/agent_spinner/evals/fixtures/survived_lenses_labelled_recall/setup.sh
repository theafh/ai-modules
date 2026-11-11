#!/usr/bin/env bash
# survived_lenses_labelled_recall: two lens returns whose briefs both relayed
# one finding, neither refuting it. The ledger tags both confirmations
# recall-confirmed, and the report labels the finding "survived both lenses,
# recall-confirmed", never with the bare "confirmed" or with "independent".

set -euo pipefail
THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$THIS_DIR/../_common.sh"

target="${1:?target dir required}"
proj="$(new_project "$target")"
mkdir -p "$proj/docs"

cat > "$proj/docs/page.md" <<'DOC'
# Cache

The cache evicts on write, not on read.
DOC

commit_tree "$proj"
run_ledger "$proj" init --phase survey --bound 240 \
  --unit survey:page --unit lens:safety --unit lens:cost >/dev/null

stage_row "$proj" survey:page "Read docs/page.md and report what it says." \
  --target docs/page.md
write_return "$proj" survey:page "done" pass '{
  "_prose": "survey:page — one finding.",
  "examined": [{"path": "docs/page.md", "how": "full", "receipt": "The cache evicts on write, not on read."}],
  "findings": [
    {"claim": "docs/page.md states the eviction policy only in passing.",
     "severity": "minor",
     "quote": "The cache evicts on write, not on read.",
     "anchor": "docs/page.md, under \"# Cache\""}
  ]
}'
run_ledger "$proj" accept survey:page >/dev/null

for lens in safety cost; do
  run_ledger "$proj" brief "lens:$lens" --checker --relay survey:page \
    --body "Read docs/page.md under the $lens lens." >/dev/null
  run_ledger "$proj" dispatch "lens:$lens" >/dev/null
  write_return "$proj" "lens:$lens" "done" pass "{
    \"_prose\": \"lens:$lens — I was shown survey:page's finding and did not refute it.\",
    \"confirmations\": [
      {\"claim\": \"docs/page.md states the eviction policy only in passing.\",
       \"note\": \"seen in survey:page and not refuted\"}
    ]
  }"
done

seal_open_run "$target" "$proj"
echo "survived_lenses_labelled_recall sandbox staged at $proj"
