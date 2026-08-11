---
description: Give the wiki hub an output contract stating what each core operation returns, since all three front ends carry one and the hub states its report only per operation.
scope: plugins/knowledge_management
created: 2026-08-11T18:59:52
updated: 2026-08-11T18:59:52
status: open
reported-by: Andreas Hoffmann
---

# Give the wiki hub an output contract

## Goal

The `wiki` skill states what each of its core operations returns, so an agent
finishing an ingest, a procedure capture, a query, an archive move, or an audit
knows the shape of the report it owes the user. Reading one block answers that
question for every operation.

## Context

The hub carries no `<output_contract>`, `<validation>`, or `<inputs>` tag anywhere
in its body, though the body runs to dozens of tags. Its reporting promises live
inside individual operations, the clearest being `<report_what_changed>` inside
`<ingest>`.

All three front ends already set the pattern: `wiki_fix`, `wiki_import`, and
`wiki_wrapup` each end with an `<output_contract>` naming the report they return.
The hub, which can do all of their work itself, is the one family member without
one.

The `ai_instruction_formatting` skill's `## Tag Vocabulary` table lists
`<output_contract>` for `Response shape and validation` and states when to include
it, so the tag choice and its placement follow that table rather than a new
convention.

The operations needing coverage are the hub's `<ingest>`, `<capture_procedure>`,
`<query>`, `<archive>`, and `<lint_and_audit>` blocks, plus the
candidate-presentation output that `<present_candidates>` produces on an ambiguous
discovery, where the discovery script's `AVAILABLE:` and `EXISTING:` markers are
the canonical signal.

Body length is not part of this work: the repo's own record corrects the
skill-size question to description length among siblings rather than body length,
and the checker enforces no body-size rule.

## Approach

Author one `<output_contract>` block at the end of the hub body, stating for each
core operation what the skill returns: which files changed, the lint outcome, and
the log entry written. Where an operation already states its report inline, cite
that block by its verbatim tag name and keep its text canonical, so one statement
per promise remains. Frame each entry as the shape returned rather than as a list
of omissions.

**Out of scope:**

- Reducing the hub's body size or splitting its sections.
- Changing the three front-end contracts, which stay as they are.

## Acceptance

1. Searching the hub for `<output_contract>` returns one block, and reading it
   names the report returned for `<ingest>`, `<capture_procedure>`, `<query>`,
   `<archive>`, and `<lint_and_audit>`.
2. The block cites `<report_what_changed>` rather than restating its text, so
   searching the hub for that block's wording returns one occurrence.
3. The block names the ambiguous-discovery output in terms of the `AVAILABLE:` and
   `EXISTING:` markers the discovery script emits.
4. `lint_pseudo_xml.py` from the `ai_instruction_formatting` skill reports no
   errors on the hub after the addition.
5. The three front-end `<output_contract>` blocks are byte-identical to their
   current state, so the hub's contract adds the hub's own promise rather than
   duplicating theirs.
