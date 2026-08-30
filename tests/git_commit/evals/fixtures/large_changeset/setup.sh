#!/usr/bin/env bash
# Eval 4 fixture: 60 modified tracked files (large changeset).

set -euo pipefail
THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$THIS_DIR/../_common.sh"

target="${1:?target dir required}"
init_sandbox "$target"

(
    cd "$target"
    for i in $(seq -w 1 60); do
        printf 'v1\n' > "f$i.txt"
    done
    git add . && git commit --quiet -m "60 files baseline"
    for i in $(seq -w 1 60); do
        printf 'v2\n' > "f$i.txt"
    done
)

echo "Eval 4 sandbox staged at $target"
