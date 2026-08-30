#!/usr/bin/env bash
# missing_testing: a real test suite exists and TESTING.md does not.
# Audit must propose a grounded TESTING.md via the hub suggest flow and
# create no file.

set -euo pipefail
THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$THIS_DIR/../_common.sh"

target="${1:?target dir required}"
proj="$(new_project "$target")"

cat > "$proj/CLAUDE.md" <<'EOF'
# CLAUDE.md

Single Python library. Run tests with pytest.
EOF

cat > "$proj/CHARTER.md" <<'EOF'
# Fixture Charter

## Core Purpose

A Python library that parses TOML configuration files.

## DOES / DOES NOT Domain Boundaries

### DOES

- Parse and validate TOML configuration.

### DOES NOT

- Host a remote configuration service.

## Key Invariants

- Soft standing documents stay subordinate to this charter.
EOF

mkdir -p "$proj/src" "$proj/tests"
cat > "$proj/src/parse.py" <<'EOF'
def parse_toml(text: str) -> dict:
    return {"ok": True, "raw": text}
EOF

cat > "$proj/tests/test_parse.py" <<'EOF'
from src.parse import parse_toml


def test_parse_returns_ok():
    assert parse_toml("a = 1")["ok"] is True
EOF

cat > "$proj/pyproject.toml" <<'EOF'
[project]
name = "toml-fixture"
version = "0.1.0"

[tool.pytest.ini_options]
testpaths = ["tests"]
EOF

git_commit_all "$proj" "stage missing_testing"
record_tree_hashes "$proj" "$target/.tree_sha256"

echo "missing_testing sandbox staged at $proj"
