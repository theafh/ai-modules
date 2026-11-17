#!/usr/bin/env bash
# related-precedent-novel fixture: related precedent that covers none of the
# requested work.
#
# The create prompt asks for unit tests of truncate_cell in
# src/report/render.py. An archived finished task already covered a sibling
# function in the same module (format_severity) and settled the sys.modules
# stubbing pattern the new work will reuse. That hit shares real context —
# same module, same dependency, same settled pattern — while covering none of
# the requested truncate_cell work, so the prior-art gate must classify the
# request as Novel, continue to drafting, and cross-link the precedent in
# ## Context. Classifying it as Partially covered and stopping to ask is the
# failure this eval catches.
#
# The precedent holds constraints no other source in the sandbox carries, so
# the <markdown_policy> cross-link discipline keeps the link: reading it
# changes how the new test is written. Its ## Approach carries the stub rule
# (register the stub in sys.modules with unittest.mock.patch.dict, leave the
# production import where it is, add no runtime dependency), and its
# **Out of scope:** block rejects moving `import chartkit` into
# render_chart() because external callers patch render.chartkit at module
# scope, which the code cannot show. TESTING.md keeps only the standing gate.
# An earlier version also put the stub rule in TESTING.md; reading the
# precedent then changed nothing, and both vendors correctly left the
# relatedness-only link out.
#
# The sandbox is a git repository with its own identity, so
# `git config user.name` supplies `reported-by` without asking the user for a
# name.

set -euo pipefail
THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$THIS_DIR/../_common.sh"

target="${1:?target dir required}"
proj="$(new_project "$target" --git)"
stamp="$(now_iso)"

cat > "$proj/CLAUDE.md" <<'EOF'
# CLAUDE.md

## Repo rules

The report package ships as plain Python with no build step. Cite a standing
repo rule from a task rather than copying its text into the task body.
EOF

cat > "$proj/TESTING.md" <<'EOF'
# TESTING.md

## Standing gate

Every test runs offline, on a machine with no built artifacts and no optional
dependencies installed. The standing gate is
`python3 -m unittest discover -s tests`.
EOF

mkdir -p "$proj/src/report" "$proj/tests"

cat > "$proj/src/report/render.py" <<'EOF'
"""Report rendering.

`chartkit` is an optional heavy backend needed only by render_chart(); it is
imported at module scope, so importing this module pulls it in.
"""

import chartkit

SEVERITY_LABELS = {0: "ok", 1: "notice", 2: "warning", 3: "error"}


def format_severity(level):
    """Pure: map a numeric severity level to its display label."""
    return SEVERITY_LABELS.get(level, "unknown")


def truncate_cell(text, width):
    """Pure: clip a cell to `width`, marking the clip with an ellipsis."""
    if width <= 0:
        return ""
    if len(text) <= width:
        return text
    return text[: max(width - 1, 0)] + "…"


def render_chart(rows):
    return chartkit.bar(rows)
EOF

cat > "$proj/tests/test_render.py" <<'EOF'
import sys
import unittest
from unittest import mock


class FormatSeverityTest(unittest.TestCase):
    def test_known_levels(self):
        with mock.patch.dict(sys.modules, {"chartkit": mock.MagicMock()}):
            from src.report import render

            self.assertEqual(render.format_severity(2), "warning")
            self.assertEqual(render.format_severity(99), "unknown")
EOF

cat > "$proj/tasks/archive/report_format-severity-test.md" <<EOF
---
description: "Cover the report render module's pure format_severity helper with a unit test that stubs the chart backend rather than installing it."
scope: src/report
created: $stamp
updated: $stamp
status: finished
reported-by: Evals
implemented-by: Evals
---

# Test the report format_severity helper without installing the chart backend

## Goal

format_severity in \`src/report/render.py\` is covered by a unit test that runs
under the standing offline gate, so the suite proves the severity labels
without the optional chart backend being installed anywhere.

## Context

\`src/report/render.py\` imports the chart backend at module scope, so
importing the module at all pulls the dependency in, even for a test of a pure
helper, while the standing offline gate runs with no optional dependency
installed. This task settles how a test reaches such a module.

## Approach

A module that imports an optional heavy dependency at module scope is imported
under a stub: register the stub in \`sys.modules\` with
\`unittest.mock.patch.dict\` before importing the module under test. Leave the
production import where it is, and never add a runtime dependency just to make
a module importable from a test.

**Out of scope:**

- Moving \`import chartkit\` into \`render_chart()\`: external callers patch
  \`render.chartkit\` at module scope, so the import stays put.

## Acceptance

- \`tests/test_render.py\` asserts format_severity maps known levels to their
  labels and unknown levels to "unknown".
- The test passes with the backend absent from the environment.
EOF

git_commit_all "$proj" "seed: truncate_cell untested; format_severity precedent archived"

echo "related-precedent-novel sandbox staged at $proj"
