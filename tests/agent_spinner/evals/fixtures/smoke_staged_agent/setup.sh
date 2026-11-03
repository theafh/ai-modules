#!/usr/bin/env bash
# smoke_staged_agent: an empty sandbox. The eval stages a mock agent from
# agents/ and asks the worker to spawn it by name.

set -euo pipefail
THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$THIS_DIR/../_common.sh"

target="${1:?target dir required}"
proj="$(new_project "$target")"
printf 'smoke sandbox\n' > "$proj/README.txt"

seal "$target" "$proj"
echo "smoke_staged_agent sandbox staged at $proj"
