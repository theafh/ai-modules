#!/usr/bin/env bash
# check_exclusion_waiver fixture: the same proven-ready packaging-smoke task,
# with a root CLAUDE.md that carries an explicit project gate (`make lint`
# before any commit) and one `**Out of scope:**` entry that exempts the task's
# own work from that gate.
#
# The waiver test in the clarified <body> rule places such an entry outside
# the block — an exclusion removes work from the task, never a rule from the
# work that remains — so the <readiness_checklist> Rule-waiving exclusions
# finding must fire. No CHARTER.md is seeded, so the waived authority is an
# ordinary standing repo rule and the disposition routes through Decide or
# label rather than escalating to the Charter check disposition. task_check
# withholds ready (stamps checked) and leaves the body untouched.
#
# check_exclusion_waiver_control is the paired control: the same root gate,
# with an entry that tracks the carve-out the rule itself provides.

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

- The repo's lint gate for this change — the new script's long \`case\` lines
  would need reflowing to clear it, so this change ships without running the
  gate.

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

git_commit_all "$proj" "seed: task waiving the repo lint gate via an exclusion"

echo "check_exclusion_waiver sandbox staged at $proj"
