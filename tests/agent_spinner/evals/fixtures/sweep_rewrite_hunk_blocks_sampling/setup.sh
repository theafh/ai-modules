#!/usr/bin/env bash
# sweep_rewrite_hunk_blocks_sampling: the same four pages under the same glyph
# rule, except that docs/delta.md holds an instance the rule can remove only by
# rewriting its sentence. That hunk is no glyph-for-glyph substitution, so the
# sampling condition fails and every changed page gets a checker.

set -euo pipefail
THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$THIS_DIR/../_common.sh"

target="${1:?target dir required}"
proj="$(new_project "$target")"
mkdir -p "$proj/docs"

cat > "$proj/STYLE.md" <<'STYLE'
# Style rule

Replace every accented `é` with a plain `e`, keeping every sentence's meaning.
Where a plain `e` would turn one word into a different word, reword the sentence
instead of writing the wrong word.
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

The magazine's exposé will expose the contract's flaws.
PAGE

seal "$target" "$proj"
echo "sweep_rewrite_hunk_blocks_sampling sandbox staged at $proj"
