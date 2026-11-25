#!/usr/bin/env bash
# Stage Layer 2 scenario sandboxes. Each sandbox has its own fake HOME so
# subagents running discover_wiki.sh / init_wiki.sh with HOME overridden
# stay fully isolated from the operator's real home tree.
#
# Usage:
#   setup_scenarios.sh                          # restage ALL sandboxes under SCRIPT_DIR
#   setup_scenarios.sh <SCENARIO_ID>            # restage only one under SCRIPT_DIR/<id>
#   setup_scenarios.sh <SCENARIO_ID> <DEST_DIR> # restage one scenario into DEST_DIR

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
WIKI_SKILL="$REPO_ROOT/plugins/knowledge_management/skills/wiki"
INIT="$WIKI_SKILL/scripts/init_wiki.sh"

# Optional override: when set, reset_sandbox stages into this path instead of
# SCRIPT_DIR/<id>. Behavioural runs pass a create_sandbox_root destination here.
STAGE_DEST=""

stage() { mkdir -p "$1"; }

reset_sandbox() {
    local id=$1
    local sandbox
    if [[ -n "${STAGE_DEST}" ]]; then
        sandbox="$STAGE_DEST"
    else
        sandbox="$SCRIPT_DIR/$id"
    fi
    rm -rf "$sandbox"
    stage "$sandbox/HOME"
    printf '%s' "$sandbox"
}

# Record a file's sha256 into a baseline sidecar for `file_matches_baseline`.
# Args: <file> <baseline-path>. The baseline lives outside the fake HOME so the
# agent's wiki view never sees it.
_sha_baseline() {
    mkdir -p "$(dirname "$2")"
    python3 - "$1" "$2" <<'BASELINEPY'
import hashlib, pathlib, sys
src, dst = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
dst.write_text(hashlib.sha256(src.read_bytes()).hexdigest() + "\n")
BASELINEPY
}

# Fail loudly when a staged raw sidecar's recorded sha256 drifts from the
# constant an evals.json assertion hardcodes. Args: <raw-file> <expected-hex>.
_assert_recorded_sha256() {
    local actual
    actual=$(grep -E '^sha256:' "$1" | head -1 | awk '{print $2}')
    if [[ "$actual" != "$2" ]]; then
        echo "ERROR: $1 recorded sha256 $actual != expected $2." >&2
        echo "       An evals.json assertion hardcodes the expected value —" >&2
        echo "       update it together with this fixture body." >&2
        exit 3
    fi
}

stage_L2-1() {
    # L2-1: existing wiki at CWD; user wants to add a page.
    local sb
    sb=$(reset_sandbox L2-1)
    stage "$sb/HOME/proj"
    "$INIT" "$sb/HOME/proj/wiki" >/dev/null
}

stage_L2-2() {
    # L2-2: D6 ambiguous case — wiki at HOME, empty proj at CWD.
    local sb
    sb=$(reset_sandbox L2-2)
    "$INIT" "$sb/HOME/wiki" >/dev/null
    stage "$sb/HOME/proj"
}

stage_L2-3() {
    # L2-3: init request when wiki already exists at CWD.
    local sb
    sb=$(reset_sandbox L2-3)
    stage "$sb/HOME/proj"
    "$INIT" "$sb/HOME/proj/wiki" >/dev/null
}

stage_L2-4() {
    # L2-4: init from scratch, ambiguous discovery; user direction in prompt.
    local sb
    sb=$(reset_sandbox L2-4)
    stage "$sb/HOME/proj"
}

stage_L2-5() {
    # L2-5: .no_wiki at CWD, wiki at HOME -> auto-resolve to HOME/wiki.
    local sb
    sb=$(reset_sandbox L2-5)
    "$INIT" "$sb/HOME/wiki" >/dev/null
    stage "$sb/HOME/proj"
    : > "$sb/HOME/proj/.no_wiki"
}

stage_L2-6() {
    # L2-6: answer-only query against a populated wiki. The question is a
    # single-page lookup and the prompt forbids filing, so the session creates
    # and updates nothing — log.md must come out byte-identical. The baseline
    # sidecar lives outside HOME so it is invisible to the agent's wiki view.
    local sb
    sb=$(reset_sandbox L2-6)
    stage "$sb/HOME/proj"
    "$INIT" "$sb/HOME/proj/wiki" >/dev/null
    local wiki="$sb/HOME/proj/wiki"
    cat > "$wiki/concepts/widgets.md" <<'EOF'
---
title: widgets
created: 2026-05-01
updated: 2026-05-01
type: concept
tags: [model]
sources: []
confidence: high
---

# widgets

The widget framework renders every widget BLUE by default. The default has been
blue since v2.0, when it changed from red. An instance overrides it with the
`color` attribute.

Widgets are assembled by the [gadgets](gadgets.md) pipeline.
EOF
    cat > "$wiki/concepts/gadgets.md" <<'EOF'
---
title: gadgets
created: 2026-05-01
updated: 2026-05-01
type: concept
tags: [model]
sources: []
confidence: high
---

# gadgets

The gadget pipeline assembles widgets into shippable units. It reads the
[widgets](widgets.md) defaults and applies no color of its own.
EOF
    python3 - "$wiki/index.md" <<'PY'
import sys, pathlib
idx = pathlib.Path(sys.argv[1])
text = idx.read_text()
text = text.replace(
    "## Concepts\n",
    "## Concepts\n\n- [gadgets](concepts/gadgets.md) — assembly pipeline\n"
    "- [widgets](concepts/widgets.md) — widget framework defaults\n",
)
idx.write_text(text)
PY
    # Byte-identity baseline for the answer-only assertion.
    mkdir -p "$sb/baseline"
    python3 - "$wiki/log.md" "$sb/baseline/log.md.sha256" <<'PY'
import hashlib, pathlib, sys
src, dst = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
dst.write_text(hashlib.sha256(src.read_bytes()).hexdigest() + "\n")
PY
}

stage_L2-7() {
    # L2-7: multi-page synthesis query against a populated wiki. Four pages each
    # hold one piece of the answer — the framework default, the theme layer, the
    # precedence rule, and what production ships — so no single page answers the
    # question and the answer only exists as cross-page reasoning. The question
    # shape is what makes it valuable, so the type rule files it under queries/.
    local sb
    sb=$(reset_sandbox L2-7)
    stage "$sb/HOME/proj"
    "$INIT" "$sb/HOME/proj/wiki" >/dev/null
    local wiki="$sb/HOME/proj/wiki"
    cat > "$wiki/concepts/widget-color-defaults.md" <<'EOF'
---
title: widget color defaults
created: 2026-05-01
updated: 2026-05-01
type: concept
tags: [model]
sources: []
confidence: high
---

# widget color defaults

The widget framework renders every widget BLUE by default. The default has been
blue since v2.0, when it changed from red. A widget carries a color only when
something above the framework supplies one — the framework itself never varies
its default per deployment.

An instance overrides the default with the `color` attribute. Anything else that
changes a rendered color comes from the [theme layer](theme-layer.md), resolved
by the [config precedence](../procedures/config-precedence.md) rule.
EOF
    cat > "$wiki/concepts/theme-layer.md" <<'EOF'
---
title: theme layer
created: 2026-05-01
updated: 2026-05-01
type: concept
tags: [model]
sources: []
confidence: high
---

# theme layer

A theme is a palette file loaded at boot from `themes/<name>.yaml`. When a theme
is loaded, its palette repaints every widget that carries no instance `color`
attribute of its own; when no theme file is present, nothing repaints and the
widget keeps the framework value from
[widget color defaults](widget-color-defaults.md).

Which theme loads is a per-deployment decision, not a framework one — each
deployment names its own theme, and [config precedence](../procedures/config-precedence.md)
settles what wins when several layers speak at once.
EOF
    cat > "$wiki/procedures/config-precedence.md" <<'EOF'
---
title: config precedence
created: 2026-05-01
updated: 2026-05-01
type: procedure
tags: [model]
sources: []
confidence: high
---

# config precedence

Resolve a rendered widget property by walking the layers in fixed order and
taking the first one that supplies a value: the instance attribute, then the
loaded theme palette, then the framework default.

## When this applies

Apply this order whenever a rendered property differs between two deployments
and you need to know which layer produced the difference.

## The rule

1. Read the instance `color` attribute. When present, it wins outright.
2. Otherwise read the loaded theme palette (see [theme layer](../concepts/theme-layer.md)).
3. Otherwise fall back to the framework default (see
   [widget color defaults](../concepts/widget-color-defaults.md)).

Two deployments running the same widget code therefore diverge only at the layer
that differs between them.

## See Also

- [theme layer](../concepts/theme-layer.md)
- [prod deployment](../entities/prod-deployment.md)
EOF
    cat > "$wiki/entities/prod-deployment.md" <<'EOF'
---
title: prod deployment
created: 2026-05-01
updated: 2026-05-01
type: entity
tags: [model]
sources: []
confidence: high
---

# prod deployment

The production deployment boots with `themes/sunset.yaml`, whose palette paints
widgets RED. It has shipped that theme since the v2.4 rollout.

## Key facts and dates

- Loads `themes/sunset.yaml` (red palette) at boot, since v2.4.
- The staging deployment ships no theme file at all and loads none.
- Both deployments run identical widget code and set no instance `color`
  attributes.

## Relationships to other entities

Its rendered colors follow the [theme layer](../concepts/theme-layer.md) and the
[config precedence](../procedures/config-precedence.md) rule.
EOF
    python3 - "$wiki/index.md" <<'PY'
import sys, pathlib
idx = pathlib.Path(sys.argv[1])
text = idx.read_text()
text = text.replace(
    "## Entities\n",
    "## Entities\n\n- [prod deployment](entities/prod-deployment.md) — production deployment facts\n",
)
text = text.replace(
    "## Concepts\n",
    "## Concepts\n\n- [theme layer](concepts/theme-layer.md) — palette files and when they repaint\n"
    "- [widget color defaults](concepts/widget-color-defaults.md) — framework color default\n",
)
text = text.replace(
    "## Procedures\n",
    "## Procedures\n\n- [config precedence](procedures/config-precedence.md) — which layer wins for a rendered property\n",
)
idx.write_text(text)
PY
}

# --- re-ingest drift scenarios (<capture_raw_source> compare-before-write) ----
# Both stage a wiki that already carries a raw sidecar with a correct recorded
# sha256, plus the in-repo source file that sidecar names. L2-8's source still
# says what the sidecar recorded; L2-9's has moved on. The rule under test is
# the hub's "Re-ingest compares before it writes" bullet: decide the branch from
# a --check run over a temp copy while the sidecar on disk stays untouched.

# Build the shared shape both scenarios sit on: a git repo at HOME/proj, an
# initialized wiki inside it, and the notes/ dir the sidecar's source_path names.
# Args: <sandbox-root>. Callers write the source file and the sidecar themselves.
_reingest_sandbox() {
    local sb=$1
    stage "$sb/HOME/proj"
    git -C "$sb/HOME/proj" init -q
    "$INIT" "$sb/HOME/proj/wiki" >/dev/null
    mkdir -p "$sb/HOME/proj/notes"
}

stage_L2-8() {
    # L2-8: re-ingest of an UNCHANGED source. The on-disk source still says
    # exactly what the sidecar body records, so the compare reports `ok` and the
    # skip branch fires: the sidecar comes out byte-identical and log.md gains
    # no entry. Byte-identity is the only way to prove "no hash rewrite", since
    # the write mode would refresh the hash to the same value it already holds.
    local sb
    sb=$(reset_sandbox L2-8)
    _reingest_sandbox "$sb"
    local wiki="$sb/HOME/proj/wiki"
    cat > "$sb/HOME/proj/notes/widget-release.md" <<'EOF'
# Widget Release Notes 2.0

Widgets render BLUE by default in release 2.0. The framework sets the default
and an instance overrides it with the `color` attribute.
EOF
    mkdir -p "$wiki/raw/notes"
    cat > "$wiki/raw/notes/widget-release.md" <<'EOF'
---
source_path: ../notes/widget-release.md
ingested: 2026-05-01
sha256: placeholder
---

# Widget Release Notes 2.0

Widgets render BLUE by default in release 2.0. The framework sets the default
and an instance overrides it with the `color` attribute.
EOF
    python3 "$WIKI_SKILL/scripts/compute_sha256.py" "$wiki/raw/notes/widget-release.md" >/dev/null
    _sha_baseline "$wiki/raw/notes/widget-release.md" "$sb/baseline/widget-release.md.sha256"
    _sha_baseline "$wiki/log.md" "$sb/baseline/log.md.sha256"
}

stage_L2-9() {
    # L2-9: re-ingest of a CHANGED source. The sidecar records the release-2.0
    # body (BLUE) with a matching sha256; the on-disk source now ships release
    # 3.0 (CRIMSON). The compare must report `update` from the temp copy, and
    # only then may the sidecar body be rewritten and its hash refreshed. The
    # hardcoded old-hash assertion in evals.json is guarded below.
    local sb
    sb=$(reset_sandbox L2-9)
    _reingest_sandbox "$sb"
    local wiki="$sb/HOME/proj/wiki"
    cat > "$sb/HOME/proj/notes/widget-release.md" <<'EOF'
# Widget Release Notes 3.0

Widgets render CRIMSON by default in release 3.0. The framework sets the default
and an instance overrides it with the `color` attribute.
EOF
    mkdir -p "$wiki/raw/notes"
    cat > "$wiki/raw/notes/widget-release.md" <<'EOF'
---
source_path: ../notes/widget-release.md
ingested: 2026-05-01
sha256: placeholder
---

# Widget Release Notes 2.0

Widgets render BLUE by default in release 2.0. The framework sets the default
and an instance overrides it with the `color` attribute.
EOF
    python3 "$WIKI_SKILL/scripts/compute_sha256.py" "$wiki/raw/notes/widget-release.md" >/dev/null
    _assert_recorded_sha256 "$wiki/raw/notes/widget-release.md" "3cbc40b475dd9fc90483c1fe2e72f3a41afc8bb085fd200fc2d870b4e6757731"
    _sha_baseline "$wiki/log.md" "$sb/baseline/log.md.sha256"
}

stage_L2-10() {
    # L2-10: init from scratch on an AVAILABLE pick; hub rule alone supplies
    # the init target (no shown-field init path). Stages like L2-4.
    local sb
    sb=$(reset_sandbox L2-10)
    stage "$sb/HOME/proj"
}

stage_WI-1() {
    # WI-1: existing wiki at CWD, user pastes a fresh source. wiki_import must
    # capture raw + emit proposal without touching wiki pages.
    local sb
    sb=$(reset_sandbox WI-1)
    stage "$sb/HOME/proj"
    "$INIT" "$sb/HOME/proj/wiki" >/dev/null
}

stage_WI-2() {
    # WI-2: existing wiki + an existing concept page that the incoming paste
    # will contradict. wiki_import must surface the contradiction without
    # silently editing the existing page.
    local sb
    sb=$(reset_sandbox WI-2)
    stage "$sb/HOME/proj"
    "$INIT" "$sb/HOME/proj/wiki" >/dev/null
    cat > "$sb/HOME/proj/wiki/concepts/widgets.md" <<'EOF'
---
title: widgets
created: 2026-05-01
updated: 2026-05-01
type: concept
tags: [model]
sources: []
confidence: medium
---

# widgets

The widget framework defaults to RED. Every widget instance is rendered red unless
overridden. This has been the canonical default since v1.0.
EOF
    # Index the page so lint doesn't reject the wiki for an unindexed page.
    python3 - "$sb/HOME/proj/wiki/index.md" <<'PY'
import sys, pathlib
idx = pathlib.Path(sys.argv[1])
text = idx.read_text()
text = text.replace("## Concepts\n", "## Concepts\n\n- [widgets](concepts/widgets.md) — placeholder existing page\n")
idx.write_text(text)
PY
}

stage_WI-3() {
    # WI-3: existing wiki at CWD, user pre-approves all NEW candidates. Used to
    # verify the full end-to-end plumbing chain (raw → proposal → page → lint → log).
    local sb
    sb=$(reset_sandbox WI-3)
    stage "$sb/HOME/proj"
    "$INIT" "$sb/HOME/proj/wiki" >/dev/null
}

stage_WI-4() {
    # WI-4: existing wiki at CWD + an out-of-repo local chat-session log staged
    # under the fake HOME (outside the wiki, no public URL). wiki_import must
    # capture it as a raw/meetings/ sidecar (speaker-turn body, no source_url)
    # whose frontmatter records origin via source_path: with a standalone excerpt.
    local sb
    sb=$(reset_sandbox WI-4)
    stage "$sb/HOME/proj"
    "$INIT" "$sb/HOME/proj/wiki" >/dev/null
    stage "$sb/HOME/logs"
    cat > "$sb/HOME/logs/local-chat-log.md" <<'EOF'
User: Can you explain what self-attention does in a transformer?

Assistant: Self-attention lets each token in a sequence weigh every other token
directly, in parallel. The transformer architecture (Vaswani et al., 2017,
"Attention Is All You Need") stacks self-attention layers in place of the
recurrent layers older sequence models relied on.

User: So it replaced RNNs?

Assistant: For most modern NLP work, yes — transformers have dominated since 2017.
LSTMs still show up in some streaming or low-resource settings.

User: Great, save this to my notes.
EOF
}

stage_WI-5() {
    # WI-5 (wiki_provenance-via-raw-and-sources, Acceptance 4): a page-writing
    # request that hands over a pasted meeting note mid-conversation, not an
    # explicit import. wiki_import must take its implicit branch: capture the
    # paste as a raw sidecar with the raw-frontmatter contract, add it to the
    # consuming page's `sources:`, keep the provenance out of the body prose,
    # and complete the page write in the same turn with no three-H2 proposal.
    # The paste carries a four-backtick run and an HTML-like token, so the
    # emitted fence must be five backticks or longer and the token stays
    # unparsed (no MD033 downstream).
    local sb
    sb=$(reset_sandbox WI-5)
    stage "$sb/HOME/proj"
    "$INIT" "$sb/HOME/proj/wiki" >/dev/null
    local wiki="$sb/HOME/proj/wiki"
    python3 - "$wiki" <<'PY'
import sys, pathlib
w = pathlib.Path(sys.argv[1])
text = (w / "SCHEMA.md").read_text()
(w / "SCHEMA.md").write_text(
    text.replace("## Tag Taxonomy\n", "## Tag Taxonomy\n\n- Domain: model\n", 1)
)
(w / "concepts" / "widget-caching.md").write_text(
    "---\n"
    "title: widget caching\n"
    "created: 2026-05-01\n"
    "updated: 2026-05-01\n"
    "type: concept\n"
    "tags: [model]\n"
    "confidence: medium\n"
    "---\n\n"
    "# widget caching\n\n"
    "The widget cache keeps rendered widget output between requests.\n\n"
    "## Definition / explanation\n\n"
    "An entry is keyed by widget identity and by the inputs that affect its\n"
    "rendering. See [widget defaults](widget-defaults.md) for the values an\n"
    "entry resolves.\n\n"
    "## Current state of knowledge\n\n"
    "The cache is invalidated when a widget's source record changes.\n\n"
    "## Open questions or debates\n\n"
    "None recorded.\n\n"
    "## Related concepts\n\n"
    "- [widget defaults](widget-defaults.md)\n",
    encoding="utf-8",
)
(w / "concepts" / "widget-defaults.md").write_text(
    "---\n"
    "title: widget defaults\n"
    "created: 2026-05-01\n"
    "updated: 2026-05-01\n"
    "type: concept\n"
    "tags: [model]\n"
    "confidence: medium\n"
    "---\n\n"
    "# widget defaults\n\n"
    "The defaults table lists the framework colour for each widget class.\n\n"
    "## Definition / explanation\n\n"
    "A widget keeps the framework colour unless something above the framework\n"
    "supplies one. See [widget caching](widget-caching.md) for where the\n"
    "resolved value is stored.\n\n"
    "## Current state of knowledge\n\n"
    "The framework colour is resolved before any deployment-level override.\n\n"
    "## Open questions or debates\n\n"
    "None recorded.\n\n"
    "## Related concepts\n\n"
    "- [widget caching](widget-caching.md)\n",
    encoding="utf-8",
)
idx = w / "index.md"
text = idx.read_text()
text = text.replace(
    "## Concepts\n",
    "## Concepts\n\n"
    "- [widget caching](concepts/widget-caching.md) — rendered output kept between requests\n"
    "- [widget defaults](concepts/widget-defaults.md) — framework colour per widget class\n",
    1,
)
text = text.replace("Total pages: 0", "Total pages: 2", 1)
idx.write_text(text)
PY
}

stage_WU-1() {
    # WU-1: existing wiki + synthetic transcript embedded in the user prompt.
    # wiki_wrapup must emit a proposal without writing any wiki page.
    local sb
    sb=$(reset_sandbox WU-1)
    stage "$sb/HOME/proj"
    "$INIT" "$sb/HOME/proj/wiki" >/dev/null
}

stage_WU-2() {
    # WU-2: existing wiki + concept page contradicting the session content.
    # wiki_wrapup must surface the contradiction without editing the existing page.
    local sb
    sb=$(reset_sandbox WU-2)
    stage "$sb/HOME/proj"
    "$INIT" "$sb/HOME/proj/wiki" >/dev/null
    cat > "$sb/HOME/proj/wiki/concepts/widgets.md" <<'EOF'
---
title: widgets
created: 2026-05-01
updated: 2026-05-01
type: concept
tags: [model]
sources: []
confidence: medium
---

# widgets

The widget framework defaults to RED. Every widget instance is rendered red unless
overridden. This has been the canonical default since v1.0.
EOF
    python3 - "$sb/HOME/proj/wiki/index.md" <<'PY'
import sys, pathlib
idx = pathlib.Path(sys.argv[1])
text = idx.read_text()
text = text.replace("## Concepts\n", "## Concepts\n\n- [widgets](concepts/widgets.md) — placeholder existing page\n")
idx.write_text(text)
PY
}

stage_WU-3() {
    # WU-3: end-to-end plumbing — proposal → user pre-approval → wiki page →
    # lint → log. Mirrors WI-3 for the session-mining surface.
    local sb
    sb=$(reset_sandbox WU-3)
    stage "$sb/HOME/proj"
    "$INIT" "$sb/HOME/proj/wiki" >/dev/null
}

# --- auto_shaper_wiki audit-flow scenarios (wiki_fix fronts the agent) --------
# These stage a "dirty" wiki inside its own git repo so origin-field
# reconciliation has a controlled repo boundary, then the wiki_fix skill runs
# the audit. Graded out-of-band (they spawn the heavy audit subagent).

# Add a raw sidecar. Args: <wiki> <relpath-under-raw> <frontmatter-body> <body>
_as_raw() {
    local wiki=$1 rel=$2 fm=$3 body=$4
    mkdir -p "$(dirname "$wiki/raw/$rel")"
    printf -- '---\n%s\n---\n\n%s\n' "$fm" "$body" > "$wiki/raw/$rel"
}

stage_AS-1() {
    # AS-1 (task item 4): auto_shaper_wiki auto-reconciles deterministically
    # mislabeled or redundant origin fields — value moves to the field whose
    # form fits, an in-repo absolute source_path normalizes to repo-relative, a
    # same-origin duplicate collapses to one field. Raw bodies stay untouched;
    # no value is invented.
    local sb
    sb=$(reset_sandbox AS-1)
    stage "$sb/HOME/proj"
    git -C "$sb/HOME/proj" init -q
    "$INIT" "$sb/HOME/proj/wiki" >/dev/null
    local wiki="$sb/HOME/proj/wiki"
    # A real in-repo file (outside the wiki dir but inside the repo) that the
    # mislabeled sidecars name. Its repo-relative spelling from the wiki root is
    # ../shared/spec.md.
    mkdir -p "$sb/HOME/proj/shared"
    printf 'The in-repo spec these sidecars point at.\n' > "$sb/HOME/proj/shared/spec.md"
    local abs_spec
    abs_spec=$(python3 -c "import pathlib,sys;print(pathlib.Path(sys.argv[1]).resolve())" "$sb/HOME/proj/shared/spec.md")
    # 1. file:// source_url naming an in-repo target -> repo-relative source_path
    _as_raw "$wiki" "notes/fileurl-in-repo.md" \
        "source_url: file://$abs_spec"$'\n'"ingested: 2026-05-01" \
        "Excerpt of the in-repo spec, captured verbatim below. KEEP THIS BODY."
    # 2. remote URL sitting in source_path -> source_url
    _as_raw "$wiki" "articles/url-in-path.md" \
        "source_path: https://example.com/published-article"$'\n'"ingested: 2026-05-01" \
        "Excerpt of a published article. KEEP THIS BODY."
    # 3. absolute in-repo source_path -> its repo-relative equivalent
    _as_raw "$wiki" "notes/abs-path.md" \
        "source_path: $abs_spec"$'\n'"ingested: 2026-05-01" \
        "Another excerpt of the same in-repo spec. KEEP THIS BODY."
    # 4. both fields naming the SAME in-repo origin -> collapse to source_path
    _as_raw "$wiki" "notes/both-same-origin.md" \
        "source_url: file://$abs_spec"$'\n'"source_path: ../shared/spec.md"$'\n'"ingested: 2026-05-01" \
        "Duplicate-origin excerpt. KEEP THIS BODY."
}

stage_AS-2() {
    # AS-2 (task item 5): a wiki whose SCHEMA.md ### raw/ Frontmatter teaches the
    # superseded source_url: file://… form. The agent must SURFACE the
    # contradicting customization for the user, not silently preserve it.
    local sb
    sb=$(reset_sandbox AS-2)
    stage "$sb/HOME/proj"
    git -C "$sb/HOME/proj" init -q
    "$INIT" "$sb/HOME/proj/wiki" >/dev/null
    local wiki="$sb/HOME/proj/wiki"
    # Overwrite the canonical ### raw/ Frontmatter subsection with a legacy one
    # that teaches source_url: file://… — a contradiction of the two-field
    # contract, not an extension.
    python3 - "$wiki/SCHEMA.md" <<'PY'
import sys, pathlib, re
p = pathlib.Path(sys.argv[1])
text = p.read_text()
legacy = """### raw/ Frontmatter

Raw sources get a small frontmatter block:

```yaml
---
source_url: file://sources/local-file.md    # local file path as a file:// URL
ingested: YYYY-MM-DD
sha256: <hex digest of the body>
---
```

`source_url:` records where the source came from, including a `file://` URL for
a local file on this machine.
"""
# Replace the whole ### raw/ Frontmatter subsection (up to the next ## or ###).
pat = re.compile(r"### raw/ Frontmatter\n.*?(?=\n## |\n### |\Z)", re.DOTALL)
text2 = pat.sub(legacy.rstrip() + "\n", text, count=1)
if text2 == text:
    text2 = text.rstrip() + "\n\n" + legacy
p.write_text(text2)
PY
    # A sidecar that follows the legacy schema (so the contradiction is live).
    _as_raw "$wiki" "notes/legacy-local.md" \
        "source_url: file://sources/local-file.md"$'\n'"ingested: 2026-05-01" \
        "Legacy sidecar following the contradicting schema."
}

stage_AS-3() {
    # AS-3 (task item 9): irreducible origin cases the agent must SURFACE, not
    # auto-resolve — two fields naming DIFFERENT plausible origins, and an
    # out-of-repo file:// with no stand-alone body excerpt. Origin left
    # unchanged; no value invented.
    local sb
    sb=$(reset_sandbox AS-3)
    stage "$sb/HOME/proj"
    git -C "$sb/HOME/proj" init -q
    "$INIT" "$sb/HOME/proj/wiki" >/dev/null
    local wiki="$sb/HOME/proj/wiki"
    # 1. a broken source_path beside a valid but DIFFERENT source_url — choosing
    #    one discards provenance, so the user decides.
    _as_raw "$wiki" "articles/different-origins.md" \
        "source_url: https://example.com/the-real-article"$'\n'"source_path: ../nonexistent/other-thing.md"$'\n'"ingested: 2026-05-01" \
        "Excerpt whose two origin fields name different sources."
    # 2. an out-of-repo file:// with NO stand-alone excerpt — dropping the field
    #    would strand the source, so the user confirms before it drops to an
    #    excerpt-plus-locality-note.
    _as_raw "$wiki" "notes/stranded.md" \
        "source_url: file:///Users/someone/private/scratch.md"$'\n'"ingested: 2026-05-01" \
        "See attached."
}

stage_AS-4() {
    # AS-4 (wiki_source-path-anchor-language, task item 3): auto_shaper_wiki
    # reconciles a legacy `file://` source_url whose value names an in-repo source
    # ONE DIRECTORY OUTSIDE the wiki — the pre-split migration shape
    # `sources/earlier-versions/foo.md`, a repo-root sibling of the wiki — to a
    # `source_path:` written as the wiki-root-relative `../sources/…` form the
    # linter's raw-origin warn computes and carries as its `-> ../…` rewrite, NOT
    # the lint-failing repo-root reading `sources/…` (which the wiki-root join
    # misses, yielding a blocking "does not resolve"). Re-linting is clean
    # (0 blocking); the raw body stays untouched.
    local sb
    sb=$(reset_sandbox AS-4)
    stage "$sb/HOME/proj"
    git -C "$sb/HOME/proj" init -q
    "$INIT" "$sb/HOME/proj/wiki" >/dev/null
    local wiki="$sb/HOME/proj/wiki"
    # The in-repo source lives outside the wiki dir but inside the repo. Its
    # wiki-root-relative spelling is ../sources/earlier-versions/foo.md; a naive
    # repo-root reading of the legacy value would (wrongly) be
    # sources/earlier-versions/foo.md, which the linter rejects.
    mkdir -p "$sb/HOME/proj/sources/earlier-versions"
    printf 'Legacy pre-split source carried into a code repo. KEEP THIS BODY.\n' \
        > "$sb/HOME/proj/sources/earlier-versions/foo.md"
    # An anchorless file:// source_url naming that repo-root sibling — the exact
    # migration shape this task fixes.
    _as_raw "$wiki" "notes/legacy-fileurl.md" \
        "source_url: file://sources/earlier-versions/foo.md"$'\n'"ingested: 2026-05-01" \
        "Excerpt of the in-repo source, captured below. KEEP THIS BODY."
}

stage_AS-5() {
    # AS-5 (wiki_auto-shaper-internal-contradictions, Acceptance item 4): one
    # genuine cross-page factual contradiction. The agent must mark both pages
    # contested: true without merging or hedging either body, and report
    # K >= 1 contested pages on the final_line. Against the pre-carve-out
    # clean bar the scenario fails (unreachable "no warn" exit); with the
    # contested-warn carve-out it reaches all-passes-clean.
    local sb
    sb=$(reset_sandbox AS-5)
    stage "$sb/HOME/proj"
    git -C "$sb/HOME/proj" init -q
    "$INIT" "$sb/HOME/proj/wiki" >/dev/null
    local wiki="$sb/HOME/proj/wiki"
    cat > "$wiki/concepts/widget-default-color.md" <<'EOF'
---
title: widget default color
created: 2026-05-01
updated: 2026-05-01
type: concept
tags: [model]
sources: []
confidence: high
---

# widget default color

## Definition / explanation

KEEP CLAIM RED: The widget framework defaults every widget instance to RED.
Red is the only canonical default; an instance overrides it with the `color`
attribute.

## Current state of knowledge

This is the framework default since v1.0. See also
[rendering defaults](rendering-defaults.md).

## Open questions or debates

None recorded.

## Related concepts

- [rendering defaults](rendering-defaults.md)
EOF
    cat > "$wiki/concepts/rendering-defaults.md" <<'EOF'
---
title: rendering defaults
created: 2026-05-01
updated: 2026-05-01
type: concept
tags: [model]
sources: []
confidence: high
---

# rendering defaults

## Definition / explanation

KEEP CLAIM BLUE: The widget framework defaults every widget instance to BLUE.
Blue is the only canonical default; an instance overrides it with the `color`
attribute.

## Current state of knowledge

This is the framework default since v2.0. See also
[widget default color](widget-default-color.md).

## Open questions or debates

None recorded.

## Related concepts

- [widget default color](widget-default-color.md)
EOF
    python3 - "$wiki/index.md" <<'PY'
import sys, pathlib
idx = pathlib.Path(sys.argv[1])
text = idx.read_text()
text = text.replace(
    "## Concepts\n",
    "## Concepts\n\n"
    "- [rendering defaults](concepts/rendering-defaults.md) — claimed BLUE widget default\n"
    "- [widget default color](concepts/widget-default-color.md) — claimed RED widget default\n",
)
idx.write_text(text)
PY
}

stage_AS-6() {
    # AS-6 (wiki_metadata-in-headings, Approach "Harness placement"): the wiki
    # keeps the scaffold `procedure` type and `## Procedure Pages` section, so
    # its SCHEMA declares the scaffold label vocabulary. A procedure page and a
    # concept page each carry mixed-source entries with parenthesised
    # attribution jammed into their labels. After wiki_fix the procedure page's
    # labels match the vocabulary verbatim, the concept page keeps its own
    # anatomy labels, both route the displaced dates to `sources:`, and the
    # report names the routing in its per-file change list.
    local sb
    sb=$(reset_sandbox AS-6)
    stage "$sb/HOME/proj"
    git -C "$sb/HOME/proj" init -q
    "$INIT" "$sb/HOME/proj/wiki" >/dev/null
    local wiki="$sb/HOME/proj/wiki"
    python3 - "$wiki/SCHEMA.md" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1])
text = p.read_text()
text = text.replace("## Tag Taxonomy\n", "## Tag Taxonomy\n\n- Domain: model\n", 1)
p.write_text(text)
PY
    # Two captured sessions so the displaced dates have a `sources:` target.
    _as_raw "$wiki" "sessions/triage-2026-01-15.md" \
        "source_url: https://example.com/triage-2026-01-15"$'\n'"ingested: 2026-01-15" \
        "Triage session, 2026-01-15: the release checklist and the widget default were reviewed."
    _as_raw "$wiki" "sessions/design-review-2026-02-02.md" \
        "source_url: https://example.com/design-review-2026-02-02"$'\n'"ingested: 2026-02-02" \
        "Design review, 2026-02-02: the release rule was restated for the current programme."
    python3 "$WIKI_SKILL/scripts/compute_sha256.py" \
        "$wiki/raw/sessions/triage-2026-01-15.md" \
        "$wiki/raw/sessions/design-review-2026-02-02.md" >/dev/null
    cat > "$wiki/procedures/release-checklist.md" <<'EOF'
---
title: release checklist
created: 2026-01-10
updated: 2026-01-10
type: procedure
tags: [model]
confidence: high
---

# release checklist

Run the release checklist before every tagged build.

**When this applies (2026-01-15 triage session):**
A release is about to be tagged and the changelog has no owner.

**The rule (2026-02-02 design review session):**
Tag only after the full checklist passes.

**See Also:**
- [widget default](../concepts/widget-default.md)
EOF
    cat > "$wiki/concepts/widget-default.md" <<'EOF'
---
title: widget default
created: 2026-01-10
updated: 2026-01-10
type: concept
tags: [model]
confidence: high
---

# widget default

The widget default is the value a tenant inherits when it sets no override.

## Definition / explanation (2026-01-15 triage session)

The default is the value the framework applies when an instance sets no
`color` attribute.

## Current state of knowledge

Unchanged since the last release. See also the
[release checklist](../procedures/release-checklist.md).

## Open questions or debates

None recorded.

## Related concepts

- [release checklist](../procedures/release-checklist.md)
EOF
    python3 - "$wiki/index.md" <<'PY'
import pathlib, sys
idx = pathlib.Path(sys.argv[1])
text = idx.read_text()
text = text.replace(
    "## Concepts\n",
    "## Concepts\n\n- [widget default](concepts/widget-default.md) — inherited widget default\n",
    1,
)
text = text.replace(
    "## Procedures\n",
    "## Procedures\n\n- [release checklist](procedures/release-checklist.md) — pre-release steps\n",
    1,
)
text = text.replace("Total pages: 0", "Total pages: 2", 1)
idx.write_text(text)
PY
}

stage_AS-7() {
    # AS-7 (wiki_metadata-in-headings, Approach "Harness placement"): the wiki's
    # SCHEMA declares no label vocabulary — its `type:` enum omits `procedure`
    # and it carries no `## Procedure Pages` section. Existing labels already
    # match the concept anatomy, and one bold label carries a parenthesised
    # session date. After wiki_fix the label wording is left alone, no scaffold
    # vocabulary is invented, and only the displaced date is routed to
    # `sources:`.
    local sb
    sb=$(reset_sandbox AS-7)
    stage "$sb/HOME/proj"
    git -C "$sb/HOME/proj" init -q
    "$INIT" "$sb/HOME/proj/wiki" >/dev/null
    local wiki="$sb/HOME/proj/wiki"
    python3 - "$wiki/SCHEMA.md" <<'PY'
import pathlib, re, sys
p = pathlib.Path(sys.argv[1])
text = p.read_text()
text = text.replace("## Tag Taxonomy\n", "## Tag Taxonomy\n\n- Domain: model\n", 1)
text = text.replace(
    "type: entity | concept | comparison | query | summary | procedure",
    "type: entity | concept | comparison | query | summary",
    1,
)
text = re.sub(r"## Procedure Pages\n.*?(?=\n## |\Z)", "", text, flags=re.DOTALL)
text = re.sub(r"\n{3,}", "\n\n", text)
p.write_text(text)
PY
    _as_raw "$wiki" "sessions/triage-2026-01-15.md" \
        "source_url: https://example.com/triage-2026-01-15"$'\n'"ingested: 2026-01-15" \
        "Triage session, 2026-01-15: the widget default was reviewed."
    python3 "$WIKI_SKILL/scripts/compute_sha256.py" \
        "$wiki/raw/sessions/triage-2026-01-15.md" >/dev/null
    cat > "$wiki/concepts/widget-default.md" <<'EOF'
---
title: widget default
created: 2026-01-10
updated: 2026-01-10
type: concept
tags: [model]
confidence: high
---

# widget default

The widget default is the value a tenant inherits when it sets no override.

## Definition / explanation

The default is the value the framework applies when an instance sets no
`color` attribute.

## Current state of knowledge

**What the canon says (2026-01-15 triage session):**
The default has not moved since the framework shipped.

## Open questions or debates

None recorded.

## Related concepts

- [widget colour defaults](widget-colour-defaults.md)
EOF
    cat > "$wiki/concepts/widget-colour-defaults.md" <<'EOF'
---
title: widget colour defaults
created: 2026-01-10
updated: 2026-01-10
type: concept
tags: [model]
confidence: high
---

# widget colour defaults

The colour default is on unless a tenant disables it.

## Definition / explanation

An instance inherits the framework colour unless it sets one.

## Current state of knowledge

Unchanged since the last release. See also
[widget default](widget-default.md).

## Open questions or debates

None recorded.

## Related concepts

- [widget default](widget-default.md)
EOF
    python3 - "$wiki/index.md" <<'PY'
import pathlib, sys
idx = pathlib.Path(sys.argv[1])
text = idx.read_text()
text = text.replace(
    "## Concepts\n",
    "## Concepts\n\n"
    "- [widget colour defaults](concepts/widget-colour-defaults.md) — inherited colour default\n"
    "- [widget default](concepts/widget-default.md) — inherited widget default\n",
    1,
)
text = text.replace("Total pages: 0", "Total pages: 2", 1)
idx.write_text(text)
PY
}

stage_AS-12() {
    # AS-12 (wiki_two-pass-normalisation, Approach "Harness placement"): a
    # declared custom field whose value embeds a displaceable qualifier
    # (scope: alpha (Q3 only) against a declared scope: alpha | beta). The
    # agent must apply the named "two-pass remediation" rule through the
    # <fix_undeclared_custom_field> invalid-declared-value branch: route the
    # qualifier to the declared window: field FIRST, then normalise scope to
    # the clean enum member alpha. Q3 is scope metadata, so the routing target
    # is frontmatter — not sources:/raw/, and not ## Derived from. Both halves
    # must be named in the live remediation summary and in the final per-file
    # change report. The companion page carries clean values for both declared
    # fields so neither is "declared but unused" before remediation, and the
    # two pages cross-link so neither is an orphan.
    local sb
    sb=$(reset_sandbox AS-12)
    stage "$sb/HOME/proj"
    git -C "$sb/HOME/proj" init -q
    "$INIT" "$sb/HOME/proj/wiki" >/dev/null
    local wiki="$sb/HOME/proj/wiki"
    # Declare both custom fields as enums in SCHEMA.md's ## Frontmatter yaml
    # block, so lint's check_custom_fields validates values against the
    # declared sets instead of flagging undeclared keys.
    python3 - "$wiki/SCHEMA.md" <<'SCHEMAPY'
import sys, pathlib, re
p = pathlib.Path(sys.argv[1])
text = p.read_text()
pat = re.compile(r"(## Frontmatter\n\n```yaml\n.*?)(\n---\n```\n)", re.DOTALL)
m = pat.search(text)
assert m, "## Frontmatter yaml block not found in SCHEMA.md"
added = (
    "\n# Custom domain-specific fields:\n"
    "scope: alpha | beta                    # which delivery track the page covers\n"
    "window: Q3 | full                      # which time window its claims cover"
)
p.write_text(text[:m.end(1)] + added + text[m.start(2):])
SCHEMAPY
    # The fixture page: a declared field whose value embeds a qualifier.
    cat > "$wiki/concepts/track-alpha-rollout.md" <<'ALPHA'
---
title: track alpha rollout
created: 2026-05-01
updated: 2026-05-01
type: concept
tags: [model]
scope: alpha (Q3 only)
confidence: high
---

# track alpha rollout

## Definition / explanation

The alpha delivery track ships the rollout behind a per-tenant flag. It is one
of the two tracks the programme runs; the other is described on
[track beta rollout](track-beta-rollout.md).

## Current state of knowledge

The flag defaults to off and is enabled per tenant after a staged soak.

## Open questions or debates

None recorded.

## Related concepts

- [track beta rollout](track-beta-rollout.md)
ALPHA
    # Companion page: clean values for both declared fields, so neither field
    # is unused before remediation and neither page is an orphan.
    cat > "$wiki/concepts/track-beta-rollout.md" <<'BETA'
---
title: track beta rollout
created: 2026-05-01
updated: 2026-05-01
type: concept
tags: [model]
scope: beta
window: full
confidence: high
---

# track beta rollout

## Definition / explanation

The beta delivery track ships the rollout to every tenant at once. It is the
counterpart to [track alpha rollout](track-alpha-rollout.md).

## Current state of knowledge

The track has run unchanged since the programme opened.

## Open questions or debates

None recorded.

## Related concepts

- [track alpha rollout](track-alpha-rollout.md)
BETA
    python3 - "$wiki/index.md" <<'IDXPY'
import sys, pathlib
idx = pathlib.Path(sys.argv[1])
text = idx.read_text()
text = text.replace(
    "## Concepts\n",
    "## Concepts\n\n"
    "- [track alpha rollout](concepts/track-alpha-rollout.md) — alpha delivery track, flagged per tenant\n"
    "- [track beta rollout](concepts/track-beta-rollout.md) — beta delivery track, enabled for every tenant\n",
)
idx.write_text(text)
IDXPY
}

# Replace log.md's entries while keeping whatever preamble is already in the
# file, so a scenario stages the entry shape it needs without disturbing the
# canonical (or deliberately stale) preamble above the first `##` heading.
# Args: <log.md path> then one argument per entry, each "heading|||body line".
_set_log_entries() {
    python3 - "$@" <<'SETLOGPY'
import sys, pathlib
p = pathlib.Path(sys.argv[1])
text = p.read_text()
i = text.find("\n## ")
preamble = (text[:i] if i != -1 else text).rstrip("\n") + "\n"
entries = ""
for spec in sys.argv[2:]:
    heading, body = spec.split("|||", 1)
    entries += f"\n{heading}\n\n{body}\n"
p.write_text(preamble + entries)
SETLOGPY
}

# The log.md preamble as it stood BEFORE the timestamped-heading format and the
# repair carve-out landed: a date-only `> Format:` line and no `> Repair:`
# group. Staged verbatim so lint's boilerplate check reports real drift and the
# agent's <fix_log_preamble_drift> move has something to restore.
_stale_log_preamble() {
    cat <<'STALEPRE'
# Wiki Log

> Chronological record of wiki changes. Append-only.
> Format: `## [YYYY-MM-DD] action | subject`
> Actions: ingest, update, query, lint, create, archive, delete, audit, import, session-wrapup
> Entries: an operation that creates or updates wiki files appends one entry; an
> operation that changes no file appends none. Lint and audit runs are the
> exception — each records its outcome, including a zero-change one, as a
> process record.
> Body: list only files actually created or updated. Skip files that were
> inspected, considered, or deliberately left unchanged, and do not narrate
> decisions about what not to do. Aim for roughly 20 lines per entry.
> When this file exceeds 500 entries, rotate: rename to log-YYYY.md — or to the first free log-YYYY-N.md when that name is taken — start fresh; the next audit cold-walks once and records a fresh baseline in the new log.
STALEPRE
}

# Stage a wiki whose log.md carries the pre-change preamble plus <entries>.
# Args: <wiki> then one "heading|||body line" per entry.
_stage_stale_log_preamble() {
    local wiki=$1; shift
    _stale_log_preamble > "$wiki/log.md"
    _set_log_entries "$wiki/log.md" "$@"
}

stage_AS-8() {
    # AS-8 (wiki_log-heading-uniqueness-and-repair, Acceptance: the preamble
    # reaches an existing wiki through the boilerplate-drift channel): the
    # fixture log.md carries the preamble as it stood before this change — a
    # date-only `> Format:` line and no repair carve-out — and SCHEMA.md
    # declares no deviation for that slot. lint's boilerplate warn is therefore
    # real, and <fix_log_preamble_drift> must restore the canonical preamble so
    # both the timestamped `## [YYYY-MM-DD HH:MM] action | subject` format and
    # the repair-not-rewrite carve-out end up in the wiki's own log.md. The
    # entries below the preamble are unique, so no log-heading finding competes
    # for the agent's attention.
    local sb
    sb=$(reset_sandbox AS-8)
    stage "$sb/HOME/proj"
    git -C "$sb/HOME/proj" init -q
    "$INIT" "$sb/HOME/proj/wiki" >/dev/null
    local wiki="$sb/HOME/proj/wiki"
    _stage_stale_log_preamble "$wiki" \
        "## [2026-06-17] create | Wiki initialized|||- Domain: widget delivery" \
        "## [2026-06-18] session-wrapup | 0 new, 2 extended, 0 contested|||- concepts/alpha.md: extended"
}

# Two byte-identical entry headings, each body carrying its own marker so an
# order check and a substance check both have something to anchor on. Shared by
# AS-9 (routine pass leaves them alone) and AS-10 (operator asks for the
# repair), so both run against the same collision.
_stage_duplicate_log_headings() {
    local wiki=$1
    _set_log_entries "$wiki/log.md" \
        "## [2026-06-17] create | Wiki initialized|||- Domain: widget delivery" \
        "## [2026-06-18] session-wrapup | 0 new, 2 extended, 0 contested|||- KEEP FIRST: concepts/alpha.md extended" \
        "## [2026-06-18] session-wrapup | 0 new, 2 extended, 0 contested|||- KEEP SECOND: concepts/beta.md extended"
}

stage_AS-9() {
    # AS-9 (same task, Acceptance: a routine pass surfaces without rewriting):
    # the same duplicate-heading fixture as the Layer 1 scenario, audited with
    # NO repair request. The linter emits one info `log-heading` finding, and
    # the remdiate gate keeps <fix_log_heading_duplicate> from firing off the
    # issue list, so both colliding headings must still be byte-identical
    # afterwards and no `(2)` suffix may appear.
    local sb
    sb=$(reset_sandbox AS-9)
    stage "$sb/HOME/proj"
    git -C "$sb/HOME/proj" init -q
    "$INIT" "$sb/HOME/proj/wiki" >/dev/null
    _stage_duplicate_log_headings "$sb/HOME/proj/wiki"
}

stage_AS-10() {
    # AS-10 (same task, Acceptance: the on-demand move runs when asked): the
    # same fixture as AS-9 with an explicit clean-the-duplicate-headings
    # request. The later (bottom-most) colliding heading takes the minimal
    # non-time suffix `(2)`, the earliest keeps its exact text, both bodies and
    # the entry order survive, and no timestamp is invented for either entry.
    local sb
    sb=$(reset_sandbox AS-10)
    stage "$sb/HOME/proj"
    git -C "$sb/HOME/proj" init -q
    "$INIT" "$sb/HOME/proj/wiki" >/dev/null
    _stage_duplicate_log_headings "$sb/HOME/proj/wiki"
}

stage_AS-11() {
    # AS-11 (same task, Acceptance: repeat-until-clean): THREE byte-identical
    # headings, so one pass of the suffix rule is not enough. The move must
    # repeat until no duplicate group remains, leaving the earliest heading
    # bare and the two later ones carrying `(2)` and `(3)`.
    local sb
    sb=$(reset_sandbox AS-11)
    stage "$sb/HOME/proj"
    git -C "$sb/HOME/proj" init -q
    "$INIT" "$sb/HOME/proj/wiki" >/dev/null
    local wiki="$sb/HOME/proj/wiki"
    _set_log_entries "$wiki/log.md" \
        "## [2026-06-17] create | Wiki initialized|||- Domain: widget delivery" \
        "## [2026-06-18] session-wrapup | 0 new, 2 extended, 0 contested|||- KEEP FIRST: concepts/alpha.md extended" \
        "## [2026-06-18] session-wrapup | 0 new, 2 extended, 0 contested|||- KEEP SECOND: concepts/beta.md extended" \
        "## [2026-06-18] session-wrapup | 0 new, 2 extended, 0 contested|||- KEEP THIRD: concepts/gamma.md extended"
}

# Fail loudly when the canonical log template no longer carries a literal string
# an evals.json assertion hardcodes. A co-editor rewording a shared preamble unit
# would otherwise turn an AS-14..AS-18 assertion into a silent false failure.
# Args: <literal string>...
_assert_template_log_contains() {
    local missing=false s
    for s in "$@"; do
        if ! grep -qF -- "$s" "$WIKI_SKILL/references/template_log.md"; then
            echo "ERROR: references/template_log.md no longer carries: $s" >&2
            missing=true
        fi
    done
    if $missing; then
        echo "       An evals.json assertion for AS-14..AS-18 hardcodes this text —" >&2
        echo "       update the fixture and the assertion together." >&2
        exit 3
    fi
}

# Rewrite log.md's preamble from the CANONICAL template, applying one fixture
# mutation per spec, and leave the entries below untouched. Reading the canonical
# text from `references/template_log.md` rather than hardcoding it keeps these
# fixtures correct after a co-editor rewords a shared unit.
#
# A preamble unit is either a labeled blockquote group (`> Entries: …` plus its
# continuation lines) or one of the unlabeled lines, matched by greppable stem —
# the same unit boundary `<fix_log_preamble_drift>` works on.
#
# Specs, each "op|||arg[|||arg]":
#   drop-group|||<Label>            drop a labeled group whole
#   drop-line|||<stem>              drop the unlabeled line carrying <stem>
#   reword-group|||<Label>|||<text> collapse a labeled group to older wording
#   reword-line|||<stem>|||<text>   collapse an unlabeled line to older wording
#   add-owner|||<text>              append an owner-added line to the region
#
# Args: <log.md path> <template path> <spec>...
_stage_log_preamble() {
    python3 - "$@" <<'PREAMBLEPY'
import re
import sys
import pathlib

log = pathlib.Path(sys.argv[1])
template = pathlib.Path(sys.argv[2])
specs = sys.argv[3:]

LABEL_RE = re.compile(r"^> ([A-Z][A-Za-z]*): ")
UNLABELED_STEMS = ("Chronological record", "When this file exceeds")


def preamble_of(text):
    i = text.find("\n## ")
    return (text[:i] if i != -1 else text).rstrip("\n") + "\n"


def is_boundary(line):
    return bool(LABEL_RE.match(line)) or any(
        line.startswith("> " + stem) for stem in UNLABELED_STEMS
    )


canonical = preamble_of(template.read_text()).splitlines()
first = next(n for n, ln in enumerate(canonical) if is_boundary(ln))
header, body = canonical[:first], canonical[first:]

units = []
for line in body:
    if is_boundary(line) or not units:
        units.append([line])
    else:
        units[-1].append(line)


def find(pred):
    for n, unit in enumerate(units):
        if pred(unit[0]):
            return n
    raise SystemExit(f"fixture error: no preamble unit matched in {template}")


for spec in specs:
    op, *args = spec.split("|||")
    if op == "drop-group":
        del units[find(lambda ln, a=args[0]: ln.startswith(f"> {a}: "))]
    elif op == "drop-line":
        del units[find(lambda ln, a=args[0]: ln.startswith(f"> {a}"))]
    elif op == "reword-group":
        units[find(lambda ln, a=args[0]: ln.startswith(f"> {a}: "))] = [
            f"> {args[0]}: {args[1]}"
        ]
    elif op == "reword-line":
        units[find(lambda ln, a=args[0]: ln.startswith(f"> {a}"))] = [f"> {args[1]}"]
    elif op == "add-owner":
        units.append([f"> {args[0]}"])
    else:
        raise SystemExit(f"fixture error: unknown preamble op {op!r}")

rebuilt = "\n".join(header + [ln for unit in units for ln in unit]) + "\n"
existing = log.read_text()
i = existing.find("\n## ")
log.write_text(rebuilt + (existing[i:] if i != -1 else ""))
PREAMBLEPY
}

# Two entries whose bodies are byte-stable across a run, one of them carrying a
# bullet whose SUBJECT is a repo file outside the wiki — the drift the log-scope
# check surfaces and no fix move repairs. Shared by AS-13 so the entry text an
# assertion pins and the file the repo-root branch resolves stay together.
_stage_out_of_wiki_log_entry() {
    local wiki=$1 repo=$2
    mkdir -p "$repo/plugins/widget"
    printf 'version: 2.4.0\n' > "$repo/plugins/widget/config.yaml"
    _set_log_entries "$wiki/log.md" \
        "## [2026-06-17 09:14] create | Wiki initialized|||- Domain: widget delivery" \
        "## [2026-06-19 10:00] update | shipped the tenant flag|||$(printf -- '- concepts/alpha.md: recorded the rollout dates\n- plugins/widget/config.yaml: bumped the version to 2.4.0\n- Ran the suite: 41 passed, 0 failed')"
}

stage_AS-13() {
    # AS-13 (wiki_log-scope-wiki-changes-only, Acceptance: a violating historical
    # entry is surfaced but never rewritten): one existing entry carries a bullet
    # whose subject is `plugins/widget/config.yaml`, a real file under the repo
    # root and outside the wiki, so lint's info `log-scope` finding is real. The
    # log is append-only in substance and this change ships no clearing move, so
    # the agent must name the entry in its report and leave its bytes alone —
    # trimming a historical entry is the owner's editorial call.
    local sb
    sb=$(reset_sandbox AS-13)
    stage "$sb/HOME/proj"
    git -C "$sb/HOME/proj" init -q
    "$INIT" "$sb/HOME/proj/wiki" >/dev/null
    _stage_out_of_wiki_log_entry "$sb/HOME/proj/wiki" "$sb/HOME/proj"
}

stage_AS-14() {
    # AS-14 (same task, Acceptance: a preamble predating the rule converges): the
    # fixture preamble is the canonical one with the `Scope:` group removed, and
    # SCHEMA.md declares no deviation for that slot. lint's boilerplate warn is
    # real, so <fix_log_preamble_drift> must INSERT the absent canonical unit and
    # leave the run's log.md carrying the `Scope:` group at template text.
    _assert_template_log_contains \
        "> Scope: an entry records changes to this wiki, and only those. Name the files" \
        "parking lot for findings no page"
    local sb
    sb=$(reset_sandbox AS-14)
    stage "$sb/HOME/proj"
    git -C "$sb/HOME/proj" init -q
    "$INIT" "$sb/HOME/proj/wiki" >/dev/null
    local wiki="$sb/HOME/proj/wiki"
    _stage_log_preamble "$wiki/log.md" "$WIKI_SKILL/references/template_log.md" \
        "drop-group|||Scope"
    _set_log_entries "$wiki/log.md" \
        "## [2026-06-17 09:14] create | Wiki initialized|||- Domain: widget delivery" \
        "## [2026-06-18 10:00] session-wrapup | 0 new, 2 extended, 0 contested|||- concepts/alpha.md: extended"
}

stage_AS-15() {
    # AS-15 (same task, Acceptance: insert without a wholesale region restore):
    # the same missing `Scope:` group, plus an owner-added line inside the
    # preamble region. The move must insert the canonical unit AND leave the
    # owner's line byte-identical, which a verbatim full-region restore cannot
    # do. Only the log.md postconditions are graded: the owner insert-only line
    # is an acknowledged locked-slot extension with no live `boilerplate` warn.
    _assert_template_log_contains \
        "> Scope: an entry records changes to this wiki, and only those. Name the files"
    local sb
    sb=$(reset_sandbox AS-15)
    stage "$sb/HOME/proj"
    git -C "$sb/HOME/proj" init -q
    "$INIT" "$sb/HOME/proj/wiki" >/dev/null
    local wiki="$sb/HOME/proj/wiki"
    _stage_log_preamble "$wiki/log.md" "$WIKI_SKILL/references/template_log.md" \
        "drop-group|||Scope" \
        "add-owner|||Local: this vault names the tenant alongside every rollout entry."
    _set_log_entries "$wiki/log.md" \
        "## [2026-06-17 09:14] create | Wiki initialized|||- Domain: widget delivery" \
        "## [2026-06-18 10:00] session-wrapup | 0 new, 2 extended, 0 contested|||- concepts/alpha.md: extended"
}

stage_AS-16() {
    # AS-16 (same task, Acceptance: unlabeled-unit insert): the preamble is the
    # canonical one with the unlabeled rotation rule removed, and SCHEMA.md
    # declares no deviation for that slot. A label-only ensure pass would miss
    # it, so this pins the stem-matched half of the unit inventory.
    _assert_template_log_contains \
        "> When this file exceeds 500 entries, rotate: rename to log-YYYY.md — or to the first free log-YYYY-N.md when that name is taken — start fresh; the new log carries no baseline, so the next audit reads every page in the wiki in full and records a fresh baseline only when it does, otherwise writing \`unavailable\`."
    local sb
    sb=$(reset_sandbox AS-16)
    stage "$sb/HOME/proj"
    git -C "$sb/HOME/proj" init -q
    "$INIT" "$sb/HOME/proj/wiki" >/dev/null
    local wiki="$sb/HOME/proj/wiki"
    _stage_log_preamble "$wiki/log.md" "$WIKI_SKILL/references/template_log.md" \
        "drop-line|||When this file exceeds"
    _set_log_entries "$wiki/log.md" \
        "## [2026-06-17 09:14] create | Wiki initialized|||- Domain: widget delivery" \
        "## [2026-06-18 10:00] session-wrapup | 0 new, 2 extended, 0 contested|||- concepts/alpha.md: extended"
}

stage_AS-17() {
    # AS-17 (same task, Acceptance: refresh-by-label): the `Entries:` group is
    # present but carries an older co-editor reword, and an owner-added line sits
    # in the same region. The move must refresh the labeled unit to current
    # template text while leaving the owner's line byte-identical — a refresh,
    # not an insert, and not a region restore. Only the log.md postconditions are
    # graded; the owner insert-only line is an acknowledged locked-slot
    # extension with no live `boilerplate` warn.
    _assert_template_log_contains \
        "> Entries: an operation that creates or updates wiki files appends one entry; an"
    local sb
    sb=$(reset_sandbox AS-17)
    stage "$sb/HOME/proj"
    git -C "$sb/HOME/proj" init -q
    "$INIT" "$sb/HOME/proj/wiki" >/dev/null
    local wiki="$sb/HOME/proj/wiki"
    _stage_log_preamble "$wiki/log.md" "$WIKI_SKILL/references/template_log.md" \
        "reword-group|||Entries|||every operation that creates or updates wiki files appends one entry." \
        "add-owner|||Local: this vault names the tenant alongside every rollout entry."
    _set_log_entries "$wiki/log.md" \
        "## [2026-06-17 09:14] create | Wiki initialized|||- Domain: widget delivery" \
        "## [2026-06-18 10:00] session-wrapup | 0 new, 2 extended, 0 contested|||- concepts/alpha.md: extended"
}

stage_AS-18() {
    # AS-18 (same task, Acceptance: refresh-by-stem): the unlabeled
    # chronological-record opener keeps its committed stem but carries a reworded
    # body, and an owner-added line sits in the same region. The move must
    # refresh the unlabeled unit by its greppable stem while leaving the owner's
    # line byte-identical. The stem stays present by design: a reword that also
    # drops the stem is the ambiguous local-rewrite case the convergence script
    # refuses, not a refresh case. Only the log.md postconditions are graded;
    # the owner insert-only line is an acknowledged locked-slot extension with
    # no live `boilerplate` warn.
    _assert_template_log_contains \
        "> Chronological record of wiki changes. Append-only."
    local sb
    sb=$(reset_sandbox AS-18)
    stage "$sb/HOME/proj"
    git -C "$sb/HOME/proj" init -q
    "$INIT" "$sb/HOME/proj/wiki" >/dev/null
    local wiki="$sb/HOME/proj/wiki"
    _stage_log_preamble "$wiki/log.md" "$WIKI_SKILL/references/template_log.md" \
        "reword-line|||Chronological record|||Chronological record of changes to this wiki." \
        "add-owner|||Local: this vault names the tenant alongside every rollout entry."
    _set_log_entries "$wiki/log.md" \
        "## [2026-06-17 09:14] create | Wiki initialized|||- Domain: widget delivery" \
        "## [2026-06-18 10:00] session-wrapup | 0 new, 2 extended, 0 contested|||- concepts/alpha.md: extended"
}

# Exact production VerbatimSlot.label for the log.md preamble.
LOG_SLOT_LABEL='log.md preamble (H1 plus blockquote above first `##`)'

_add_declared_boilerplate() {
    local wiki=$1 reason=$2
    python3 - "$wiki/SCHEMA.md" "$LOG_SLOT_LABEL" "$reason" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1])
label, reason = sys.argv[2], sys.argv[3]
text = p.read_text().rstrip() + f"\n\n- Declared boilerplate: {label} — {reason}\n"
p.write_text(text)
PY
}

_rewrite_log_preamble_divergence() {
    local wiki=$1
    python3 - "$wiki/log.md" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1])
text = p.read_text()
i = text.find("\n## ")
rest = text[i:] if i != -1 else ""
p.write_text(
    "# Custom Log Title\n\n"
    "> House conventions: tenant-scoped rollout notes stay in the preamble.\n"
    + rest
)
PY
}

_baseline_skill_templates() {
    local sb=$1
    local t
    for t in "$WIKI_SKILL"/references/template_*.md; do
        _sha_baseline "$t" "$sb/baseline/$(basename "$t").sha256"
    done
}

stage_AS-19() {
    # AS-19 (wiki_sanctioned-template-deviations): insert-only owner extension on
    # an otherwise canonical preamble. The agent must leave the owner line
    # byte-identical and must not claim a scaffold repair it did not make.
    local sb
    sb=$(reset_sandbox AS-19)
    stage "$sb/HOME/proj"
    git -C "$sb/HOME/proj" init -q
    "$INIT" "$sb/HOME/proj/wiki" >/dev/null
    local wiki="$sb/HOME/proj/wiki"
    _stage_log_preamble "$wiki/log.md" "$WIKI_SKILL/references/template_log.md" \
        "add-owner|||Local: this vault names the tenant alongside every rollout entry."
    _set_log_entries "$wiki/log.md" \
        "## [2026-06-17 09:14] create | Wiki initialized|||- Domain: widget delivery" \
        "## [2026-06-18 10:00] session-wrapup | 0 new, 2 extended, 0 contested|||- concepts/alpha.md: extended"
    _sha_baseline "$wiki/log.md" "$sb/baseline/log.md.sha256"
}

stage_AS-20() {
    # AS-20 (wiki_sanctioned-template-deviations): declared delete/replace
    # divergence. The agent must leave the declared preamble region
    # byte-identical.
    local sb
    sb=$(reset_sandbox AS-20)
    stage "$sb/HOME/proj"
    git -C "$sb/HOME/proj" init -q
    "$INIT" "$sb/HOME/proj/wiki" >/dev/null
    local wiki="$sb/HOME/proj/wiki"
    _rewrite_log_preamble_divergence "$wiki"
    _add_declared_boilerplate "$wiki" \
        "tenant-scoped rollout notes belong in the preamble for this vault"
    _set_log_entries "$wiki/log.md" \
        "## [2026-06-17 09:14] create | Wiki initialized|||- Domain: widget delivery" \
        "## [2026-06-18 10:00] session-wrapup | 0 new, 2 extended, 0 contested|||- concepts/alpha.md: extended"
    _sha_baseline "$wiki/log.md" "$sb/baseline/log.md.sha256"
}

stage_AS-21() {
    # AS-21 (wiki_sanctioned-template-deviations): declared divergence framed as
    # a general improvement. The agent must preserve the region, name it as a
    # template candidate in the report, and leave skill templates unedited.
    local sb
    sb=$(reset_sandbox AS-21)
    stage "$sb/HOME/proj"
    git -C "$sb/HOME/proj" init -q
    "$INIT" "$sb/HOME/proj/wiki" >/dev/null
    local wiki="$sb/HOME/proj/wiki"
    _rewrite_log_preamble_divergence "$wiki"
    _add_declared_boilerplate "$wiki" \
        "tenant-scoped rollout notes belong in every wiki preamble"
    _set_log_entries "$wiki/log.md" \
        "## [2026-06-17 09:14] create | Wiki initialized|||- Domain: widget delivery" \
        "## [2026-06-18 10:00] session-wrapup | 0 new, 2 extended, 0 contested|||- concepts/alpha.md: extended"
    _sha_baseline "$wiki/log.md" "$sb/baseline/log.md.sha256"
    _baseline_skill_templates "$sb"
}

stage_AS-22() {
    # AS-22 (wiki_declared-source-roots): a declared source root widens
    # `sources:` to a live in-repo document. Page alpha already cites a
    # declared-root file in frontmatter and must keep it (no ## Derived from).
    # Page beta carries a body ## Sources bullet resolving under the declared
    # root and must have it hoisted into `sources:` (no ## Derived from). Both
    # re-lint clean.
    local sb
    sb=$(reset_sandbox AS-22)
    stage "$sb/HOME/proj"
    git -C "$sb/HOME/proj" init -q
    "$INIT" "$sb/HOME/proj/wiki" >/dev/null
    local wiki="$sb/HOME/proj/wiki"
    mkdir -p "$sb/HOME/proj/paper"
    printf 'Chapter three of the paper.\n' > "$sb/HOME/proj/paper/ch03.tex"
    printf 'Chapter four of the paper.\n' > "$sb/HOME/proj/paper/ch04.tex"
    python3 - "$wiki/SCHEMA.md" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1])
text = p.read_text()
text = text.replace(
    "## Lint\n",
    "## Lint\n\n- Declared source root: ../paper — the paper this wiki classifies\n",
    1,
)
text = text.replace(
    "## Tag Taxonomy\n",
    "## Tag Taxonomy\n\n- Domain: model\n",
    1,
)
p.write_text(text)
PY
    mkdir -p "$wiki/concepts"
    cat > "$wiki/concepts/alpha.md" <<'EOF'
---
title: alpha
created: 2026-05-01
updated: 2026-05-01
type: concept
tags: [model]
sources: [../paper/ch03.tex]
confidence: high
---

# alpha

The chapter three argument ([ch03](../paper/ch03.tex)) defines the widget
contract. See also [beta](beta.md).
EOF
    cat > "$wiki/concepts/beta.md" <<'EOF'
---
title: beta
created: 2026-05-01
updated: 2026-05-01
type: concept
tags: [model]
confidence: high
---

# beta

The chapter four argument defines the rollout sequence. See also
[alpha](alpha.md).

## Sources

- [ch04](../paper/ch04.tex) — the specification chapter
EOF
    python3 - "$wiki/index.md" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1])
text = p.read_text()
text = text.replace(
    "## Concepts\n",
    "## Concepts\n\n- [alpha](concepts/alpha.md) — widget contract\n"
    "- [beta](concepts/beta.md) — rollout sequence\n",
    1,
)
p.write_text(text)
PY
}

# --- full-read baseline / checked-date scenarios -----------------------------
# Four scenarios share one shape: a git-backed wiki whose log.md carries one
# earlier `audit` entry recording the first staging commit as its baseline, then
# a second commit that changes one concepts/ page and one procedures/ page. The
# agent's new audit entry must record the same baseline only when it read every
# changed page in full, and a page's `checked` date moves only after its whole
# body and every claim were checked.

_as_git_commit() {
    local repo=$1 msg=$2
    git -C "$repo" add -A
    git -C "$repo" -c user.name="Fixture Author" -c user.email="fixture@example.com" \
        commit -qm "$msg"
}

# Append one prior `audit` entry recording <baseline>, so the audit has an
# incremental baseline to compare against. Args: <wiki> <baseline>.
_as_prior_audit_entry() {
    local wiki=$1 baseline=$2
    python3 - "$wiki/log.md" "$baseline" <<'PRIORAUDIT'
import sys, pathlib
p = pathlib.Path(sys.argv[1])
text = p.read_text().rstrip("\n")
entry = (
    "\n\n## [2026-06-17 09:14] audit | 0 blocking, 0 warn, 0 info; 0 pages updated, 0 pages split\n\n"
    "- Audit baseline: " + sys.argv[2] + "\n"
    "- Cold page reads: none\n"
)
p.write_text(text + entry)
PRIORAUDIT
}

# Stage the shared wiki pages and index entries for the four scenarios. Every
# page keeps two outbound links and at least two inbound links, and the two
# changed pages (concepts/widget-caching.md, procedures/release-checklist.md)
# carry different subjects and never link each other, so the contradiction-peer
# rule adds no full read between them.
# Args: <wiki>
_as_baseline_wiki_pages() {
    local wiki=$1
    cat > "$wiki/concepts/widget-caching.md" <<'EOF'
---
title: widget caching
created: 2026-05-01
updated: 2026-05-01
type: concept
tags: [model]
confidence: high
---

# widget caching

## Definition / explanation

The widget cache keeps rendered widget output between requests. An entry is
keyed by widget identity and by the inputs that affect its rendering.

## Current state of knowledge

The cache is invalidated when a widget's source record changes. See
[backup drill](../procedures/backup-drill.md) for the recovery procedure and
[incident triage](../procedures/incident-triage.md) for the escalation path.

## Open questions or debates

None recorded.

## Related concepts

- [backup drill](../procedures/backup-drill.md)
- [incident triage](../procedures/incident-triage.md)
EOF
    cat > "$wiki/procedures/release-checklist.md" <<'EOF'
---
title: release checklist
created: 2026-05-01
updated: 2026-05-01
type: procedure
tags: [model]
confidence: high
---

# release checklist

Run this checklist before publishing a widget release.

## When this applies

Apply it to every release that changes a rendered widget.

## The rule

1. Confirm the widget cache is warm; see [widget caching](../concepts/widget-caching.md).
2. Confirm the recovery path is current; see [backup drill](backup-drill.md).

## Pitfalls / edge cases

- Skip no step: a release that skips one step is not ready.

## See Also

- [backup drill](backup-drill.md)
- [incident triage](incident-triage.md)
EOF
    cat > "$wiki/procedures/backup-drill.md" <<'EOF'
---
title: backup drill
created: 2026-05-01
updated: 2026-05-01
type: procedure
tags: [model]
confidence: high
---

# backup drill

Run the backup drill on a fixed schedule.

## When this applies

Apply it whenever the stored widget records must be proven recoverable.

## The rule

1. Restore the widget cache from the last stored snapshot; see
   [widget caching](../concepts/widget-caching.md).
2. Confirm the release path still holds; see
   [release checklist](release-checklist.md).

## See Also

- [incident triage](incident-triage.md)
- [widget caching](../concepts/widget-caching.md)
EOF
    cat > "$wiki/procedures/incident-triage.md" <<'EOF'
---
title: incident triage
created: 2026-05-01
updated: 2026-05-01
type: procedure
tags: [model]
confidence: high
---

# incident triage

Sort an incident by blast radius before acting.

## When this applies

Apply it when a rendered widget misbehaves in a live deployment.

## The rule

1. Confirm the recovery path; see [backup drill](backup-drill.md).
2. Confirm the release gate; see [release checklist](release-checklist.md).

## See Also

- [widget caching](../concepts/widget-caching.md)
- [release checklist](release-checklist.md)
EOF
    python3 - "$wiki/index.md" <<'BASELINEIDX'
import sys, pathlib
idx = pathlib.Path(sys.argv[1])
text = idx.read_text()
text = text.replace(
    "## Concepts\n",
    "## Concepts\n\n- [widget caching](concepts/widget-caching.md) — rendered output kept between requests\n",
    1,
)
text = text.replace(
    "## Procedures\n",
    "## Procedures\n\n"
    "- [backup drill](procedures/backup-drill.md) — prove stored records recoverable\n"
    "- [incident triage](procedures/incident-triage.md) — sort an incident by blast radius\n"
    "- [release checklist](procedures/release-checklist.md) — gate a widget release\n",
    1,
)
text = text.replace("Total pages: 0", "Total pages: 4", 1)
idx.write_text(text)
BASELINEIDX
}

# Init the repo and wiki and write the shared baseline pages. The caller adds
# any scenario-specific page that must exist before the first commit, then
# calls `_as_first_commit`. Args: <sandbox-root>
_as_baseline_repo() {
    local sb=$1
    stage "$sb/HOME/proj"
    git -C "$sb/HOME/proj" init -q
    "$INIT" "$sb/HOME/proj/wiki" >/dev/null
    python3 - "$sb/HOME/proj/wiki/SCHEMA.md" <<'TAXONOMY'
import sys, pathlib
p = pathlib.Path(sys.argv[1])
text = p.read_text()
text = text.replace("## Tag Taxonomy\n", "## Tag Taxonomy\n\n- Domain: model\n", 1)
p.write_text(text)
TAXONOMY
    _as_baseline_wiki_pages "$sb/HOME/proj/wiki"
}

# Commit the first staging state and append the prior audit entry that records
# its sha as the baseline. Args: <sandbox-root>
_as_first_commit() {
    local sb=$1
    _as_git_commit "$sb/HOME/proj" "first staging commit"
    _as_prior_audit_entry "$sb/HOME/proj/wiki" "$(git -C "$sb/HOME/proj" rev-parse HEAD)"
}

# Write the second-commit page changes: insert one paragraph above the closing
# section of each changed page. Args: <wiki> <concept-paragraph> <procedure-paragraph>
_as_second_commit_changes() {
    local wiki=$1 concept_extra=$2 procedure_extra=$3
    python3 - "$wiki/concepts/widget-caching.md" "$wiki/procedures/release-checklist.md" \
        "$concept_extra" "$procedure_extra" <<'SECONDCOMMIT'
import sys, pathlib
concept, procedure, concept_extra, procedure_extra = sys.argv[1:5]
for path, extra, heading in (
    (concept, concept_extra, "## Open questions or debates"),
    (procedure, procedure_extra, "## Pitfalls / edge cases"),
):
    if not extra:
        continue
    p = pathlib.Path(path)
    text = p.read_text()
    p.write_text(text.replace(heading, extra + "\n\n" + heading, 1))
SECONDCOMMIT
}

stage_AS-23() {
    # AS-23 (wiki_audit-baseline-after-full-reads, Acceptance 7): the request
    # limits the audit to procedures/. The changed concepts/ page stays unread,
    # so the new audit entry must repeat the staged baseline and its Cold page
    # reads line must name no concepts/ page.
    local sb
    sb=$(reset_sandbox AS-23)
    _as_baseline_repo "$sb"
    _as_first_commit "$sb"
    _as_second_commit_changes "$sb/HOME/proj/wiki" \
        "A cache entry also records the render inputs it was built from." \
        "The release is recorded in the team log once both checks pass."
    _as_git_commit "$sb/HOME/proj" "second staging commit"
    mkdir -p "$sb/baseline"
    git -C "$sb/HOME/proj" rev-parse HEAD~1 > "$sb/baseline/first-commit.sha"
}

stage_AS-24() {
    # AS-24 (same task, Acceptance 11): a full audit. Every changed page is
    # read in full, so the baseline advances to the second commit, and the
    # entity page's checked date moves because every claim cites a source the
    # run can read (a raw note inside the wiki, a document under a declared
    # source root beside it).
    local sb
    sb=$(reset_sandbox AS-24)
    _as_baseline_repo "$sb"
    _as_first_commit "$sb"
    local wiki="$sb/HOME/proj/wiki"
    mkdir -p "$sb/HOME/proj/paper"
    printf 'The widget service caps throughput at 150 units per minute.\n' \
        > "$sb/HOME/proj/paper/spec.md"
    python3 - "$wiki/SCHEMA.md" <<'DECLAREROOT'
import sys, pathlib
p = pathlib.Path(sys.argv[1])
text = p.read_text()
text = text.replace(
    "## Lint\n",
    "## Lint\n\n- Declared source root: ../paper — the specification this wiki classifies\n",
    1,
)
p.write_text(text)
DECLAREROOT
    mkdir -p "$wiki/raw/notes"
    cat > "$wiki/raw/notes/throughput.md" <<'THROUGHPUT'
---
source_url: https://example.com/throughput-note
ingested: 2026-06-18
sha256: placeholder
---

The widget service caps throughput at 150 units per minute.
THROUGHPUT
    python3 "$WIKI_SKILL/scripts/compute_sha256.py" "$wiki/raw/notes/throughput.md" >/dev/null
    cat > "$wiki/entities/widget-service.md" <<'ENTITY'
---
title: widget service
created: 2026-05-01
updated: 2026-05-01
type: entity
tags: [model]
sources: [raw/notes/throughput.md, ../paper/spec.md]
confidence: high
checked: 2026-01-01
---

# widget service

## Overview

The widget service renders and serves widgets for every deployment.

## Key facts and dates

- The service caps throughput at 150 units per minute, as the
  [throughput note](../raw/notes/throughput.md) records.
- Its service boundary is defined in the specification listed in `sources:`.

## Relationships to other entities

Its rendered output feeds the [widget cache](../concepts/widget-caching.md) and
the [release checklist](../procedures/release-checklist.md).
ENTITY
    python3 - "$wiki/concepts/widget-caching.md" "$wiki/procedures/release-checklist.md" <<'INBOUND'
import sys, pathlib
concept, procedure = sys.argv[1:3]
p = pathlib.Path(concept)
text = p.read_text().replace(
    "## Open questions or debates",
    "The service that renders these widgets is the\n"
    "[widget service](../entities/widget-service.md).\n\n"
    "## Open questions or debates",
    1,
)
p.write_text(text)
p = pathlib.Path(procedure)
text = p.read_text().replace(
    "## See Also\n",
    "## See Also\n\n- [widget service](../entities/widget-service.md)\n",
    1,
)
p.write_text(text)
INBOUND
    python3 - "$wiki/index.md" <<'ENTITYIDX'
import sys, pathlib
p = pathlib.Path(sys.argv[1])
text = p.read_text()
text = text.replace(
    "## Entities\n",
    "## Entities\n\n- [widget service](entities/widget-service.md) — renders and serves widgets\n",
    1,
)
text = text.replace("Total pages: 4", "Total pages: 5", 1)
p.write_text(text)
ENTITYIDX
    _as_second_commit_changes "$wiki" \
        "A cache entry also records the render inputs it was built from." \
        "The release is recorded in the team log once both checks pass."
    _as_git_commit "$sb/HOME/proj" "second staging commit"
    mkdir -p "$sb/baseline"
    git -C "$sb/HOME/proj" rev-parse HEAD > "$sb/baseline/second-commit.sha"
}

stage_AS-25() {
    # AS-25 (same task, Acceptance 9): the request checks one figure against the
    # raw note it cites. The page also carries claims whose sources lie outside
    # the sandbox, so only some claims are checked and `checked` must stay.
    local sb
    sb=$(reset_sandbox AS-25)
    _as_baseline_repo "$sb"
    _as_first_commit "$sb"
    local wiki="$sb/HOME/proj/wiki"
    mkdir -p "$wiki/raw/notes"
    cat > "$wiki/raw/notes/throughput.md" <<'THROUGHPUT'
---
source_url: https://example.com/throughput-note
ingested: 2026-06-18
sha256: placeholder
---

The widget service caps throughput at 150 units per minute.
THROUGHPUT
    python3 "$WIKI_SKILL/scripts/compute_sha256.py" "$wiki/raw/notes/throughput.md" >/dev/null
    cat > "$wiki/entities/widget-throughput.md" <<'ENTITY'
---
title: widget throughput
created: 2026-05-01
updated: 2026-05-01
type: entity
tags: [model]
sources: [raw/notes/throughput.md]
confidence: high
checked: 2026-01-01
---

# widget throughput

## Overview

The widget service renders and serves widgets for every deployment.

## Key facts and dates

- The documented ceiling is 200 units per minute, as the
  [throughput note](../raw/notes/throughput.md) records.
- A vendor benchmark reported 95 units per minute
  ([vendor benchmark](https://example.com/vendor-benchmark)).
- An independent report described 110 units per minute
  ([independent report](https://example.com/independent-report)).

## Relationships to other entities

Its rendered output feeds the [widget cache](../concepts/widget-caching.md) and
the [release checklist](../procedures/release-checklist.md).
ENTITY
    python3 - "$wiki/concepts/widget-caching.md" "$wiki/procedures/release-checklist.md" <<'INBOUND'
import sys, pathlib
concept, procedure = sys.argv[1:3]
p = pathlib.Path(concept)
text = p.read_text().replace(
    "## Open questions or debates",
    "The service that renders these widgets is the\n"
    "[widget throughput](../entities/widget-throughput.md).\n\n"
    "## Open questions or debates",
    1,
)
p.write_text(text)
p = pathlib.Path(procedure)
text = p.read_text().replace(
    "## See Also\n",
    "## See Also\n\n- [widget throughput](../entities/widget-throughput.md)\n",
    1,
)
p.write_text(text)
INBOUND
    python3 - "$wiki/index.md" <<'ENTITYIDX'
import sys, pathlib
p = pathlib.Path(sys.argv[1])
text = p.read_text()
text = text.replace(
    "## Entities\n",
    "## Entities\n\n- [widget throughput](entities/widget-throughput.md) — throughput claims for the service\n",
    1,
)
text = text.replace("Total pages: 4", "Total pages: 5", 1)
p.write_text(text)
ENTITYIDX
    _as_second_commit_changes "$wiki" \
        "A cache entry also records the render inputs it was built from." \
        "The release is recorded in the team log once both checks pass."
    _as_git_commit "$sb/HOME/proj" "second staging commit"
}

stage_AS-26() {
    # AS-26 (same task, Acceptance 8): a page unchanged since the baseline is
    # reached only as a search excerpt while the run fixes a broken
    # cross-reference on another page. Its checked date and bytes must stay.
    local sb
    sb=$(reset_sandbox AS-26)
    _as_baseline_repo "$sb"
    local wiki="$sb/HOME/proj/wiki"
    cat > "$wiki/concepts/widget-colour-defaults.md" <<'EXCERPT'
---
title: widget colour defaults
created: 2026-05-01
updated: 2026-05-01
type: concept
tags: [model]
confidence: high
checked: 2026-01-01
---

# widget colour defaults

## Definition / explanation

The defaults table lists the framework colour for each widget class. A widget
keeps the framework colour unless something above the framework supplies one.

## Current state of knowledge

The framework colour is resolved before any deployment-level override. See
[backup drill](../procedures/backup-drill.md) for the recovery procedure and
[incident triage](../procedures/incident-triage.md) for escalation.

## Open questions or debates

None recorded.

## Related concepts

- [backup drill](../procedures/backup-drill.md)
- [incident triage](../procedures/incident-triage.md)
EXCERPT
    cat > "$wiki/concepts/release-cadence.md" <<'CADENCE'
---
title: release cadence
created: 2026-05-01
updated: 2026-05-01
type: concept
tags: [model]
confidence: high
---

# release cadence

## Definition / explanation

The release cadence sets how often a widget release may ship. It is independent
of any rendering choice.

## Current state of knowledge

The cadence follows the operational window in
[backup drill](../procedures/backup-drill.md). See
[incident triage](../procedures/incident-triage.md) for the operational paths.

## Open questions or debates

None recorded.

## Related concepts

- [backup drill](../procedures/backup-drill.md)
- [incident triage](../procedures/incident-triage.md)
CADENCE
    python3 - "$wiki/index.md" <<'EXCERPTIDX'
import sys, pathlib
p = pathlib.Path(sys.argv[1])
text = p.read_text()
text = text.replace(
    "## Concepts\n",
    "## Concepts\n\n"
    "- [release cadence](concepts/release-cadence.md) — how often a widget release may ship\n"
    "- [widget colour defaults](concepts/widget-colour-defaults.md) — framework colour per widget class\n",
    1,
)
text = text.replace("Total pages: 4", "Total pages: 6", 1)
p.write_text(text)
EXCERPTIDX
    python3 - "$wiki/procedures/backup-drill.md" "$wiki/procedures/incident-triage.md" <<'ANCHORLINKS'
import sys, pathlib
for path in sys.argv[1:3]:
    p = pathlib.Path(path)
    text = p.read_text().replace(
        "## See Also\n",
        "## See Also\n\n"
        "- [release cadence](../concepts/release-cadence.md)\n"
        "- [widget colour defaults](../concepts/widget-colour-defaults.md)\n",
        1,
    )
    p.write_text(text)
ANCHORLINKS
    _as_first_commit "$sb"
    # The second commit breaks the fix page's cross-reference, so the audit must
    # search for the right target and confirm it before repairing the link.
    python3 - "$wiki/concepts/release-cadence.md" <<'BREAKLINK'
import sys, pathlib
p = pathlib.Path(sys.argv[1])
text = p.read_text()
text = text.replace(
    "The cadence follows the operational window in\n"
    "[backup drill](../procedures/backup-drill.md). See\n"
    "[incident triage](../procedures/incident-triage.md) for the operational paths.",
    "The cadence follows the defaults table ([the defaults table](defaults-table.md))\n"
    "for the scheduling window. See\n"
    "[incident triage](../procedures/incident-triage.md) for the operational paths.",
    1,
)
p.write_text(text)
BREAKLINK
    _as_second_commit_changes "$wiki" \
        "A cache entry also records the render inputs it was built from." \
        "The release is recorded in the team log once both checks pass."
    _as_git_commit "$sb/HOME/proj" "second staging commit"
    _sha_baseline "$wiki/concepts/widget-colour-defaults.md" \
        "$sb/baseline/widget-colour-defaults.md.sha256"
}

stage_AS-27() {
    # AS-27 (wiki_non-english-languages-ascii-slugs, Acceptance 10): a
    # German-language wiki that is otherwise clean, whose only live finding is
    # a non-ASCII page filename (`concepts/künstliche-evolution.md`, NFC). The
    # three reference classes that can name a page all point at the old slug:
    # the `index.md` entry, a markdown link on the companion page, and a
    # `contradictions:` frontmatter entry. The audit must apply
    # `<fix_non_ascii_filename>`: `git mv` to the German-folded slug
    # `kuenstliche-evolution.md`, re-point all three, keep the readable
    # `title:` in its native characters, and reach a clean lint. No raw sidecar
    # is staged, so the `raw/` carve-out is not in play. The filenames are
    # created at run time from \u escapes; a committed non-ASCII name would be
    # normalized on checkout and could mask the case.
    local sb
    sb=$(reset_sandbox AS-27)
    stage "$sb/HOME/proj"
    git -C "$sb/HOME/proj" init -q
    "$INIT" "$sb/HOME/proj/wiki" >/dev/null
    local wiki="$sb/HOME/proj/wiki"
    python3 - "$wiki" <<'PY'
import sys, pathlib
w = pathlib.Path(sys.argv[1])
nfc = "k\u00fcnstliche-evolution.md"  # Künstliche Evolution
text = (w / "SCHEMA.md").read_text()
text = text.replace("## Tag Taxonomy\n", "## Tag Taxonomy\n\n- Domain: model\n", 1)
(w / "SCHEMA.md").write_text(text)
(w / "concepts" / nfc).write_text(
    "---\n"
    "title: K\u00fcnstliche Evolution\n"
    "created: 2026-05-01\n"
    "updated: 2026-05-01\n"
    "type: concept\n"
    "tags: [model]\n"
    "confidence: medium\n"
    "---\n\n"
    "# K\u00fcnstliche Evolution\n\n"
    "## Definition / explanation\n\n"
    "Evolution\u00e4re Verfahren bilden die nat\u00fcrliche Auslese mit einem\n"
    "Fitnesma\u00df nach. Die verwandte Suchheuristik steht auf\n"
    "[genetische Algorithmen](genetische-algorithmen.md).\n\n"
    "## Current state of knowledge\n\n"
    "Das Verfahren ist etabliert und wird breit eingesetzt.\n\n"
    "## Open questions or debates\n\n"
    "Keine offenen Fragen.\n\n"
    "## Related concepts\n\n"
    "- [genetische Algorithmen](genetische-algorithmen.md)\n",
    encoding="utf-8",
)
(w / "concepts" / "genetische-algorithmen.md").write_text(
    "---\n"
    "title: Genetische Algorithmen\n"
    "created: 2026-05-01\n"
    "updated: 2026-05-01\n"
    "type: concept\n"
    "tags: [model]\n"
    "confidence: medium\n"
    "contradictions: [k\u00fcnstliche-evolution]\n"
    "---\n\n"
    "# Genetische Algorithmen\n\n"
    "## Definition / explanation\n\n"
    "Genetische Algorithmen optimieren eine Population von L\u00f6sungen. Sie\n"
    "sind die konkrete Auspr\u00e4gung von\n"
    "[k\u00fcnstliche Evolution](" + nfc + ").\n\n"
    "## Current state of knowledge\n\n"
    "Die Verfahren sind unver\u00e4ndert seit Jahren im Einsatz.\n\n"
    "## Open questions or debates\n\n"
    "Die Gewichtung der Fitnesfunktion bleibt umstritten.\n\n"
    "## Related concepts\n\n"
    "- [k\u00fcnstliche Evolution](" + nfc + ")\n",
    encoding="utf-8",
)
idx = w / "index.md"
text = idx.read_text()
text = text.replace(
    "## Concepts\n",
    "## Concepts\n\n"
    "- [Genetische Algorithmen](concepts/genetische-algorithmen.md) \u2014 "
    "populationsbasierte Optimierung\n"
    "- [K\u00fcnstliche Evolution](concepts/" + nfc + ") \u2014 "
    "Auslese als Suchverfahren\n",
    1,
)
text = text.replace("Total pages: 0", "Total pages: 2", 1)
idx.write_text(text)
PY
    _as_git_commit "$sb/HOME/proj" "staging commit"
}

stage_AS-28() {
    # AS-28 (wiki_fix-accept-confirmed-findings-scope, Acceptance 4/5): a
    # git-backed wiki whose prior audit entry records the first staging commit
    # as its baseline, then a second commit that changes one page the approved
    # findings list does not name (concepts/widget-release-notes.md, which
    # carries no lint finding so nothing draws the scoped run to read it). A
    # findings file outside the wiki lists four entries: a section-order defect
    # with a quoted span, a confidence defect with no quoted span, an entry the
    # page refutes, and an internal contradiction the run must surface without
    # editing. A separate unlisted page (concepts/widget-colour.md) carries an
    # off-taxonomy tag (`shipgate`) that lint reports and the scoped run must
    # leave unfixed; it is unchanged since the baseline, so reading it cannot
    # advance the baseline. The scoped run reads only the listed pages, so the
    # changed unlisted page stays unread and the baseline holds.
    local sb
    sb=$(reset_sandbox AS-28)
    stage "$sb/HOME/proj"
    git -C "$sb/HOME/proj" init -q
    "$INIT" "$sb/HOME/proj/wiki" >/dev/null
    local wiki="$sb/HOME/proj/wiki"
    python3 - "$wiki/SCHEMA.md" <<'TAXONOMY'
import sys, pathlib
p = pathlib.Path(sys.argv[1])
p.write_text(
    p.read_text().replace("## Tag Taxonomy\n", "## Tag Taxonomy\n\n- Domain: model\n", 1)
)
TAXONOMY
    cat > "$wiki/concepts/widget-caching.md" <<'CACHING'
---
title: widget caching
created: 2026-05-01
updated: 2026-05-01
type: concept
tags: [model]
confidence: medium
---

# widget caching

The widget cache keeps rendered widget output between requests.

## Current state of knowledge

The cache is invalidated when a widget's source record changes. See
[widget defaults](widget-defaults.md) for the defaults it resolves,
[widget colour](widget-colour.md) for the shade it stores,
[widget release notes](widget-release-notes.md) for the release it shipped
in, and the [backup drill](../procedures/backup-drill.md) for the recovery
path.

## Definition / explanation

An entry is keyed by widget identity and by the inputs that affect its
rendering.

## Open questions or debates

None recorded.

## Related concepts

- [widget defaults](widget-defaults.md)
- [widget colour](widget-colour.md)
CACHING
    cat > "$wiki/concepts/widget-defaults.md" <<'DEFAULTS'
---
title: widget defaults
created: 2026-05-01
updated: 2026-05-01
type: concept
tags: [model]
confidence: high
---

# widget defaults

The defaults table lists the framework colour for each widget class.

## Definition / explanation

A widget keeps the framework colour unless something above the framework
supplies one. See [widget caching](widget-caching.md) for how the
resolved value is stored.

## Current state of knowledge

The framework colour is resolved before any deployment-level override.
See [widget rendering](widget-rendering.md) for the pass that applies it.

## Open questions or debates

None recorded.

## Related concepts

- [widget caching](widget-caching.md)
- [widget rendering](widget-rendering.md)
- [widget release notes](widget-release-notes.md)
DEFAULTS
    cat > "$wiki/concepts/widget-rendering.md" <<'RENDERING'
---
title: widget rendering
created: 2026-05-01
updated: 2026-05-01
type: concept
tags: [model]
confidence: medium
---

# widget rendering

Rendering turns a widget record into the output a deployment serves.

## Definition / explanation

Rendering runs in three passes: resolve the defaults, compose the layout,
and paint the result. See [widget defaults](widget-defaults.md) for the
first pass.

## Current state of knowledge

The pass count is fixed for the current release. See
[widget caching](widget-caching.md) for how a painted result is kept.

## Open questions or debates

None recorded.

## Related concepts

- [widget defaults](widget-defaults.md)
- [widget caching](widget-caching.md)
RENDERING
    cat > "$wiki/procedures/backup-drill.md" <<'DRILL'
---
title: backup drill
created: 2026-05-01
updated: 2026-05-01
type: procedure
tags: [model]
confidence: medium
---

# backup drill

Run the backup drill on a fixed schedule.

## When this applies

Apply it whenever the stored widget records must be proven recoverable.

## The rule

1. Run the drill every 7 days.
2. Restore the widget cache from the last stored snapshot; see
   [widget caching](../concepts/widget-caching.md).
3. Confirm the rendered output matches the snapshot; see
   [widget rendering](../concepts/widget-rendering.md).

## Pitfalls / edge cases

- The drill runs on a 30-day cycle, so a 7-day schedule double-counts it.
DRILL
    cat > "$wiki/concepts/widget-colour.md" <<'COLOUR'
---
title: widget colour
created: 2026-05-01
updated: 2026-05-01
type: concept
tags: [shipgate]
confidence: medium
---

# widget colour

The widget colour names the framework shade a rendered widget carries.

## Definition / explanation

Colour is chosen per widget class before rendering starts. See
[widget defaults](widget-defaults.md) for the default shade.

## Current state of knowledge

The shade is recorded with the rendered output. See
[widget caching](widget-caching.md) for where that record lives.

## Open questions or debates

None recorded.

## Related concepts

- [widget defaults](widget-defaults.md)
- [widget caching](widget-caching.md)
COLOUR
    cat > "$wiki/concepts/widget-release-notes.md" <<'RELEASENOTES'
---
title: widget release notes
created: 2026-05-01
updated: 2026-05-01
type: concept
tags: [model]
confidence: medium
---

# widget release notes

The release notes record what changed in each widget release.

## Definition / explanation

Each release note names the widgets it touched and the rendering change it
shipped. See [widget rendering](widget-rendering.md) for the pass model the
notes describe.

## Current state of knowledge

The notes for the current release are complete. See
[widget caching](widget-caching.md) for the cache behaviour the release
changed.

## Open questions or debates

None recorded.

## Related concepts

- [widget rendering](widget-rendering.md)
- [widget caching](widget-caching.md)
RELEASENOTES
    python3 - "$wiki/index.md" <<'INDEX'
import sys, pathlib
p = pathlib.Path(sys.argv[1])
text = p.read_text()
text = text.replace(
    "## Concepts\n",
    "## Concepts\n\n"
    "- [widget caching](concepts/widget-caching.md) — rendered output kept between requests\n"
    "- [widget colour](concepts/widget-colour.md) — framework shade a widget carries\n"
    "- [widget defaults](concepts/widget-defaults.md) — framework colour per widget class\n"
    "- [widget release notes](concepts/widget-release-notes.md) — what changed in each release\n"
    "- [widget rendering](concepts/widget-rendering.md) — how a widget record becomes output\n",
    1,
)
text = text.replace(
    "## Procedures\n",
    "## Procedures\n\n- [backup drill](procedures/backup-drill.md) — prove stored records recoverable\n",
    1,
)
text = text.replace("Total pages: 0", "Total pages: 6", 1)
p.write_text(text)
INDEX
    _as_git_commit "$sb/HOME/proj" "first staging commit"
    _as_prior_audit_entry "$wiki" "$(git -C "$sb/HOME/proj" rev-parse HEAD)"
    cat > "$sb/HOME/proj/approved-findings.md" <<'FINDINGS'
# Approved findings

The user reviewed and approved these findings. Fix exactly these entries.

1. Page: wiki/concepts/widget-caching.md
   Defect: The page's sections are out of order; "Current state of knowledge"
   sits before "Definition / explanation".
   Evidence: "## Current state of knowledge" then "## Definition / explanation".

2. Page: wiki/concepts/widget-defaults.md
   Defect: The page declares `confidence: high` while it cites no source.

3. Page: wiki/concepts/widget-rendering.md
   Defect: The page says rendering runs in two passes.
   Evidence: "rendering runs in two passes".

4. Page: wiki/procedures/backup-drill.md
   Defect: The page carries two conflicting drill intervals, so a repair has to
   choose one of them.
   Evidence: "Run the drill every 7 days" and "the drill runs on a 30-day cycle".
FINDINGS
    python3 - "$wiki/concepts/widget-release-notes.md" <<'SECONDCOMMIT'
import sys, pathlib
p = pathlib.Path(sys.argv[1])
text = p.read_text().replace(
    "## Open questions or debates",
    "The release also recorded the shade it shipped with.\n\n"
    "## Open questions or debates",
    1,
)
p.write_text(text)
SECONDCOMMIT
    _as_git_commit "$sb/HOME/proj" "second staging commit"
    _sha_baseline "$wiki/concepts/widget-rendering.md" \
        "$sb/baseline/widget-rendering.md.sha256"
    _sha_baseline "$wiki/procedures/backup-drill.md" \
        "$sb/baseline/backup-drill.md.sha256"
    _sha_baseline "$wiki/concepts/widget-colour.md" \
        "$sb/baseline/widget-colour.md.sha256"
}

stage_AS-29() {
    # AS-29 (wiki_provenance-via-raw-and-sources, Acceptance 5): a git-backed
    # wiki whose only defect is a page body narrating a mid-conversation
    # source ("during an authoring session, the user enforced…"). The source
    # resolves under neither raw/ nor a declared root, so the assess pass must
    # list the page and remediation must halt: add no provenance prose, create
    # no sidecar, and surface the artifact for wiki_import in the per-file
    # report. No raw sidecar is staged, so the raw/ carve-out is not in play.
    local sb
    sb=$(reset_sandbox AS-29)
    stage "$sb/HOME/proj"
    git -C "$sb/HOME/proj" init -q
    "$INIT" "$sb/HOME/proj/wiki" >/dev/null
    local wiki="$sb/HOME/proj/wiki"
    python3 - "$wiki" <<'PY'
import sys, pathlib
w = pathlib.Path(sys.argv[1])
text = (w / "SCHEMA.md").read_text()
(w / "SCHEMA.md").write_text(
    text.replace("## Tag Taxonomy\n", "## Tag Taxonomy\n\n- Domain: model\n", 1)
)
(w / "concepts" / "rollout-cadence.md").write_text(
    "---\n"
    "title: rollout cadence\n"
    "created: 2026-05-01\n"
    "updated: 2026-05-01\n"
    "type: concept\n"
    "tags: [model]\n"
    "confidence: medium\n"
    "---\n\n"
    "# rollout cadence\n\n"
    "The widget rollout ships every second Tuesday.\n\n"
    "## Definition / explanation\n\n"
    "The cadence is a fixed two-week release window. During an authoring\n"
    "session, the user enforced that the window stays fixed so downstream\n"
    "teams can plan. See [widget caching](widget-caching.md) for what a\n"
    "release changes.\n\n"
    "## Current state of knowledge\n\n"
    "The window is announced a week ahead. See\n"
    "[widget defaults](widget-defaults.md) for the colour a release resolves.\n\n"
    "## Open questions or debates\n\n"
    "None recorded.\n\n"
    "## Related concepts\n\n"
    "- [widget caching](widget-caching.md)\n"
    "- [widget defaults](widget-defaults.md)\n",
    encoding="utf-8",
)
(w / "concepts" / "widget-caching.md").write_text(
    "---\n"
    "title: widget caching\n"
    "created: 2026-05-01\n"
    "updated: 2026-05-01\n"
    "type: concept\n"
    "tags: [model]\n"
    "confidence: medium\n"
    "---\n\n"
    "# widget caching\n\n"
    "The widget cache keeps rendered widget output between requests.\n\n"
    "## Definition / explanation\n\n"
    "An entry is keyed by widget identity and by the inputs that affect its\n"
    "rendering. See [widget defaults](widget-defaults.md) for the values an\n"
    "entry resolves.\n\n"
    "## Current state of knowledge\n\n"
    "The cache is invalidated when a widget's source record changes. See\n"
    "[rollout cadence](rollout-cadence.md) for when a release ships.\n\n"
    "## Open questions or debates\n\n"
    "None recorded.\n\n"
    "## Related concepts\n\n"
    "- [widget defaults](widget-defaults.md)\n"
    "- [rollout cadence](rollout-cadence.md)\n",
    encoding="utf-8",
)
(w / "concepts" / "widget-defaults.md").write_text(
    "---\n"
    "title: widget defaults\n"
    "created: 2026-05-01\n"
    "updated: 2026-05-01\n"
    "type: concept\n"
    "tags: [model]\n"
    "confidence: medium\n"
    "---\n\n"
    "# widget defaults\n\n"
    "The defaults table lists the framework colour for each widget class.\n\n"
    "## Definition / explanation\n\n"
    "A widget keeps the framework colour unless something above the framework\n"
    "supplies one. See [widget caching](widget-caching.md) for where the\n"
    "resolved value is stored.\n\n"
    "## Current state of knowledge\n\n"
    "The framework colour is resolved before any deployment-level override.\n"
    "See [rollout cadence](rollout-cadence.md) for when a release ships.\n\n"
    "## Open questions or debates\n\n"
    "None recorded.\n\n"
    "## Related concepts\n\n"
    "- [widget caching](widget-caching.md)\n"
    "- [rollout cadence](rollout-cadence.md)\n",
    encoding="utf-8",
)
idx = w / "index.md"
text = idx.read_text()
text = text.replace(
    "## Concepts\n",
    "## Concepts\n\n"
    "- [rollout cadence](concepts/rollout-cadence.md) — when the widget rollout ships\n"
    "- [widget caching](concepts/widget-caching.md) — rendered output kept between requests\n"
    "- [widget defaults](concepts/widget-defaults.md) — framework colour per widget class\n",
    1,
)
text = text.replace("Total pages: 0", "Total pages: 3", 1)
idx.write_text(text)
PY
    _as_git_commit "$sb/HOME/proj" "staging commit"
}

stage_MP-1() {
    # MP-1 (wiki_meta-prose-in-page-bodies): oversized custom `todo` page that
    # trips the page-size info finding. After wiki_fix the page body must
    # gain no meta-prose / sanction paragraph; any accepted-finding rationale
    # lands only in SCHEMA.md's ## Lint section or the audit log.
    local sb
    sb=$(reset_sandbox MP-1)
    stage "$sb/HOME/proj"
    git -C "$sb/HOME/proj" init -q
    "$INIT" "$sb/HOME/proj/wiki" >/dev/null
    local wiki="$sb/HOME/proj/wiki"
    python3 - "$wiki/SCHEMA.md" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1])
text = p.read_text()
text = text.replace(
    "type: entity | concept | comparison | query | summary | procedure",
    "type: entity | concept | comparison | query | summary | procedure | todo",
    1,
)
# Live taxonomy so the todo/concept page tags validate (no unused tags).
text = text.replace(
    "## Tag Taxonomy\n",
    "## Tag Taxonomy\n\n- Domain: model, backlog\n",
    1,
)
p.write_text(text)
PY
    mkdir -p "$wiki/todos" "$wiki/concepts"
    cat > "$wiki/concepts/widget.md" <<'EOF'
---
title: widget
created: 2026-05-01
updated: 2026-05-01
type: concept
tags: [model]
sources: []
confidence: medium
---

# widget

Companion concept for the backlog page. See also
[backlog items](../todos/backlog-items.md).
EOF
    # Oversized todo page: load-bearing entries only, no meta/sanction prose.
    python3 - "$wiki/todos/backlog-items.md" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
entries = "\n".join(
    f"### Item {i}\n\n"
    f"KEEP BODY ITEM {i}: Deliver the widget milestone {i} outcome.\n"
    for i in range(1, 80)
)
path.write_text(
    "---\n"
    "title: backlog items\n"
    "created: 2026-05-01\n"
    "updated: 2026-05-01\n"
    "type: todo\n"
    "tags: [backlog]\n"
    "sources: []\n"
    "confidence: medium\n"
    "---\n"
    "\n"
    "# backlog items\n"
    "\n"
    "Open delivery items for the widget programme. See also "
    "[widget](../concepts/widget.md).\n"
    "\n"
    "## Open\n"
    "\n"
    + entries
)
PY
    python3 - "$wiki/index.md" <<'PY'
import sys, pathlib
idx = pathlib.Path(sys.argv[1])
text = idx.read_text()
text = text.replace(
    "## Concepts\n",
    "## Concepts\n\n"
    "- [widget](concepts/widget.md) — companion concept for the backlog\n",
    1,
)
if "## Todos" not in text:
    text = text.rstrip() + (
        "\n\n## Todos\n\n"
        "- [backlog items](todos/backlog-items.md) — open delivery items\n"
    )
idx.write_text(text if text.endswith("\n") else text + "\n")
PY
}

ALL_SCENARIOS=(L2-1 L2-2 L2-3 L2-4 L2-5 L2-6 L2-7 L2-8 L2-9 L2-10 WI-1 WI-2 WI-3 WI-4 WI-5 WU-1 WU-2 WU-3 AS-1 AS-2 AS-3 AS-4 AS-5 AS-6 AS-7 AS-8 AS-9 AS-10 AS-11 AS-12 AS-13 AS-14 AS-15 AS-16 AS-17 AS-18 AS-19 AS-20 AS-21 AS-22 AS-23 AS-24 AS-25 AS-26 AS-27 AS-28 AS-29 MP-1)

if [[ $# -eq 0 ]]; then
    for sid in "${ALL_SCENARIOS[@]}"; do
        "stage_$sid"
    done
    echo "Layer 2 sandboxes staged under $SCRIPT_DIR"
    ls -1 "$SCRIPT_DIR"
elif [[ $# -eq 1 || $# -eq 2 ]]; then
    sid=$1
    if [[ $# -eq 2 ]]; then
        STAGE_DEST=$2
    fi
    fn="stage_$sid"
    if ! declare -F "$fn" >/dev/null; then
        echo "ERROR: unknown scenario id '$sid' (known: ${ALL_SCENARIOS[*]})" >&2
        exit 2
    fi
    "$fn"
else
    echo "ERROR: usage: setup_scenarios.sh [<SCENARIO_ID> [<DEST_DIR>]]" >&2
    exit 2
fi
