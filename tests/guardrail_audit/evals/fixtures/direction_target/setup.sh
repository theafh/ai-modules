#!/usr/bin/env bash
# direction_target: ARCHITECTURE.md's ## Direction names a streaming pipeline
# component the code has not built, while every descriptive section matches the
# code exactly. Audit must read the unreached target in the hub's
# declared-direction register — drive-toward work, not a describing falsehood —
# offer no softening or deletion of the target, and edit nothing.

set -euo pipefail
THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$THIS_DIR/../_common.sh"

target="${1:?target dir required}"
proj="$(new_project "$target")"

cat > "$proj/CLAUDE.md" <<'EOF'
# CLAUDE.md

Read ARCHITECTURE.md before reshaping the cleaning job. Respect CHARTER.md
boundaries on every edit.
EOF

cat > "$proj/CHARTER.md" <<'EOF'
# Fixture Charter

## Core Purpose

A local batch job that cleans CSV exports on disk.

## DOES / DOES NOT Domain Boundaries

### DOES

- Clean and normalise CSV files on disk from the command line.

### DOES NOT

- Become a hosted service, SaaS backend, or product UI.

## Key Invariants

- A cleaning run is reproducible from the input file alone.
- Soft standing documents stay subordinate to this charter.
EOF

cat > "$proj/ARCHITECTURE.md" <<'EOF'
# Architecture

## System Overview

A local batch job that cleans CSV exports on disk: it reads a file, normalises
its rows, and writes the result back beside the input. The shape serves one
goal — a cleaning run is reproducible from the file alone, with no service, no
stored state, and no configuration outside the command line.

## Components

- `src/clean.py` — the entry point. Reads the input CSV, hands each row to the
  normaliser, and writes the cleaned file beside the input.
- `src/normalise.py` — the row rules: whitespace trimming, empty-field
  defaults, and header casing.

## Technology Choices

- Python 3 standard library only. A dependency-free job runs anywhere the
  export lands.

## Design Decisions

- The row rules live apart from file handling, so a rule changes without
  touching the read and write path.

## Direction

The cleaner is steered toward a streaming pipeline: `src/pipeline.py` carries a
`StreamPipeline` that pulls rows through a chain of stage callables, so an
export larger than memory cleans without being read whole, and `src/clean.py`
becomes one stage in that chain rather than the file-handling entry point.
EOF

mkdir -p "$proj/src"
cat > "$proj/src/clean.py" <<'EOF'
"""Entry point: read a CSV whole, normalise every row, write the result."""

import csv
import sys

from normalise import normalise_row


def clean_file(path: str) -> str:
    with open(path, newline="") as handle:
        rows = list(csv.reader(handle))

    header, body = rows[0], rows[1:]
    cleaned = [normalise_row(header, row) for row in body]

    out_path = path.replace(".csv", ".clean.csv")
    with open(out_path, "w", newline="") as handle:
        writer = csv.writer(handle)
        writer.writerow([column.strip().title() for column in header])
        writer.writerows(cleaned)
    return out_path


if __name__ == "__main__":
    print(clean_file(sys.argv[1]))
EOF

cat > "$proj/src/normalise.py" <<'EOF'
"""Row rules, kept apart from file handling."""


def normalise_row(header: list[str], row: list[str]) -> list[str]:
    padded = row + [""] * (len(header) - len(row))
    return [field.strip() or "-" for field in padded]
EOF

git_commit_all "$proj" "stage direction_target"
record_tree_hashes "$proj" "$target/.tree_sha256"

echo "direction_target sandbox staged at $proj"
