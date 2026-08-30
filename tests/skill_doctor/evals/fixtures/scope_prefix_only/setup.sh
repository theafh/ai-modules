#!/usr/bin/env bash
# Stage a prefix-only (no <family>) wiki-like skill tree.
set -euo pipefail
ROOT="${1:-.}"
mkdir -p "$ROOT/plugins/km/skills/wiki"
mkdir -p "$ROOT/plugins/km/skills/wiki_import"
mkdir -p "$ROOT/plugins/km/skills/wiki_wrapup"
mkdir -p "$ROOT/plugins/km/skills/spr"

cat > "$ROOT/plugins/km/skills/wiki/SKILL.md" <<'EOF'
---
name: wiki
description: Wiki hub without a family block. Use when testing prefix-only family resolution.
version: 1.0.0
author: Test
license: MIT
---

# wiki

<wiki>
<role>Hub without family enumeration.</role>
</wiki>
EOF

cat > "$ROOT/plugins/km/skills/wiki_import/SKILL.md" <<'EOF'
---
name: wiki_import
description: Wiki import sibling. Use when testing prefix family membership.
version: 1.0.0
author: Test
license: MIT
---

# wiki_import
EOF

cat > "$ROOT/plugins/km/skills/wiki_wrapup/SKILL.md" <<'EOF'
---
name: wiki_wrapup
description: Wiki wrapup sibling. Use when testing prefix family membership.
version: 1.0.0
author: Test
license: MIT
---

# wiki_wrapup
EOF

cat > "$ROOT/plugins/km/skills/spr/SKILL.md" <<'EOF'
---
name: spr
description: Unrelated distillation skill. Use when proving family exclusion.
version: 1.0.0
author: Test
license: MIT
---

# spr
EOF
