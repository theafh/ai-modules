#!/usr/bin/env bash
# smoke_withheld_shell: an empty sandbox. The eval asks for one shell command
# while the runner withholds the shell class.

set -euo pipefail
THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$THIS_DIR/../_common.sh"

target="${1:?target dir required}"
proj="$(new_project "$target")"
printf 'smoke sandbox\n' > "$proj/README.txt"

seal "$target" "$proj"
echo "smoke_withheld_shell sandbox staged at $proj"
