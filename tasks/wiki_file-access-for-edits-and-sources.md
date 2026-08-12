---
description: Add a file_handling_discipline rule to use Read (not Bash grep/cat/tail) when staging an Edit, and a note that sources: and raw source_path: values resolve against the wiki root when opened.
scope: plugins/knowledge_management
created: 2026-05-28T20:05:29
updated: 2026-08-12T21:55:09
status: ready
reported-by: Andreas Hoffmann
---

# File-access guidance: Read to stage edits; resolve `sources:` and `source_path:` against the wiki root

## Goal

The wiki authoring contract steers the agent to use the right tool for two recurring file-access patterns, eliminating two predictable round-trips: (1) locating an edit target with `Read` (which satisfies the Edit precondition) instead of a Bash `grep`/`cat`/`tail` that does not; and (2) resolving a `sources:` / `source_path:` value against the wiki root before opening it, instead of treating it as a CWD-relative path.

## Context

Two distinct but small failure modes recur during wiki editing, both fixable with a sentence of guidance in the skill prose:

1. **Bash-locate then Edit fails the read-precondition.** When the agent locates the span to change with a Bash command (`grep -n`, `cat`, `tail`) and then calls `Edit`, the edit fails with "File has not been read yet" because the Edit tool requires a prior `Read` of *that* file in the session — a Bash grep does not satisfy it. The agent then has to `Read` and re-`Edit`: a three-call round-trip where one `Read` + one `Edit` would do. [skills/wiki/SKILL.md](../plugins/knowledge_management/skills/wiki/SKILL.md) now carries a `<file_handling_discipline>` section (the auto-shaper carries matching between-groups re-Read guidance inline inside `<fix_workflow>`) whose `<re_read_after_mutation>` rule covers the *stale-read-after-mutation* case and quotes this exact error — but no rule yet covers *first location*: the skill's search and log guidance still leans on Bash inspection idioms without flagging that they do not prepare an Edit.

2. **`sources:` paths read as CWD-relative.** By convention, `sources:` entries are paths relative to the **wiki root** (the linter resolves them that way — `check_source_paths_exist` in [skills/wiki/scripts/lint.py](../plugins/knowledge_management/skills/wiki/scripts/lint.py)). But nothing in the agent-facing prose says so, so when the agent reads a `sources:` value literally (e.g. `raw/notes/<slug>.md`) it opens the wrong path, gets "file does not exist", and falls back to a `find` to locate the real `<wiki>/raw/notes/<slug>.md`. A one-line note removes the failed-Read-then-find detour.

This task is the *read-time* counterpart to the provenance tasks. [wiki_provenance-via-raw-and-sources.md](wiki_provenance-via-raw-and-sources.md) and [wiki_raw-kind-rubric-and-out-of-repo-paths.md](archive/wiki_raw-kind-rubric-and-out-of-repo-paths.md) define how provenance is *written* (the `raw/` sidecar + `sources:` convention, and the `source_path:` field the finished rubric task introduced); this task only adds the guidance for correctly *opening* those paths and for staging edits. Keep the write-side conventions in those tasks; do not duplicate them here.

Files involved:

- [plugins/knowledge_management/skills/wiki/SKILL.md](../plugins/knowledge_management/skills/wiki/SKILL.md) — the `**Provenance**` / `sources:` description for the `sources:` opening note, and `<capture_raw_source>` for the `source_path:` opening note.
- [plugins/knowledge_management/agents/auto_shaper_wiki.md](../plugins/knowledge_management/agents/auto_shaper_wiki.md) — mirror the `sources:` note in `<external_source_pointer>` and the `source_path:` note in `<fix_raw_source_frontmatter_missing>`.

`wiki_import` currently restates hub `<file_handling_discipline>` siblings (`<too_large_to_read_in_one_shot>`, `<list_before_unfamiliar_path>`) rather than citing them; [wiki_family-inheritance-blocks.md](wiki_family-inheritance-blocks.md) replaces those restated blocks with hub citations. This task authors the new read-to-stage-edits rule only in the hub `SKILL.md` and the auto-shaper mirror above.

## Approach

1. **Read-to-stage-edits rule.** Rewrite SKILL.md's `<file_handling_discipline>` section in place so a fourth rule sits beside the existing three, and the section lead-in becomes "Four rules keep tool use stable…" (superseding "Three rules keep tool use stable…"), and place the matching guidance in the auto-shaper beside the existing between-groups re-Read paragraph inside `<fix_workflow>`: when locating a span you intend to `Edit`, use `Read` — it both shows the content and satisfies Edit's read-precondition, which Bash `grep`/`cat`/`tail` alone do not. Keep `<too_large_to_read_in_one_shot>`'s Bash-`grep`-then-`Read` path and `<appending_to_log>`'s post-edit `grep` verification unchanged; those uses still end in `Read` before any Edit, or verify after an Edit.
2. **`sources:` / `source_path:` resolution notes.** Rewrite in place SKILL.md's `**Provenance**` bullet so it states that `sources:` entries are paths relative to the **wiki root** and must be prefixed with `$WIKI/` (or the wiki dir) when opened with `Read`. Rewrite in place `<capture_raw_source>`'s origin-field guidance so the same wiki-root prefix rule covers raw-sidecar `source_path:` — the field is shipped (introduced by the finished [wiki_raw-kind-rubric-and-out-of-repo-paths.md](archive/wiki_raw-kind-rubric-and-out-of-repo-paths.md)) and resolves from the wiki root as well. Mirror the `sources:` opening note in the auto-shaper inside `<external_source_pointer>`, beside the existing bullet that resolves `sources:` under `$WIKI/raw/`. Mirror the `source_path:` opening note in the auto-shaper inside `<fix_raw_source_frontmatter_missing>`, beside that block's existing wiki-root-relative `source_path:` normalization language. Leave `<fix_raw_frontmatter_subsection_missing>` unchanged — it stays a verbatim SCHEMA-template copy and must not gain agent Read/open prose.
3. Keep both additions to a sentence or two each — these are tool-use clarifications, not new conventions.

**Out of scope:**

- Switching the prescribed log-read idiom from fixed-line `tail` to entry-aware retrieval — owned by [wiki_log-rotation-and-retrieval.md](wiki_log-rotation-and-retrieval.md).
- Editing `wiki_import`, including restating or citing the new read-to-stage-edits rule there.

## Acceptance

- SKILL.md's `<file_handling_discipline>` section and the auto-shaper's `<fix_workflow>` re-read guidance both state that `Read` is the way to stage an `Edit`, and that Bash grep/cat/tail do not satisfy the Edit precondition; SKILL.md's `<file_handling_discipline>` lead-in states four rules, and the prior "Three rules keep tool use stable…" phrasing is gone.
- The read-to-stage-edits rule in SKILL.md's `<file_handling_discipline>` and the auto-shaper's `<fix_workflow>` re-read guidance reserves Bash `grep`/`cat`/`tail` for counting, log-offset / entry-anchor retrieval, and the existing `<too_large_to_read_in_one_shot>` locate-then-`Read` and `<appending_to_log>` post-edit verification paths — not for preparing an `Edit` — and leaves the existing `<too_large_to_read_in_one_shot>` locate-then-`Read` and `<appending_to_log>` post-edit verification paths unchanged (no log-read idiom rewrite in this task).
- SKILL.md's `**Provenance**` bullet and the auto-shaper's `<external_source_pointer>` state that `sources:` values resolve against the wiki root and must be prefixed accordingly when opened; SKILL.md's `<capture_raw_source>` and the auto-shaper's `<fix_raw_source_frontmatter_missing>` state the same for raw-sidecar `source_path:`.
- The auto-shaper's `<fix_raw_frontmatter_subsection_missing>` remains a verbatim SCHEMA-template copy with no agent Read/open prose added.
- The additions are short prose only; no new lint check is required (though a fixture walkthrough confirming no "File has not been read yet" and no failed `sources:` Read is welcome).
