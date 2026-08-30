#!/usr/bin/env bash
# presence_gate: CHARTER.md + CLAUDE.md only. Audit those two; raise no
# missing-doc error for absent ARCHITECTURE/TESTING/SECURITY.

set -euo pipefail
THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$THIS_DIR/../_common.sh"

target="${1:?target dir required}"
proj="$(new_project "$target")"

cat > "$proj/CLAUDE.md" <<'EOF'
# CLAUDE.md

Follow the project charter when present. Prefer Make and POSIX shell
for automation.
EOF

cat > "$proj/CHARTER.md" <<'EOF'
# Fixture Charter

## Core Purpose

A small library that formats markdown tables.

## DOES / DOES NOT Domain Boundaries

### DOES

- Format markdown tables for documentation.

### DOES NOT

- Ship a hosted SaaS product or analytics backend.

## Key Invariants

- Soft standing documents stay subordinate to this charter.
EOF

git_commit_all "$proj" "stage presence_gate"
record_tree_hashes "$proj" "$target/.tree_sha256"

echo "presence_gate sandbox staged at $proj"
