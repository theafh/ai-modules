#!/usr/bin/env bash
# doc_vs_doc: ARCHITECTURE.md mandates a hosted SaaS product that the
# charter's DOES NOT forbids. Audit must surface the contradiction with
# charter authoritative and the architecture passage to reconcile.

set -euo pipefail
THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$THIS_DIR/../_common.sh"

target="${1:?target dir required}"
proj="$(new_project "$target")"

cat > "$proj/CLAUDE.md" <<'EOF'
# CLAUDE.md

Keep edits inside the charter boundaries.
EOF

cat > "$proj/CHARTER.md" <<'EOF'
# Fixture Charter

## Core Purpose

A CLI tool that validates OpenAPI specs locally.

## DOES / DOES NOT Domain Boundaries

### DOES

- Validate OpenAPI documents on the developer's machine.

### DOES NOT

- Become a hosted SaaS product or multi-tenant API gateway.

## Key Invariants

- Soft standing documents stay subordinate to this charter.
EOF

cat > "$proj/ARCHITECTURE.md" <<'EOF'
# Architecture

## Goals

Deliver a multi-tenant hosted SaaS product with a public API gateway
that validates OpenAPI specs for paying customers in the cloud.

## Stack

- TypeScript services behind a managed Kubernetes cluster
- Shared billing and tenant isolation layer
EOF

git_commit_all "$proj" "stage doc_vs_doc"
record_tree_hashes "$proj" "$target/.tree_sha256"

echo "doc_vs_doc sandbox staged at $proj"
