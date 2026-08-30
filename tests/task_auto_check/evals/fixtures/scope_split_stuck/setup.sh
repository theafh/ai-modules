#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/../_common.sh"

target="${1:?target dir required}"
init_proj "$target"

cat > "$target/proj/tasks/api_combo-auth-billing.md" <<'EOF'
---
description: Oversized fixture that combines unrelated API auth and billing export work.
scope: "api"
created: 2026-01-01T00:00:00
updated: 2026-01-01T00:00:00
status: open
reported-by: Harness
---

# API auth and billing export combo

## Goal

Update API authentication errors and redesign billing CSV exports in one pass.

## Context

API auth lives in `src/api/auth.py`; billing export lives in `src/billing/export.py`.

## Approach

Change both systems together.

## Acceptance

- API auth failures return HTTP 401 with a JSON error code.
- Billing CSV exports include tax-region columns.
EOF

commit_proj "$target"
