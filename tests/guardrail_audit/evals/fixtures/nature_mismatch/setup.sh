#!/usr/bin/env bash
# nature_mismatch: mixed multi-project layout. Audit must name the
# mismatch and propose nothing ill-fitting (no single-root ARCHITECTURE
# over unrelated projects).

set -euo pipefail
THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$THIS_DIR/../_common.sh"

target="${1:?target dir required}"
proj="$(new_project "$target")"

cat > "$proj/CLAUDE.md" <<'EOF'
# CLAUDE.md

This repository is a mixed multi-project layout: several unrelated
products share one checkout. Prefer per-project standing docs.
EOF

mkdir -p "$proj/projects/alpha/src" "$proj/projects/beta/src" "$proj/notes"
cat > "$proj/projects/alpha/README.md" <<'EOF'
# Alpha

A Go HTTP service for inventory.
EOF
cat > "$proj/projects/alpha/src/main.go" <<'EOF'
package main

func main() {}
EOF
cat > "$proj/projects/beta/README.md" <<'EOF'
# Beta

A Python data notebook collection, unrelated to Alpha.
EOF
cat > "$proj/projects/beta/src/analysis.py" <<'EOF'
def run():
    return "notebook"
EOF
cat > "$proj/notes/README.md" <<'EOF'
# Shared scratch notes

Not a product.
EOF

git_commit_all "$proj" "stage nature_mismatch"
record_tree_hashes "$proj" "$target/.tree_sha256"

echo "nature_mismatch sandbox staged at $proj"
