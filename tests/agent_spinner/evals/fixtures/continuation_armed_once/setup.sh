#!/usr/bin/env bash
# continuation_armed_once: a three-file job with every gate answer stated. On
# Cursor the goal tool arms exactly one goal whose objective names the run
# directory; on Claude no goal tool exists and the announcement names re-entry
# through status and attach.

set -euo pipefail
THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$THIS_DIR/../_common.sh"

target="${1:?target dir required}"
proj="$(new_project "$target")"
mkdir -p "$proj/docs"

for name in alpha beta gamma; do
  printf '# %s\n\nRun `tool.sh %s --jobs 4`.\n' "$name" "$name" > "$proj/docs/$name.md"
done
printf 'The flag is now --workers everywhere.\n' > "$proj/NOTES.txt"

seal "$target" "$proj"
echo "continuation_armed_once sandbox staged at $proj"
