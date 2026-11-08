#!/usr/bin/env bash
# one_remediation_round: verification fails on one item. Exactly one
# remediation round runs, no second verification loop is attempted, and the
# report marks the remediated output unverified.

set -euo pipefail
THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$THIS_DIR/../_common.sh"

target="${1:?target dir required}"
proj="$(new_project "$target")"
mkdir -p "$proj/docs" "$proj/bin"

printf '#!/usr/bin/env bash\necho "verify --strict"\n' > "$proj/bin/tool.sh"
chmod +x "$proj/bin/tool.sh"
printf '# verify\n\nRun `tool.sh verify --strict`.\n\nAdd `--fail-fast` to stop early.\n' \
  > "$proj/docs/verify.md"
printf '# status\n\nRun `tool.sh status`.\n' > "$proj/docs/status.md"

commit_tree "$proj"
run_ledger "$proj" init --phase check --bound 240 \
  --unit check:verify --unit check:status >/dev/null

stage_row "$proj" check:verify "Check docs/verify.md against bin/tool.sh." \
  --checker --target docs/verify.md
write_return "$proj" check:verify "done" fail '{
  "_prose": "check:verify — FAIL.",
  "examined": [{"path": "docs/verify.md", "how": "full", "receipt": "Add `--fail-fast`"}],
  "checklist": [
    {"verdict": "fail", "span": "Add `--fail-fast` to stop early."},
    {"verdict": "pass", "span": "# verify"}
  ],
  "findings": [
    {"claim": "docs/verify.md documents --fail-fast, which bin/tool.sh does not accept.",
     "severity": "major",
     "quote": "Add `--fail-fast` to stop early.",
     "anchor": "docs/verify.md, under \"# verify\""}
  ]
}'

stage_row "$proj" check:status "Check docs/status.md against bin/tool.sh." \
  --checker --target docs/status.md
write_return "$proj" check:status "done" pass '{
  "_prose": "check:status — PASS.",
  "examined": [{"path": "docs/status.md", "how": "full", "receipt": "Run `tool.sh status`"}],
  "checklist": [
    {"verdict": "pass", "span": "Run `tool.sh status`."}
  ]
}'

seal_open_run "$target" "$proj"
echo "one_remediation_round sandbox staged at $proj"
