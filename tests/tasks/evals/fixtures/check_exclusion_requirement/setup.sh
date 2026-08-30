#!/usr/bin/env bash
# check_exclusion_requirement fixture: the proven-ready packaging-smoke task
# (same body as standing_rules_check_control, which reaches `ready`) with one
# variable changed — its `**Out of scope:**` block files two entries the
# clarified <body> rule keeps out of the block:
#
#   1. a guardrail the task itself builds (never passes a manifest missing a
#      required field / always names the missing field) — an in-scope
#      requirement that belongs in Goal, Approach, or Acceptance;
#   2. a meta note asserting that something is NOT excluded — noise in a block
#      that records work-not-done.
#
# The extended <readiness_checklist> Contradictions lens must surface both as
# contradiction-rank findings routed through Decide or label, and task_check
# must withhold ready (stamp checked) while leaving the body untouched.
#
# The task is deliberately additive — it creates a script, a Make target, and
# fixtures that do not exist yet — so the premise check verifies against an
# empty sandbox and the miscategorized exclusions stay the only findings.
# check_exclusion_requirement_control is the paired control.

set -euo pipefail
THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$THIS_DIR/../_common.sh"

target="${1:?target dir required}"
proj="$(new_project "$target" --git)"
now="$(now_iso)"

cat > "$proj/CLAUDE.md" <<'EOF'
# CLAUDE.md

## Repo Rules

Use Make plus POSIX shell for repo automation.
Keep package-manager setup out of automation tasks unless explicitly required.
EOF

cat > "$proj/AGENTS.md" <<'EOF'
# AGENTS.md

Follow the repo rules when task work touches automation, packaging, or build
entry points.
When a task needs a standing rule, cite it as the standing repo rules rather
than naming CLAUDE.md, AGENTS.md, or another harness-specific file.
EOF

cat > "$proj/tasks/build_packaging-smoke.md" <<EOF
---
description: Add a packaging smoke-test script for plugin manifest checks.
scope: "build"
created: $now
updated: $now
status: open
reported-by: Test User
---

# Add packaging smoke test

## Goal

Add a POSIX shell script and Make target that validate plugin manifest "name"
and "version" fields, pass on seeded good fixtures, and name the missing field
on malformed fixtures.

## Context

Follow the standing repo rules for automation tooling.

Plugin manifests are JSON files whose smoke-test fixture contract checks for
top-level "name" and "version" fields. The command belongs in the repository
automation surface.

## Approach

Create \`scripts/check-plugin-manifests.sh\` and a \`check-plugin-manifests\` Make
target. Seed \`fixtures/plugin-manifests/good/valid.json\` with top-level
"name" and "version" fields, seed \`fixtures/plugin-manifests/bad/missing-name.json\`
without "name", and seed \`fixtures/plugin-manifests/bad/missing-version.json\`
without "version". The script scans \`fixtures/plugin-manifests/good/*.json\`
and \`fixtures/plugin-manifests/bad/*.json\`, confirms every good fixture has
both required fields, and confirms every bad fixture is rejected with an error
naming the missing field.

**Out of scope:**

- The script never passes a manifest that lacks a required field, and never
  reports a generic failure without naming the field it found missing.
- Keeping the script's output human-readable is not an exclusion — plain text
  stays the reporting format.

## Acceptance

- Running \`make check-plugin-manifests\` from the repository root exits 0 with
  the seeded good and bad fixtures in place.
- Deleting the "name" field from a good fixture makes
  \`make check-plugin-manifests\` exit non-zero and name the missing field.
- Deleting the "version" field from a good fixture makes
  \`make check-plugin-manifests\` exit non-zero and name the missing field.
- Adding both required fields to \`fixtures/plugin-manifests/bad/missing-name.json\`
  makes \`make check-plugin-manifests\` exit non-zero and report that an
  expected-bad fixture passed validation.
- Adding both required fields to \`fixtures/plugin-manifests/bad/missing-version.json\`
  makes \`make check-plugin-manifests\` exit non-zero and report that an
  expected-bad fixture passed validation.
EOF

git_commit_all "$proj" "seed: task filing an in-scope guardrail as an exclusion"

echo "check_exclusion_requirement sandbox staged at $proj"
