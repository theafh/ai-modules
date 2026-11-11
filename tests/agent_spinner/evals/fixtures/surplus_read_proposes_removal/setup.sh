#!/usr/bin/env bash
# surplus_read_proposes_removal: a merged artifact restates a rule another file
# holds. The surplus read's return names the restated rule for conversion into
# a citation, and the artifact stays byte-identical.

set -euo pipefail
THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$THIS_DIR/../_common.sh"

target="${1:?target dir required}"
proj="$(new_project "$target")"
mkdir -p "$proj/docs"

cat > "$proj/docs/rules.md" <<'DOC'
# Rules

Every write helper names exactly one target path.
DOC
cat > "$proj/docs/merged.md" <<'DOC'
# Merged guide

## Scope

The guide covers the write path.

## Handoff

Every write helper names exactly one target path.
DOC

seal "$target" "$proj"
echo "surplus_read_proposes_removal sandbox staged at $proj"
