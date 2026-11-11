#!/usr/bin/env bash
# reader_gets_snapshot: a checker reads a page while the orchestrator edits that
# page's index entry. The checker brief names a snapshot copy under
# .agent_spinner/snapshots/, the report names the delta between the snapshot and
# the final file, and the run adds no ref or object to the sandbox repository.

set -euo pipefail
THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$THIS_DIR/../_common.sh"

target="${1:?target dir required}"
proj="$(new_project "$target")"
mkdir -p "$proj/docs"

cat > "$proj/docs/page.md" <<'DOC'
# Page

Run `tool.sh page --jobs 4`.
DOC

cat > "$proj/docs/index.md" <<'DOC'
# Index

- page.md — the page command
- other.md — another page
DOC

printf '# Other\n\nRun `tool.sh other`.\n' > "$proj/docs/other.md"

seal "$target" "$proj"
record_repo_guard "$target" "$proj"
echo "reader_gets_snapshot sandbox staged at $proj"
