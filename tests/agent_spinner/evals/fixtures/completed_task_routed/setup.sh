#!/usr/bin/env bash
# completed_task_routed: a repair set of task files where one is already
# finished. The completed file stays byte-identical, the run opens a fork or
# gate naming it, settles nothing itself, and routes it to the owning gate.

set -euo pipefail
THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$THIS_DIR/../_common.sh"

target="${1:?target dir required}"
proj="$(new_project "$target")"
mkdir -p "$proj/tasks/archive" "$proj/src"

printf 'The alpha command accepts --workers.\n' > "$proj/src/alpha.py"
printf 'The beta command accepts --dry-run.\n' > "$proj/src/beta.py"
printf 'The gamma command accepts no flags.\n' > "$proj/src/gamma.py"

cat > "$proj/tasks/alpha.md" <<'DOC'
---
description: Document the alpha command's worker flag.
scope: docs
created: 2026-01-01T00:00:00Z
updated: 2026-01-02T00:00:00Z
status: open
reported-by: Demo
---

# Document the alpha worker flag

## Goal

The alpha docs name `--jobs`; the command accepts `--workers`.
DOC

cat > "$proj/tasks/beta.md" <<'DOC'
---
description: Document the beta command's dry-run flag.
scope: docs
created: 2026-01-01T00:00:00Z
updated: 2026-01-02T00:00:00Z
status: ready
reported-by: Demo
---

# Document the beta dry-run flag

## Goal

The beta docs name `--dry-run`; the command accepts it.
DOC

cat > "$proj/tasks/archive/gamma.md" <<'DOC'
---
description: Retire the gamma command's legacy flag.
scope: docs
created: 2025-12-01T00:00:00Z
updated: 2025-12-20T00:00:00Z
status: finished
reported-by: Demo
implemented-by: Demo
design-extended: false
---

# Retire the gamma legacy flag

## Goal

The gamma command accepts `--legacy` for old scripts.
DOC

seal "$target" "$proj"
echo "completed_task_routed sandbox staged at $proj"
