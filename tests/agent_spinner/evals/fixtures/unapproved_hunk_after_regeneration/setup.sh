#!/usr/bin/env bash
# unapproved_hunk_after_regeneration: an approved-edit list holds two ids, and
# the regenerated file carries both edits plus one extra change. The file stays
# byte-identical, the checker's brief carries the list, and the report quotes
# the hunk that maps to no id.

set -euo pipefail
THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$THIS_DIR/../_common.sh"

target="${1:?target dir required}"
proj="$(new_project "$target")"
mkdir -p "$proj/docs"

cat > "$proj/docs/spec.md" <<'DOC'
# Spec

The parser reads a line at a time.

The writer emits one record per line.

Retries are bounded.
DOC

cat > "$proj/approved-edits.json" <<'JSON'
{
  "edits": [
    {"id": "e1", "path": "docs/spec.md", "text": "The parser reads a record at a time."},
    {"id": "e2", "path": "docs/spec.md", "text": "Retries are capped at three."}
  ]
}
JSON

commit_tree "$proj"
run_ledger "$proj" init --phase produce --bound 240 \
  --unit produce:spec --unit-path produce:spec=docs/spec.md >/dev/null
stage_row "$proj" produce:spec "Regenerate docs/spec.md from the approved edits." \
  --target docs/spec.md

# The regeneration applied both approved edits and appended one extra change.
cat > "$proj/docs/spec.md" <<'DOC'
# Spec

The parser reads a record at a time.

The writer emits one record per line.

Retries are capped at three.

Draft note: this paragraph was not approved.
DOC

seal_open_run "$target" "$proj"
echo "unapproved_hunk_after_regeneration sandbox staged at $proj"
