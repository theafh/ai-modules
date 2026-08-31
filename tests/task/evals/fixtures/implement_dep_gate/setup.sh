#!/usr/bin/env bash
# implement_dep_gate fixture: task A (render_wire-palette, ready) forward-
# references a `<palette>` block that a live task B (theme_palette-block,
# status open) is the one to create. task_implement's pre-flight dependency
# gate must surface B as a hard prerequisite, list it with evidence, ask
# whether to build A ahead of it, and STOP with no code edit and no status
# change. A headless/subagent worker has no user to green-light the build,
# so the correct outcome leaves the sandbox git tree clean and A still ready.

set -euo pipefail
THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$THIS_DIR/../_common.sh"

target="${1:?target dir required}"
proj="$(new_project "$target" --git)"
now="$(now_iso)"

mkdir -p "$proj/src"
cat > "$proj/src/render.py" <<'EOF'
"""Renderer with a hardcoded color map (to be wired to the shared palette)."""

COLORS = {"fg": "#000000", "bg": "#ffffff"}


def color(name):
    return COLORS[name]
EOF

# Task A — the one task_implement is pointed at. It CONSUMES a <palette>
# block that does not exist yet; task B is the one that creates it.
cat > "$proj/tasks/render_wire-palette.md" <<EOF
---
description: Wire the renderer to read the shared palette block instead of its hardcoded map.
scope: src
created: $now
updated: $now
status: ready
reported-by: Test User
---

# Wire the renderer to the shared palette block

## Goal

Have \`src/render.py\` read every color from the shared \`<palette>\` block instead of its hardcoded \`COLORS\` map.

## Context

The \`<palette>\` block does not exist yet — the [palette-block task](theme_palette-block.md) is the one that creates it. This task consumes that block once it is in place.

## Approach

Point the renderer at the \`<palette>\` block the palette-block task adds, and delete the local \`COLORS\` map.

## Acceptance

- \`src/render.py\` reads every color from the \`<palette>\` block.
- No hardcoded \`COLORS\` map remains in \`src/render.py\`.
EOF

# Task B — a live prerequisite (status open). It CREATES the <palette> block
# that task A forward-references.
cat > "$proj/tasks/theme_palette-block.md" <<EOF
---
description: Introduce the shared palette block as the single source of theme colors.
scope: src
created: $now
updated: $now
status: open
reported-by: Test User
---

# Introduce the shared palette block

## Goal

Add a \`<palette>\` block that holds every theme color once, for other modules to read.

## Context

Colors are duplicated across modules today. This task creates the \`<palette>\` block the renderer and other modules will consume.

## Approach

Author the \`<palette>\` block in the theme module.

## Acceptance

- A \`<palette>\` block exists and lists every theme color.
EOF

git_commit_all "$proj" "seed: task A consumes a block that live task B creates"

echo "implement_dep_gate sandbox staged at $proj"
