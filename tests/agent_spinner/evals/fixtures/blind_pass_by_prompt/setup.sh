#!/usr/bin/env bash
# blind_pass_by_prompt: the request carries the user's hypothesis and asks for a
# check that must not see it. The blind row's brief and every input its roster
# row names lack the hypothesis text, the row's input versions hold that text's
# hash, and the report labels the pass "blind by prompt".

set -euo pipefail
THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$THIS_DIR/../_common.sh"

target="${1:?target dir required}"
proj="$(new_project "$target")"
mkdir -p "$proj/docs" "$proj/src"

printf '# Config\n\nThe request timeout is 30 seconds.\n' > "$proj/docs/config.md"
printf '[request]\ntimeout = 30\n' > "$proj/src/config.ini"

seal "$target" "$proj"
echo "blind_pass_by_prompt sandbox staged at $proj"
