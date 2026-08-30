#!/usr/bin/env bash
# Stage a hub-with-<family> skill tree for skill_doctor evals.
set -euo pipefail
ROOT="${1:-.}"
mkdir -p "$ROOT/plugins/demo/skills/demo"
mkdir -p "$ROOT/plugins/demo/skills/demo_alpha"
mkdir -p "$ROOT/plugins/demo/skills/shared_linter"
# The out-of-family skill carries an invented snake_case name on purpose: the
# grader scans the response for occurrences of this name, so a name that also
# reads as ordinary English ("other") matches prose like "one over the other"
# and fails a correct run.
mkdir -p "$ROOT/plugins/demo/skills/lone_gizmo"

cat > "$ROOT/plugins/demo/skills/demo/SKILL.md" <<'EOF'
---
name: demo
description: Demo hub skill for family resolution tests. Use when testing hub family union.
version: 1.0.0
author: Test
license: MIT
---

# demo

<demo>
<family>
- `demo` — hub
- `demo_alpha` — sibling
- `shared_linter` — named only in family block
</family>
</demo>
EOF

cat > "$ROOT/plugins/demo/skills/demo_alpha/SKILL.md" <<'EOF'
---
name: demo_alpha
description: Demo alpha sibling. Use when testing prefix family membership.
version: 1.0.0
author: Test
license: MIT
---

# demo_alpha
EOF

cat > "$ROOT/plugins/demo/skills/shared_linter/SKILL.md" <<'EOF'
---
name: shared_linter
description: Shared linter named only via family block. Use when testing family union.
version: 1.0.0
author: Test
license: MIT
---

# shared_linter
EOF

# The description carries none of the exclusion markers the grader accepts
# (exclud, outside, not part, omit, skip, beyond, unrelated), so a run that
# wrongly pulls this skill into the resolved set cannot satisfy the marker
# check just by quoting its description back.
cat > "$ROOT/plugins/demo/skills/lone_gizmo/SKILL.md" <<'EOF'
---
name: lone_gizmo
description: Standalone gizmo skill that shares no family token with the demo hub. Use when proving family resolution stops at the token boundary.
version: 1.0.0
author: Test
license: MIT
---

# lone_gizmo
EOF
