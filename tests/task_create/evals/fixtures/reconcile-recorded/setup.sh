#!/usr/bin/env bash
# reconcile-recorded fixture: the evidence-settled fork.
#
# The create prompt names an either/or about how new tests reach the pure
# helpers in a module that imports a heavy optional dependency at module scope.
# Every tier of the base **Decide or label** evidence base points the same way:
# TESTING.md prescribes the stubbing mechanism and the offline standing gate,
# the archived precedent task took that same path, and the code shows the
# module-scope import that forces it. No tier is against it, so the fork is a
# reconciliation, not an open decision: the written task must carry no
# "Open decision:" at all and must record the settled path, citing the standing
# rule rather than copying it.
#
# This mirrors the observed failure the rule tightening closes — an authoring
# session that labeled an evidence-settled test-reachability fork as its open
# decision, with a default the evidence had already picked.

set -euo pipefail
THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$THIS_DIR/../_common.sh"

target="${1:?target dir required}"
proj="$(new_project "$target")"
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

## Reaching code behind a heavy module-scope import

A module that imports an optional heavy dependency at module scope is imported
under a stub: register the stub in `sys.modules` with
`unittest.mock.patch.dict` before importing the module under test. Leave the
production import where it is, and never add a runtime dependency just to make
a module importable from a test.
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

cat > "$proj/tests/test_render_chart.py" <<'EOF'
import sys
import unittest
from unittest import mock


class RenderChartTest(unittest.TestCase):
    def test_delegates_to_chartkit(self):
        stub = mock.MagicMock()
        with mock.patch.dict(sys.modules, {"chartkit": stub}):
            from src.report import render

            render.render_chart([("a", 1)])
        stub.bar.assert_called_once()
EOF

cat > "$proj/tasks/archive/report_chart-delegation-test.md" <<EOF
---
description: Cover render_chart's delegation to the chart backend with a test that stubs the backend rather than installing it.
scope: src/report
created: $stamp
updated: $stamp
status: finished
reported-by: Evals
implemented-by: Evals
---

# Test render_chart's delegation without installing the chart backend

## Goal

render_chart's delegation to the chart backend is covered by a test that runs
under the standing offline gate, so the suite proves the delegation without the
optional dependency being installed anywhere.

## Context

\`src/report/render.py\` imports the chart backend at module scope, so importing
the module at all pulls the dependency in. The standing repo rules on testing
settle how a test reaches such a module.

## Approach

Register a stub for the backend in \`sys.modules\` with
\`unittest.mock.patch.dict\` before importing the module under test, and leave
the production import untouched.

## Acceptance

- \`tests/test_render_chart.py\` asserts render_chart calls the backend's bar
  entry point exactly once.
- The test passes with the backend absent from the environment.
EOF

echo "reconcile-recorded sandbox staged at $proj"
