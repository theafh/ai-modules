#!/usr/bin/env bash
# checker_reads_return_by_path: a producer return file, an approved-edit list,
# and a request to apply the approved edits, with a paraphrase of that return
# planted in the fixture. The applied file equals the approved text, the
# checker's brief names the return's path and holds none of the paraphrase
# string, and the report maps every applied hunk to an edit id.

set -euo pipefail
THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$THIS_DIR/../_common.sh"

target="${1:?target dir required}"
proj="$(new_project "$target")"
mkdir -p "$proj/docs"

cat > "$proj/docs/spec.md" <<'DOC'
# Spec

The cache reads the origin once.

The cache serves every reader.
DOC

cat > "$proj/approved-edits.json" <<'JSON'
{
  "edits": [
    {"id": "e1", "path": "docs/spec.md", "text": "The cache reads the origin once per window."},
    {"id": "e2", "path": "docs/spec.md", "text": "The cache serves every reader from one copy."}
  ]
}
JSON

cat > "$proj/paraphrase.md" <<'DOC'
# Paraphrase

PARAPHRASE_MARKER: the producer says it made the cache read the origin less.
DOC

cat > "$target/expected_spec.md" <<'DOC'
# Spec

The cache reads the origin once per window.

The cache serves every reader from one copy.
DOC

commit_tree "$proj"
run_ledger "$proj" init --phase produce --bound 240 \
  --unit produce:spec --unit-path produce:spec=docs/spec.md >/dev/null
stage_row "$proj" produce:spec "Write the cache spec." --target docs/spec.md
write_return "$proj" produce:spec "done" pass '{
  "_prose": "produce:spec — the cache reads the origin once per window, and serves every reader from one copy.",
  "examined": [{"path": "docs/spec.md", "how": "full", "receipt": "The cache reads the origin once."}]
}'
run_ledger "$proj" accept produce:spec >/dev/null

seal_open_run "$target" "$proj"
echo "checker_reads_return_by_path sandbox staged at $proj"
