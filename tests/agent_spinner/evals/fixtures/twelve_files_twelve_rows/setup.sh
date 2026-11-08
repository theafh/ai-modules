#!/usr/bin/env bash
# twelve_files_twelve_rows: an imperative over twelve pages. The run opens
# twelve rows and writes twelve item briefs, one page each.

set -euo pipefail
THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$THIS_DIR/../_common.sh"

target="${1:?target dir required}"
proj="$(new_project "$target")"
mkdir -p "$proj/docs"

for n in $(seq -w 1 12); do
  printf '# page%s\n\nRun `tool.sh page%s --jobs 4`.\n' "$n" "$n" \
    > "$proj/docs/page$n.md"
done
printf 'The flag is now --workers everywhere.\n' > "$proj/NOTES.txt"

seal "$target" "$proj"
echo "twelve_files_twelve_rows sandbox staged at $proj"
