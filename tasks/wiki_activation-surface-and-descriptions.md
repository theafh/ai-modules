---
description: Realign the wiki family's activation surface: hub stops claiming import and audit ground, purpose-first descriptions, em-dash sentence splits, and trigger fixtures aligned to the boundary.
scope: plugins/knowledge_management
created: 2026-08-11T18:59:52
updated: 2026-08-30T17:36:22
status: ready
reported-by: Andreas Hoffmann
---

# Realign the wiki family's activation surface and descriptions

## Goal

The four wiki-family skills advertise one non-overlapping activation surface. The
hub `wiki` keeps the wiki-building, page-writing, and querying ground it owns and
hands single-source import to `wiki_import`, session capture to `wiki_wrapup`, and
audit-and-repair to `wiki_fix`. A router reading only the frontmatter descriptions
plus the hub's `<when_to_activate>` list sends each of those four request kinds to
one skill. Each description leads with the user-facing purpose summary and follows
with its trigger language, per the standing repo rule on writing skill
descriptions for both audiences.

## Context

The hub's body and its description disagree about what the hub covers. Its
`<when_to_activate>` list still carries the entry
`Asks to ingest, add, or process a source into their wiki.`, which is
`wiki_import`'s surface, and an entry beginning
`Asks to lint, audit, fix, health-check, clean up, or auto-repair their wiki`,
which is `wiki_fix`'s. Three commits on 2026-05-25 (`2583ceb`, `2190a01`,
`497c141`) narrowed the frontmatter `description:` out of exactly that ground; the
body never followed.

That audit entry also routes the work straight to the `auto_shaper_wiki` agent,
while `wiki_fix` exists as the named front end for that handoff. The two are
separable: activation belongs to `wiki_fix`, and the hub's own
`<lint_and_audit>` operation legitimately spawns the agent for a session already
working inside a wiki. The entry to change is the activation one.

The hub description opens with a router directive,
`Activate this skill whenever the user mentions their wiki, knowledge base, or
research notes in any way`, and reaches its purpose sentence second. It closes
with `even as a passing reference`. Those two catch-alls claim requests the
repo's own routing fixtures assign elsewhere: in `tests/trigger_evals/wiki.json`
the query about a wiki page for a new attribution model built from a pasted
transcript carries `expected_skill` of `wiki_import`, and the query beginning
`fix my wiki` carries `expected_skill` of `wiki_fix`.

The em dash in the hub description, and both in `wiki_fix`'s, hold clause breaks
the sentences never earned. The `ai_instruction_writing` skill's
`<sentence_construction>` rules own that rewrite: split into two sentences and
keep UTF-8, rather than substituting a hyphen or an en dash, which keeps the same
break.

Two related items bound the work. [archive/task-family_sibling-trigger-routing.md](archive/task-family_sibling-trigger-routing.md)
records that description-sharpening regressed routing for the `task_*` family
while naming helped, so treat wording changes here as measured rather than
assumed. The trigger-eval surface measures in deployed mode, where the wiki
fixtures score non-zero, so that measurement is available to check the wording
changes here rather than blocked on a runner repair.

Co-edit:
[ai-dev_skill-doctor-typographic-punctuation-finding.md](archive/ai-dev_skill-doctor-typographic-punctuation-finding.md)
renamed the `discovery_safety.py` finding codes and narrowed both findings from
the ASCII boundary to a typographic punctuation set. The Acceptance check that
runs `scripts/discovery_safety.py` names the two shipped codes,
`description_typographic_punctuation` and
`sibling_typographic_punctuation_outlier`. Neither task blocks the other, and
the em dash stays a flagged character under both the old and the new code, so
this task's verification holds either way.

## Approach

1. Rewrite the two `<when_to_activate>` entries in place so the source-ingest
   entry and the audit entry name the owning sibling instead of claiming the
   work, leaving the hub's remaining entries as they are.
2. Rewrite the hub description so the purpose sentence leads, the `Use when`
   trigger language follows, and the two catch-all clauses narrow to the ground
   the hub keeps after the `<when_to_activate>` sibling-owner rewrite.
3. Split the unearned clause breaks in the hub and `wiki_fix` descriptions into
   separate sentences, keeping every hub trigger phrase that remains after the
   hub description drops the catch-alls. The `<when_to_activate>` sibling-owner
   rewrite edits only the hub body list; the hub description rewrite and the
   em-dash sentence splits edit only the hub and `wiki_fix` frontmatter
   descriptions; leave `wiki_import` and `wiki_wrapup` descriptions unchanged
   when they already lead with purpose before `Use when`.
4. Bring the trigger fixtures into agreement with the boundary this task sets,
   changing a fixture expectation only where it contradicts that boundary.

**Out of scope:**

- Rewriting `wiki_import` or `wiki_wrapup` descriptions that already lead with
  purpose before trigger language.
- The hub's `<lint_and_audit>` operation, which keeps spawning the agent for a
  session already inside a wiki.
- Family declaration and authority blocks, owned by
  [wiki_family-inheritance-blocks.md](wiki_family-inheritance-blocks.md).
- Changing the trigger-eval runner, a separate harness this task does not touch.

## Acceptance

1. Searching the hub `SKILL.md` for `Asks to ingest, add, or process a source`
   returns no match, and the entry that replaces it names `wiki_import` as the
   owner of that request kind.
2. Searching the hub `SKILL.md` for `Asks to lint, audit, fix, health-check, clean up, or auto-repair`
   returns no match, and the entry that replaces it names `wiki_fix` as the
   owner of that request kind.
3. The hub `<when_to_activate>` list still contains each of these entries
   verbatim: `Asks to create, build, or start a wiki or knowledge base.`; `Asks
   a question that an existing wiki at the discovered location could answer.`;
   `References their wiki, knowledge base, or "notes" in a research context.`;
   and `Asks to capture procedural knowledge — workflows, conventions, runbooks
   — alongside the wiki's subject pages.`
4. Reading the hub's `<lint_and_audit>` block shows it unchanged, so the agent
   handoff for an in-session audit still exists.
5. The hub description's first sentence states the skill's purpose with no router
   directive, its `Use when` clause retains trigger language for create, build,
   start, or initialize a wiki or knowledge base; add, create, or write wiki
   pages; query, compare, contrast, reference, or analyze an existing wiki to
   answer a research or domain question; and archive or reorganize wiki pages,
   and searching both `in any way` and `even as a passing reference` in that
   description returns no match.
6. Searching the hub and `wiki_fix` descriptions for the em dash character
   returns no match, both files remain valid UTF-8, and each former dash break
   reads as two sentences.
7. Running `scripts/discovery_safety.py` from the `skill_doctor` skill over the
   four family skills reports neither `description_typographic_punctuation` nor
   `sibling_typographic_punctuation_outlier` for `wiki` or `wiki_fix`.
8. Every expectation in `tests/trigger_evals/wiki*.json` agrees with the boundary
   this task sets, verified by reading each positive and negative entry against
   the four descriptions.
9. Reading the `wiki_import`, `wiki_wrapup`, and `wiki_fix` frontmatter
   descriptions shows each opens with its purpose sentence before `Use when`,
   with no router directive in the opening sentence.
10. Reading the `wiki_import` and `wiki_wrapup` frontmatter descriptions shows
    each unchanged.
