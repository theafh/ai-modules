---
description: Route the wiki hub's own bundled-script invocations through the resolved bundle path, since its bare relative calls resolve only when the working directory is the skill bundle.
scope: plugins/knowledge_management
created: 2026-08-11T18:59:52
updated: 2026-08-11T18:59:52
status: open
reported-by: Andreas Hoffmann
---

# Route the wiki hub's own script calls through the resolved bundle path

## Goal

The `wiki` skill invokes its bundled scripts through a path that resolves from
wherever the skill runs, so `discover_wiki.sh`, `init_wiki.sh`, `lint.py`, and
`compute_sha256.py` are found when the working directory is the user's project
rather than the skill bundle. Every command the hub prescribes is runnable as
written.

## Context

The hub prescribes bare relative invocations throughout. Its `<tools>` snippet
runs `scripts/discover_wiki.sh`, then `scripts/init_wiki.sh "$WIKI"` and
`python3 scripts/lint.py`; the ingest flow runs
`python3 scripts/compute_sha256.py raw/<kind>/<slug>.md`; the ingest loop, the
archive step, and the audit section each run `python3 scripts/lint.py`. Each of
those resolves only when the working directory is the skill bundle, while the
skill's own model puts the working directory in the user's project and discovers
`$WIKI` separately, so the prescribed command finds the project's own `scripts/`
or nothing.

The sibling task
[wiki_front-end-skill-dir-resolution.md](wiki_front-end-skill-dir-resolution.md)
authors the bundle-resolution block inside this same hub file and rewrites the
bare calls in `wiki_import` and `wiki_wrapup`. Its goal and acceptance cover those
two front ends only, so the hub's own calls stay unaddressed there. This task
consumes the block that task authors and adds no second statement of the
resolution rule. Both tasks edit the hub file, and that task supplies what this
one depends on, so it ships first or alongside.

The resolved form is already in use elsewhere in the plugin: the
`auto_shaper_wiki` agent runs `python3 "$WIKI_SKILL/scripts/lint.py" "$WIKI"` and
`"$WIKI_SKILL/scripts/discover_wiki.sh"`, so this task follows a shape the plugin
already ships rather than inventing one.

## Approach

Rewrite each bare `scripts/...` invocation in the hub to the resolved
`"$WIKI_SKILL/scripts/..."` form, citing the resolution block by its verbatim tag
name at first use. Cover the `<tools>` shell snippet, the discovery and init flow
in `<resolving_the_wiki_location>`, the ingest sha256 call, the linter calls in the
ingest loop and the archive step, and the linter usage examples in
`<lint_and_audit>`. Keep every shell block runnable with quoting intact, so a
reader can paste it once `$WIKI_SKILL` is resolved.

**Out of scope:**

- Authoring the resolution rule itself, owned by
  [wiki_front-end-skill-dir-resolution.md](wiki_front-end-skill-dir-resolution.md).
- `<fallback_without_scripts>`, which describes inline discovery for the case
  where the scripts are unreachable and prescribes no script path.

## Acceptance

1. Searching the hub for `python3 scripts/lint.py` and for `scripts/discover_wiki.sh`
   returns no bare form; every remaining hit carries the `$WIKI_SKILL` prefix.
2. The same holds for `init_wiki.sh` and `compute_sha256.py`: no bare relative
   invocation of either remains in the hub.
3. The hub cites the resolution block by its verbatim tag name and states the
   resolution rule nowhere else, so searching for that tag returns the citation
   plus the block itself.
4. The `<tools>` snippet runs end to end from a project directory with
   `$WIKI_SKILL` set to a checkout of the skill: discovery resolves, the init
   branch is reachable, and the linter runs.
5. A portability read-through of the hub, per the repo's portability review skill,
   finds no remaining bare sibling-bundle path, recorded as a checklist item in
   the change.
6. `<fallback_without_scripts>` is unchanged, so the no-scripts path keeps its
   inline discovery rule.
