---
description: Give the wiki hub an output contract stating what each core operation returns, since all three front ends carry one and the hub states its report only per operation.
scope: plugins/knowledge_management
created: 2026-08-11T18:59:52
updated: 2026-08-12T21:20:23
status: ready
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

Insert one `<output_contract>` immediately after `</pitfalls>` and before
`<family>` when that block is present, otherwise immediately before `</wiki>`,
matching the task hub precedent. For each core operation, state the
report shape the agent returns:

- **`<ingest>`** — files created or updated; cite `<report_what_changed>` and
  keep its text canonical there.
- **`<capture_procedure>`** — the procedure page path created or updated and the
  `index.md` navigation updates applied.
- **`<query>`** — synthesized answer with citations plus the one-line filing
  decision from **Report the filing decision in one line** (filed page path, or
  skip reason in the trigger's terms); cite that step rather than restating it.
- **`<archive>`** — archived page path, `index.md` and inbound-link updates, and
  post-archive lint outcome.
- **`<lint_and_audit>`** — inline lint finding counts logged to `log.md`, or the
  delegated agent's per-file change list and audit-complete line for broad scope.
- **`<present_candidates>`** — every `AVAILABLE:` and `EXISTING:` candidate in
  walk order, the chosen or adopted path, and the one-line adoption report per
  `<adopt_when_user_named_the_path>` when it applies.

Cite an existing inline promise by its verbatim pseudo-XML tag when one exists;
otherwise cite the step's verbatim bold lead-in. Frame each entry as what the
agent returns to the user — file paths, lint counts, log lines, filing
decisions, or candidate lists. One statement per promise remains in the hub.

**Out of scope:**

- Reducing the hub's body size or splitting its sections.
- Changing the three front-end contracts, which stay as they are.

## Acceptance

1. Searching `plugins/knowledge_management/skills/wiki/SKILL.md` for
   `<output_contract>` returns exactly one block positioned after `</pitfalls>`
   and immediately before `<family>` when that block is present, otherwise
   immediately before `</wiki>`.
2. Reading that block names the report returned for `<ingest>`,
   `<capture_procedure>`, `<query>`, `<archive>`, `<lint_and_audit>`, and
   ambiguous-discovery output from `<present_candidates>`.
3. For `<ingest>`, the block cites `<report_what_changed>` rather than restating
   its text, so searching the hub for that tag's body wording returns one
   occurrence.
4. For `<query>`, the block cites **Report the filing decision in one line**
   rather than restating that step's text, so searching the hub for that lead-in's
   body wording returns one occurrence, and names the synthesized answer with
   citations plus the one-line filing decision (filed page path, or skip reason in
   the trigger's terms).
5. For `<capture_procedure>`, the block names the procedure page path created or
   updated and the `index.md` navigation updates applied, and cites
   `<update_navigation_for_procedure>` rather than restating its text, so
   searching the hub for that tag's body wording returns one occurrence.
6. For `<archive>`, the block names the archived page path, `index.md` and
   inbound-link updates, and the post-archive lint outcome.
7. For `<lint_and_audit>`, the block names inline lint finding counts logged to
   `log.md`, or the delegated agent's per-file change list and audit-complete
   line for broad scope; for the narrow inline path it cites
   `<inline_iteration_loop>` rather than restating its text, so searching the hub
   for that tag's body wording returns one occurrence.
8. For ambiguous discovery, the block cites `<present_candidates>` rather than
   restating its text, so searching the hub for that tag's body wording returns
   one occurrence, and names candidate presentation in terms of the `AVAILABLE:`
   and `EXISTING:` markers and the chosen or adopted path (including the
   one-line adoption report per `<adopt_when_user_named_the_path>` when it
   applies).
9. Each operation entry states what the agent returns using positive shape
   labels; no entry defines its report primarily as omitted elements.
10. `lint_pseudo_xml.py` from the `ai_instruction_formatting` skill reports no
    errors on the hub after the addition.
11. The three front-end `<output_contract>` blocks in `wiki_fix`, `wiki_import`,
    and `wiki_wrapup` remain byte-identical to their current state.
