#!/usr/bin/env bash
# Stage a repo that ships skills with none of this repository's conventions.
#
# The layout is a repo-root skills/ tree — no plugins/, no plugin manifest, no
# marketplace file — and AGENTS.md states no naming, README-listing, or
# version rule. Every registration check therefore has no subject here, so a
# correct run reports the surface as not applicable rather than as missing, and
# the absent `version:` reports at info saying no rule was found.
set -euo pipefail
ROOT="${1:-.}"
mkdir -p "$ROOT/skills/alpha_widget" "$ROOT/skills/beta_sprocket"

cat > "$ROOT/AGENTS.md" <<'EOF'
# AGENTS.md

**widget-shop is a widget toolkit.** It ships skills that audit widgets.

## Conventions

- **Keep every artefact plain markdown.** Prefer plain files over generated
  formats so any editor can read them.
- **Write one skill per capability.** A skill that grows a second capability
  splits into siblings.
EOF

cat > "$ROOT/skills/alpha_widget/SKILL.md" <<'EOF'
---
name: alpha_widget
description: Audit alpha widgets for structural correctness and packaging readiness. Use when checking alpha widgets, alpha widget manifests, or alpha release readiness.
author: Test
license: MIT
---

# alpha_widget

<alpha_widget_skill>

<role>
alpha_widget audits alpha widgets for structural correctness and packaging
readiness. It reports findings with paths and evidence and edits nothing.
</role>

<workflow>
1. **Orient.** Read the widget manifest and name the selected widget set.
2. **Check.** Inspect each widget for structural correctness.
3. **Report.** Emit findings with paths and evidence.
</workflow>

<output_contract>
Report each finding with its path and its evidence, then close with the checks
that ran.
</output_contract>

</alpha_widget_skill>
EOF

cat > "$ROOT/skills/beta_sprocket/SKILL.md" <<'EOF'
---
name: beta_sprocket
description: Audit beta sprockets for fit and torque tolerance. Use when checking beta sprockets, sprocket tolerances, or sprocket assembly readiness.
author: Test
license: MIT
---

# beta_sprocket

<beta_sprocket_skill>

<role>
beta_sprocket audits beta sprockets for fit and torque tolerance. It reports
findings with paths and evidence and edits nothing.
</role>

<workflow>
1. **Orient.** Read the sprocket table and name the selected sprocket set.
2. **Check.** Measure each sprocket against its tolerance.
3. **Report.** Emit findings with paths and evidence.
</workflow>

<output_contract>
Report each finding with its path and its evidence, then close with the checks
that ran.
</output_contract>

</beta_sprocket_skill>
EOF
