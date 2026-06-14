---
description: "Build the ghost_writer skill: rules for writing and especially editing strong prose, with one ruleset per genre — scientific, essays, blog posts, social media, case studies."
scope: "ai_editorial plugin"
created: 2026-06-01T23:31:06
updated: 2026-06-14T18:35:44
status: open
reported-by: Andreas Hoffmann
---

# Build the ghost_writer skill

## Goal

Add the `ghost_writer` skill to the `ai_editorial` plugin. It carries the rules for writing strong human-facing prose and, especially, for **editing** existing text, with a dedicated ruleset per target genre — scientific writing, essays, blog posts, social media, and case studies. Given a draft or a brief plus a genre, it writes or edits prose to that genre's rules.

## Context

- Depends on the plugin shell: build [ai-editorial_plugin-scaffold.md](ai-editorial_plugin-scaffold.md) first. This skill lands in `plugins/ai_editorial/skills/ghost_writer/`.
- **Rule content needs a source — prerequisite input.** The substance of this skill is the rulesets themselves. Before authoring, gather the source from the user — existing style guides, the user's own writing notes and preferences, or named references per genre. With no source provided, agree the rule content with the user rather than inventing five genre rulesets unprompted. This task is ready to *build* once that input exists; until then it is ready to *scaffold and outline*.
- Pairs with [ai-editorial_slop-catch-skill.md](ai-editorial_slop-catch-skill.md): `slop_catch` flags AI tells; `ghost_writer` produces and edits prose that avoids them. Decide whether `ghost_writer` references `slop_catch`'s tell ruleset to stay consistent (a deployment-agnostic, direct reference if so).
- Keep distinct from `ai_instruction_writing` (machine-facing). Write the `description:` so it triggers on producing and editing human-facing prose by genre.
- Follow the standing repo rules for skill authoring; this task supplies the `ghost_writer`-specific workflow, genre set, and source requirements.

## Approach

1. `plugins/ai_editorial/skills/ghost_writer/SKILL.md` — frontmatter `name: ghost_writer`; body sections for role, when-to-activate, the write-and-edit workflow keyed by genre, and output contract. State that editing existing text is the primary mode.
2. `skills/ghost_writer/references/` — the shared prose-writing and editing rules, plus one ruleset per genre: scientific writing, essays, blog posts, social media, case studies. Each ruleset states what good looks like for that genre and how to edit toward it. Populate from the source gathered in Context.
3. If the file set outgrows a single coherent unit — for instance if each genre ruleset becomes substantial — split the per-genre rulesets into a follow-up task rather than letting this one pass 300 lines.

## Acceptance

- `plugins/ai_editorial/skills/ghost_writer/` holds `SKILL.md` and a `references/` set covering the shared prose/editing rules plus the five named genre rulesets.
- Each genre ruleset traces to the agreed source from Context, not invented unprompted.
- The skill `description:` triggers on human-facing prose work and stays distinct from the `ai_instruction_*` skills.
- `./deployment/deployment.sh --global --dry-run` previews `ghost_writer` without error.
