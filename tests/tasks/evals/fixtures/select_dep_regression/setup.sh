#!/usr/bin/env bash
# select_dep_regression fixture: the two archived dependency-aware behaviors
# that must STILL hold after task_select is repointed to inherit the base
# taxonomy. Unfiltered backlog with two independent relationships:
#
#   1. Creator-first: render_wire-palette (consumer, ready) forward-references
#      a `<palette>` block that theme_palette-block (creator, ready) creates,
#      so the creator is a hard prerequisite and must rank AHEAD of the
#      consumer regardless of relative impact.
#   2. Disjoint companions: docs_glossary-page and docs_faq-page (both ready)
#      declare each other companions ("neither depends on the other"), edit
#      disjoint files, and must surface as a soft companion relationship with
#      NO forced order between them.

set -euo pipefail
THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$THIS_DIR/../_common.sh"

target="${1:?target dir required}"
proj="$(new_project "$target" --git)"
now="$(now_iso)"

emit_task() { # <path> <description> <scope> <status> <title> <body>
  cat > "$1" <<EOF
---
description: $2
scope: "$3"
created: $now
updated: $now
status: $4
reported-by: Test User
---

# $5

$6
EOF
}

# Creator — the task that CREATES the <palette> block (hard prerequisite).
emit_task "$proj/tasks/theme_palette-block.md" \
  "Introduce the shared palette block as the single source of theme colors." \
  "theme" "ready" "Introduce the shared palette block" \
  "## Goal

Add a \`<palette>\` block that holds every theme color once.

## Context

Colors are duplicated across modules today. This task creates the \`<palette>\` block other modules will read.

## Approach

Author the \`<palette>\` block in the theme module.

## Acceptance

- A \`<palette>\` block exists and lists every theme color."

# Consumer — forward-references the <palette> block the creator makes.
emit_task "$proj/tasks/render_wire-palette.md" \
  "Wire the renderer to read the shared palette block instead of its hardcoded map." \
  "render" "ready" "Wire the renderer to the shared palette block" \
  "## Goal

Have the renderer read every color from the shared \`<palette>\` block.

## Context

The \`<palette>\` block does not exist yet — the [palette-block task](theme_palette-block.md) is the one that creates it. This task consumes that block once it is in place.

## Approach

Point the renderer at the \`<palette>\` block the palette-block task adds and delete the local map.

## Acceptance

- The renderer reads every color from the \`<palette>\` block."

# Companion 1 — writes only docs/glossary.md; declares no dependency on the FAQ.
emit_task "$proj/tasks/docs_glossary-page.md" \
  "Write the glossary page for the docs site." \
  "docs" "ready" "Write the glossary page" \
  "## Goal

Add a glossary page defining the project's core terms.

## Context

Companion to the [FAQ page task](docs_faq-page.md): the two ship together as the new reference section, but neither depends on the other. This task writes only \`docs/glossary.md\`.

## Approach

Author \`docs/glossary.md\` with one entry per core term.

## Acceptance

- \`docs/glossary.md\` defines every core term."

# Companion 2 — writes only docs/faq.md; declares no dependency on the glossary.
emit_task "$proj/tasks/docs_faq-page.md" \
  "Write the FAQ page for the docs site." \
  "docs" "ready" "Write the FAQ page" \
  "## Goal

Add an FAQ page answering the most common user questions.

## Context

Companion to the [glossary page task](docs_glossary-page.md): they ship together as the reference section, but neither blocks the other. This task writes only \`docs/faq.md\`.

## Approach

Author \`docs/faq.md\` with one entry per common question.

## Acceptance

- \`docs/faq.md\` answers every listed common question."

git_commit_all "$proj" "seed: creator/consumer pair plus disjoint companions"

echo "select_dep_regression sandbox staged at $proj"
