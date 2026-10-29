---
description: "Give the wiki family one source of truth: a hub family block, an authority block per front end, cited rather than restated base rules, and one orientation log-read quantity."
scope: plugins/knowledge_management
created: 2026-08-11T18:49:52
updated: 2026-10-29T06:02:01
status: ready
reported-by: Andreas Hoffmann
---

# Give the wiki family one source of truth for its shared rules

## Goal

The `wiki` hub declares its family, and each `wiki_*` front-end sibling
inherits the hub's rules by citation, so every shared rule has exactly one
statement in the family. A reader of any front end can see which
skill owns the rule it follows, and the orientation log read is stated once and
reads the same wherever it is cited.

## Context

The family carries none of the inheritance structure the repo's other family
uses, so shared rules sit in copies today.

The hub carries no `<family>` block declaring the family or the one job each
front end covers; its front-end names appear only as pointers, such as the
`wiki_import` and `wiki_fix` activation lines in `<when_to_activate>` and the
`wiki_import` and `wiki_wrapup` sibling paths in `<resolve_wiki_skill_bundle>`.
The precedent to
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

The orientation log read is stated in several places with two incompatible
idioms. The hub carries it twice: `<resuming_an_existing_wiki>` names "the last
20 to 30 entries" beside a `tail -n 350 "$WIKI/log.md"` command, and
`<searching>` shows a bare `tail -n 350 "$WIKI/log.md"` fence labelled
`~last 20 log entries`. `wiki_wrapup` restates "roughly the last 350 lines of
`log.md`" at both of its sites, its `<orient_first>` policy and its orientation
step. `wiki_import` restates a fixed line count at three sites,
`<orient_first_top>`, `<orient_first>`, and its orientation step.

Co-edit: [wiki_log-rotation-and-retrieval.md](archive/wiki_log-rotation-and-retrieval.md)
replaces the prescribed log-read idiom with an entry-based read, owns the
entry-anchor retrieval recipe, and owns the `auto_shaper_wiki` agent's copy of
the orientation log read, so the quantity this task settles and that sibling's
entry-anchor idiom must land coherently whichever ships first.

## Approach

1. Add a `<family>` block to the hub naming every `wiki_*` front-end sibling the
   walk finds under `plugins/knowledge_management/skills/`, with the one job each
   covers, placed as a column-0 block immediately after `</output_contract>` and
   closing before `</wiki>` in the `task_*` hub's
   `<output_contract>`-then-`<family>` order, and following the `task_*` block's
   shape and the repo's deployment-agnostic cross-reference rule.
2. Add an `<authority>` block to each front end that cites the hub as the source
   of truth for wiki structure, discovery, orientation, ingest, and lint. In
   `wiki_import` and `wiki_wrapup`, rewrite the prose deferral sentence it
   replaces so one statement remains: the hub citation in `<authority>`. In
   `wiki_fix`, pair `<authority>` with the agent-delegation contract: the hub
   owns shared family rules; `auto_shaper_wiki` remains the execution delegate
   for discovery, orientation, lint, semantic audit, remediation, and
   verification. Rewrite `wiki_fix`'s objective deferral so hub citation and
   agent delegation each appear once and do not compete.
3. Replace `wiki_import`'s two restated discipline blocks with citations of the
   hub's blocks by their verbatim tag names, keeping any genuinely
   import-specific detail that the hub's version does not carry.
4. State the orientation log-read quantity once in the hub's
   `<resuming_an_existing_wiki>` block as the last 20 to 30 entries retrieved
   by entry boundary (not a fixed line count), keeping that statement coherent
   with the entry-anchor idiom in `wiki_log-rotation-and-retrieval`, as
   `## Context` records. `<searching>` is the one hub site this step leaves to `tasks/archive/wiki_log-rotation-and-retrieval.md`, which claims that rewrite in its own `## Context` ("Hub `<searching>` citation of `<resuming_an_existing_wiki>` after retiring its `tail -n 350` example stays this task's edit") and proves it in its own Acceptance; so this step retires the orientation-read idiom at `<resuming_an_existing_wiki>` and the two front ends, while the sibling retires the `<searching>` fence, and the hub's two statements read as one rule whichever ships first. Rewrite `<resuming_an_existing_wiki>` to hold that
   canonical quantity. Leave the hub's `<orient_first>` pitfall as it stands: it already reads
   "Read SCHEMA + index + recent log before any operation. *(see
   `<resuming_an_existing_wiki>`)*", so it already cites the tag verbatim and
   carries no quantity or `tail -n 350` to remove; this step needs no edit there. Have `wiki_import` and `wiki_wrapup` cite
   `<resuming_an_existing_wiki>` by tag, superseding their `<orient_first_top>`,
   `<orient_first>`, and orientation-step wording.
5. Rewrite the hub's `<role>` sentence so it identifies the skill without naming
   the plugin or the marketplace repository, keeping the authorship credit and the
   RAG contrast the block carries.

**Out of scope:**

- Defining how a front end resolves the hub's bundle path, owned by
  [wiki_front-end-skill-dir-resolution.md](archive/wiki_front-end-skill-dir-resolution.md).
- The hub's output contract, owned by
  [wiki_base-skill-output-contract.md](archive/wiki_base-skill-output-contract.md).
- Rewriting the hub `<searching>` block, owned by
  `tasks/archive/wiki_log-rotation-and-retrieval.md`.

## Acceptance

1. Searching the hub for `<family>` returns one block naming every `wiki_*`
   front-end sibling the walk finds under `plugins/knowledge_management/skills/`,
   each with one job, and naming no plugin, marketplace, or installed path, and
   reading the hub from `</output_contract>` finds that block as the immediate
   next content, closing before `</wiki>`, the placement
   `tests/wiki/layer1/hub_output_contract.py` pins with its
   `block is not immediately before <family>` failure text.
2. Searching every `wiki_*` front-end sibling the walk finds for `<authority>`
   returns one block citing the hub.
   Searching `wiki_import` and `wiki_wrapup` for `Defer all wiki structure,
   discovery, orientation` returns no match. Searching `wiki_fix` for `Defer
   all wiki structure, discovery, orientation, ingest, and lint behavior to the
   `wiki`skill` returns no match; searching its `<objective>` for `Defer all
   discovery, orientation, lint, semantic audit, remediation, and verification
   behavior to the agent` returns no match; and searching it for
   `auto_shaper_wiki` returns one match in `<role>`, one in `<delegate>`, and
   one in `<steps>`.
3. Searching `wiki_import` for `exceeds maximum allowed tokens` returns no match,
   the file cites the hub's `<too_large_to_read_in_one_shot>` and
   `<list_before_manipulating_unfamiliar_paths>` by tag name, and searching
   `wiki_import` for `raw/<kind>/` returns a match guarding writes into a
   `raw/<kind>/` bucket with `ls "$WIKI/raw/<kind>/"`.
4. Searching the hub and every `wiki_*` front-end sibling the walk finds under
   `plugins/knowledge_management/skills/` for `the last 20 to 30 entries` returns
   no match outside the hub and one match in the hub's
   `<resuming_an_existing_wiki>` naming the last 20 to 30 entries by entry
   boundary (not line count); the same phrase in
   `plugins/knowledge_management/agents/auto_shaper_wiki.md` is that agent's
   surface and lies outside this search. Searching the
   hub's pitfall `<orient_first>` finds it cites `<resuming_an_existing_wiki>`
   by its verbatim tag name and restates no quantity. Searching `wiki_import` and `wiki_wrapup` finds each cites
   `<resuming_an_existing_wiki>` by tag, so a reader of `wiki_wrapup` finds
   one quantity rather than two.
5. Searching the hub for `knowledge_management` and for the marketplace repository
   URL returns no match, while the `<role>` block still credits the author and
   keeps its RAG contrast.
6. Running `lint_pseudo_xml.py` from the `ai_instruction_formatting` skill over
   the hub and every `wiki_*` front-end sibling the walk finds reports no
   errors; any homogeneous-list hint it emits
   on the new blocks is an accepted info-level hint rather than an error, so the
   run carries no blocking finding.
7. Searching the hub's `<resuming_an_existing_wiki>` and pitfall `<orient_first>`,
   plus `wiki_import` and `wiki_wrapup`, for `350 lines` and `tail -n 350`
   returns no match. With `tasks/archive/wiki_log-rotation-and-retrieval.md` read for
   the entry-aware log-read idiom it prescribes, the hub
   orientation-read statement and the cited front-end references name the same
   entry bound the sibling prescribes when it has shipped, or the same entry
   bound settled in Acceptance item 4 when it has not. Reading the hub's
   `<searching>` block, it carries a log-read clause citing
   `<resuming_an_existing_wiki>` and no `~last 20 log entries` fence once
   `tasks/archive/wiki_log-rotation-and-retrieval.md` has shipped, and while that
   sibling is unshipped the fence there is the sibling's edit named in the
   task's `**Out of scope:**` block. So whichever ships
   first, the quantity and idiom read as one coordinated rule.
