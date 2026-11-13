#!/usr/bin/env bash
# move_integrity_flags_low_similarity: a multi-file run staged after its Check
# phase. The task's acceptance list names two moves. In the working tree one
# move kept its content, and the other was made as a delete plus an add whose
# content differs in most lines. The gate suite must report both, with the
# delete-plus-add path's similarity from a second, low-threshold pass.

set -euo pipefail
THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$THIS_DIR/../_common.sh"

target="${1:?target dir required}"
proj="$(new_project "$target")"
mkdir -p "$proj/src" "$proj/tasks"

cat > "$proj/tasks/demo-moves.md" <<'TASK'
---
status: ready
---

# Move two modules into lib

## Acceptance

- Move `src/alpha.py` to `lib/alpha.py` with its content unchanged.
- Move `src/beta.py` to `lib/beta.py`, rewritten to the new interface.
TASK

cat > "$proj/src/alpha.py" <<'PY'
def alpha(value):
    return value + 1
PY

cat > "$proj/src/beta.py" <<'PY'
import os
import sys


def beta(path):
    root = os.path.dirname(path)
    names = sorted(os.listdir(root))
    return [name for name in names if name.endswith(".txt")]


def beta_count(path):
    return len(beta(path))
PY

commit_tree "$proj"

run_ledger "$proj" init --phase rewrite --bound 60 \
  --unit write:alpha --unit write:beta \
  --unit-path write:alpha=lib/alpha.py \
  --unit-path write:beta=lib/beta.py >/dev/null

# The two moves land in the working tree after the baseline commit.
mkdir -p "$proj/lib"
mv "$proj/src/alpha.py" "$proj/lib/alpha.py"
mv "$proj/src/beta.py" "$proj/lib/beta.py"
cat > "$proj/lib/beta.py" <<'PY'
"""Beta helpers for the new interface."""

from pathlib import Path


def beta(path):
    root = Path(path)
    names = sorted(item.name for item in root.iterdir())
    return [name for name in names if name.endswith(".txt")]


def beta_count(path):
    return len(beta(path))


def beta_report(path):
    return ", ".join(beta(path))
PY

# The added side is still untracked here, so the run's diff sees four changed
# paths and gives each one a check row.
run_ledger "$proj" diff --add-checks >/dev/null

# Intent-to-add then puts the added side in the diff, so the move-integrity gate
# can see the rename status version control reports.
sandbox_git "$proj" add -N lib/alpha.py lib/beta.py

stage_row "$proj" write:alpha "Rewrite lib/alpha.py for the move into lib." \
  --target lib/alpha.py --kind write
write_return "$proj" write:alpha "done" pass '{"_prose": "write:alpha — moved with its content unchanged."}'
run_ledger "$proj" accept write:alpha >/dev/null

stage_row "$proj" write:beta "Rewrite lib/beta.py to the new interface." \
  --target lib/beta.py --kind write
write_return "$proj" write:beta "done" pass '{"_prose": "write:beta — rewritten to the new interface."}'
run_ledger "$proj" accept write:beta >/dev/null

for path in lib/alpha.py lib/beta.py src/alpha.py src/beta.py; do
  label="check:$(printf '%s' "$path" | tr '/' '-')"
  stage_row "$proj" "$label" "Check $path against the acceptance list." \
    --checker --target "$path"
  write_return "$proj" "$label" "done" pass "{\"_prose\": \"$label checked against the acceptance list.\"}"
  run_ledger "$proj" accept "$label" >/dev/null
done

seal_open_run "$target" "$proj"
echo "move_integrity_flags_low_similarity sandbox staged at $proj"
