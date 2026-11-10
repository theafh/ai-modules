#!/usr/bin/env bash
# explicit_spinner_on_family_job: the user names agent_spinner for a job a mock
# family skill owns. The family's writer stays the only writer, the read-only
# finders run at the orchestrator's level, and every repair waits for the user's
# approval of the family writer's scope. Five notes pages each carry one
# planted defect.

set -euo pipefail
THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$THIS_DIR/../_common.sh"

target="${1:?target dir required}"
proj="$(new_project "$target")"
mkdir -p "$proj/family/mock_notes" "$proj/notes"

cat > "$proj/family/mock_notes/SKILL.md" <<'SKILL'
---
name: mock_notes_family
description: Repair the notes pages under notes/.
---

# mock_notes_family

Hand the job to the `notes_repairer` agent. Its scope is every page under
`notes/`; do not narrow that scope unless the user supplies a narrower one.
Do not re-list the agent's checks; the agent owns them.
SKILL

cat > "$proj/notes/alpha.md" <<'PAGE'
# Alpha

### Overview

The alpha workspace holds the release notes.
PAGE

cat > "$proj/notes/beta.md" <<'PAGE'
# Beta

See [the setup guide](../setup.md) for installation.
PAGE

cat > "$proj/notes/gamma.md" <<'PAGE'
# Gamma

See [the migration notes](missing-page.md) before upgrading.
PAGE

cat > "$proj/notes/delta.md" <<'PAGE'
# Delta

#### Details

The delta workspace lists the supported hosts.
PAGE

cat > "$proj/notes/epsilon.md" <<'PAGE'
# Epsilon

TODO: write this section.

See [the changelog](../CHANGELOG.md).
PAGE

seal "$target" "$proj"
echo "explicit_spinner_on_family_job sandbox staged at $proj"
