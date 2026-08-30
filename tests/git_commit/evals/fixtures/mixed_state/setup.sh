#!/usr/bin/env bash
# Eval 3 fixture: mixed pre-staged + unstaged + untracked working tree.

set -euo pipefail
THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$THIS_DIR/../_common.sh"

target="${1:?target dir required}"
init_sandbox "$target"

(
    cd "$target"
    printf 'baseline old_staged\n' > old_staged.txt
    git add old_staged.txt && git commit --quiet -m "baseline old_staged"

    # Unstaged modification to seed.txt
    printf 'unstaged update\n' > seed.txt

    # Pre-staged change to old_staged.txt
    printf 'pre-staged change\n' > old_staged.txt
    git add old_staged.txt

    # Untracked new file
    printf 'fresh\n' > new.txt
)

echo "Eval 3 sandbox staged at $target"
