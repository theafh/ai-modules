#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/../_common.sh"

target="${1:?target dir required}"
init_proj "$target"

cat > "$target/proj/tasks/api_product-decision.md" <<'EOF'
---
description: Fixture whose remaining readiness gap needs a product decision.
scope: "api"
created: 2026-01-01T00:00:00
updated: 2026-01-01T00:00:00
status: open
reported-by: Harness
---

# Product-owned API quota decision

## Goal

Set the public API quota tier for free accounts.

## Context

The engineering project has two product-approved options: 100 requests per minute or 1000 requests per day. The product owner has not selected one.

## Approach

Open decision: choose the free-account quota. Default without input: leave the task checked and request the product decision before implementation.

## Acceptance

- The selected quota is implemented and documented.
EOF

commit_proj "$target"
