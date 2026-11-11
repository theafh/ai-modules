#!/usr/bin/env bash
# confirmation_provenance: one pass surfaces a finding on its own; a second
# pass is shown that report and does not refute it. The report marks the
# second recall-confirmed and the first independently surfaced.

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
run_ledger "$proj" init --phase check --bound 240 \
  --unit survey:verify --unit check:verify-check >/dev/null

stage_row "$proj" survey:verify "Read docs/verify.md against bin/tool.sh."
write_return "$proj" survey:verify "done" pass '{
  "_prose": "survey:verify — 1 finding, raised from my own read of docs/verify.md and bin/tool.sh. I was shown no prior report.",
  "findings": [
    {"claim": "docs/verify.md documents --fail-fast; bin/tool.sh accepts --strict only.",
     "severity": "major",
     "quote": "Add `--fail-fast` to stop at the first failure.",
     "anchor": "docs/verify.md, under \"# verify\""}
  ],
  "confirmations": [
    {"claim": "docs/verify.md documents --fail-fast; bin/tool.sh accepts --strict only.",
     "note": "raised from my own read"}
  ]
}'
run_ledger "$proj" accept survey:verify >/dev/null

run_ledger "$proj" brief check:verify-check --checker --relay survey:verify \
  --body "You were handed survey:verify's report verbatim. Check it and report what you find." >/dev/null
run_ledger "$proj" dispatch check:verify-check >/dev/null
write_return "$proj" check:verify-check "done" pass '{
  "_prose": "check:verify-check — I was handed survey:verify'\''s report verbatim and checked it. I do not refute the finding; I did not surface it myself.",
  "findings": [
    {"claim": "docs/verify.md documents --fail-fast; bin/tool.sh accepts --strict only.",
     "severity": "major",
     "quote": "Add `--fail-fast` to stop at the first failure.",
     "anchor": "docs/verify.md, under \"# verify\""}
  ],
  "confirmations": [
    {"claim": "docs/verify.md documents --fail-fast; bin/tool.sh accepts --strict only.",
     "note": "relayed from survey:verify and not refuted"}
  ]
}'

seal_open_run "$target" "$proj"
echo "confirmation_provenance sandbox staged at $proj"
