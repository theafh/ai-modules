#!/usr/bin/env bash
# Eval 1 fixture: one modified tracked file.

set -euo pipefail
THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$THIS_DIR/../_common.sh"

target="${1:?target dir required}"
init_sandbox "$target"

(
    cd "$target"
    printf 'updated content\n' > seed.txt
)

echo "Eval 1 sandbox staged at $target"
