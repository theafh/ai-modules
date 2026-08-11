---
description: Give the wiki family one source of truth: a hub family block, an authority block per front end, cited rather than restated base rules, and one orientation log-read quantity.
scope: plugins/knowledge_management
created: 2026-08-11T18:49:52
updated: 2026-08-11T18:50:15
status: open
reported-by: Andreas Hoffmann
---

# Give the wiki family one source of truth for its shared rules

## Goal

The `wiki` hub declares its family, and each of `wiki_fix`, `wiki_import`, and
`wiki_wrapup` inherits the hub's rules by citation, so every shared rule has
exactly one statement in the family. A reader of any front end can see which
skill owns the rule it follows, and the orientation log read is stated once and
reads the same wherever it is cited.

## Context

The family carries none of the inheritance structure the repo's other family
uses, so shared rules sit in copies today.

The hub carries no `<family>` block and names none of its three front ends
anywhere in its body; only the `auto_shaper_wiki` agent appears. The precedent to
follow is the `<family>` block in the base `task` skill, which opens
"This base `task` skill is the hub of a `task_*` family" and lists each front end
with the one job it covers.

None of the three front ends carries an `<authority>` block; each defers in prose,
for example "Defer all wiki structure, discovery, orientation, ingest, and lint
behavior to the `wiki` skill." The `task_*` precedent pairs an `<authority>` block
with a `<path_resolution>` block in every sibling, the authority block opening
"The base `task` skill's `SKILL.md` is the source of truth for the task-file
shape".

`wiki_import` restates two base-skill rules instead of citing them. Its
`<too_large_to_read_in_one_shot>` policy duplicates the same-named block inside
the hub's `<file_handling_discipline>`, down to the
`exceeds maximum allowed tokens` failure string, and its
`<list_before_unfamiliar_path>` duplicates the hub's
`<list_before_manipulating_unfamiliar_paths>` under a shortened tag name. The
standing repo rule authors a family rule once in the family's base skill and has
the front ends inherit it.

The hub's `<role>` block also breaks the standing deployment-agnostic
cross-reference rule, naming both the plugin that ships the skill and the
marketplace repository it comes from in the sentence beginning
"This LLM-Wiki is managed by the `wiki` skill created by". The rule has an
artefact reference sibling artefacts by name instead, so the fix belongs with the
family's other cross-reference work.

The orientation log read is stated three ways. `wiki_wrapup` contradicts itself:
its `<orient_first>` policy says "the last 20–30 entries of `log.md`" while its
own steps say "roughly the last 350 lines of `log.md`". `wiki_import` says 350
lines in both places, and the hub says only `recent log`.

Co-edit: [wiki_log-rotation-and-retrieval.md](wiki_log-rotation-and-retrieval.md)
replaces the prescribed log-read idiom with an entry-based read, so the quantity
this task settles and that idiom must land coherently whichever ships first.

## Approach

1. Add a `<family>` block to the hub naming `wiki_import`, `wiki_wrapup`, and
   `wiki_fix` with the one job each covers, following the `task_*` block's shape
   and the repo's deployment-agnostic cross-reference rule.
2. Add an `<authority>` block to each front end that cites the hub as the source
   of truth for wiki structure, discovery, orientation, ingest, and lint, and
   rewrite the prose deferral sentence it replaces so one statement remains.
3. Replace `wiki_import`'s two restated discipline blocks with citations of the
   hub's blocks by their verbatim tag names, keeping any genuinely
   import-specific detail that the hub's version does not carry.
4. State the orientation log-read quantity once in the hub and have both ingest
   front ends cite that statement, superseding all three current statements.
5. Rewrite the hub's `<role>` sentence so it identifies the skill without naming
   the plugin or the marketplace repository, keeping the authorship credit and the
   RAG contrast the block carries.

**Out of scope:**

- Defining how a front end resolves the hub's bundle path, owned by
  [wiki_front-end-skill-dir-resolution.md](wiki_front-end-skill-dir-resolution.md).
- The hub's output contract, owned by
  [wiki_base-skill-output-contract.md](wiki_base-skill-output-contract.md).

## Acceptance

1. Searching the hub for `<family>` returns one block naming all three front ends,
   each with one job, and naming no plugin, marketplace, or installed path.
2. Searching each front end for `<authority>` returns one block citing the hub,
   and the prose deferral sentence it replaces returns no match in that file.
3. Searching `wiki_import` for `exceeds maximum allowed tokens` returns no match,
   and the file cites the hub's `<too_large_to_read_in_one_shot>` and
   `<list_before_manipulating_unfamiliar_paths>` by tag name.
4. Searching the family for `the last 20–30 entries` returns no match, one hub
   statement of the quantity exists, and both ingest front ends cite it, so a
   reader of `wiki_wrapup` finds one quantity rather than two.
5. Searching the hub for `knowledge_management` and for the marketplace repository
   URL returns no match, while the `<role>` block still credits the author and
   keeps its RAG contrast.
6. Running `lint_pseudo_xml.py` from the `ai_instruction_formatting` skill over
   all four family skills reports no errors, and any homogeneous-list hint on the
   new blocks is recorded as judged in the commit.
