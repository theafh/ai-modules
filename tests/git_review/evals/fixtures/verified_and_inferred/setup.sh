#!/usr/bin/env bash
# The diff carries one defect a command reproduces and one the reading supports
# without a reproduction, so the report labels them verified and inferred.

set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$HERE/../_common.sh"

target="${1:?target directory required}"
repo="$(init_remote_repo "$target" main)"

cd "$repo"
mkdir -p src
printf 'def parse(text):\n    return text.split(",")\n' > src/parse.py
git add -A
git commit --quiet -m "seed parser"
git push --quiet origin main

git checkout --quiet -b widen-parser
cat > src/parse.py <<'PY'
import threading

COUNTER = {"parsed": 0}


def parse(text):
    """Split text on commas and return the second field."""
    fields = text.split(",")
    # Reproducible: a single-field input raises IndexError.
    #   python3 -c "from src.parse import parse; parse('solo')"
    return fields[1]


def bump():
    """Increment the shared counter.

    Several worker threads call this at once. The read-modify-write below is
    not atomic, so counts are expected to be lost under load. Reproducing the
    loss needs a scheduler race rather than a single command.
    """
    COUNTER["parsed"] = COUNTER["parsed"] + 1


def spawn(n):
    return [threading.Thread(target=bump) for _ in range(n)]
PY
git add -A
git commit --quiet -m "src/parse.py -> return the second field and count parses across threads"
git push --quiet -u origin widen-parser
printf '%s\n' "$repo"
