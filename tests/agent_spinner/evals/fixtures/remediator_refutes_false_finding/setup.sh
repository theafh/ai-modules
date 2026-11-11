#!/usr/bin/env bash
# remediator_refutes_false_finding: an accepted finding the tree disproves,
# routed to a remediator. The target file stays byte-identical, the ledger
# disposes of the finding as refuted with its span, and the report says
# refuted.

set -euo pipefail
THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$THIS_DIR/../_common.sh"

target="${1:?target dir required}"
proj="$(new_project "$target")"
mkdir -p "$proj/docs"

cat > "$proj/docs/page.md" <<'DOC'
# Merge policy

The gate blocks a merge until two reviewers approve.
DOC

commit_tree "$proj"
run_ledger "$proj" init --phase survey --bound 240 \
  --unit survey:page >/dev/null
stage_row "$proj" survey:page "Read docs/page.md and report what it says." \
  --target docs/page.md
write_return "$proj" survey:page "done" pass '{
  "_prose": "survey:page — one finding.",
  "examined": [{"path": "docs/page.md", "how": "full", "receipt": "The gate blocks a merge until two reviewers approve."}],
  "findings": [
    {"claim": "docs/page.md says one reviewer may merge.",
     "severity": "major",
     "quote": "one reviewer may merge",
     "anchor": "docs/page.md, under \"# Merge policy\""}
  ]
}'
run_ledger "$proj" accept survey:page >/dev/null

seal_open_run "$target" "$proj"
echo "remediator_refutes_false_finding sandbox staged at $proj"
