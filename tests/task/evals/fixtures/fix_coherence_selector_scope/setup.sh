#!/usr/bin/env bash
# fix_coherence_selector_scope fixture: a two-scope live backlog sized for the
# scope-filter selector form. Three live tasks carry scope `tool`, two carry
# scope `docs`, and the prompt names the tool scope. The assessment must cover
# exactly the three tool tasks and leave the two docs tasks out of the selected
# live set.
#
# Task names are deliberately distinct single words (alpha/beta/gamma vs
# delta/epsilon) so grade.sh can grep one without matching another.
#
# The prompt asks for the assessment in coherence-report.md as well as in the
# response, because grade.sh never sees the agent's response text; the report
# file is what makes the selected-set boundary deterministically gradeable.

set -euo pipefail
THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$THIS_DIR/../_common.sh"

target="${1:?target dir required}"
proj="$(new_project "$target" --git)"
now="$(now_iso)"

mkdir -p "$proj/tool" "$proj/docs"

cat > "$proj/tool/flags.py" <<'EOF'
"""Command-line flags the checker accepts."""

FLAGS = ["--json", "--quiet"]
EOF

cat > "$proj/docs/flags.md" <<'EOF'
# Flags

| Flag | Meaning |
| --- | --- |
| `--json` | render findings as JSON |
| `--quiet` | suppress output on a clean run |
EOF

seed_task() {
    local name="$1" scope="$2" title="$3" goal="$4" ctx="$5" approach="$6" acc="$7"
    cat > "$proj/tasks/$name" <<EOF
---
description: $goal
scope: $scope
created: $now
updated: $now
status: ready
reported-by: Test User
---

# $title

## Goal

$goal

## Context

$ctx

## Approach

$approach

## Acceptance

- $acc
EOF
}

seed_task tool_alpha-flag.md tool "Add a strict severity flag" \
    "Add a --strict flag that promotes every info finding to warn severity." \
    "[tool/flags.py](../tool/flags.py) lists the accepted flags." \
    "Append the new flag to FLAGS and promote info findings when it is set." \
    "A run with --strict reports every info finding at warn severity."

seed_task tool_beta-flag.md tool "Add a fail-fast flag" \
    "Add a --fail-fast flag that stops the run at the first blocking finding." \
    "[tool/flags.py](../tool/flags.py) lists the accepted flags." \
    "Append the new flag to FLAGS and return from the run loop on the first block." \
    "A run with --fail-fast stops at the first blocking finding."

seed_task tool_gamma-flag.md tool "Sort the accepted flag list" \
    "Sort the accepted flags in FLAGS alphabetically so the help output has a stable order." \
    "[tool/flags.py](../tool/flags.py) lists the flags in the order they were added." \
    "Rewrite the FLAGS list in tool/flags.py in alphabetical order." \
    "FLAGS in tool/flags.py is in alphabetical order."

seed_task docs_delta-page.md docs "Document the strict flag" \
    "Document the --strict flag in the flag table so its severity promotion is discoverable." \
    "[docs/flags.md](../docs/flags.md) carries the flag table." \
    "Add a row to the table in docs/flags.md for the --strict flag." \
    "The table in docs/flags.md carries a --strict row."

seed_task docs_epsilon-page.md docs "Document the fail-fast flag" \
    "Document the --fail-fast flag in the flag table so its early return is discoverable." \
    "[docs/flags.md](../docs/flags.md) carries the flag table." \
    "Add a row to the table in docs/flags.md for the --fail-fast flag." \
    "The table in docs/flags.md carries a --fail-fast row."

git_commit_all "$proj" "seed: two-scope backlog for the scope-filter selector"

echo "fix_coherence_selector_scope sandbox staged at $proj"
