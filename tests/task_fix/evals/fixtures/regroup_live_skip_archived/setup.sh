#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/../_common.sh"

target="${1:?target dir required}"
init_proj "$target"

mkdir -p "$target/proj/docs" "$target/proj/src/export"

cat > "$target/proj/src/export/csv.py" <<'EOF'
"""CSV export for the reporting endpoints."""

COLUMNS = ["tenant", "period", "requests"]


def write_rows(rows, out):
    out.write(",".join(COLUMNS) + "\n")
    for row in rows:
        out.write(",".join(str(row[c]) for c in COLUMNS) + "\n")
EOF

cat > "$target/proj/docs/export.md" <<'EOF'
# Export formats

## CSV

The reporting CSV export writes one header row followed by one row per
tenant-period pair.
EOF

# The live link target. Nothing here points back, so the regroup has no reason
# to touch it.
cat > "$target/proj/tasks/api_export-schema.md" <<'EOF'
---
description: Fix the reporting CSV column order and publish it as the schema every export consumer reads.
scope: src/export
created: 2026-01-01T00:00:00
updated: 2026-01-01T00:00:00
status: open
reported-by: Harness
---

# Published column order for the reporting CSV

## Goal

Publish a fixed column order for the reporting CSV so every export consumer
reads one schema instead of inferring the order from the first row.

## Context

`src/export/csv.py` holds the column order in its module-level `COLUMNS`
list. `docs/export.md` describes the CSV shape without naming the order.

## Approach

Move the column order into a published schema constant, and document it in
the `## CSV` section of `docs/export.md`.

## Acceptance

- `docs/export.md` names the published column order under its `## CSV`
  section.
- `src/export/csv.py` reads the column order from the published schema.
EOF

# The live target of the run. Goal and Context carry the SAME account of one
# handoff, that the sibling task fixes the column order this task consumes,
# each with its own link. Goal still states the deliverable and its
# user-visible outcome once that account moves out, so the regroup is
# meaning-preserving and lands in Context, which owns background and current
# state under the body anatomy.
cat > "$target/proj/tasks/api_export-gzip.md" <<'EOF'
---
description: Gzip the reporting CSV export so large tenant exports transfer in a fraction of the bytes.
scope: src/export
created: 2026-01-01T00:00:00
updated: 2026-01-01T00:00:00
status: open
reported-by: Harness
---

# Gzip the reporting CSV export

## Goal

Compress the reporting CSV export with gzip so a large tenant export
transfers in a fraction of the bytes it costs today. The column order the
compressed stream carries is fixed by
[api_export-schema](api_export-schema.md), which this task consumes.

## Context

`src/export/csv.py` writes uncompressed rows through `write_rows()`, and
`docs/export.md` documents the CSV shape. The column order written into the
stream is fixed by [api_export-schema](api_export-schema.md), and this task
consumes that order rather than setting it.

## Approach

Wrap the `write_rows()` output stream in a gzip writer, and document the
compressed content encoding in the `## CSV` section of `docs/export.md`.

## Acceptance

- `src/export/csv.py` writes the export through a gzip stream.
- `docs/export.md` names the compressed content encoding under its `## CSV`
  section.
EOF

# Archived pair. The archived task links one archived target twice; the
# archive-inclusive lint draws no finding on that archived body, and the
# run leaves those bytes exactly as archived.
cat > "$target/proj/tasks/archive/api_legacy-columns.md" <<'EOF'
---
description: Retire the legacy fixed column list from the first reporting export.
scope: src/export
created: 2025-06-01T00:00:00
updated: 2025-07-01T00:00:00
status: finished
reported-by: Harness
implemented-by: Harness
---

# Retire the legacy column list

## Goal

Retire the legacy fixed column list the first reporting export shipped with.

## Context

The first export hard-coded its columns in the request handler.

## Approach

Delete the legacy list once no caller reads it.

## Acceptance

- No module references the legacy column list.
EOF

cat > "$target/proj/tasks/archive/api_legacy-export.md" <<'EOF'
---
description: Ship the first reporting CSV export behind the legacy column list.
scope: src/export
created: 2025-05-01T00:00:00
updated: 2025-06-15T00:00:00
status: finished
reported-by: Harness
implemented-by: Harness
---

# First reporting CSV export

## Goal

Ship the first reporting CSV export, writing the legacy column list defined
by [api_legacy-columns](api_legacy-columns.md).

## Context

No export existed. The legacy column list from
[api_legacy-columns](api_legacy-columns.md) is the order this export writes.

## Approach

Write the rows in the legacy order behind the reporting endpoint.

## Acceptance

- The reporting endpoint returns a CSV body.
EOF

commit_proj "$target"
