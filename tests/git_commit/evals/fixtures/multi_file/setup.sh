#!/usr/bin/env bash
# Eval 2 fixture: three modified tracked files across two directories.

set -euo pipefail
THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$THIS_DIR/../_common.sh"

target="${1:?target dir required}"
init_sandbox "$target"

(
    cd "$target"
    mkdir -p src docs
    printf 'baseline a\n' > src/a.py
    printf 'baseline b\n' > src/b.py
    printf 'baseline notes\n' > docs/notes.md
    git add . && git commit --quiet -m "baseline tree"
    printf 'updated a\n' > src/a.py
    printf 'updated b\n' > src/b.py
    printf 'updated notes\n' > docs/notes.md
)

echo "Eval 2 sandbox staged at $target"
