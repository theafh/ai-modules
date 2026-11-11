#!/usr/bin/env bash
# verifier_brief_carries_no_preference: two reviewer returns and a notes file
# that states a preference. The verifier's brief names both return files by
# path and holds none of the notes' preference strings.

set -euo pipefail
THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$THIS_DIR/../_common.sh"

target="${1:?target dir required}"
proj="$(new_project "$target")"
mkdir -p "$proj/reviews"

cat > "$proj/reviews/a.md" <<'DOC'
# Option A

A local index answers the read path without a network hop.
DOC
cat > "$proj/reviews/b.md" <<'DOC'
# Option B

A shared cache keeps one copy warm for every reader.
DOC
cat > "$proj/notes.md" <<'DOC'
# Notes

This is my own read: I likely approve A, and I prefer A over B.
DOC

commit_tree "$proj"
run_ledger "$proj" init --phase check --bound 240 \
  --unit check:compare >/dev/null

seal_open_run "$target" "$proj"
echo "verifier_brief_carries_no_preference sandbox staged at $proj"
