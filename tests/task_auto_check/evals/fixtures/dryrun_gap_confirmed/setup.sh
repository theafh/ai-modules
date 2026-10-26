#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/../_common.sh"

target="${1:?target dir required}"
init_proj "$target"
mkdir -p "$target/proj/skills/release_notes"

# The fixture skill file: its ordering rule already directs newest-first for
# every section, explicitly including the pinned entries section. The fixture
# task below adds a rule that directs the opposite for that one case and never
# mentions this rule, so only a walk of the new rule against the rules beside
# it — the pre-gate dry run in the implementer's seat — surfaces the conflict.
cat > "$target/proj/skills/release_notes/SKILL.md" <<'EOF'
---
name: release_notes
description: Draft the project's release notes from the merged commits.
version: 1.0.0
---

# release_notes

<policy>
  <rule>Ordering rule: Order every section newest-first, including the pinned entries section.</rule>
  <rule>Line rule: Keep each entry to one line.</rule>
</policy>
EOF

# Staged so one ordinary repair round can settle the planted conflict: Goal,
# description, and title already name both the pinned oldest-first deliverable
# and the Ordering-rule rewrite that makes that deliverable the sole pinned
# directive. Approach still appends without naming the live newest-first
# pinned clause, which is the gap the dry run must find.
cat > "$target/proj/tasks/notes_pinned-order.md" <<'EOF'
---
description: "Rewrite release_notes Ordering so pinned entries are oldest-first only, and add one Pinned-order rule."
scope: skills
created: 2026-01-01T00:00:00
updated: 2026-01-01T00:00:00
status: open
reported-by: Harness
---

# Rewrite release_notes pinned ordering to oldest-first

## Goal

Rewrite the `release_notes` skill so pinned entries render oldest-first as the sole pinned ordering directive, and keep every non-pinned section newest-first.

## Context

`skills/release_notes/SKILL.md` holds the skill's `<policy>` rules for drafting release notes. Its pinned entries section carries the entries a release keeps at the top across versions. The skill has no other writers or consumers in this repository.

## Approach

Append this rule to the `<policy>` block of `skills/release_notes/SKILL.md`:

- Pinned-order rule: Render pinned entries oldest-first, first entry added first.

## Acceptance

- After the change, `skills/release_notes/SKILL.md` carries exactly one ordering directive for the pinned entries section, and it directs oldest-first.
EOF

commit_proj "$target"
