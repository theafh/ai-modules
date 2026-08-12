---
description: Trim the hub's wiki pitfall to the archive-time lesson instruction it alone carries, leaving not_in_scope the single statement of the wiki boundary.
scope: plugins/ai_dev/skills/task
created: 2026-08-12T09:09:35
updated: 2026-08-12T09:09:35
status: open
reported-by: Andreas Hoffmann
---

# State the hub's wiki boundary once

## Goal

The base `task` skill states the task-versus-wiki boundary in exactly one place.
`<not_in_scope>` keeps it, and the `<pitfalls>` entry that currently repeats it
keeps only the instruction no other passage carries: capture a lasting lesson in
the wiki when archiving. A reader meets one wording of the boundary, and a later
edit to it has one place to land instead of two that drift apart.

## Context

Two passages in `plugins/ai_dev/skills/task/SKILL.md` state the same boundary.
`<not_in_scope>` opens with "The wiki skill captures durable knowledge (concepts,
procedures, references). The task skill captures *upcoming work* on this project."
The `<not_a_wiki>` entry inside `<pitfalls>` says it again in its own words:
"**Tasks are not wiki pages.** Upcoming work goes here; durable subject knowledge
goes in the `wiki` skill. If a task taught a lasting lesson, capture that lesson
separately in the wiki when archiving."

Only that third sentence is unique. The archive-time instruction to move a lasting
lesson into the wiki appears nowhere else in the file, and the `<archive>` workflow
does not carry it either, so the entry earns its place once the restatement goes.

[The hub contract-surfaces task](archive/task-family_hub-contract-surfaces.md) rewrote
`<not_in_scope>` in place and set the expectation that its wiki sentence is the
single canonical statement of that boundary. It left this duplication standing
because trimming a `<pitfalls>` entry sat outside its declared scope, which is the
gap this task closes.

The tag name and the lead-in both describe the sentence being removed rather than
the one being kept. `<not_a_wiki>` is referenced nowhere outside its own opening
and closing tags in the whole `plugins/` tree, so renaming it breaks no
cross-reference. The lead-in is also the only negation-framed one among the six
entries in `<pitfalls>`: its siblings read "**One task per file.**", "**Split at
300 lines.**", "**Status matches location.**", "**Bump `updated` on every
change.**", and "**Write for a single-shot implementer.**", each naming the action
to take. The standing repo rules on positive, action-oriented authoring govern the
replacement wording.

## Approach

Rewrite the `<not_a_wiki>` entry in place, inside `<pitfalls>` and in its current
position among the six entries, so it carries the archive-time instruction alone.
Drop the "**Tasks are not wiki pages.**" lead-in and the "Upcoming work goes here;
durable subject knowledge goes in the `wiki` skill." sentence, since
`<not_in_scope>` already states both halves. Give the entry a positive bold
lead-in naming the action it asks for, matching the shape its five siblings use.

Rename the tag to match the instruction that remains, keeping it snake_case and
lowercase per the repo's pseudo-XML conventions. The rename is safe because the
current tag has no reader elsewhere, and leaving a tag named for a boundary
statement that the entry no longer makes would reintroduce in the tag exactly the
drift this task removes from the prose.

Leave `<not_in_scope>` byte-identical. It is already the surviving statement of
the boundary, so this task moves nothing into it.

**Out of scope:** rewording the `<not_in_scope>` wiki sentence itself, and adding
the archive-time lesson instruction to the `<archive>` workflow, which would put
the surviving instruction in two places and recreate the defect this task fixes.

## Acceptance

- `rg 'Tasks are not wiki pages' plugins/ai_dev/skills/task/SKILL.md` returns
  nothing, where it returns one hit today.
- `rg 'durable subject knowledge goes in the' plugins/ai_dev/skills/task/SKILL.md`
  returns nothing, where it returns one hit today.
- `rg 'The wiki skill captures durable knowledge' plugins/ai_dev/skills/task/SKILL.md`
  still returns exactly one hit, and that `<not_in_scope>` paragraph is unchanged
  from its pre-task text.
- `rg 'lasting lesson' plugins/ai_dev/skills/task/SKILL.md` returns a hit inside
  the rewritten `<pitfalls>` entry, so the one instruction the entry uniquely
  carried survives the trim.
- The rewritten entry opens with a bold lead-in stating the action to take, and no
  entry in `<pitfalls>` is framed as a negation.
- The renamed tag names the surviving instruction, opens and closes around that
  entry, and `rg 'not_a_wiki' plugins/` returns nothing.
- `python3 plugins/ai_dev/skills/ai_instruction_formatting/scripts/lint_pseudo_xml.py plugins/ai_dev/skills/task/SKILL.md`
  reports PASS with every tag closed and snake_case, and `<pitfalls>` still holds
  six entries.
