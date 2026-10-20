#!/usr/bin/env bash
# reconcile-recorded fixture: the evidence-settled fork.
#
# The create prompt names an either/or about how new tests reach the pure
# helpers in a module that imports a heavy optional dependency at module scope.
# Every tier of the base **Decide or label** evidence base points the same way:
# TESTING.md prescribes the stubbing mechanism and the offline standing gate,
# an archived precedent task took that same path, and the code shows both the
# module-scope import that forces it and an existing test that already uses it.
# No tier is against it, so the fork is a reconciliation, not an open decision:
# the written task must carry no labeled open-decision lead-in at all and must
# record the settled path, citing the standing rule rather than copying it.
#
# This mirrors the observed failure the rule tightening closes: an authoring
# session that labeled an evidence-settled test-reachability fork as its open
# decision, with a default the evidence had already picked.
#
# Two choices keep the run from stopping at a question before it drafts, so
# the eval measures only the reconcile behaviour. The archived precedent
# covers src/dashboard/plots.py, a different module that imports the same
# chart backend and took the stubbing path, so it is precedent for the pattern
# while covering nothing in src/report/render.py; a precedent that tested
# another function of render.py read as overlap and stopped draws at the
# base skill's <prior_art> gate with a "Partially covered" ask. The sandbox is
# a git repository with its own identity, so `git config user.name` supplies
# `reported-by` without asking the user for a name.

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

## Reaching code behind a heavy module-scope import

A module that imports an optional heavy dependency at module scope is imported
under a stub: register the stub in `sys.modules` with
`unittest.mock.patch.dict` before importing the module under test. Leave the
production import where it is, and never add a runtime dependency just to make
a module importable from a test.
EOF

mkdir -p "$proj/src/report" "$proj/src/dashboard" "$proj/tests"

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

cat > "$proj/src/dashboard/plots.py" <<'EOF'
"""Dashboard plotting.

`chartkit` is the optional heavy chart backend; it is imported at module scope,
so importing this module pulls it in.
"""

import chartkit


def axis_ticks(max_value, count):
    """Pure: `count` evenly spaced tick values from zero up to `max_value`."""
    if count < 2 or max_value <= 0:
        return [0]
    step = max_value / (count - 1)
    return [round(i * step, 2) for i in range(count)]


def plot_trend(points):
    return chartkit.line(points)
EOF

cat > "$proj/tests/test_plots.py" <<'EOF'
import sys
import unittest
from unittest import mock


class AxisTicksTest(unittest.TestCase):
    def test_evenly_spaced_from_zero(self):
        with mock.patch.dict(sys.modules, {"chartkit": mock.MagicMock()}):
            from src.dashboard import plots

            self.assertEqual(plots.axis_ticks(10, 3), [0, 5.0, 10.0])
EOF

cat > "$proj/tasks/archive/dashboard_axis-ticks-test.md" <<EOF
---
description: "Cover the dashboard plots module's pure axis_ticks helper with a unit test that stubs the chart backend rather than installing it."
scope: src/dashboard
created: $stamp
updated: $stamp
status: finished
reported-by: Evals
implemented-by: Evals
---

# Test the dashboard axis_ticks helper without installing the chart backend

## Goal

axis_ticks in \`src/dashboard/plots.py\` is covered by a unit test that runs
under the standing offline gate, so the suite proves the tick spacing without
the optional chart backend being installed anywhere.

## Context

\`src/dashboard/plots.py\` imports the chart backend at module scope, so
importing the module at all pulls the dependency in, even for a test of a pure
helper. The standing repo rules on testing settle how a test reaches such a
module.

## Approach

Register a stub for the backend in \`sys.modules\` with
\`unittest.mock.patch.dict\` before importing the module under test, and leave
the production import untouched.

## Acceptance

- \`tests/test_plots.py\` asserts axis_ticks returns evenly spaced ticks from
  zero up to the maximum.
- The test passes with the backend absent from the environment.
EOF

git_commit_all "$proj" "seed: report helpers untested; dashboard precedent archived"

echo "reconcile-recorded sandbox staged at $proj"
