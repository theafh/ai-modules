#!/usr/bin/env bash
# sweep_sampling_needs_user: four short prose pages, all piloted by the first
# wave, under a rule that swaps one glyph for another. Every hunk the rule makes
# is a glyph-for-glyph substitution, so a sampled checker set is available and
# the run must put it to the user rather than take it.

set -euo pipefail
THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$THIS_DIR/../_common.sh"

target="${1:?target dir required}"
proj="$(new_project "$target")"
mkdir -p "$proj/docs"

cat > "$proj/STYLE.md" <<'STYLE'
# Style rule

Replace every accented `é` with a plain `e`.
STYLE

cat > "$proj/docs/alpha.md" <<'PAGE'
# alpha

The café keeps a fiancé's décor in the back room.
PAGE

cat > "$proj/docs/beta.md" <<'PAGE'
# beta

A café and a fiancé share the décor.
PAGE

cat > "$proj/docs/gamma.md" <<'PAGE'
# gamma

The fiancé ordered café décor for the hall.
PAGE

cat > "$proj/docs/delta.md" <<'PAGE'
# delta

Décor notes sit beside the café ledger.
PAGE

seal "$target" "$proj"
echo "sweep_sampling_needs_user sandbox staged at $proj"
