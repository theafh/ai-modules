#!/usr/bin/env bash
# select_inbound_dep fixture: the inbound-note direction under a scope filter.
# Candidate A (api_rate-limit-endpoint, ready) is SILENT about ordering in its
# own body. Task B (infra_shared-config-loader, ready) names a first-ship order
# over A in B's OWN body ("must ship before the rate-limit endpoint task ...").
# Under an "api" scope filter, A is in-filter and B is outside it. The rewritten
# <workflow> "Derive dependency and ordering relationships" step must scan the
# full live eligible set for the INBOUND note and report B as A's blocking
# prerequisite even though A says nothing and B is outside the filter. An
# unrelated unblocked api task (C) gives the selector a clean recommendation.

set -euo pipefail
THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$THIS_DIR/../_common.sh"

target="${1:?target dir required}"
proj="$(new_project "$target" --git)"
now="$(now_iso)"

emit_task() { # <path> <description> <scope> <status> <title> <body>
  cat > "$1" <<EOF
---
description: $2
scope: "$3"
created: $now
updated: $now
status: $4
reported-by: Test User
---

# $5

$6
EOF
}

# A — in-filter candidate, silent about ordering (mentions config keys only
# generically; no task link, no "depends on", no forward reference).
emit_task "$proj/tasks/api_rate-limit-endpoint.md" \
  "Add a per-key rate-limit endpoint to the public API." \
  "api" "ready" "Add the per-key rate-limit endpoint" \
  "## Goal

Expose an endpoint that returns and enforces the per-key request budget.

## Context

The endpoint reads its budget values from shared config keys.

## Approach

Add the handler, read the budget from config, and enforce it per key.

## Acceptance

- The endpoint returns the correct remaining budget for a known key."

# B — outside the api filter, names a first-ship order over A in its own body.
emit_task "$proj/tasks/infra_shared-config-loader.md" \
  "Build the shared config loader that defines the budget keys." \
  "infra" "ready" "Build the shared config loader" \
  "## Goal

Introduce the config loader that defines and exposes the per-key budget values.

## Context

This task must ship before the [rate-limit endpoint task](api_rate-limit-endpoint.md), which reads the budget keys this loader defines. Build this loader first so the endpoint has real keys to read.

## Approach

Author the loader, define the budget keys, and expose them to the API layer.

## Acceptance

- The loader exposes every budget key the API layer needs."

# C — an unrelated, unblocked api task so the filter has a clean recommendation.
emit_task "$proj/tasks/api_response-cache.md" \
  "Add a short-TTL response cache to the public API read path." \
  "api" "ready" "Add a response cache to the read path" \
  "## Goal

Cache read responses for a short TTL to cut repeated backend hits.

## Context

Self-contained change on the API read path; no other task touches it.

## Approach

Add a small in-process TTL cache in front of the read handler.

## Acceptance

- Repeated identical reads within the TTL are served from cache."

git_commit_all "$proj" "seed: inbound ordering note from an outside-scope task"

echo "select_inbound_dep sandbox staged at $proj"
