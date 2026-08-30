#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/../_common.sh"

target="${1:?target dir required}"
init_proj "$target"

cat > "$target/proj/tasks/api_pathological.md" <<'EOF'
---
description: Pathological task fixture that remains under-specified across repair attempts.
scope: "api"
created: 2026-01-01T00:00:00
updated: 2026-01-01T00:00:00
status: open
reported-by: Harness
---

# Pathological API task

## Goal

Make the API better for enterprise users.

## Context

Important enterprise details are unavailable in the repository.

## Approach

Improve the API after figuring out what enterprise users need.

## Acceptance

- Enterprise users are happier.
EOF

commit_proj "$target"
