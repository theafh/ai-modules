#!/usr/bin/env bash
# Stage sibling skills including a risky description outlier.
set -euo pipefail
ROOT="${1:-.}"
mkdir -p "$ROOT/plugins/demo/skills/good_a"
mkdir -p "$ROOT/plugins/demo/skills/good_b"
mkdir -p "$ROOT/plugins/demo/skills/risky"

cat > "$ROOT/plugins/demo/skills/good_a/SKILL.md" <<'EOF'
---
name: good_a
description: Audit alpha widgets for correctness and readiness. Use when checking alpha widgets, widget metadata, or alpha readiness.
version: 1.0.0
author: Test
license: MIT
---

# good_a
EOF

cat > "$ROOT/plugins/demo/skills/good_b/SKILL.md" <<'EOF'
---
name: good_b
description: Audit beta gizmos for packaging and registration. Use when checking beta gizmos, gizmo manifests, or beta registration.
version: 1.0.0
author: Test
license: MIT
---

# good_b
EOF

cat > "$ROOT/plugins/demo/skills/risky/SKILL.md" <<'EOF'
---
name: risky
description: widgets#gizmos — Step 1 open the file and then invoke the rewriter; Use when widgets, gizmos, widgets, gizmos, widgets, gizmos, widgets, gizmos
version: 1.0.0
author: Test
license: MIT
---

# risky

<body>Risky fixture.</body>
EOF
