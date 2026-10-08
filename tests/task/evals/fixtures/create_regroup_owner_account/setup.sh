#!/usr/bin/env bash
# create_regroup_owner_account fixture: one live sibling task builds the
# output-format registry for the report command and owns the --yaml flag. The
# create prompt asks for a --json task that registers through that registry and
# leaves --yaml to the same sibling. That is the Context-plus-deferral shape: a
# draft wants to link the sibling from Context for the dependency and again
# from its `**Out of scope:**` entry for the deferral, which draws a
# repeated-link warn. task_create must keep the body's account of the sibling
# together under one link while the deferral still names the sibling as the
# owner of --yaml. The project is a git repo so grade.sh can hold the sibling
# byte-identical against the seed commit.

set -euo pipefail
THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$THIS_DIR/../_common.sh"

target="${1:?target dir required}"
proj="$(new_project "$target" --git)"

mkdir -p "$proj/src/report"

cat > "$proj/src/report/cli.py" <<'EOF'
"""The report command. Prints the report as a plain text table."""

import sys


def render_table(rows):
    """Return the report as a tab-separated text table."""
    return "\n".join(f"{row['name']}\t{row['count']}" for row in rows)


def main(argv=None):
    rows = [{"name": "alpha", "count": 3}, {"name": "beta", "count": 5}]
    sys.stdout.write(render_table(rows) + "\n")
EOF

# The live sibling. It creates the registry the new task builds on and owns the
# --yaml writer the new task defers, so the new task's account of it has two
# halves that belong in one passage.
cat > "$proj/tasks/cli_output-format-registry.md" <<'EOF'
---
description: Add an output-format registry to the report command so each output flag registers one writer, and ship the --yaml writer as its first format.
scope: src/report
created: 2026-01-01T00:00:00
updated: 2026-01-01T00:00:00
status: open
reported-by: Evals
---

# Output-format registry for the report command

## Goal

Give the report command one output-format registry, so each output flag
registers a writer instead of adding a branch to `src/report/cli.py`, and ship
the `--yaml` writer as the first format registered through it.

## Context

`src/report/cli.py` prints the report as a text table through
`render_table()` and takes no format flag today, so every new output format
would add another branch to `main()`.

## Approach

Add `src/report/formats.py` with a `register(flag, writer)` function and a
lookup `main()` uses to pick the writer for the flag it received. Register the
text table writer as the default, then register a `--yaml` writer.

## Acceptance

- `src/report/formats.py` exposes `register(flag, writer)`, and `main()`
  resolves its writer through it.
- `report --yaml` prints the report as YAML.
EOF

git_commit_all "$proj" "seed create_regroup_owner_account fixture"

echo "create_regroup_owner_account sandbox staged at $proj"
