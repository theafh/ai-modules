#!/usr/bin/env bash
# check_count_stable fixture: one task body carrying BOTH quantity classes the
# base <markdown_policy> count-stable rule separates.
#
#   1. A frozen mutable-set count — "all 3 plugin manifests under
#      `plugins/*/plugin.json`". The sandbox really does hold three manifests,
#      so the number matches today and the Premise check clears it; it rots the
#      moment a fourth plugin lands. The <readiness_checklist> Ambiguity /
#      under-specification lens must flag it against the count-stable rule, with
#      the selector rewrite ("every plugin manifest under `plugins/*/plugin.json`")
#      as the minimum fix.
#   2. A legal measurement-protocol count — the "5 runs over the fixed
#      denominator of 6 seeded fixture manifests" Acceptance item, whose run
#      count, fixed denominator, and baseline the count-stable rule keeps legal
#      under the Acceptance contract's **Measured, with a fail branch** clause.
#      It must stay UNFLAGGED. The measured quantity is wall-clock duration
#      against a same-run `make lint` baseline, which is genuinely variable, so
#      the 5-run protocol earns its place and the fail branch is reachable; the
#      item also names where the numbers land, so the Acceptance contract draws
#      no separate finding on it either.
#
# The precision half is the point: a lens that flags every number in a body
# would fire on the measurement item too. One fixture carries both so a single
# run records both verdicts.
#
# The body is otherwise the proven-ready packaging-smoke task shared by the
# exclusion evals, minus the `**Out of scope:**` block (nothing here is
# excluded, and the boundary lenses are covered by their own scenarios). No
# CHARTER.md is seeded, so the finding rides the ordinary readiness-issue path.
# task_check withholds ready (stamps checked) and leaves the body untouched.
#
# The count-stable violation is meant to be the ONLY blocking finding, which is
# what makes grade.sh's `status: checked` assertion a real discriminator: were
# the rule to regress, no other defect would hold ready back. Every other
# promise the body makes is paired with its own Acceptance item, including the
# real-manifest pass the Approach commits to.

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

# An automation surface the task's new target can join, so approach-fitness
# has no missing-Makefile finding to raise beside the quantity under test.
printf '.PHONY: lint\nlint:\n\t@echo "lint: ok"\n' > "$proj/Makefile"

# Exactly three plugin manifests: the mutable set the task body freezes as a
# count. Membership grows with the next plugin, which is what makes "all 3"
# a count-stable violation even though the number is accurate right now.
for plugin in alpha beta gamma; do
    mkdir -p "$proj/plugins/$plugin"
    printf '{\n  "name": "%s",\n  "version": "1.0.0"\n}\n' "$plugin" \
        > "$proj/plugins/$plugin/plugin.json"
done

cat > "$proj/tasks/build_manifest-smoke.md" <<EOF
---
description: Add a manifest smoke-test script and Make target that validate plugin manifest name and version fields.
scope: "build"
created: $now
updated: $now
status: open
reported-by: Test User
---

# Add plugin manifest smoke test

## Goal

Add a POSIX shell script and Make target that validate plugin manifest "name"
and "version" fields, pass on seeded good fixtures, and name every field a
malformed fixture is missing.

## Context

Follow the standing repo rules for automation tooling.

Plugin manifests are JSON files whose smoke-test fixture contract checks for
top-level "name" and "version" fields. The command belongs in the repository
automation surface.

## Approach

Create \`scripts/check-plugin-manifests.sh\` and a \`check-plugin-manifests\` Make
target. Seed \`fixtures/plugin-manifests/good/\` with three manifests carrying
top-level "name" and "version" fields, and seed
\`fixtures/plugin-manifests/bad/\` with \`missing-name.json\`,
\`missing-version.json\`, and \`missing-both.json\`. The script scans
\`fixtures/plugin-manifests/good/*.json\` and
\`fixtures/plugin-manifests/bad/*.json\`, confirms every good fixture has both
required fields, and confirms every bad fixture is rejected with an error naming
every field that manifest is missing. In the same pass it validates all 3 plugin
manifests under \`plugins/*/plugin.json\`, so a real manifest that loses a
required field fails the target too.

## Acceptance

- Running \`make check-plugin-manifests\` from the repository root exits 0 with
  the seeded good and bad fixtures in place, reporting each good fixture as
  valid and each bad fixture as correctly rejected.
- Deleting the "name" field from a good fixture makes
  \`make check-plugin-manifests\` exit non-zero and name the missing field.
- Deleting the "version" field from a good fixture makes
  \`make check-plugin-manifests\` exit non-zero and name the missing field.
- Adding both required fields to \`fixtures/plugin-manifests/bad/missing-name.json\`
  makes \`make check-plugin-manifests\` exit non-zero and report that an
  expected-bad fixture passed validation.
- The \`make check-plugin-manifests\` output for
  \`fixtures/plugin-manifests/bad/missing-both.json\` names both "name" and
  "version" as the fields that manifest is missing.
- Deleting the "name" field from \`plugins/alpha/plugin.json\` makes
  \`make check-plugin-manifests\` exit non-zero and name "name" as the missing
  field, and restoring the field returns the target to exit 0, so the
  real-manifest pass is exercised rather than only the fixture pass.
- Running \`make check-plugin-manifests\` 5 times over the fixed denominator of
  6 seeded fixture manifests, beside 5 runs of the existing \`make lint\` target
  as the baseline, records the wall-clock median of each and writes both numbers
  into this task body as a Findings note. The recorded medians are the
  deliverable: when the new target's median lands above twice the \`make lint\`
  baseline median, the two numbers are recorded with the slowest fixture named,
  rather than tuned until the ratio passes.
EOF

git_commit_all "$proj" "seed: task carrying a frozen mutable-set count beside a legal measurement count"

echo "check_count_stable sandbox staged at $proj"
