#!/usr/bin/env bash
# ledger_unavailable_by_hand: command execution is withheld, so the ledger
# cannot run. The run keeps the roster, briefs, and returns as hand-kept files
# under .agent_spinner/ and labels each mechanical check unenforced.

set -euo pipefail
THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$THIS_DIR/../_common.sh"

target="${1:?target dir required}"
proj="$(new_project "$target")"
mkdir -p "$proj/docs"

printf '# alpha\n\nRun `tool.sh alpha --jobs 4`.\n' > "$proj/docs/alpha.md"
printf 'The flag is now --workers everywhere.\n' > "$proj/NOTES.txt"

seal "$target" "$proj"
echo "ledger_unavailable_by_hand sandbox staged at $proj"
