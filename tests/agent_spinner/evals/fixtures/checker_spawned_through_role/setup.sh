#!/usr/bin/env bash
# checker_spawned_through_role: one page edited from a recorded instruction,
# with its baseline. The host registers the read-only checker role, so the run
# probes it and spawns the check through it.

set -euo pipefail
THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$THIS_DIR/../_common.sh"

target="${1:?target dir required}"
proj="$(new_project "$target")"
mkdir -p "$proj/baseline"

cat > "$proj/INSTRUCTION.txt" <<'INSTRUCTION'
Recorded instruction: set the retry count in settings.md to 5.
INSTRUCTION
printf '# Settings\n\nretry count: 3\n' > "$proj/baseline/settings.md"
printf '# Settings\n\nretry count: 5\n' > "$proj/settings.md"

seal "$target" "$proj"
echo "checker_spawned_through_role sandbox staged at $proj"
