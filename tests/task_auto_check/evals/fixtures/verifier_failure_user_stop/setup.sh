#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/../_common.sh"

target="${1:?target dir required}"
init_proj "$target"

mkdir -p "$target/proj/docs" "$target/proj/src/api"
: > "$target/proj/docs/api.md"
: > "$target/proj/src/api/quota.py"

cat > "$target/proj/tasks/api_quota-headers.md" <<'EOF'
---
description: Add quota usage headers to API responses.
scope: "api"
created: 2026-01-01T00:00:00
updated: 2026-01-01T00:00:00
status: open
reported-by: Harness
---

# Quota usage headers for API responses

## Goal

Add quota usage headers to public API responses.

## Context

The implementation lives in the API quota code.

## Approach

TBD.

## Acceptance

- The quota headers work properly.
EOF

commit_proj "$target"
