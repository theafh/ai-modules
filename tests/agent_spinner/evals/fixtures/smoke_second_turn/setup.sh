#!/usr/bin/env bash
# smoke_second_turn: an empty sandbox. The first turn carries one token, the
# between step writes a second, and the resumed turn writes both to smoke.txt.

set -euo pipefail
THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$THIS_DIR/../_common.sh"

target="${1:?target dir required}"
proj="$(new_project "$target")"
printf 'smoke sandbox\n' > "$proj/README.txt"

seal "$target" "$proj"
echo "smoke_second_turn sandbox staged at $proj"
