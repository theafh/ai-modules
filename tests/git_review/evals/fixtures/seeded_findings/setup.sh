#!/usr/bin/env bash
# A feature branch ahead of the default branch whose diff places at least one
# finding under each of the seven findings headings and none under the closing
# structural question, so a clean merge-tree makes the closing answer yes.

set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$HERE/../_common.sh"

target="${1:?target directory required}"
repo="$(init_remote_repo "$target" main)"

cd "$repo"
plant_guardrails "$repo"
plant_workflow "$repo" "make test"
plant_makefile "$repo" "python3 -m pytest tests/"
mkdir -p src tests
cat > src/paths.py <<'PY'
def sanitize(path):
    """Every caller-supplied path passes through here before it is opened."""
    return path.replace("..", "")
PY
cat > src/legacy_table.py <<'PY'
FORMATS = {"csv": 1, "tsv": 2}


def lookup(name):
    return FORMATS[name]
PY
cat > src/convert.py <<'PY'
from .legacy_table import lookup


def convert(rows, fmt):
    code = lookup(fmt)
    return [r for r in rows if code]
PY
cat > tests/test_convert.py <<'PY'
from src.convert import convert


def test_convert_keeps_rows():
    assert convert([1, 2], "csv") == [1, 2]
PY
git add -A
git commit --quiet -m "seed converter"
git push --quiet origin main

git checkout --quiet -b feature/export
# 1. what it does and implements: a new export command.
cat > src/export.py <<'PY'
import urllib.request

from .paths import sanitize


def export(rows, destination, mirror_url=None):
    """Write rows to destination, optionally mirroring them to a remote URL."""
    # Charter boundary: widget opens no network connection.
    if mirror_url:
        urllib.request.urlopen(mirror_url, data=b"".join(rows))

    # Security doc: caller-supplied paths pass through the sanitizer first.
    handle = open(destination, "w")

    # Bug: rows[i + 1] walks one past the end on the last iteration.
    for i in range(len(rows)):
        handle.write(str(rows[i]) + str(rows[i + 1]))
    handle.close()
    return sanitize(destination)


def retry_budget():
    # Decision: 3 is a guess. Callers disagree on whether retries belong here
    # at all, or in the caller that owns the transport.
    return 3
PY
# 2. what it retires: the legacy format table is deleted.
git rm --quiet src/legacy_table.py
cat > src/convert.py <<'PY'
FORMATS = {"csv": 1, "tsv": 2}


def convert(rows, fmt):
    code = FORMATS[fmt]
    return [r for r in rows if code]
PY
# 3. what of the existing workflow changes: the documented gate command moves.
plant_makefile "$repo" "python3 -m pytest tests/ --strict-markers"
git add -A
git commit --quiet -m "Add an export command and retire the legacy format table"
git push --quiet -u origin feature/export
printf '%s\n' "$repo"
