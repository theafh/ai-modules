#!/usr/bin/env bash
# A repository carrying all four root guardrail documents, whose history already
# holds a prior commit touching the same charter constraint, and whose branch
# crosses that charter boundary, diverges from TESTING.md and SECURITY.md, and
# falls short of the direction ARCHITECTURE.md declares.

set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$HERE/../_common.sh"

target="${1:?target directory required}"
repo="$(init_remote_repo "$target" main)"

cd "$repo"
plant_guardrails "$repo"
mkdir -p src tests
cat > src/paths.py <<'PY'
def sanitize(path):
    """Every caller-supplied path passes through here before it is opened."""
    return path.replace("..", "")
PY
cat > src/convert.py <<'PY'
FORMATS = {"csv": 1, "tsv": 2}


def convert(rows, fmt):
    return [r for r in rows if FORMATS[fmt]]
PY
cat > tests/test_convert.py <<'PY'
from src.convert import convert


def test_convert():
    assert convert([1], "csv") == [1]
PY
git add -A
git commit --quiet -m "seed converter, its test, and the guardrail documents"
git push --quiet origin main

# The precedent commit: an earlier change that hit the same charter constraint
# and was resolved by keeping the work offline.
cat > src/fetch_hint.py <<'PY'
def remote_hint(url):
    """Charter: widget opens no network connection.

    An earlier revision called urllib here. It was replaced by this offline
    hint so the converter keeps the charter's no-network boundary.
    """
    return "run `widget fetch {}` yourself and pass the file".format(url)
PY
git add -A
git commit --quiet -m "src/fetch_hint.py -> keep the URL path offline rather than opening a connection, per CHARTER.md"
git push --quiet origin main

git checkout --quiet -b add-sync
cat > src/sync.py <<'PY'
import urllib.request


def sync(rows, endpoint, destination):
    """Push rows to an endpoint and mirror them to a local file."""
    # Crosses the charter boundary: widget opens no network connection.
    urllib.request.urlopen(endpoint, data=b"".join(rows))

    # Diverges from SECURITY.md: caller-supplied paths pass the sanitizer first.
    with open(destination, "w") as fh:
        fh.write("synced")


def sync_dry_run(rows):
    """A second public function, shipped without the unit test TESTING.md asks for."""
    return len(rows)
PY
# ARCHITECTURE.md declares a plugin registry as the direction; this stays on the
# hardcoded table, which is unmet work rather than a defect.
cat > src/convert.py <<'PY'
FORMATS = {"csv": 1, "tsv": 2, "jsonl": 3}


def convert(rows, fmt):
    return [r for r in rows if FORMATS[fmt]]
PY
git add -A
git commit --quiet -m "Add a sync command and a third hardcoded format"
git push --quiet -u origin add-sync
printf '%s\n' "$repo"
