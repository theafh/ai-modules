#!/usr/bin/env bash
# shape_matched_no_recipe: an enumerated imperative over five pages matches
# per-artifact fan-out, and the recipe table is empty, so the ask matches a
# shape and no recipe. The run proceeds from the body and says so.

set -euo pipefail
THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$THIS_DIR/../_common.sh"

target="${1:?target dir required}"
proj="$(new_project "$target")"
mkdir -p "$proj/docs"

cat > "$proj/docs/alpha.md" <<'PAGE'
# Alpha

The alpha service stores release notes and serves them over HTTP.
PAGE

cat > "$proj/docs/beta.md" <<'PAGE'
# Beta

The beta service indexes documents and answers search queries.
PAGE

cat > "$proj/docs/gamma.md" <<'PAGE'
# Gamma

The gamma service schedules jobs and reports their status.
PAGE

cat > "$proj/docs/delta.md" <<'PAGE'
# Delta

The delta service stores audit records and expires them on a fixed schedule.
PAGE

cat > "$proj/docs/epsilon.md" <<'PAGE'
# Epsilon

The epsilon service forwards notifications and retries failed deliveries.
PAGE

seal "$target" "$proj"
echo "shape_matched_no_recipe sandbox staged at $proj"
