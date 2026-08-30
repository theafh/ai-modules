#!/usr/bin/env bash
# check_exclusion_requirement_control fixture: the paired control for
# check_exclusion_requirement. Same root, same task body, same
# `**Out of scope:**` block position — but the block holds only genuine
# work-not-done rejections (type validation of field values, a CI workflow),
# and no guardrail the task builds and no meta not-an-exclusion note appear
# in it.
#
# task_check must raise NO miscategorized-exclusion finding and stamp the
# task ready, so the Contradictions extension stays precise instead of firing
# on every `**Out of scope:**` block it meets.

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

- Type validation of the manifest field values — this task checks that the two
  required fields are present and never inspects the types of their values.
- A CI workflow that runs the new target on every push — this task ships the
  script and the Make target and never touches CI configuration.

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

git_commit_all "$proj" "seed: task whose exclusions are genuine work-not-done"

echo "check_exclusion_requirement_control sandbox staged at $proj"
