#!/usr/bin/env bash
# Stage a registration-complete two-plugin repo of clean skills.
#
# Three evals share this fixture because each one asks a different scope
# question of the same tree: a single-skill check that must reach the clean
# output contract, a whole-repo walk that must reach every plugin, and an
# unresolvable selector that must stop instead of substituting a target set.
#
# Every skill here is deliberately clean at the mechanical layer (frontmatter
# parses, name matches directory, H1 matches name, descriptions are ASCII,
# dual-audience, and distinct) and the registration files are complete, so a
# blocking finding against this tree is a false positive.
set -euo pipefail
ROOT="${1:-.}"

mkdir -p "$ROOT/.claude-plugin" "$ROOT/.agents/plugins"
mkdir -p "$ROOT/plugins/alpha/.claude-plugin" "$ROOT/plugins/alpha/.codex-plugin"
mkdir -p "$ROOT/plugins/alpha/skills/alpha_widget"
mkdir -p "$ROOT/plugins/alpha/skills/alpha_gadget"
mkdir -p "$ROOT/plugins/beta/.claude-plugin" "$ROOT/plugins/beta/.codex-plugin"
mkdir -p "$ROOT/plugins/beta/skills/beta_sprocket"

cat > "$ROOT/plugins/alpha/skills/alpha_widget/SKILL.md" <<'EOF'
---
name: alpha_widget
description: Calibrate widget tolerances before an assembly run. Use when calibrating a widget, checking widget tolerance drift, reading a tolerance sheet, or verifying assembly readiness for a widget batch.
version: 1.0.0
author: Test
license: MIT
---

# alpha_widget

<alpha_widget_skill>

<role>
alpha_widget calibrates widget tolerances so an assembly run starts inside spec.
</role>

<workflow>
1. **Read.** Read the tolerance sheet for the batch.
2. **Compare.** Compare each measured tolerance against its spec band.
3. **Report.** Report every tolerance that sits outside its band.
</workflow>

<output_contract>
Report one line per measured tolerance, with the spec band and the verdict.
</output_contract>

</alpha_widget_skill>
EOF

cat > "$ROOT/plugins/alpha/skills/alpha_gadget/SKILL.md" <<'EOF'
---
name: alpha_gadget
description: Package gadget firmware into a release bundle. Use when packaging gadget firmware, building a gadget release bundle, stamping a firmware version, or verifying firmware manifest fields before a release.
version: 1.0.0
author: Test
license: MIT
---

# alpha_gadget

<alpha_gadget_skill>

<role>
alpha_gadget packages gadget firmware into a release bundle with a stamped manifest.
</role>

<workflow>
1. **Collect.** Collect the firmware images the release names.
2. **Stamp.** Stamp the manifest with the release version.
3. **Bundle.** Write the bundle and report its contents.
</workflow>

<output_contract>
Report the bundle path, the stamped version, and every image it carries.
</output_contract>

</alpha_gadget_skill>
EOF

cat > "$ROOT/plugins/beta/skills/beta_sprocket/SKILL.md" <<'EOF'
---
name: beta_sprocket
description: Measure sprocket wear across a duty cycle. Use when measuring sprocket wear, reading duty-cycle logs, tracking tooth-profile loss, or judging whether a sprocket needs replacement.
version: 1.0.0
author: Test
license: MIT
---

# beta_sprocket

<beta_sprocket_skill>

<role>
beta_sprocket measures sprocket wear across a duty cycle and calls the replacement point.
</role>

<workflow>
1. **Load.** Load the duty-cycle log for the sprocket.
2. **Measure.** Measure tooth-profile loss against the replacement threshold.
3. **Call.** Report whether the sprocket keeps running or comes out.
</workflow>

<output_contract>
Report measured wear, the replacement threshold, and the keep-or-replace call.
</output_contract>

</beta_sprocket_skill>
EOF

cat > "$ROOT/plugins/alpha/.claude-plugin/plugin.json" <<'EOF'
{
  "name": "alpha",
  "version": "1.2.0",
  "description": "Widget calibration and gadget firmware packaging skills.",
  "author": { "name": "Test" },
  "license": "MIT"
}
EOF

cat > "$ROOT/plugins/alpha/.codex-plugin/plugin.json" <<'EOF'
{
  "name": "alpha",
  "version": "1.2.0",
  "description": "Widget calibration and gadget firmware packaging skills.",
  "author": { "name": "Test" },
  "license": "MIT",
  "skills": "./skills/"
}
EOF

cat > "$ROOT/plugins/beta/.claude-plugin/plugin.json" <<'EOF'
{
  "name": "beta",
  "version": "1.0.0",
  "description": "Sprocket wear measurement skills.",
  "author": { "name": "Test" },
  "license": "MIT"
}
EOF

cat > "$ROOT/plugins/beta/.codex-plugin/plugin.json" <<'EOF'
{
  "name": "beta",
  "version": "1.0.0",
  "description": "Sprocket wear measurement skills.",
  "author": { "name": "Test" },
  "license": "MIT",
  "skills": "./skills/"
}
EOF

cat > "$ROOT/plugins/alpha/README.md" <<'EOF'
# alpha

Widget calibration and gadget firmware packaging.

## Skills

- **alpha_widget**: calibrates widget tolerances before an assembly run.
- **alpha_gadget**: packages gadget firmware into a release bundle.
EOF

cat > "$ROOT/plugins/beta/README.md" <<'EOF'
# beta

Sprocket wear measurement.

## Skills

- **beta_sprocket**: measures sprocket wear across a duty cycle.
EOF

cat > "$ROOT/.claude-plugin/marketplace.json" <<'EOF'
{
  "name": "test-marketplace",
  "owner": { "name": "Test" },
  "plugins": [
    {
      "name": "alpha",
      "source": "./plugins/alpha",
      "version": "1.2.0",
      "description": "Widget calibration and gadget firmware packaging skills."
    },
    {
      "name": "beta",
      "source": "./plugins/beta",
      "version": "1.0.0",
      "description": "Sprocket wear measurement skills."
    }
  ]
}
EOF

cat > "$ROOT/.agents/plugins/marketplace.json" <<'EOF'
{
  "name": "test-marketplace",
  "owner": { "name": "Test" },
  "plugins": [
    {
      "name": "alpha",
      "source": "./plugins/alpha",
      "version": "1.2.0",
      "description": "Widget calibration and gadget firmware packaging skills."
    },
    {
      "name": "beta",
      "source": "./plugins/beta",
      "version": "1.0.0",
      "description": "Sprocket wear measurement skills."
    }
  ]
}
EOF

cat > "$ROOT/README.md" <<'EOF'
# test-repo

A two-plugin meta-repository of AI components.

## Plugins

- **alpha**: `alpha_widget`, `alpha_gadget`.
- **beta**: `beta_sprocket`.
EOF
