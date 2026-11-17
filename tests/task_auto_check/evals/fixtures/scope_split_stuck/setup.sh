#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/../_common.sh"

target="${1:?target dir required}"
init_proj "$target"

mkdir -p "$target/proj/src/api" "$target/proj/src/billing"

# Both files the Context names exist, so the premise holds and the two
# unrelated deliverables (the auth failure response and the CSV columns)
# leave scope/focus as the substantive readiness issue.
cat > "$target/proj/src/api/auth.py" <<'EOF'
"""Authenticate public API requests by API key."""

API_KEYS = {"key-alice": "user-alice", "key-bob": "user-bob"}


def authenticate(request):
    """Return (user_id, None) on success, or (None, error response) on failure."""
    user_id = API_KEYS.get(request.get("headers", {}).get("X-API-Key"))
    if user_id is None:
        return None, {
            "status": 403,
            "headers": {"Content-Type": "text/plain"},
            "body": "forbidden",
        }
    return user_id, None
EOF

cat > "$target/proj/src/billing/export.py" <<'EOF'
"""Billing CSV export."""

import csv
import io

COLUMNS = ["invoice_id", "customer_id", "amount", "currency"]


def export_invoices_csv(invoices):
    """Render invoice dicts as CSV with one header row."""
    buffer = io.StringIO()
    writer = csv.DictWriter(buffer, fieldnames=COLUMNS, extrasaction="ignore")
    writer.writeheader()
    writer.writerows(invoices)
    return buffer.getvalue()
EOF

cat > "$target/proj/tasks/api_combo-auth-billing.md" <<'EOF'
---
description: Oversized fixture that combines unrelated API auth and billing export work.
scope: "api"
created: 2026-01-01T00:00:00Z
updated: 2026-01-01T00:00:00Z
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
