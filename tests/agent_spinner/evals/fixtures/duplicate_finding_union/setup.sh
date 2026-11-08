#!/usr/bin/env bash
# duplicate_finding_union: two lens passes raise the same finding. The run
# sends it through its own refute-by-default check and counts no agreement.

set -euo pipefail
THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$THIS_DIR/../_common.sh"

target="${1:?target dir required}"
proj="$(new_project "$target")"
mkdir -p "$proj/docs" "$proj/bin"

printf '#!/usr/bin/env bash\necho "verify --strict"\n' > "$proj/bin/tool.sh"
chmod +x "$proj/bin/tool.sh"
cat > "$proj/docs/verify.md" <<'DOC'
# verify

Run `tool.sh verify --strict`.

Add `--fail-fast` to stop at the first failure.
DOC

commit_tree "$proj"
run_ledger "$proj" init --phase lens --bound 240 \
  --unit lens:accuracy --unit lens:completeness >/dev/null
for label in lens:accuracy lens:completeness; do
  stage_row "$proj" "$label" "Read docs/verify.md against bin/tool.sh under the ${label#lens:} lens."
done

write_return "$proj" lens:accuracy "done" pass '{
  "_prose": "lens:accuracy — 1 finding.",
  "findings": [
    {"claim": "docs/verify.md documents --fail-fast; bin/tool.sh accepts --strict only.",
     "severity": "major",
     "quote": "Add `--fail-fast` to stop at the first failure.",
     "anchor": "docs/verify.md, under \"# verify\""}
  ]
}'
write_return "$proj" lens:completeness "done" pass '{
  "_prose": "lens:completeness — 1 finding.",
  "findings": [
    {"claim": "docs/verify.md documents --fail-fast; bin/tool.sh accepts --strict only.",
     "severity": "major",
     "quote": "Add `--fail-fast` to stop at the first failure.",
     "anchor": "docs/verify.md, under \"# verify\""}
  ]
}'

seal_open_run "$target" "$proj"
echo "duplicate_finding_union sandbox staged at $proj"
