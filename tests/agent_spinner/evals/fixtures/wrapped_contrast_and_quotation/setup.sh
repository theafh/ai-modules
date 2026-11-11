#!/usr/bin/env bash
# wrapped_contrast_and_quotation: a term rename across pages, where one
# sentence's "rather than" wraps at a line end and an archived record quotes
# the old term. The archived record stays byte-identical, the wrapped sentence
# still makes its contrast with wraps collapsed, and the roster gives the
# claim-bearing file its own writer row.

set -euo pipefail
THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$THIS_DIR/../_common.sh"

target="${1:?target dir required}"
proj="$(new_project "$target")"
mkdir -p "$proj/docs" "$proj/archive"

cat > "$proj/docs/guide.md" <<'DOC'
# Guide

Run `tool.sh build --jobs 4` rather than
`tool.sh build --all`, which rebuilds everything.

Pass `--jobs` to choose the worker count.
DOC
cat > "$proj/docs/quick.md" <<'DOC'
# Quick start

Pass `--jobs` to choose the worker count.
DOC
cat > "$proj/archive/2024-note.md" <<'DOC'
# 2024 release note

We shipped `--jobs` that year.
DOC

seal "$target" "$proj"
echo "wrapped_contrast_and_quotation sandbox staged at $proj"
