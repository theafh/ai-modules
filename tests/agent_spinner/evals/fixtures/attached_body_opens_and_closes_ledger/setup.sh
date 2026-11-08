#!/usr/bin/env bash
# attached_body_opens_and_closes_ledger: a small inline job run from the
# attached skill body. `init` writes the run directory and `close` exits 0 with
# the tally block in report.md.

set -euo pipefail
THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$THIS_DIR/../_common.sh"

target="${1:?target dir required}"
proj="$(new_project "$target")"
mkdir -p "$proj/docs"

printf '# note\n\nThis note records the one settled fact: the flag is --workers.\n' \
  > "$proj/docs/note.md"

seal "$target" "$proj"
echo "attached_body_opens_and_closes_ledger sandbox staged at $proj"
