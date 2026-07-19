---
description: Define $WIKI_SKILL resolution once in the base wiki skill and route wiki_import/wiki_wrapup script and reference invocations through it, replacing an undefined variable and bare scripts/ paths.
scope: plugins/knowledge_management
created: 2026-07-19T18:51:20
updated: 2026-07-19T18:51:20
status: open
reported-by: Andreas Hoffmann
---

# Resolve the wiki skill bundle from the front-end skills

## Goal

`wiki_import` and `wiki_wrapup` can locate the wiki skill's bundled scripts and references deterministically. The resolution rule is authored once in the base `wiki` skill, and both front ends invoke `discover_wiki.sh`, `lint.py`, `compute_sha256.py`, and `references/raw_taxonomy.md` through it — replacing today's undefined `$WIKI_SKILL` variable and bare `scripts/…` paths that point into a bundle those skills do not contain.

## Context

Both front-end skills invoke another skill's bundled assets without any resolution rule:

- [skills/wiki_import/SKILL.md](../plugins/knowledge_management/skills/wiki_import/SKILL.md) instructs `python3 $WIKI_SKILL/scripts/compute_sha256.py …` and "consult `$WIKI_SKILL/references/raw_taxonomy.md`", but `$WIKI_SKILL` is defined nowhere in that skill — the only definition in the plugin is the `<resolve_runtime_paths>` block inside [agents/auto_shaper_wiki.md](../plugins/knowledge_management/agents/auto_shaper_wiki.md).
- [skills/wiki_wrapup/SKILL.md](../plugins/knowledge_management/skills/wiki_wrapup/SKILL.md) instructs "Run `discover_wiki.sh`" and "run `python3 scripts/lint.py`" — skill-relative paths that resolve inside the `wiki` skill's bundle, while `wiki_wrapup`'s own directory contains only its `SKILL.md`.

This works only when the executing model improvises the sibling bundle's install path. The standing repo rules and `CHARTER.md` both name the governing conventions: helper scripts are bundled beside the skill that executes them and "resolve paths from documented roots", and "Skill-family rules live in the family base skill" with front ends inheriting rather than carrying divergent copies. The shipped precedent is [archive/wiki_auto-shaper-skill-dir-resolution.md](archive/wiki_auto-shaper-skill-dir-resolution.md) (finished), which built the agent's run-local `$WIKI_SKILL`/`$WIKI` resolution; this task extends the same capability to the two front ends, with the rule's canonical home moving to the base skill.

Co-edit note: [wiki_reingest-drift-check-protocol.md](wiki_reingest-drift-check-protocol.md) rewrites the re-ingest sentence inside the same `<capture_raw>` block of `wiki_import` this task retargets to `$WIKI_SKILL` paths — coordinate wording so the block is edited coherently whichever lands first.

## Approach

1. **Author the rule once in the base skill.** Add a compact, greppably tagged block to the `<tools>` section of [skills/wiki/SKILL.md](../plugins/knowledge_management/skills/wiki/SKILL.md) (for example `<resolve_wiki_skill_bundle>`) defining how a sibling artefact resolves `$WIKI_SKILL`: the active artefact's own directory when the harness exposes it, then the sibling `wiki` skill inside the same plugin bundle or checkout, then deployed user-skill locations, then a bounded search of agent configuration roots — accepting a candidate only when the required assets exist (`SKILL.md`, `scripts/discover_wiki.sh`, `scripts/lint.py`), and stopping with a clear message otherwise. Condense from the agent's proven `<resolve_runtime_paths>` order.
2. **Route the front ends through it.** In `wiki_import` and `wiki_wrapup`, define `$WIKI_SKILL` by citing the base-skill block by its verbatim tag before first use, and rewrite every bare invocation to the resolved form: `wiki_wrapup`'s `discover_wiki.sh` and `python3 scripts/lint.py` become `$WIKI_SKILL/scripts/…`; `wiki_import`'s existing `$WIKI_SKILL` uses gain the definition they currently lack (its own bare `python3 scripts/lint.py` step included).
3. **Keep the agent self-contained, marked as a mirror.** `auto_shaper_wiki` resolves paths before it can read any skill file, so its `<resolve_runtime_paths>` block stays; add one line there naming the base-skill block as the canonical statement it mirrors, per the repo convention of pairing enforcement copies with the canonical rule.

**Out of scope:**

- Copying scripts into the front-end bundles — duplicated artefacts diverge; the family shares one script set in the base skill.
- Restructuring the agent's resolution block beyond the one-line mirror note — its self-contained form is load-bearing for its isolated execution context.

## Acceptance

1. The base `wiki` `SKILL.md` carries the new resolution block under a greppable tag, and that tag is the target both front ends cite; `rg` for the tag name returns the definition plus the two citations.
2. `rg '\$WIKI_SKILL' ../plugins/knowledge_management/skills/wiki_import/SKILL.md ../plugins/knowledge_management/skills/wiki_wrapup/SKILL.md` shows every use covered by a preceding resolution reference in the same file, and `rg 'python3 scripts/lint.py' ../plugins/knowledge_management/skills/wiki_import/SKILL.md ../plugins/knowledge_management/skills/wiki_wrapup/SKILL.md` returns no match — both superseded by the `$WIKI_SKILL/scripts/…` form.
3. `wiki_wrapup`'s discovery step names `$WIKI_SKILL/scripts/discover_wiki.sh` rather than a bare script name.
4. The agent's `<resolve_runtime_paths>` block names the base-skill block as its canonical source in one line, with its resolution order otherwise unchanged.
5. A harness-portability read-through (per the repo's portability review skill) of both front-end skills finds no remaining bare sibling-bundle path; recorded as a checklist item in the change, with `tests/wiki/run_all.sh` still passing.
