#!/usr/bin/env bash
# A feature branch one commit ahead whose change introduces no finding under any
# heading: a docstring correction with its test already in place.

set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$HERE/../_common.sh"

target="${1:?target directory required}"
repo="$(init_remote_repo "$target" main)"

cd "$repo"
mkdir -p src tests
cat > src/greet.py <<'PY'
def greet(name):
    """Return a greeting for name."""
    return "hello " + name
PY
cat > tests/test_greet.py <<'PY'
from src.greet import greet


def test_greet():
    assert greet("ada") == "hello ada"
PY
git add -A
git commit --quiet -m "seed greeter"
git push --quiet origin main

git checkout --quiet -b docs/greet-docstring
cat > src/greet.py <<'PY'
def greet(name):
    """Return the greeting "hello <name>" for the given name."""
    return "hello " + name
PY
git add -A
git commit --quiet -m "src/greet.py -> state the exact greeting the docstring promises"
git push --quiet -u origin docs/greet-docstring
printf '%s\n' "$repo"
