#!/usr/bin/env bash
# attached_body_reads_recipe: five short pages and one audit rubric. The ask is
# a read-only audit of every page, so the selector matches the check-only-audit
# recipe. The worker gets the skill body as an attachment, without its reference
# files, and must still read and name the recipe its ask matches.

set -euo pipefail
THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$THIS_DIR/../_common.sh"

target="${1:?target dir required}"
proj="$(new_project "$target")"
mkdir -p "$proj/pages"

printf '# Alpha\n\nAlpha holds one sentence about the first topic.\n' \
  > "$proj/pages/alpha.md"
printf '# Beta\n\nBeta holds one sentence about the second topic.\n' \
  > "$proj/pages/beta.md"
printf '# Gamma\n\nGamma holds one sentence about the third topic.\n' \
  > "$proj/pages/gamma.md"
printf '# Delta\n\nDelta holds one sentence about the fourth topic.\n' \
  > "$proj/pages/delta.md"
printf '# Epsilon\n\nEpsilon holds one sentence about the fifth topic.\n' \
  > "$proj/pages/epsilon.md"

cat > "$proj/rubric.md" <<'RUBRIC'
# Page audit rubric

Check every page under pages/ against these lines:

1. The page opens with one level-one heading.
2. Every heading level below the first appears once, in order.
3. Every relative link resolves to a page in this tree.
4. No placeholder marker (TODO, FIXME, TBD) appears.
5. The page states its topic in one sentence.
RUBRIC

seal "$target" "$proj"
echo "attached_body_reads_recipe sandbox staged at $proj"
