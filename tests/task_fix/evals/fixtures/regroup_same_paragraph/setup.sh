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

# The link target. Nothing here points back, so the run has no reason to touch
# it.
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

# Target task. Its only repeat sits inside one Context paragraph, which links
# the sibling twice and nowhere else names it. The material is already
# gathered, so the react protocol's one-paragraph case applies: the run names
# the sibling again in plain text inside that paragraph, the warn clears, and
# the finding reads regrouped. Every other section stays as staged.
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
transfers in a fraction of the bytes it costs today.

## Context

`src/export/csv.py` writes uncompressed rows through `write_rows()`. The
column order the stream carries is fixed by
[api_export-schema](api_export-schema.md), and this task compresses that
stream without reordering it, so it lands after
[api_export-schema](api_export-schema.md) has published the order.

## Approach

Wrap the `write_rows()` output stream in a gzip writer, and document the
compressed content encoding in the `## CSV` section of `docs/export.md`.

## Acceptance

- `src/export/csv.py` writes the export through a gzip stream.
- `docs/export.md` names the compressed content encoding under its `## CSV`
  section.
EOF

commit_proj "$target"
