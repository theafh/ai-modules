#!/usr/bin/env bash
# check_exclusion_waiver_control fixture: the paired control for
# check_exclusion_waiver. Same root gate (`make lint` before any commit), plus
# the carve-out the gate itself provides — the lint surface skips everything
# under `fixtures/`. The task's single `**Out of scope:**` entry tracks exactly
# that carve-out: it declines to hand-format the generated fixture files the
# rule already leaves off the lint surface.
#
# That entry narrows work rather than a rule, so the clarified waiver test
# blesses it and the Rule-waiving exclusions finding must NOT fire. task_check
# stamps the task ready.

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
Run `make lint` and resolve every finding before creating any commit.
The lint surface skips everything under `fixtures/`; generated fixture files
stay outside it.
EOF

cat > "$proj/AGENTS.md" <<'EOF'
# AGENTS.md

Follow the repo rules when task work touches automation, packaging, or build
entry points.
When a task needs a standing rule, cite it as the standing repo rules rather
than naming CLAUDE.md, AGENTS.md, or another harness-specific file.
EOF

# A Makefile with a working `lint` target already exists, so the root gate
# ("run make lint before any commit") is satisfiable and the task's Approach
# only needs to ADD its own target. Without it, approach-fitness correctly
# flags the missing lint target and that unrelated finding — not the exclusion
# under test — becomes the reason ready is withheld.
printf '.PHONY: lint\nlint:\n\t@echo "lint: ok"\n' > "$proj/Makefile"

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

- Hand-formatting the generated manifest fixtures this task seeds — the
  standing repo rules keep everything under \`fixtures/\` off the lint surface,
  so the files land as written.

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

git_commit_all "$proj" "seed: task tracking a carve-out its governing rule provides"

echo "check_exclusion_waiver_control sandbox staged at $proj"
