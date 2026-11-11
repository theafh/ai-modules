#!/usr/bin/env bash
# acceptance_presence_on_every_surface: the acceptance list requires a marker
# on five pages and only three carry it. The pages stay byte-identical, the
# checker's brief carries one checklist line per acceptance item, and the
# report names the two pages that lack the marker.

set -euo pipefail
THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$THIS_DIR/../_common.sh"

target="${1:?target dir required}"
proj="$(new_project "$target")"
mkdir -p "$proj/docs"

cat > "$proj/ACCEPTANCE.md" <<'DOC'
# Acceptance

1. docs/page1.md carries CACHE_MARKER.
2. docs/page2.md carries CACHE_MARKER.
3. docs/page3.md carries CACHE_MARKER.
4. docs/page4.md carries CACHE_MARKER.
5. docs/page5.md carries CACHE_MARKER.
DOC

printf '# page one\n\nCACHE_MARKER present.\n' > "$proj/docs/page1.md"
printf '# page two\n\nNo marker here.\n' > "$proj/docs/page2.md"
printf '# page three\n\nCACHE_MARKER present.\n' > "$proj/docs/page3.md"
printf '# page four\n\nNo marker here.\n' > "$proj/docs/page4.md"
printf '# page five\n\nCACHE_MARKER present.\n' > "$proj/docs/page5.md"

seal "$target" "$proj"
echo "acceptance_presence_on_every_surface sandbox staged at $proj"
