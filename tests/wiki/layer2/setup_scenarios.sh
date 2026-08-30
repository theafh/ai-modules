#!/usr/bin/env bash
# Stage Layer 2 scenario sandboxes. Each sandbox has its own fake HOME so
# subagents running discover_wiki.sh / init_wiki.sh with HOME overridden
# stay fully isolated from the operator's real home tree.
#
# Usage:
#   setup_scenarios.sh               # restage ALL sandboxes
#   setup_scenarios.sh <SCENARIO_ID> # restage only one (e.g. L2-1, WI-2, WU-3)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
WIKI_SKILL="$REPO_ROOT/plugins/knowledge_management/skills/wiki"
INIT="$WIKI_SKILL/scripts/init_wiki.sh"

stage() { mkdir -p "$1"; }

reset_sandbox() {
    local id=$1
    local sandbox="$SCRIPT_DIR/$id"
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
> When this file exceeds 500 entries, rotate: rename to log-YYYY.md, start fresh.
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
    # do. Only the log.md postconditions are graded: a leftover `boilerplate`
    # warn about the owner extension is expected here, because classifying an
    # owner extension belongs to wiki_sanctioned-template-deviations.
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
        "> When this file exceeds 500 entries, rotate: rename to log-YYYY.md, start fresh."
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
    # graded.
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
    # chronological-record opener is present but reworded, and an owner-added
    # line sits in the same region. The move must refresh the unlabeled unit by
    # its greppable stem while leaving the owner's line byte-identical. Only the
    # log.md postconditions are graded.
    _assert_template_log_contains \
        "> Chronological record of wiki changes. Append-only."
    local sb
    sb=$(reset_sandbox AS-18)
    stage "$sb/HOME/proj"
    git -C "$sb/HOME/proj" init -q
    "$INIT" "$sb/HOME/proj/wiki" >/dev/null
    local wiki="$sb/HOME/proj/wiki"
    _stage_log_preamble "$wiki/log.md" "$WIKI_SKILL/references/template_log.md" \
        "reword-line|||Chronological record|||Chronological log of changes to this wiki." \
        "add-owner|||Local: this vault names the tenant alongside every rollout entry."
    _set_log_entries "$wiki/log.md" \
        "## [2026-06-17 09:14] create | Wiki initialized|||- Domain: widget delivery" \
        "## [2026-06-18 10:00] session-wrapup | 0 new, 2 extended, 0 contested|||- concepts/alpha.md: extended"
}

ALL_SCENARIOS=(L2-1 L2-2 L2-3 L2-4 L2-5 L2-6 L2-7 L2-8 L2-9 WI-1 WI-2 WI-3 WI-4 WU-1 WU-2 WU-3 AS-1 AS-2 AS-3 AS-4 AS-5 AS-8 AS-9 AS-10 AS-11 AS-12 AS-13 AS-14 AS-15 AS-16 AS-17 AS-18)

if [[ $# -eq 0 ]]; then
    for sid in "${ALL_SCENARIOS[@]}"; do
        "stage_$sid"
    done
    echo "Layer 2 sandboxes staged under $SCRIPT_DIR"
    ls -1 "$SCRIPT_DIR"
else
    sid=$1
    fn="stage_$sid"
    if ! declare -F "$fn" >/dev/null; then
        echo "ERROR: unknown scenario id '$sid' (known: ${ALL_SCENARIOS[*]})" >&2
        exit 2
    fi
    "$fn"
fi
